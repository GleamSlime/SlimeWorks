import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class AppUpdateService {
  static const String _feedUrl =
      'https://gleamslime.github.io/SlimeWorks/appcast.xml';
  static const String _feedHost = 'gleamslime.github.io';

  // 自动更新偏好键
  static const String _prefKeyAutoUpdate = 'auto_update_enabled';
  // 闲置判定阈值：5 分钟无交互视为闲置
  static const Duration _idleThreshold = Duration(minutes: 5);
  // 闲置轮询周期：每分钟检查一次闲置状态
  static const Duration _idlePollInterval = Duration(minutes: 1);
  // Sparkle 内置定时检查间隔（秒）
  static const int _sparkleCheckIntervalSec = 3600;

  final Loggers _logger = Loggers(name: '应用更新');
  final Dio _probeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  final RxBool isChecking = false.obs;
  final Rx<AppUpdateInfo?> updateInfo = Rx<AppUpdateInfo?>(null);
  // 自动更新开关（持久化到 SharedPreferences）
  final RxBool autoUpdateEnabled = false.obs;
  // 最近一次检查是否发现新版本（供 UI 判断提示语）
  bool lastCheckHadUpdate = false;

  bool _feedUrlSet = false;
  DateTime _lastActiveTime = DateTime.now();
  Timer? _idleCheckTimer;

  /// 从 SharedPreferences 加载偏好，启动时调用
  Future<void> loadPrefs() async {
    // Debug 模式下禁用更新检查（避免开发期间弹出更新提示）
    if (kDebugMode) return;
    if (!Platform.isMacOS && !Platform.isWindows) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoUpdateEnabled.value = prefs.getBool(_prefKeyAutoUpdate) ?? false;
      _logger.info(
        '[应用更新] 加载偏好: autoUpdate=${autoUpdateEnabled.value}',
      );
      if (autoUpdateEnabled.value) {
        startAutoCheck();
      }
    } catch (e) {
      _logger.error('[应用更新] 加载偏好失败: $e');
    }
  }

  /// 切换自动更新开关
  Future<void> setAutoUpdateEnabled(bool enabled) async {
    if (autoUpdateEnabled.value == enabled) return;
    autoUpdateEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyAutoUpdate, enabled);
    } catch (e) {
      _logger.error('[应用更新] 保存开关失败: $e');
    }
    if (enabled) {
      startAutoCheck();
    } else {
      stopAutoCheck();
    }
  }

  /// 启动自动检查：闲置定时器 + Sparkle 内置定时检查
  void startAutoCheck() {
    if (!Platform.isMacOS && !Platform.isWindows) return;
    _idleCheckTimer?.cancel();
    _lastActiveTime = DateTime.now();
    _idleCheckTimer = Timer.periodic(_idlePollInterval, (_) => _maybeIdleCheck());
    // 设置 Sparkle 内置定时检查（每小时一次）
    _ensureFeedUrlSet();
    autoUpdater.setScheduledCheckInterval(_sparkleCheckIntervalSec);
    _logger.info(
      '[应用更新] 已启动自动检查（闲置阈值 ${_idleThreshold.inMinutes} 分钟）',
    );
  }

  /// 停止自动检查
  void stopAutoCheck() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = null;
    // 关闭 Sparkle 内置定时检查
    autoUpdater.setScheduledCheckInterval(0);
    _logger.info('[应用更新] 已停止自动检查');
  }

  /// 由 main.dart 在 AppLifecycleState 变化时调用
  void onLifecycleStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastActiveTime = DateTime.now();
    }
  }

  /// 用户最近交互时间更新（如鼠标活动检测可调用）
  void markUserActive() {
    _lastActiveTime = DateTime.now();
  }

  /// 闲置检查：达到阈值且开关开启时触发一次自动检查
  Future<void> _maybeIdleCheck() async {
    if (!autoUpdateEnabled.value || isChecking.value) return;
    final idleDuration = DateTime.now().difference(_lastActiveTime);
    if (idleDuration < _idleThreshold) return;

    _logger.info(
      '[应用更新] 检测到闲置 ${idleDuration.inMinutes} 分钟，开始自动检查',
    );
    await _performAutoCheck();
  }

  Future<void> _ensureFeedUrlSet() async {
    if (_feedUrlSet) return;
    final reachable = await _probeFeedUrl();
    if (!reachable) {
      _logger.info('[应用更新] 更新服务器不可达，跳过 feedURL 设置');
      return;
    }
    await autoUpdater.setFeedURL(_feedUrl);
    _feedUrlSet = true;
  }

  /// 自动检查：发现新版本后直接走原生下载安装流程，不弹自定义 dialog
  Future<void> _performAutoCheck() async {
    if (isChecking.value) return;
    isChecking.value = true;
    try {
      final reachable = await _probeFeedUrl();
      if (!reachable) {
        _logger.info('[应用更新] 自动检查：服务器不可达');
        return;
      }
      final info = await _fetchAppcast();
      if (info == null) {
        _logger.info('[应用更新] 自动检查：appcast.xml 解析失败');
        return;
      }

      final currentBuild = int.tryParse(AppInfoService.buildNumber) ?? 0;
      final remoteBuild = int.tryParse(info.buildNumber) ?? 0;
      if (remoteBuild <= currentBuild) {
        _logger.info('[应用更新] 自动检查：已是最新版本');
        return;
      }

      updateInfo.value = info;
      _logger.info(
        '[应用更新] 自动检查：发现新版本 v${info.version}+${info.buildNumber}，触发原生下载安装',
      );
      // 直接触发原生 Sparkle/WinSparkle 流程，自动下载并提示安装
      await _ensureFeedUrlSet();
      autoUpdater.checkForUpdates();
    } catch (e) {
      _logger.error('[应用更新] 自动检查失败: $e');
    } finally {
      isChecking.value = false;
    }
  }

  /// 用户主动触发检查更新（设置页"立即检查"按钮）
  Future<void> checkForUpdates({bool silent = true}) async {
    // Debug 模式下不弹更新提示
    if (kDebugMode) {
      _logger.info('[应用更新] Debug 模式，跳过更新检查');
      return;
    }
    if (isChecking.value) return;
    isChecking.value = true;
    lastCheckHadUpdate = false;

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
        // appcast.xml 解析失败时静默跳过，不回退原生检查（避免 Sparkle 弹出错误弹窗）
        _logger.info('[应用更新] 无法解析 appcast.xml，跳过检查');
        return;
      }

      final currentBuild = int.tryParse(AppInfoService.buildNumber) ?? 0;
      final remoteBuild = int.tryParse(info.buildNumber) ?? 0;

      if (remoteBuild <= currentBuild) {
        _logger.info('[应用更新] 已是最新版本');
        return;
      }

      updateInfo.value = info;
      lastCheckHadUpdate = true;

      // 有更新时弹出自定义弹窗，用户点击"立即更新"后走原生下载流程
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        _showUpdateDialog(context, info);
      }
      // 无 context 时不回退原生检查，避免 Sparkle 弹出错误弹窗
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
              // 用户主动触发更新时才调用原生检查，并启用定时检查
              autoUpdater.checkForUpdates();
              autoUpdater.setScheduledCheckInterval(3600);
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
