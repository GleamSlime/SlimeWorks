import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/mock/seams/media_api_seam.dart' as media_api;

const Loggers _logger = Loggers(name: '视频波形');

/// 视频预览「振幅进度条」的波形服务。
///
/// 核心原则：**谁存着文件谁算振幅**，客户端只收几 KB 的 JSON。
/// - 本地文件 → 本机 Rust 解码（symphonia 优先，ffmpeg 兜底），结果写资源旁
///   `.SlimeWorks/waveform/`；
/// - 远程节点 → 交给**节点**解码，客户端通过 `read/ensure_media_waveform`
///   只取回数组。移动端走远程节点时这点是硬要求：绝不能把整段视频拉到手机
///   上再跑 ffmpeg（流量、耗时、内存都不可接受）。
///
/// 缓存与源文件身份（size|mtime）绑定，文件被替换自动失效；随资源目录一起
/// 移动/共享，换客户端也能直接命中。
///
/// 归一化与 gamma 抬升在 Rust 侧统一做（`normalize_waveform`），这里只负责
/// 选链路、去重与进程内缓存。
/// 「本次没有真正解码」的信号：同 key 已在解码中，或等待超时后放弃了。
///
/// 与真正的失败（解码报错/无音轨）区分开：那些该进负缓存，这类**不该**——
/// 后台那份解码还在跑，落盘后下次就该能命中，不能被进程内负缓存挡死。
class _DecodeSkipped implements Exception {
  const _DecodeSkipped();
}

class VideoWaveformService {
  VideoWaveformService({
    required this.nodeService,
    this.decodeTimeout = _timeout,
    this.ensureDecodeOverride,
  });

  final NodeSettingsService nodeService;

  /// 单次本地解码的耐心上限（默认 [_timeout]）。抽成字段是为了让单测用毫秒级
  /// 超时验证「超时后闸门不跟着释放」这条语义，不必真等 5 分钟。
  @visibleForTesting
  final Duration decodeTimeout;

  /// 单测注入的解码实现（默认走 FRB 的 ensureVideoWaveform）。
  @visibleForTesting
  final Future<List<double>> Function({
    required String filePath,
    required int bins,
  })? ensureDecodeOverride;

  /// 默认 bins 数（波形颗粒度）。
  ///
  /// 1200 根：在 1200px 宽的画面里每根约 1px，配合绘制层按可用宽度自适应的
  /// 间距，高声段的起止边界能看清；480 根时一根覆盖 2~3px，边界显得粗。
  /// 再往上收益很小而 JSON 体积与聚合成本线性上升，故止步于此。
  static const int defaultBins = 1200;

  /// 单次提取的耐心上限：超大影片整段解码可能几十秒。
  static const Duration _timeout = Duration(minutes: 5);

  /// 进程级缓存（key → 结果；空列表占位表示"试过且失败"，不再反复重试）。
  ///
  /// 按 LRU 截断到 [maxMemoryEntries]：一条 1200 bins 的波形约 9.6KB（double
  /// 数组 + 列表头），无上限时整库扫一遍就会把上万个文件的波形全驻留内存。
  /// Map 是插入序，命中时先删后插挪到队尾，队首即最久未用。
  final Map<String, List<double>?> _memory = {};

  /// 内存缓存条数上限（200 × ~9.6KB ≈ 2MB）。
  static const int maxMemoryEntries = 200;

  /// 在飞请求去重：邻页预热与当前页同时打开同一文件时只跑一份。
  final Map<String, Future<List<double>?>> _inFlight = {};

  /// 正在解码的 key 集合：同一文件（同 bins）已经在解码时不再重复发起。
  ///
  /// 与 [_inFlight] 的区别：_inFlight 反映的是「有人正 await 这个 future」，
  /// 而 .timeout 之后调用方已经放弃、await 结束，但 Rust 侧的整段解码还在跑。
  /// 这段时间再点一次同一文件（关掉预览再打开），旧实现会立刻又排一份新解码，
  /// 两路同时读同一个几 GB 文件——是超时钳制失效后的连带浪费。
  final Set<String> _decodingKeys = {};

  /// 本地解码并发闸门：最多 2 路同时跑。
  ///
  /// 为什么必须有：`ensureVideoWaveform` 是 FRB 异步调用，全部共享同一个
  /// 默认线程池（大小 = CPU 核数）。导入/重扫会对**每个**视频/音频条目调
  /// `_ensureItemWaveform`，一屏集合几十上百个文件同时涌入；超大视频
  /// （几 GB、几小时）整段音频解码要几分钟，8 路并发直接把池占满，
  /// 封面生成（ensureCoverThumbnail / extractVideoScrubFrames）排在后面
  /// 拿不到线程——实测封面队列 123/190 后停滞 6 分钟，进程里 8 个线程
  /// 全卡在 symphonia 解码上，ffmpeg 子进程数为 0。
  /// 波形是"预览时才需要"的后台补齐，不该抢封面（用户立刻可见）的算力。
  /// 远程来源不占本地池（解码在节点侧），不走这个闸门。
  static const int _maxLocalDecodes = 2;
  int _localDecoding = 0;
  final List<void Function()> _decodeWaiters = [];

  Future<void> _acquireDecodeSlot() {
    if (_localDecoding < _maxLocalDecodes) {
      _localDecoding++;
      return Future.value();
    }
    final c = Completer<void>();
    _decodeWaiters.add(() => c.complete());
    return c.future;
  }

  void _releaseDecodeSlot() {
    if (_decodeWaiters.isNotEmpty) {
      // 名额直接转给下一个等待者，计数不变
      _decodeWaiters.removeAt(0)();
    } else {
      _localDecoding--;
    }
  }

  /// 远程来源判定：节点媒体走 http(s) 直链。
  static bool isRemoteSource(String source) =>
      source.startsWith('http://') || source.startsWith('https://');

  /// 该播放源是否有振幅可用（**同步版，零磁盘 IO**）。
  ///
  /// 全平台可用：本地文件交给本机 Rust；远程节点交给节点算，客户端只取 JSON，
  /// 所以移动端也能用（这正是把解码移出客户端的目的）。
  ///
  /// ★ 本地文件不做存在性检查：旧版这里 `existsSync`，SMB/外置卷每次 stat
  /// 一趟网络往返（卷休眠时秒级），重扫封面对每个条目调一次 = 主 isolate
  /// 被几百次同步 stat 卡死（鼠标转圈整个 App 无响应的直接根因）。
  /// 文件不存在的情况交给 _load 里 Rust 的 metadata 检查兜底（在 FRB 池线程，
  /// 不占 UI），语义不变：不存在的源最终照样返回 null。
  bool supports(String? source) {
    if (source == null || source.isEmpty) return false;
    if (isRemoteSource(source)) {
      // 能反查到节点才有取数通道；外链视频没有节点侧算力可用
      return nodeService.resolveNodeFromMediaUrl(source) != null;
    }
    return true;
  }

  /// 取波形（0~1，长度 = bins）。失败返回 null。
  ///
  /// [ensure] = false 时只读已有缓存（导入/重扫之外的轻量探测用）；
  /// 默认 true：没有就现算一份并落盘，供下次（含其它客户端）直接命中。
  Future<List<double>?> waveformFor(
    String source, {
    int bins = defaultBins,
    bool ensure = true,
  }) async {
    if (!supports(source)) return null;
    final key = '$source|$bins';
    if (_memory.containsKey(key)) {
      final cached = _memory.remove(key);
      _memory[key] = cached; // 命中即挪到队尾（LRU）
      return cached == null || cached.isEmpty ? null : cached;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _load(source, bins, ensure);
    _inFlight[key] = future;
    try {
      final result = await future;
      _remember(key, result ?? const <double>[]);
      return result;
    } on _DecodeSkipped {
      // 本次根本没解码（被跳过或超时后放弃）：绝不能记成负缓存，
      // 否则后台那份解码落盘后，本进程会一直以为"这文件没波形"直到重启
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  void _remember(String key, List<double>? value) {
    _memory.remove(key);
    _memory[key] = value;
    while (_memory.length > maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// 该源在磁盘/节点上是否已有波形缓存（导入/重扫据此决定要不要补算）。
  Future<bool> hasWaveform(String source, {int bins = defaultBins}) async {
    final data = await waveformFor(source, bins: bins, ensure: false);
    return data != null && data.isNotEmpty;
  }

  Future<List<double>?> _load(String source, int bins, bool ensure) async {
    try {
      if (isRemoteSource(source)) {
        final resolved = nodeService.resolveNodeFromMediaUrl(source);
        if (resolved == null) return null;
        // 解码在节点侧发生，这里只收数组
        final data = await nodeService
            .fetchNodeMediaWaveform(
              nodeId: resolved.nodeId,
              filePath: resolved.filePath,
              bins: bins,
              ensure: ensure,
            )
            .timeout(_timeout);
        return (data == null || data.isEmpty) ? null : data;
      }
      // 本地：先读资源旁缓存（纯读盘），没有再让 Rust 解码并落盘
      if (!ensure) {
        final cached = await media_api.readVideoWaveform(filePath: source, bins: bins);
        return (cached == null || cached.isEmpty) ? null : cached;
      }
      // 解码是重活（超大视频几分钟），过并发闸门再进 FRB 池，
      // 别把池占满让封面生成排队（详见 _maxLocalDecodes 注释）
      final decodeKey = '$source|$bins';
      if (_decodingKeys.contains(decodeKey)) {
        // 上一次（超时后被放弃的）解码还在跑：不再起第二份，本次直接放弃。
        // 等它落盘后，下次打开会命中磁盘缓存。
        _logger.info('[VideoWaveform] 同一文件已在解码中，跳过重复发起: $source');
        throw const _DecodeSkipped();
      }
      await _acquireDecodeSlot();
      if (_decodingKeys.contains(decodeKey)) {
        // 排队等名额期间，前一个同名解码可能已经起了（并发调用同一文件）
        _releaseDecodeSlot();
        throw const _DecodeSkipped();
      }
      _decodingKeys.add(decodeKey);
      // 闸门必须在**真正的解码结束**时放，不能跟着 .timeout 放。
      // 旧实现把 release 写在 finally 里：5 分钟超时后调用方拿到 null 走了，
      // Rust 侧那条解码线程还在跑几分钟，而闸门名额已经还回去了——后续 2 路
      // 立刻占上新名额，进程里同时跑的解码数就会超过 _maxLocalDecodes，
      // 把共享的 FRB 池越占越满（封面生成被饿死的原始症状又回来了）。
      // 于是把「解析/回报结果」与「释放名额」拆开挂在被放弃的那个 future 上：
      // 只有当它自己真正完成（成功、失败或被后续忽略）才 whenComplete 释放。
      final decode = (ensureDecodeOverride ?? media_api.ensureVideoWaveform)(
        filePath: source,
        bins: bins,
      );
      var released = false;
      void releaseOnce() {
        if (released) return;
        released = true;
        _decodingKeys.remove(decodeKey);
        _releaseDecodeSlot();
      }

      unawaited(
        decode
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(releaseOnce),
      );
      try {
        final data = await decode.timeout(decodeTimeout);
        return data.isEmpty ? null : data;
      } on TimeoutException {
        // 超时只是"本次调用方不等了"，解码在后台继续跑、名额由 whenComplete 负责还
        _logger.info('[VideoWaveform] 解码超时（后台继续）: $source');
        throw const _DecodeSkipped();
      }
    } on _DecodeSkipped {
      rethrow;
    } catch (e) {
      _logger.error('[VideoWaveform] 取振幅失败: $source err=$e');
      return null;
    }
  }

  /// 当前内存缓存条数（单测断言 LRU 上限用）。
  @visibleForTesting
  int get memoryEntryCount => _memory.length;

  /// 当前占用本地解码名额的数量（单测断言闸门用）。
  @visibleForTesting
  int get localDecodingCount => _localDecoding;

  /// 当前被标记为「解码中」的 key 数量（单测断言去重用）。
  @visibleForTesting
  int get decodingKeyCount => _decodingKeys.length;

  /// 清掉某个源的进程内缓存（源文件被替换/重新生成后调用）。
  void invalidate(String source) {
    _memory.removeWhere((key, _) => key.startsWith('$source|'));
  }
}
