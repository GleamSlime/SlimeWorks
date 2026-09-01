import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';
import 'package:slime_works/core/utils/logger.dart';
const Loggers _logger = Loggers(name: 'FFmpeg');


class RustFFmpeg {
  const RustFFmpeg();

  static Future<String?>? _pathFuture;
  static Future<String?>? _probeFuture;

  /// 返回可用 ffmpeg 可执行路径，优先探测系统 PATH（用户用 brew/包管理器安装的），
  /// 系统 PATH 未命中则检查内置模块，仍未命中则触发下载；
  /// 全部失败时返回 null。结果在本次运行期间只解析一次（无论成功或失败均缓存）。
  static Future<String?> resolvePath() async {
    if (_pathFuture != null) {
      _logger.info('[FFmpeg] resolvePath: 复用已缓存的 future');
      return _pathFuture!;
    }
    _logger.info('[FFmpeg] resolvePath: 开始首次解析');
    _pathFuture = _resolvePathImpl();
    final result = await _pathFuture!;
    _logger.info('[FFmpeg] resolvePath: 解析完成 → ${result ?? "未找到 ffmpeg"}');
    return result;
  }

  /// 返回可用 ffprobe 可执行路径。解析顺序与 [resolvePath] 一致：
  /// 先探测系统 PATH，未命中再下载内置，再 fallback。
  static Future<String?> resolveProbe() async {
    if (_probeFuture != null) return _probeFuture!;
    _probeFuture = _resolveProbeImpl();
    final result = await _probeFuture!;
    _logger.info('[FFmpeg] resolveProbe: 解析完成 → ${result ?? "未找到 ffprobe"}');
    return result;
  }

  static Future<String?> _resolvePathImpl() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      _logger.info('[FFmpeg] 非 Windows/macOS 平台，跳过');
      return null;
    }

    // ① 优先探测系统 PATH（用户用 brew/包管理器等安装的 ffmpeg）
    try {
      final r = await Process.run('ffmpeg', ['-version']);
      if (r.exitCode == 0) {
        _logger.info('[FFmpeg] 使用系统 PATH 中的 ffmpeg');
        return 'ffmpeg';
      }
      _logger.info('[FFmpeg] 系统 ffmpeg 检测失败 exitCode=${r.exitCode}');
    } catch (e) {
      _logger.info('[FFmpeg] 系统 PATH 未发现 ffmpeg: $e');
    }

    // ② 系统 PATH 未命中，检查内置模块
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final ext = Platform.isWindows ? '.exe' : '';
      final internalPath = '${appDir.path}${sep}modules${sep}ffmpeg${sep}ffmpeg$ext';
      _logger.info('[FFmpeg] 检查内置路径: $internalPath');

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 内置 ffmpeg 已存在，直接使用');
        return internalPath;
      }

      // ③ 内置不存在，触发下载
      _logger.info('[FFmpeg] 内置 ffmpeg 未找到，触发下载...');
      await initialize();

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 下载后内置 ffmpeg 可用: $internalPath');
        return internalPath;
      }
      _logger.error('[FFmpeg] 下载后仍未找到内置 ffmpeg');
    } catch (e) {
      _logger.error('[FFmpeg] 内置路径检测/下载异常: $e');
    }

    _logger.error('[FFmpeg] 所有路径均不可用，返回 null');
    return null;
  }

  static Future<String?> _resolveProbeImpl() async {
    if (!(Platform.isWindows || Platform.isMacOS)) return null;

    // ① 优先探测系统 PATH
    try {
      final r = await Process.run('ffprobe', ['-version']);
      if (r.exitCode == 0) {
        _logger.info('[FFmpeg] 使用系统 PATH 中的 ffprobe');
        return 'ffprobe';
      }
      _logger.info('[FFmpeg] 系统 ffprobe 检测失败 exitCode=${r.exitCode}');
    } catch (e) {
      _logger.info('[FFmpeg] 系统 PATH 未发现 ffprobe: $e');
    }

    // ② 系统 PATH 未命中，检查内置模块
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final ext = Platform.isWindows ? '.exe' : '';
      final internalPath = '${appDir.path}${sep}modules${sep}ffmpeg${sep}ffprobe$ext';
      _logger.info('[FFmpeg] 检查内置 ffprobe 路径: $internalPath');

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 内置 ffprobe 已存在，直接使用');
        return internalPath;
      }

      // ③ 尝试下载 ffprobe
      _logger.info('[FFmpeg] 内置 ffprobe 未找到，触发下载...');
      await _initializeProbe(internalPath);

      if (File(internalPath).existsSync()) {
        _logger.info('[FFmpeg] 下载后内置 ffprobe 可用: $internalPath');
        return internalPath;
      }
      _logger.error('[FFmpeg] 下载后仍未找到内置 ffprobe');
    } catch (e) {
      _logger.error('[FFmpeg] ffprobe 内置路径检测/下载异常: $e');
    }

    _logger.error('[FFmpeg] ffprobe 所有路径均不可用，返回 null');
    return null;
  }

  static Future<void> initialize() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final windowsUrl = dotenv.env['FFMPEG_WINDOWS_URL']?.trim() ?? '';
      final macosUrl = dotenv.env['FFMPEG_MACOS_URL']?.trim() ?? '';

      _logger.info('[FFmpeg] initialize: windowsUrl="$windowsUrl" macosUrl="$macosUrl"');

      if (windowsUrl.isEmpty || macosUrl.isEmpty) {
        _logger.info('[FFmpeg] ⚠️ .env 中 FFMPEG_WINDOWS_URL / FFMPEG_MACOS_URL 未配置');
        return;
      }

      _logger.info('[FFmpeg] 开始下载 FFmpeg 到 ${appDir.path}...');
      await initializeFfmpeg(windowsUrl: windowsUrl, macosUrl: macosUrl, installDir: appDir.path);
      _logger.info('[FFmpeg] ✅ initializeFfmpeg 调用完成');
    } catch (e, st) {
      _logger.error('[FFmpeg] ❌ initialize 异常: $e\n$st');
    }
  }

  /// 下载 ffprobe 到与 ffmpeg 相同的目录。
  static Future<void> _initializeProbe(String targetPath) async {
    try {
      final windowsUrl = dotenv.env['FFPROBE_WINDOWS_URL']?.trim() ?? '';
      final macosUrl = dotenv.env['FFPROBE_MACOS_URL']?.trim() ?? '';
      if (windowsUrl.isEmpty || macosUrl.isEmpty) {
        _logger.info('[FFmpeg] ⚠️ .env 中 FFPROBE_WINDOWS_URL / FFPROBE_MACOS_URL 未配置，跳过 ffprobe 下载');
        return;
      }
      final url = Platform.isWindows ? windowsUrl : macosUrl;
      _logger.info('[FFmpeg] 开始下载 ffprobe: $url → $targetPath');
      final dir = File(targetPath).parent;
      await dir.create(recursive: true);
      final result = await Process.run(
        Platform.isWindows ? 'powershell' : 'curl',
        Platform.isWindows
            ? ['-Command', 'Invoke-WebRequest -Uri "$url" -OutFile "$targetPath"-UseBasicParsing']
            : ['-L', '-o', targetPath, url],
      );
      if (result.exitCode == 0 && File(targetPath).existsSync()) {
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', targetPath]);
        }
        _logger.info('[FFmpeg] ✅ ffprobe 下载完成: $targetPath');
      } else {
        _logger.error('[FFmpeg] ❌ ffprobe 下载失败 exitCode=${result.exitCode} stderr=${result.stderr}');
      }
    } catch (e) {
      _logger.error('[FFmpeg] ❌ ffprobe 下载异常: $e');
    }
  }
}
