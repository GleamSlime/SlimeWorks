import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/components/window/theme_preview_screen.dart';
import 'package:slime_works/pages/dashboard_screen.dart';

/// 应用路由配置
class AppRoutes {
  AppRoutes._();

  // 路由名称常量
  static const String dashboard = '/dashboard';
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

  /// 获取所有路由
  static List<GetPage> getPages() {
    return [
      GetPage(
        name: dashboard,
        page: () => const DashboardScreen(),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: themePreview,
        page: () => const ThemePreviewScreen(),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: datasource,
        page: () => _buildPlaceholderPage('数据源'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: clearwater,
        page: () => _buildPlaceholderPage('清水账'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: aliyun,
        page: () => _buildPlaceholderPage('阿里云'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: imageTools,
        page: () => _buildPlaceholderPage('图片工具'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: imageToolbox,
        page: () => _buildPlaceholderPage('图片工具盒'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: mediaLibrary,
        page: () => _buildPlaceholderPage('媒体库'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: cloudWord,
        page: () => _buildPlaceholderPage('云词间'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: distributed,
        page: () => _buildPlaceholderPage('分布式算'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: requestHost,
        page: () => _buildPlaceholderPage('请求托管'),
        transition: Transition.fadeIn,
      ),
      GetPage(
        name: settings,
        page: () => _buildPlaceholderPage('设置'),
        transition: Transition.fadeIn,
      ),
    ];
  }

  /// 构建占位页面
  static DesktopLayout _buildPlaceholderPage(String title) {
    return DesktopLayout(
      title: title,
      child: Center(
        child: Text('$title 页面开发中...', style: Get.textTheme.headlineSmall),
      ),
    );
  }
}
