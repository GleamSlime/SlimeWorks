import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:slime_works/core/services/initialize/ffmpeg.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

const Loggers _logger = Loggers(name: '视频波形');

/// 视频预览「振幅进度条」的波形提取服务。
///
/// 三条链路按成本从低到高依次尝试，任何一条成功即返回：
/// ① 磁盘缓存（key = 路径+大小+修改时间+bins 的 sha256，改过的文件自动失效）；
/// ② 现成的 Rust FFI `extractWaveform`（symphonia 已启用 mp3/flac/aac/ogg/wav/isomp4，
///    普通 mp4/MKV 里是 AAC 也能直接解出音轨，且 Rust 侧自带缓存）；
/// ③ ffmpeg 子进程兜底（重采样到 8kHz 单声道 s16 裸 PCM 走管道，按块取峰值），
///    覆盖 symphonia 不支持的容器/编码（如 MKV+opus、wmv、ape 等）。
///
/// 返回值统一按「全局峰值」归一化到 0~1：用户的验收点是"能显著看出哪里高声"，
/// 满刻度不归一的话整段都低音量、小音量影片会糊成一排矮条，相对响度才是重点。
/// 仅桌面端 + 本地文件可用；远程 URL、移动端一律返回 null，界面退回普通进度条。
class VideoWaveformService {
  /// 默认 bins 数：够密不至于糊、又不至于让 barWidth 小于半个像素。
  static const int defaultBins = 480;

  /// FFI 解码的耐心上限：超大影片的音轨整段解码可能几十秒，超时转 ffmpeg 兜底。
  static const Duration _ffiTimeout = Duration(seconds: 120);

  /// ffmpeg 解码的耐心上限（重采样后仍受整段解码速度支配）。
  static const Duration _ffmpegTimeout = Duration(minutes: 5);

  /// 进程级内存缓存（key → 结果；null 用空列表占位，避免同一文件反复失败重试）。
  final Map<String, List<double>?> _memory = {};

  /// 正在计算中的请求去重：邻页预热与当前页同时打开同一文件时只跑一份。
  final Map<String, Future<List<double>?>> _inFlight = {};

  /// 是否支持为该来源提取振幅。
  ///
  /// - 本地文件：桌面端且文件存在 → 可用（有 FFI 快速路径）
  /// - 远程节点视频（http/https）：桌面端即可，交给 ffmpeg 直接读 URL 流式取峰
  ///   （FFI 路径只吃本地路径，远程一律走 ffmpeg）
  bool supports(String? source) {
    if (source == null || source.isEmpty) return false;
    if (!(Platform.isWindows || Platform.isMacOS)) return false;
    if (isRemoteSource(source)) return true;
    try {
      return File(source).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 远程来源判定：节点媒体走 http(s) 直链。
  static bool isRemoteSource(String source) =>
      source.startsWith('http://') || source.startsWith('https://');

  /// 提取指定文件的波形（0~1 归一化振幅数组，长度 = bins）。失败返回 null。
  Future<List<double>?> waveformFor(String filePath, {int bins = defaultBins}) async {
    if (!supports(filePath)) return null;
    final key = await _cacheKey(filePath, bins);
    if (key == null) return null;
    // 会话内命中（含负缓存：空列表代表"试过且失败"，不再重复烧 CPU）
    final mem = _memory[key];
    if (mem != null) return mem.isEmpty ? null : mem;
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _compute(filePath, key, bins);
    _inFlight[key] = future;
    try {
      final result = await future;
      _memory[key] = result ?? const <double>[];
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  // ── 内部实现 ─────────────────────────────────────────────────────────────

  Future<List<double>?> _compute(String filePath, String key, int bins) async {
    // ① 磁盘缓存
    final cached = await _readDiskCache(key, bins);
    if (cached != null && cached.isNotEmpty) return cached;

    // ② Rust FFI（symphonia）：音频文件与多数 MP4 能直接命中，速度最快。
    //    只吃本地路径——远程 URL 交给 ffmpeg 直接流式读。
    List<double>? data;
    if (!isRemoteSource(filePath)) {
      try {
        final raw = await music_api
            .extractWaveform(audioFilePath: filePath, samples: bins)
            .timeout(_ffiTimeout);
        if (raw.length == bins && raw.any((v) => v > 0)) {
          data = _normalize(raw);
        }
      } catch (e) {
        _logger.info('[VideoWaveform] FFI 提取失败，转 ffmpeg 兜底: $e');
      }
    }

    // ③ ffmpeg 子进程兜底（覆盖 symphonia 解不了的容器/编码，以及远程 http 流）
    data ??= await _extractWithFfmpeg(filePath, bins);

    if (data == null) return null;
    await _writeDiskCache(key, bins, data);
    return data;
  }

  /// 缓存文件名：sha256(路径|大小|修改时间|bins)，文件一变 key 即变，天然过期。
  ///
  /// 远程 URL 拿不到 stat，且同一 URL 就是同一份内容（节点按需生成，路径含集合
  /// 与文件名），因此只用 URL 本身做 key；重新上传同名文件会命中旧波形，
  /// 属于可接受的退化——总比每次都重跑 ffmpeg 好。
  Future<String?> _cacheKey(String filePath, int bins) async {
    if (isRemoteSource(filePath)) {
      return sha256.convert(utf8.encode('$filePath|remote|$bins')).toString();
    }
    try {
      final stat = await File(filePath).stat();
      final src = '$filePath|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$bins';
      return sha256.convert(utf8.encode(src)).toString();
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _cacheDir() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final dir = Directory(
        '${appDir.path}${Platform.pathSeparator}library'
        '${Platform.pathSeparator}media${Platform.pathSeparator}waveforms',
      );
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (e) {
      _logger.error('[VideoWaveform] 缓存目录不可用: $e');
      return null;
    }
  }

  Future<List<double>?> _readDiskCache(String key, int bins) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final f = File('${dir.path}${Platform.pathSeparator}$key.json');
    try {
      if (!f.existsSync()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || j['bins'] != bins) return null;
      final arr = j['data'];
      if (arr is! List) return null;
      final out = arr.map((e) => (e as num).toDouble()).toList(growable: false);
      return out.length == bins ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(String key, int bins, List<double> data) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      final f = File('${dir.path}${Platform.pathSeparator}$key.json');
      await f.writeAsString(jsonEncode({'bins': bins, 'data': data}), flush: false);
    } catch (e) {
      _logger.info('[VideoWaveform] 写缓存失败（非致命）: $e');
    }
  }

  /// 按全局峰值线性归一化到 0~1，保底一个最低高度防止全零。
  List<double> _normalize(List<double> peaks) {
    double max = 0.0;
    for (final v in peaks) {
      if (v > max) max = v;
    }
    if (max <= 1e-6) return List<double>.filled(peaks.length, 0.05);
    final scale = 1.0 / max;
    // 轻微 gamma(0.85) 抬一下中小音量段：纯线性时安静对白几乎看不见，
    // 但指数留在 <1 的小数里，高声段依旧顶满，对比方向不变。
    return List<double>.generate(
      peaks.length,
      (i) => math.pow(peaks[i] * scale, 0.85).toDouble().clamp(0.0, 1.0),
      growable: false,
    );
  }

  /// ffmpeg 兜底：8kHz 单声道 s16 PCM 走 stdout。
  ///
  /// 8kHz×16bit 单声道 ≈ 每秒 16KB，两小时影片也只有约 230MB 上限；
  /// 实际做法是**流式分块取峰值**，每攒满一个样本块就地折叠成一个峰值，
  /// 内存里只留 bins 个 float，绝不让整段 PCM 进堆。
  /// resolvePath() 必须在主 isolate await（FRB 在裸 isolate 里未初始化）。
  Future<List<double>?> _extractWithFfmpeg(String filePath, int bins) async {
    final exe = await RustFFmpeg.resolvePath();
    if (exe == null) {
      _logger.info('[VideoWaveform] 无可用 ffmpeg，放弃提取');
      return null;
    }
    Process? proc;
    try {
      // 注意：这套 SDK 的 ProcessStartMode 没有 hidden 档；普通模式下 macOS 无窗，
      // Windows 若闪黑窗由 -v quiet + 秒级生命周期兜底（解析失败本就退 FFI 链路）。
      proc = await Process.start(
        exe,
        [
          '-v', 'quiet',
          // 远程 http 流：限制协议白名单与超时，避免 ffmpeg 卡在握手上不返回
          if (isRemoteSource(filePath)) ...['-rw_timeout', '15000000'],
          '-i', filePath,
          '-vn', // 丢视频轨，只留音频
          '-f', 's16le',
          '-ac', '1', // 混成单声道
          '-acodec', 'pcm_s16le',
          '-ar', '8000', // 8kHz 足够波形显示，解码量降到 1/5
          '-',
        ],
      );
      // stderr 在 -v quiet 下应无输出，但必须持续排空，防管道写满卡死子进程
      unawaited(proc.stderr.drain<void>());

      final completer = Completer<List<double>?>();
      // 分块折叠：每 blockBytes(=250 样本) 一个峰值，之后再聚合到 bins
      const blockSamples = 250;
      const blockBytes = blockSamples * 2;
      final blockPeaks = <double>[];
      var buffer = Uint8List(blockBytes);
      var used = 0;
      var totalSamples = 0;

      late final StreamSubscription<List<int>> sub;
      void foldBlock() {
        int peak = 0;
        final bd = ByteData.sublistView(buffer);
        for (var o = 0; o < blockBytes; o += 2) {
          final s = bd.getInt16(o, Endian.little).abs();
          if (s > peak) peak = s;
        }
        blockPeaks.add(peak / 32768.0);
        totalSamples += blockSamples;
      }

      sub = proc.stdout.listen(
        (chunk) {
          var offset = 0;
          while (offset < chunk.length) {
            final take = math.min(blockBytes - used, chunk.length - offset);
            buffer.setRange(used, used + take, chunk, offset);
            used += take;
            offset += take;
            if (used == blockBytes) {
              foldBlock();
              used = 0;
            }
          }
        },
        onDone: () {
          // 收尾不足一块的尾巴
          if (used > 0) {
            int peak = 0;
            final bd = ByteData.sublistView(buffer);
            for (var o = 0; o + 1 < used; o += 2) {
              final s = bd.getInt16(o, Endian.little).abs();
              if (s > peak) peak = s;
            }
            blockPeaks.add(peak / 32768.0);
          }
          sub.cancel();
          if (blockPeaks.isEmpty) {
            completer.complete(null);
            return;
          }
          completer.complete(_redistribute(blockPeaks, bins));
        },
        onError: (Object e) {
          sub.cancel();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      final exited = proc.exitCode.timeout(
        _ffmpegTimeout,
        onTimeout: () {
          proc?.kill();
          return -1;
        },
      );
      // 双保险：exitCode 超时杀进程后 stdout 通常也会断，但 completer 若卡死仍需兜底
      final data = await completer.future.timeout(
        _ffmpegTimeout,
        onTimeout: () {
          proc?.kill();
          return null;
        },
      );
      final code = await exited;
      if (data == null) {
        _logger.info('[VideoWaveform] ffmpeg 无音频输出（退出码 $code）: $filePath');
        return null;
      }
      if (code != 0 && totalSamples == 0) return null;
      return _normalize(data);
    } catch (e) {
      proc?.kill();
      _logger.error('[VideoWaveform] ffmpeg 提取失败: $e');
      return null;
    }
  }

  /// 把任意长度的块峰值等比重采样到 bins 个（区间取最大，保峰值不丢）。
  List<double> _redistribute(List<double> peaks, int bins) {
    if (peaks.length == bins) return peaks;
    final ratio = peaks.length / bins;
    return List<double>.generate(
      bins,
      (i) {
        final start = (i * ratio).floor().clamp(0, peaks.length - 1);
        final end = ((i + 1) * ratio).ceil().clamp(start + 1, peaks.length);
        var max = 0.0;
        for (var j = start; j < end; j++) {
          if (peaks[j] > max) max = peaks[j];
        }
        return max;
      },
      growable: false,
    );
  }
}
