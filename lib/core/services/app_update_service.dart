import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:auto_updater/auto_updater.dart';

class AppUpdateService {
  static const String _feedUrl =
      'https://gleamslime.github.io/slime_works/appcast.xml';
  static const String _feedHost = 'gleamslime.github.io';

  final Loggers _logger = Loggers(name: '应用更新');
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  final RxBool isChecking = false.obs;
  final Rx<AppUpdateInfo?> updateInfo = Rx<AppUpdateInfo?>(null);

  bool _feedUrlSet = false;

  Future<void> checkForUpdates({bool silent = true}) async {
    if (isChecking.value) return;
    isChecking.value = true;

    try {
      final reachable = await _probeFeedUrl();
      if (!reachable) {
        _logger.info('[应用更新] 更新服务器不可达，跳过检查');
        return;
      }

      // 域名可达才设置 feedURL（避免 Sparkle 在后台自动弹出错误）
      if (!_feedUrlSet) {
        await autoUpdater.setFeedURL(_feedUrl);
        _feedUrlSet = true;
      }

      final info = await _fetchAppcast();
      if (info == null) {
        _logger.info('[应用更新] 无法解析 appcast.xml，回退原生检查');
        await _fallbackNativeCheck(silent: silent);
        return;
      }

      final currentBuild = int.tryParse(AppInfoService.buildNumber) ?? 0;
      final remoteBuild = int.tryParse(info.buildNumber) ?? 0;

      if (remoteBuild <= currentBuild) {
        _logger.info('[应用更新] 已是最新版本');
        // 即使是最新版也设置定时检查，保持后台自动更新能力
        await autoUpdater.setScheduledCheckInterval(3600);
        return;
      }

      updateInfo.value = info;

      if (silent) {
        // 静默模式：有更新时弹出自定义弹窗，用户点击后走原生下载流程
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          _showUpdateDialog(context, info);
        } else {
          await autoUpdater.checkForUpdates();
        }
      } else {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          _showUpdateDialog(context, info);
        } else {
          await autoUpdater.checkForUpdates();
        }
      }
    } catch (e) {
      _logger.error('[应用更新] 检查更新失败: $e');
    } finally {
      isChecking.value = false;
    }
  }

  Future<bool> _probeFeedUrl() async {
    try {
      final result = await InternetAddress.lookup(_feedHost);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      try {
        await _probeDio.head<dynamic>('https://$_feedHost');
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> _fallbackNativeCheck({bool silent = true}) async {
    try {
      await autoUpdater.checkForUpdates();
      await autoUpdater.setScheduledCheckInterval(3600);
    } catch (e) {
      _logger.error('[应用更新] 原生检查失败: $e');
    }
  }

  Future<AppUpdateInfo?> _fetchAppcast() async {
    try {
      final response = await _probeDio.get<String>(_feedUrl);
      if (response.statusCode != 200 || response.data == null) return null;

      final xml = response.data!;
      return _parseAppcast(xml);
    } catch (e) {
      _logger.error('[应用更新] 获取 appcast.xml 失败: $e');
      return null;
    }
  }

  AppUpdateInfo? _parseAppcast(String xml) {
    try {
      final titleMatch = RegExp(r'<title>\s*(.*?)\s*</title>').firstMatch(xml);
      final descMatch =
          RegExp(r'<!\[CDATA\[(.*?)\]\]>').firstMatch(xml) ??
          RegExp(r'<description>\s*(.*?)\s*</description>').firstMatch(xml);
      final versionMatch = RegExp(
        r'sparkle:shortVersionString="([^"]+)"',
      ).firstMatch(xml);
      final buildMatch = RegExp(r'sparkle:version="([^"]+)"').firstMatch(xml);
      final urlMatch = RegExp(r'url="([^"]+)"').firstMatch(xml);

      if (versionMatch == null || buildMatch == null) return null;

      return AppUpdateInfo(
        version: versionMatch.group(1) ?? '',
        buildNumber: buildMatch.group(1) ?? '',
        title: titleMatch?.group(1) ?? '',
        description: descMatch?.group(1)?.trim() ?? '',
        downloadUrl: urlMatch?.group(1) ?? '',
      );
    } catch (e) {
      _logger.error('[应用更新] 解析 appcast.xml 失败: $e');
      return null;
    }
  }

  void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: m.radius12),
        title: Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              size: m.iconSize24,
              color: theme.colorScheme.primary,
            ),
            SizedBox(width: m.kSpace8),
            Text('发现新版本', style: TextStyle(fontSize: m.fontSize18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${info.version} (Build ${info.buildNumber})',
              style: TextStyle(
                fontSize: m.fontSize15,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            if (info.description.isNotEmpty) ...[
              SizedBox(height: m.kSpace8),
              Container(
                constraints: BoxConstraints(maxHeight: scaleW(200)),
                child: SingleChildScrollView(
                  child: Text(
                    info.description,
                    style: TextStyle(fontSize: m.fontSize13),
                  ),
                ),
              ),
            ],
            SizedBox(height: m.kSpace4),
            Text(
              '当前版本: v${AppInfoService.version} (Build ${AppInfoService.buildNumber})',
              style: TextStyle(
                fontSize: m.fontSize12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('稍后提醒', style: TextStyle(fontSize: m.fontSize13)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              autoUpdater.checkForUpdates();
            },
            child: Text('立即更新', style: TextStyle(fontSize: m.fontSize13)),
          ),
        ],
      ),
    );
  }
}

class AppUpdateInfo {
  final String version;
  final String buildNumber;
  final String title;
  final String description;
  final String downloadUrl;

  AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.title,
    required this.description,
    required this.downloadUrl,
  });
}
