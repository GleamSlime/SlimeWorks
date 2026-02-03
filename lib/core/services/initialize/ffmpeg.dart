import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';

class RustFFmpeg {
  const RustFFmpeg();

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
