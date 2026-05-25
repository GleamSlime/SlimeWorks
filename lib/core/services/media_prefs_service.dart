import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/utils/logger.dart';
const Loggers _logger = Loggers(name: '媒体偏好');


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

  /// ffmpeg `-vf scale=scaleWidth:-2`
  final int scaleWidth;

  /// ffmpeg `-q:v qv`  (值越小质量越高)
  final int qv;

  /// ffprobe 成功时提取的帧数
  final int frameCount;

  /// ffprobe 失败时提取的帧数（保守）
  final int frameCountFallback;
}

class MediaPrefsService {
  static const _keyQuality = 'media_thumb_quality';
  static const _keyConcurrency = 'media_thumb_concurrency';
  static const _keyRemoteCoverWidth = 'media_remote_cover_width';
  static const _keyRemoteImageWidth = 'media_remote_image_width';
  static const _keyLocalPreviewWidth = 'media_local_preview_width';
  static const _keyCacheLimitBytes = 'media_cache_limit_bytes';

  /// 质量等级 1-5 (默认 3)。
  final quality = 3.obs;

  /// 封面生成并发量 1-20 (默认 2)。
  final concurrency = 2.obs;

  /// 远程节点封面拉取宽度(px)，0 表示原图，默认 240px。
  final remoteCoverWidth = 240.obs;

  /// 远程节点图片预览拉取宽度(px)，0 表示原图，默认 0（原图）。
  final remoteImageWidth = 0.obs;

  /// 本地图片列表缩略图解码宽度(px)，0 表示原图，默认 480px。
  /// Flutter Image 的 cacheWidth 参数，在解码阶段缩放，无需写临时文件。
  final localPreviewWidth = 480.obs;

  /// 缓存大小上限（字节），0 表示不限制，默认 1 GB。
  final cacheLimitBytes = (1 * 1024 * 1024 * 1024).obs;

  /// 缓存大小上限预设列表。
  static const cacheLimitPresets = [
    (label: '512 MB', value: 512 * 1024 * 1024),
    (label: '1 GB', value: 1 * 1024 * 1024 * 1024),
    (label: '2 GB', value: 2 * 1024 * 1024 * 1024),
    (label: '5 GB', value: 5 * 1024 * 1024 * 1024),
    (label: '10 GB', value: 10 * 1024 * 1024 * 1024),
    (label: '无限制', value: 0),
  ];

  /// 远程封面宽度预设列表。
  static const remoteCoverWidthPresets = [
    (label: '原图', value: 0),
    (label: '960px', value: 960),
    (label: '720px', value: 720),
    (label: '480px', value: 480),
    (label: '360px', value: 360),
    (label: '240px', value: 240),
    (label: '180px', value: 180),
    (label: '120px', value: 120),
    (label: '100px', value: 100),
    (label: '50px', value: 50),
  ];

  /// 远程图片预览宽度预设列表（比封面更高分辨率）。
  static const remoteImageWidthPresets = [
    (label: '原图', value: 0),
    (label: '1920px', value: 1920),
    (label: '1080px', value: 1080),
    (label: '720px', value: 720),
    (label: '480px', value: 480),
    (label: '360px', value: 360),
  ];

  /// 本地图片列表预览宽度预设列表。
  static const localPreviewWidthPresets = [
    (label: '原图', value: 0),
    (label: '1080px', value: 1080),
    (label: '720px', value: 720),
    (label: '480px', value: 480),
    (label: '360px', value: 360),
    (label: '240px', value: 240),
  ];

  static const levels = [
    ThumbQualityLevel(label: '极低', scaleWidth: 120, qv: 10, frameCount: 3, frameCountFallback: 2),
    ThumbQualityLevel(label: '低', scaleWidth: 180, qv: 8, frameCount: 4, frameCountFallback: 2),
    ThumbQualityLevel(label: '中', scaleWidth: 240, qv: 6, frameCount: 6, frameCountFallback: 3),
    ThumbQualityLevel(label: '高', scaleWidth: 360, qv: 4, frameCount: 6, frameCountFallback: 3),
    ThumbQualityLevel(label: '超高', scaleWidth: 480, qv: 3, frameCount: 8, frameCountFallback: 4),
  ];

  ThumbQualityLevel get currentLevel => levels[(quality.value - 1).clamp(0, levels.length - 1)];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    quality.value = (prefs.getInt(_keyQuality) ?? 3).clamp(1, 5);
    concurrency.value = (prefs.getInt(_keyConcurrency) ?? 2).clamp(1, 20);
    remoteCoverWidth.value = prefs.getInt(_keyRemoteCoverWidth) ?? 240;
    remoteImageWidth.value = prefs.getInt(_keyRemoteImageWidth) ?? 0;
    localPreviewWidth.value = prefs.getInt(_keyLocalPreviewWidth) ?? 480;
    cacheLimitBytes.value = prefs.getInt(_keyCacheLimitBytes) ?? (1 * 1024 * 1024 * 1024);
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

  /// 设置远程封面拉取宽度，0 表示原图。
  Future<void> setRemoteCoverWidth(int v) async {
    remoteCoverWidth.value = v < 0 ? 0 : v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRemoteCoverWidth, remoteCoverWidth.value);
  }

  /// 设置远程图片预览拉取宽度，0 表示原图。
  Future<void> setRemoteImageWidth(int v) async {
    remoteImageWidth.value = v < 0 ? 0 : v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRemoteImageWidth, remoteImageWidth.value);
  }

  /// 设置本地图片列表预览宽度（cacheWidth），0 表示原图。
  Future<void> setLocalPreviewWidth(int v) async {
    localPreviewWidth.value = v < 0 ? 0 : v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLocalPreviewWidth, localPreviewWidth.value);
  }

  /// 设置缓存大小上限（字节），0 表示不限制。
  Future<void> setCacheLimitBytes(int v) async {
    cacheLimitBytes.value = v < 0 ? 0 : v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCacheLimitBytes, cacheLimitBytes.value);
  }

  /// 返回所有媒体缓存目录（视频帧缩略图 + 封面图缩略图）。
  /// 路径结构：`AppSupport/SlimeWorks/library/media/{thumbnails,covers}`
  Future<List<Directory>> getCacheDirs() async {
    final appDir = await getApplicationSupportDirectory();
    // 兼容旧路径（直接在 appDir 下）和新路径（library/media 子目录）
    final base = '${appDir.path}${Platform.pathSeparator}';
    return [
      Directory('${base}library${Platform.pathSeparator}media${Platform.pathSeparator}thumbnails'),
      Directory('${base}library${Platform.pathSeparator}media${Platform.pathSeparator}covers'),
      // 旧路径保留用于计算（不再写入，但可能存在旧缓存文件）
      Directory('${base}thumbnails'),
      Directory('${base}cover_thumb_cache'),
    ];
  }

  /// 返回对用户展示的权威缓存根目录（新结构）。
  Future<Directory> getMediaCacheBaseDir() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory(
      '${appDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}media',
    );
  }

  /// 计算所有缩略图缓存目录大小（字节），包含旧路径兼容计算。
  Future<int> calcCacheSizeBytes() async {
    try {
      int total = 0;
      for (final dir in await getCacheDirs()) {
        if (!dir.existsSync()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              total += entity.lengthSync();
            } catch (_) {}
          }
        }
      }
      return total;
    } catch (e) {
      _logger.error('[MediaPrefs] calcCacheSizeBytes error: $e');
      return 0;
    }
  }

  /// 清空所有缓存目录（含旧路径）。
  Future<void> clearCache() async {
    try {
      for (final dir in await getCacheDirs()) {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
      _logger.info('[MediaPrefs] 缓存已清除');
    } catch (e) {
      _logger.error('[MediaPrefs] clearCache error: $e');
    }
  }

  /// 检查缓存大小，若超过 [cacheLimitBytes] 则删除最旧的文件，删到上限的 50%。
  /// [cacheLimitBytes] 为 0 时跳过检查。
  Future<void> trimCacheToLimit() async {
    final limitBytes = cacheLimitBytes.value;
    if (limitBytes <= 0) return; // 0 = 无限制

    try {
      // 收集所有缓存文件及其修改时间
      final files = <({File file, DateTime modified, int size})>[];
      int totalBytes = 0;

      for (final dir in await getCacheDirs()) {
        if (!dir.existsSync()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          try {
            final stat = entity.statSync();
            files.add((file: entity, modified: stat.modified, size: stat.size));
            totalBytes += stat.size;
          } catch (_) {}
        }
      }

      if (totalBytes <= limitBytes) return; // 未超限，无需清理

      // 按修改时间升序（最旧的在前）
      files.sort((a, b) => a.modified.compareTo(b.modified));

      final targetBytes = limitBytes ~/ 2; // 删到 50%
      int deletedBytes = 0;

      for (final entry in files) {
        if (totalBytes - deletedBytes <= targetBytes) break;
        try {
          entry.file.deleteSync();
          deletedBytes += entry.size;
        } catch (_) {}
      }

      _logger.info(
        '[MediaPrefs] trimCacheToLimit: 删除 ${(deletedBytes / 1024 / 1024).toStringAsFixed(1)} MB'
        '  (剩余 ${((totalBytes - deletedBytes) / 1024 / 1024).toStringAsFixed(1)} MB)',
      );
    } catch (e) {
      _logger.error('[MediaPrefs] trimCacheToLimit error: $e');
    }
  }
}
