import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';

class RustFFmpeg {
  const RustFFmpeg();

  static Future<String?>? _pathFuture;

  /// 返回可用 ffmpeg 可执行路径，优先内置模块，其次系统 PATH；
  /// 若内置模块未下载则自动触发下载。失败时返回 null 并允许下次重试。
  static Future<String?> resolvePath() async {
    if (_pathFuture != null) return _pathFuture!;
    final future = _resolvePathImpl();
    _pathFuture = future;
    final result = await future;
    if (result == null) _pathFuture = null; // 失败时允许重试
    return result;
  }

  static Future<String?> _resolvePathImpl() async {
    if (!(Platform.isWindows || Platform.isMacOS)) return null;
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final ext = Platform.isWindows ? '.exe' : '';
      final internalPath = '${appDir.path}${sep}modules${sep}ffmpeg${sep}ffmpeg$ext';

      // 已存在直接返回
      if (File(internalPath).existsSync()) return internalPath;

      // 尝试触发下载
      await initialize();

      if (File(internalPath).existsSync()) return internalPath;
    } catch (_) {}

    // 降级到系统 ffmpeg
    try {
      final r = await Process.run('ffmpeg', ['-version']);
      if (r.exitCode == 0) return 'ffmpeg';
    } catch (_) {}

    return null;
  }

  static Future<void> initialize() async {
    if (!(Platform.isWindows || Platform.isMacOS)) {
      return;
    }

    // 在此处初始化 FFmpeg 模块
    try {
      final appDir = await getApplicationSupportDirectory();
      final windowsUrl = dotenv.env['FFMPEG_WINDOWS_URL'] ?? '';
      final macosUrl = dotenv.env['FFMPEG_MACOS_URL'] ?? '';

      if (windowsUrl.isEmpty || macosUrl.isEmpty) {
        // print('⚠️ FFmpeg URLs not configured in .env');
        return;
      }

      await initializeFfmpeg(windowsUrl: windowsUrl, macosUrl: macosUrl, installDir: appDir.path);

      print('✅ FFmpeg initialized successfully');
    } catch (e) {
      print('❌ FFmpeg initialization failed: $e');
    }
  }
}
