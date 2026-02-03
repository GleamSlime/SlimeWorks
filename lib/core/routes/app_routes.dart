import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/pages/theme_preview_screen.dart';
import 'package:slime_works/pages/dashboard_screen.dart';
import 'package:slime_works/pages/backup/capture_screen.dart';
import 'package:slime_works/pages/module_management_screen.dart';
import 'package:slime_works/pages/websocket_test_page.dart';
import 'package:slime_works/pages/novel_library/novel_library_page.dart';
import 'package:slime_works/pages/novel_reader/novel_reader_page.dart';
import 'package:slime_works/pages/http_bridge_test_page.dart';
import 'package:slime_works/pages/settings/settings_page.dart';

/// 应用路由配置
class AppRoutes {
  AppRoutes._();

  // 路由名称常量
  static const String dashboard = '/dashboard';
  static const String capture = '/capture';
  static const String moduleManagement = '/module-management';
  static const String datasource = '/datasource';
  static const String clearwater = '/clearwater';
  static const String aliyun = '/aliyun';
  static const String imageTools = '/image-tools';
  static const String imageToolbox = '/image-toolbox';
  static const String mediaLibrary = '/media-library';
  static const String cloudWord = '/cloud-word';
  static const String distributed = '/distributed';
  static const String requestHost = '/request-host';
  static const String settings = '/settings';
  static const String themePreview = '/theme-preview';
  static const String webSocketTest = '/websocket-test';
  static const String httpBridgeTest = '/http-bridge-test';
  static const String novelLibrary = '/novel-library';
  static const String novelReader = '/novel-reader';

  /// 获取所有路由
  static List<GetPage> getPages() {
    return [
      GetPage(name: dashboard, page: () => const DashboardScreen(), transition: Transition.fadeIn),
      GetPage(name: capture, page: () => const CaptureScreen(), transition: Transition.fadeIn),
      GetPage(name: moduleManagement, page: () => const ModuleManagementScreen(), transition: Transition.fadeIn),
      GetPage(name: novelLibrary, page: () => const NovelLibraryPage(), transition: Transition.fadeIn),
      GetPage(name: novelReader, page: () => const NovelReaderPage(), transition: Transition.fadeIn),
      GetPage(name: themePreview, page: () => const ThemePreviewScreen(), transition: Transition.fadeIn),
      GetPage(name: httpBridgeTest, page: () => const HttpBridgeTestPage(), transition: Transition.fadeIn),
      GetPage(name: webSocketTest, page: () => const WebSocketTestPage(), transition: Transition.fadeIn),
      GetPage(name: datasource, page: () => _buildPlaceholderPage('数据源'), transition: Transition.fadeIn),
      GetPage(name: clearwater, page: () => _buildPlaceholderPage('清水账'), transition: Transition.fadeIn),
      GetPage(name: aliyun, page: () => _buildPlaceholderPage('阿里云'), transition: Transition.fadeIn),
      GetPage(name: imageTools, page: () => _buildPlaceholderPage('图片工具'), transition: Transition.fadeIn),
      GetPage(name: imageToolbox, page: () => _buildPlaceholderPage('图片工具盒'), transition: Transition.fadeIn),
      GetPage(name: mediaLibrary, page: () => _buildPlaceholderPage('媒体库'), transition: Transition.fadeIn),
      GetPage(name: cloudWord, page: () => _buildPlaceholderPage('云词间'), transition: Transition.fadeIn),
      GetPage(name: distributed, page: () => _buildPlaceholderPage('分布式算'), transition: Transition.fadeIn),
      GetPage(name: requestHost, page: () => _buildPlaceholderPage('请求托管'), transition: Transition.fadeIn),
      GetPage(name: settings, page: () => const SettingsPage(), transition: Transition.fadeIn),
    ];
  }

  /// 构建占位页面
  static Widget _buildPlaceholderPage(String title) {
    return Center(child: Text('$title 页面开发中...', style: Get.textTheme.headlineSmall));
  }
}
