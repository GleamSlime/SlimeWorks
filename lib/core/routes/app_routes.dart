import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/widgets/binding_widget.dart';
import 'package:slime_works/core/routes/role_manager.dart';
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

/// 路由路径常量
class Routes {
  Routes._();

  static const dashboard = '/dashboard';
  static const capture = '/capture';
  static const moduleManagement = '/module-management';
  static const novelLibrary = '/novel-library';
  static const novelReader = '/novel-reader';
  static const themePreview = '/theme-preview';
  static const httpBridgeTest = '/http-bridge-test';
  static const webSocketTest = '/websocket-test';
  static const settings = '/settings';
  static const datasource = '/datasource';
  static const clearwater = '/clearwater';
  static const aliyun = '/aliyun';
  static const imageTools = '/image-tools';
  static const imageToolbox = '/image-toolbox';
  static const mediaLibrary = '/media-library';
  static const cloudWord = '/cloud-word';
  static const distributed = '/distributed';
  static const requestHost = '/request-host';
}

/// 应用路由配置
class AppRoutes {
  AppRoutes._();

  // 全局 router 实例，供无法访问 context 的地方使用
  static GoRouter? router;

  /// 创建 GoRouter 实例
  static GoRouter createRouter() {
    // 如果已创建则直接返回，避免重复初始化 late 字段导致的错误
    if (router != null) return router!;

    router = GoRouter(
      initialLocation: Routes.dashboard,
      routes: [
        GoRoute(path: Routes.dashboard, pageBuilder: (context, state) => _buildPage(context, state, const DashboardScreen())),
        GoRoute(path: Routes.capture, pageBuilder: (context, state) => _buildPage(context, state, const CaptureScreen())),
        GoRoute(path: Routes.moduleManagement, pageBuilder: (context, state) => _buildPage(context, state, const ModuleManagementScreen())),
        GoRoute(path: Routes.novelLibrary, pageBuilder: (context, state) => _buildPage(context, state, const NovelLibraryPage())),
        GoRoute(
          path: Routes.novelReader,
          pageBuilder: (context, state) => _buildPage(context, state, NovelReaderPage(novel: state.extra as NovelMetadata?)),
        ),
        GoRoute(path: Routes.themePreview, pageBuilder: (context, state) => _buildPage(context, state, const ThemePreviewScreen())),
        GoRoute(path: Routes.httpBridgeTest, pageBuilder: (context, state) => _buildPage(context, state, const HttpBridgeTestPage())),
        GoRoute(path: Routes.webSocketTest, pageBuilder: (context, state) => _buildPage(context, state, const WebSocketTestPage())),
        GoRoute(path: Routes.settings, pageBuilder: (context, state) => _buildPage(context, state, const SettingsPage())),
        GoRoute(path: Routes.datasource, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('数据源'))),
        GoRoute(path: Routes.clearwater, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('清水账'))),
        GoRoute(path: Routes.aliyun, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('阿里云'))),
        GoRoute(path: Routes.imageTools, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('图片工具'))),
        GoRoute(path: Routes.imageToolbox, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('图片工具盒'))),
        GoRoute(path: Routes.mediaLibrary, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('媒体库'))),
        GoRoute(path: Routes.cloudWord, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('云词间'))),
        GoRoute(path: Routes.distributed, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('分布式算'))),
        GoRoute(path: Routes.requestHost, pageBuilder: (context, state) => _buildPage(context, state, _buildPlaceholder('请求托管'))),
      ],
      redirect: (context, state) {
        // 权限检查 - 在路由级别进行权限控制
        final path = state.uri.path;
        final role = RoleManager.currentUserRole;

        // Module Management 需要管理用户权限
        if (path == Routes.moduleManagement && !RoleManager.hasPermission(role, Permission.manageUsers)) {
          return Routes.dashboard;
        }

        // Settings 需要访问设置权限
        if (path == Routes.settings && !RoleManager.hasPermission(role, Permission.accessSettings)) {
          return Routes.dashboard;
        }

        return null; // 无重定向
      },
    );
    return router!;
  }

  /// 构建带过渡动画的页面
  static Page<dynamic> _buildPage(BuildContext context, GoRouterState state, Widget child) {
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
  static Widget _buildPlaceholder(String title) {
    return Scaffold(
      body: Center(child: Text('$title 页面开发中...', style: const TextStyle(fontSize: 24))),
    );
  }
}

// 向后兼容 - 导出一个全局 goRouter 实例
final goRouter = AppRoutes.createRouter();

