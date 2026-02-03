import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/routes/learn_routes.dart';
import 'package:slime_works/core/widgets/binding_widget.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/pages/theme_preview_screen.dart';
import 'package:slime_works/pages/dashboard_screen.dart';
import 'package:slime_works/pages/backup/capture_screen.dart';
import 'package:slime_works/pages/module_management_screen.dart';
import 'package:slime_works/pages/websocket_test_page.dart';
import 'package:slime_works/pages/http_bridge_test_page.dart';
import 'package:slime_works/pages/settings/settings_page.dart';

part 'app_routes.g.dart';

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

    final controller = Get.put(SidebarController());

    // 路由构造器列表，用于根据 path 找到对应的 GoRouteData 实例（避免 map/switch）
    final routeConstructors = <GoRouteData>[
      const DashboardRoute(),
      const CaptureRoute(),
      const ModuleManagementRoute(),
      const NovelLibraryRoute(),
      const NovelReaderRoute(),
      const ThemePreviewRoute(),
      const HttpBridgeTestRoute(),
      const WebSocketTestRoute(),
      const SettingsRoute(),
      const DatasourceRoute(),
      const ClearwaterRoute(),
      const AliyunRoute(),
      const ImageToolsRoute(),
      const ImageToolboxRoute(),
      const MediaLibraryRoute(),
      const CloudWordRoute(),
      const DistributedRoute(),
      const RequestHostRoute(),
    ];

    router = GoRouter(
      initialLocation: '/dashboard',
      routes: $appRoutes,
      redirect: (context, state) {
        // 权限检查 - 在路由级别进行权限控制
        final path = state.uri.path;
        // 查找匹配的路由实例（直接从类定义读取 permission）
        GoRouteData? matched;
        for (final route in routeConstructors) {
          if (route.location == path) {
            matched = route;
            break;
          }
        }

        if (matched != null) {
          final permission = (matched as dynamic).permission;
          if (!RoleManager.canAccess(permission)) {
            print('无权限访问 $path (需要 $permission)，重定向到 /dashboard');
            return '/dashboard';
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selectedRoute.value = path;
        });

        return null; // 无重定向
      },
    );
    return router!;
  }

  /// 构建带过渡动画的页面
  static Page<dynamic> buildPage(BuildContext context, GoRouterState state, Widget child) {
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
  static Widget buildPlaceholder(String title) {
    return Scaffold(
      body: Center(child: Text('$title 页面开发中...', style: const TextStyle(fontSize: 24))),
    );
  }
}

// 向后兼容 - 导出一个全局 goRouter 实例
final goRouter = AppRoutes.createRouter();

@TypedGoRoute<DashboardRoute>(path: '/dashboard')
class DashboardRoute extends GoRouteData with $DashboardRoute {
  const DashboardRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DashboardRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const DashboardScreen());
  }
}

@TypedGoRoute<CaptureRoute>(path: '/capture')
class CaptureRoute extends GoRouteData with $CaptureRoute {
  const CaptureRoute();

  static const Permission routePermission = Permission.accessCapture;
  Permission get permission => CaptureRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CaptureScreen());
  }
}

@TypedGoRoute<ModuleManagementRoute>(path: '/module-management')
class ModuleManagementRoute extends GoRouteData with $ModuleManagementRoute {
  const ModuleManagementRoute();

  static const Permission routePermission = Permission.manageModules;
  Permission get permission => ModuleManagementRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ModuleManagementScreen());
  }
}

@TypedGoRoute<ThemePreviewRoute>(path: '/theme-preview')
class ThemePreviewRoute extends GoRouteData with $ThemePreviewRoute {
  const ThemePreviewRoute();

  static const Permission routePermission = Permission.accessThemePreview;
  Permission get permission => ThemePreviewRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ThemePreviewScreen());
  }
}

@TypedGoRoute<HttpBridgeTestRoute>(path: '/http-bridge-test')
class HttpBridgeTestRoute extends GoRouteData with $HttpBridgeTestRoute {
  const HttpBridgeTestRoute();

  static const Permission routePermission = Permission.accessHttpBridgeTest;
  Permission get permission => HttpBridgeTestRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const HttpBridgeTestPage());
  }
}

@TypedGoRoute<WebSocketTestRoute>(path: '/websocket-test')
class WebSocketTestRoute extends GoRouteData with $WebSocketTestRoute {
  const WebSocketTestRoute();

  static const Permission routePermission = Permission.accessWebSocketTest;
  Permission get permission => WebSocketTestRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const WebSocketTestPage());
  }
}

@TypedGoRoute<SettingsRoute>(path: '/settings')
class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static const Permission routePermission = Permission.accessSettings;
  Permission get permission => SettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SettingsPage());
  }
}

@TypedGoRoute<DatasourceRoute>(path: '/datasource')
class DatasourceRoute extends GoRouteData with $DatasourceRoute {
  const DatasourceRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DatasourceRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('数据源'));
  }
}

@TypedGoRoute<ClearwaterRoute>(path: '/clearwater')
class ClearwaterRoute extends GoRouteData with $ClearwaterRoute {
  const ClearwaterRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ClearwaterRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('清水账'));
  }
}

@TypedGoRoute<AliyunRoute>(path: '/aliyun')
class AliyunRoute extends GoRouteData with $AliyunRoute {
  const AliyunRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => AliyunRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('阿里云'));
  }
}

@TypedGoRoute<ImageToolsRoute>(path: '/image-tools')
class ImageToolsRoute extends GoRouteData with $ImageToolsRoute {
  const ImageToolsRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具'));
  }
}

@TypedGoRoute<ImageToolboxRoute>(path: '/image-toolbox')
class ImageToolboxRoute extends GoRouteData with $ImageToolboxRoute {
  const ImageToolboxRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolboxRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具盒'));
  }
}

@TypedGoRoute<MediaLibraryRoute>(path: '/media-library')
class MediaLibraryRoute extends GoRouteData with $MediaLibraryRoute {
  const MediaLibraryRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => MediaLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('媒体库'));
  }
}

@TypedGoRoute<CloudWordRoute>(path: '/cloud-word')
class CloudWordRoute extends GoRouteData with $CloudWordRoute {
  const CloudWordRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => CloudWordRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('云词间'));
  }
}

@TypedGoRoute<DistributedRoute>(path: '/distributed')
class DistributedRoute extends GoRouteData with $DistributedRoute {
  const DistributedRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DistributedRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('分布式算'));
  }
}

@TypedGoRoute<RequestHostRoute>(path: '/request-host')
class RequestHostRoute extends GoRouteData with $RequestHostRoute {
  const RequestHostRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => RequestHostRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('请求托管'));
  }
}
