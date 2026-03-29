import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 视频预览质量等级 → ffmpeg 参数映射。
class ThumbQualityLevel {
  const ThumbQualityLevel({
    required this.label,
    required this.scaleWidth,
    required this.qv,
    required this.frameCount,
    required this.frameCountFallback,
  });

  final String label;

  /// ffmpeg -vf scale=<scaleWidth>:-2
  final int scaleWidth;

  /// ffmpeg -q:v <qv>  (值越小质量越高)
  final int qv;

  /// ffprobe 成功时提取的帧数
  final int frameCount;

  /// ffprobe 失败时提取的帧数（保守）
  final int frameCountFallback;
}

class MediaPrefsService {
  static const _keyQuality = 'media_thumb_quality';
  static const _keyConcurrency = 'media_thumb_concurrency';

  /// 质量等级 1-5 (默认 3)。
  final quality = 3.obs;

  /// 封面生成并发量 1-20 (默认 2)。
  final concurrency = 2.obs;

  static const levels = [
    ThumbQualityLevel(label: '极低', scaleWidth: 120, qv: 10, frameCount: 3, frameCountFallback: 2),
    ThumbQualityLevel(label: '低',   scaleWidth: 180, qv: 8,  frameCount: 4, frameCountFallback: 2),
    ThumbQualityLevel(label: '中',   scaleWidth: 240, qv: 6,  frameCount: 6, frameCountFallback: 3),
    ThumbQualityLevel(label: '高',   scaleWidth: 360, qv: 4,  frameCount: 6, frameCountFallback: 3),
    ThumbQualityLevel(label: '超高', scaleWidth: 480, qv: 3,  frameCount: 8, frameCountFallback: 4),
  ];

  ThumbQualityLevel get currentLevel =>
      levels[(quality.value - 1).clamp(0, levels.length - 1)];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    quality.value = (prefs.getInt(_keyQuality) ?? 3).clamp(1, 5);
    concurrency.value = (prefs.getInt(_keyConcurrency) ?? 2).clamp(1, 20);
  }

  Future<void> setQuality(int v) async {
    quality.value = v.clamp(1, 5);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyQuality, quality.value);
  }

  Future<void> setConcurrency(int v) async {
    concurrency.value = v.clamp(1, 20);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyConcurrency, concurrency.value);
  }

  /// 计算缩略图缓存目录大小（字节）。
  Future<int> calcCacheSizeBytes() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}${Platform.pathSeparator}thumbnails');
      if (!cacheDir.existsSync()) return 0;
      int total = 0;
      await for (final entity in cacheDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
      return total;
    } catch (e) {
      debugPrint('[MediaPrefs] calcCacheSizeBytes error: $e');
      return 0;
    }
  }

  /// 清空缩略图缓存目录。
  Future<void> clearCache() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}${Platform.pathSeparator}thumbnails');
      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }
      debugPrint('[MediaPrefs] 缓存已清除');
    } catch (e) {
      debugPrint('[MediaPrefs] clearCache error: $e');
    }
  }
}
