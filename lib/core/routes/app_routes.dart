import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/widgets/binding_widget.dart';
import 'package:slime_works/pages/theme_preview_screen.dart';
import 'package:slime_works/pages/dashboard_screen.dart';
import 'package:slime_works/pages/backup/capture_screen.dart';
import 'package:slime_works/pages/module_management_screen.dart';
import 'package:slime_works/pages/websocket_test_page.dart';
import 'package:slime_works/pages/novel_library/novel_library_page.dart';
import 'package:slime_works/pages/novel_reader/novel_reader_page.dart';
import 'package:slime_works/pages/http_bridge_test_page.dart';
import 'package:slime_works/pages/settings/settings_page.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

final goRouter = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    GoRoute(path: AppRoutes.dashboard, name: 'dashboard', pageBuilder: (context, state) => AppRoutes.page(context, state, const DashboardScreen())),
    GoRoute(path: AppRoutes.capture, name: 'capture', pageBuilder: (context, state) => AppRoutes.page(context, state, const CaptureScreen())),
    GoRoute(
      path: AppRoutes.moduleManagement,
      name: 'module-management',
      pageBuilder: (context, state) => AppRoutes.page(context, state, const ModuleManagementScreen()),
    ),
    GoRoute(
      path: AppRoutes.novelLibrary,
      name: 'novel-library',
      pageBuilder: (context, state) => AppRoutes.page(context, state, const NovelLibraryPage()),
    ),
    GoRoute(
      path: AppRoutes.novelReader,
      name: 'novel-reader',
      pageBuilder: (context, state) => AppRoutes.page(context, state, NovelReaderPage(novel: state.extra as NovelMetadata?)),
    ),
    GoRoute(
      path: AppRoutes.themePreview,
      name: 'theme-preview',
      pageBuilder: (context, state) => AppRoutes.page(context, state, const ThemePreviewScreen()),
    ),
    GoRoute(
      path: AppRoutes.httpBridgeTest,
      name: 'http-bridge-test',
      pageBuilder: (context, state) => AppRoutes.page(context, state, const HttpBridgeTestPage()),
    ),
    GoRoute(
      path: AppRoutes.webSocketTest,
      name: 'websocket-test',
      pageBuilder: (context, state) => AppRoutes.page(context, state, const WebSocketTestPage()),
    ),
    GoRoute(
      path: AppRoutes.datasource,
      name: 'datasource',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('数据源')),
    ),
    GoRoute(
      path: AppRoutes.clearwater,
      name: 'clearwater',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('清水账')),
    ),
    GoRoute(
      path: AppRoutes.aliyun,
      name: 'aliyun',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('阿里云')),
    ),
    GoRoute(
      path: AppRoutes.imageTools,
      name: 'image-tools',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('图片工具')),
    ),
    GoRoute(
      path: AppRoutes.imageToolbox,
      name: 'image-toolbox',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('图片工具盒')),
    ),
    GoRoute(
      path: AppRoutes.mediaLibrary,
      name: 'media-library',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('媒体库')),
    ),
    GoRoute(
      path: AppRoutes.cloudWord,
      name: 'cloud-word',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('云词间')),
    ),
    GoRoute(
      path: AppRoutes.distributed,
      name: 'distributed',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('分布式算')),
    ),
    GoRoute(
      path: AppRoutes.requestHost,
      name: 'request-host',
      pageBuilder: (context, state) => AppRoutes.page(context, state, AppRoutes.placeholderPage('请求托管')),
    ),
    GoRoute(path: AppRoutes.settings, name: 'settings', pageBuilder: (context, state) => AppRoutes.page(context, state, const SettingsPage())),
  ],
);

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

  // 全局 router 实例，供无法访问 context 的地方使用
  static GoRouter? router;

  /// 构建带过渡动画的页面
  static Page<dynamic> page(BuildContext context, GoRouterState state, Widget child) {
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      child: BindingWidget(child: child),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);

        final scale = Tween(begin: 0.985, end: 1.0).animate(curved);

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: scale,
            child: Container(color: Theme.of(context).scaffoldBackgroundColor, child: child),
          ),
        );
      },
    );
  }

  /// 构建占位页面
  static Widget placeholderPage(String title) {
    return Scaffold(
      body: Center(child: Text('$title 页面开发中...', style: const TextStyle(fontSize: 24))),
    );
  }
}
