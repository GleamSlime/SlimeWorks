import 'dart:async';

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
class VideoWaveformService {
  VideoWaveformService({required this.nodeService});

  final NodeSettingsService nodeService;

  /// 默认 bins 数（波形颗粒度）。
  ///
  /// 1200 根：在 1200px 宽的画面里每根约 1px，配合绘制层按可用宽度自适应的
  /// 间距，高声段的起止边界能看清；480 根时一根覆盖 2~3px，边界显得粗。
  /// 再往上收益很小而 JSON 体积与聚合成本线性上升，故止步于此。
  static const int defaultBins = 1200;

  /// 单次提取的耐心上限：超大影片整段解码可能几十秒。
  static const Duration _timeout = Duration(minutes: 5);

  /// 进程级缓存（key → 结果；空列表占位表示"试过且失败"，不再反复重试）。
  final Map<String, List<double>?> _memory = {};

  /// 在飞请求去重：邻页预热与当前页同时打开同一文件时只跑一份。
  final Map<String, Future<List<double>?>> _inFlight = {};

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
    final mem = _memory[key];
    if (mem != null) return mem.isEmpty ? null : mem;
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _load(source, bins, ensure);
    _inFlight[key] = future;
    try {
      final result = await future;
      _memory[key] = result ?? const <double>[];
      return result;
    } finally {
      _inFlight.remove(key);
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
      await _acquireDecodeSlot();
      try {
        final data = await media_api
            .ensureVideoWaveform(filePath: source, bins: bins)
            .timeout(_timeout);
        return data.isEmpty ? null : data;
      } finally {
        _releaseDecodeSlot();
      }
    } catch (e) {
      _logger.error('[VideoWaveform] 取振幅失败: $source err=$e');
      return null;
    }
  }

  /// 清掉某个源的进程内缓存（源文件被替换/重新生成后调用）。
  void invalidate(String source) {
    _memory.removeWhere((key, _) => key.startsWith('$source|'));
  }
}
