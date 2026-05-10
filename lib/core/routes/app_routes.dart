import 'package:slime_works/core/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/pages/capture_screen_page.dart';
import 'package:slime_works/pages/collection/library/collection_library_screen.dart';
import 'package:slime_works/pages/collection/picture/collection_picture_screen.dart';
import 'package:slime_works/pages/demo/gooey_dropdown_demo_page.dart';
import 'package:slime_works/pages/demo/viewmodel_demo_page.dart';
import 'package:slime_works/pages/novel_library/novel_library_page.dart';
import 'package:slime_works/pages/novel_reader/novel_reader_page.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/core/widgets/binding_widget.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/pages/theme_preview_screen.dart';
import 'package:slime_works/pages/dashboard_screen.dart';
import 'package:slime_works/pages/module_management_screen.dart';
import 'package:slime_works/pages/websocket_test_page.dart';
import 'package:slime_works/pages/http_bridge_test_page.dart';
import 'package:slime_works/pages/settings/settings_page.dart';
import 'package:slime_works/pages/lan_transfer/lan_transfer_screen.dart';
import 'package:slime_works/pages/lan_transfer/lan_chat_screen.dart';
import 'package:slime_works/pages/game_library/home/game_library_home_screen.dart';
import 'package:slime_works/pages/game_library/library/game_library_screen.dart';
import 'package:slime_works/pages/game_library/detail/game_detail_screen.dart';
import 'package:slime_works/pages/game_library/categories/game_categories_screen.dart';
import 'package:slime_works/pages/game_library/categories/game_category_detail_screen.dart';
import 'package:slime_works/pages/game_library/stats/game_stats_screen.dart';
import 'package:slime_works/pages/game_library/settings/game_settings_screen.dart';
import 'package:slime_works/pages/picacg/picacg_home_screen.dart';
import 'package:slime_works/pages/picacg/picacg_comic_detail_screen.dart';
import 'package:slime_works/pages/picacg/picacg_history_screen.dart';
import 'package:slime_works/pages/picacg/search/picacg_search_screen.dart';
import 'package:slime_works/pages/picacg/reader/picacg_reader_screen.dart';
import 'package:slime_works/pages/picacg/picacg_downloads_screen.dart';
import 'package:slime_works/pages/about/about_page.dart';

part 'app_routes.g.dart';

// 路由模块化拆分
part 'routes/core_routes.dart';
part 'routes/novel_routes.dart';
part 'routes/business_routes.dart';
part 'routes/test_routes.dart';
part 'routes/tools_routes.dart';
part 'routes/placeholder_routes.dart';
part 'routes/collection_routes.dart';
part 'routes/demo_routes.dart';
part 'routes/capture_routers.dart';
part 'routes/lan_transfer_routes.dart';
part 'routes/picacg_routes.dart';
part 'routes/game_library_routes.dart';

// // 导航到 Dashboard
// DashboardRoute().go(context);

// // 导航到书籍阅读器（带参数）
// NovelReaderRoute($extra: novelMetadata).go(context);

// // Push 导航
// const CaptureRoute().push(context);

// // 替换导航
// const SettingsRoute().pushReplacement(context);

/// 路由路径常量
class Routes {
  Routes._();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 应用路由配置
class AppRoutes {
  AppRoutes._();

  // 全局 router 实例，供无法访问 context 的地方使用
  static GoRouter? router;

  /// 创建 GoRouter 实例
  static GoRouter createRouter() {
    if (router != null) return router!;

    final controller = Get.put(SidebarController());

    // 路由构造器列表
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
      const LanTransferRoute(),
      const LanChatRoute(peerId: '', peerName: ''),

      const GameHomeRoute(),
      const GameLibraryRoute(),
      const GameCategoriesRoute(),
      const GameStatsRoute(),
      const GameSettingsRoute(),
      const GameDetailRoute(gameId: ''),
      const GameCategoryDetailRoute(categoryId: ''),

      const GooeyDemoRoute(),
      const ViewModelDemoRoute(),

      const PicAcgHomeRoute(),
      const PicAcgComicDetailRoute(comicId: ''),
      const PicAcgSearchRoute(),
      const PicAcgReaderRoute(comicId: '', epsOrder: 0),
      const PicAcgDownloadsRoute(),
    ];

    router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        ShellRoute(
          builder: (context, state, child) => DesktopLayout(child: child),
          routes: $appRoutes,
        ),
      ],
      navigatorKey: navigatorKey,
      debugLogDiagnostics: true,
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
            debugPrint('无权限访问 $path (需要 $permission)，重定向到 /dashboard');
            return '/dashboard';
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 如果是阅读器页面，则侧边栏保持"书库"高亮
          if (path == '/novel-reader') {
            controller.selectedRoute.value = '/collection/library';
          } else {
            controller.selectedRoute.value = path;
          }
        });

        return null; // 无重定向
      },
    );
    return router!;
  }

  static const Duration kTransitionDuration = Duration(milliseconds: 220);
  static const Duration kReverseTransitionDuration = Duration(milliseconds: 180);
  static const Duration kSlowTransitionDuration = Duration(milliseconds: 320);
  static const Duration kSlowReverseTransitionDuration = Duration(milliseconds: 260);

  /// 构建带过渡动画的页面
  static Page<dynamic> buildPage(BuildContext context, GoRouterState state, Widget child) {
    if (Platform.isIOS) {
      return CupertinoPage(
        key: state.pageKey,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: BindingWidget(child: child),
        ),
      );
    }
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: kTransitionDuration,
      reverseTransitionDuration: kReverseTransitionDuration,
      child: BindingWidget(child: child),
      transitionsBuilder: _defaultTransitionsBuilder,
    );
  }

  /// 构建纯淡入过渡页面（适用于详情页等需要较慢过渡的场景）
  static Page<dynamic> buildFadePage(BuildContext context, GoRouterState state, Widget child) {
    if (Platform.isIOS) {
      return CupertinoPage(
        key: state.pageKey,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: BindingWidget(child: child),
        ),
      );
    }
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: kSlowTransitionDuration,
      reverseTransitionDuration: kSlowReverseTransitionDuration,
      child: BindingWidget(child: child),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
            child: child,
          ),
        );
      },
    );
  }

  static Widget _defaultTransitionsBuilder(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final scale = Tween(begin: 0.985, end: 1.0).animate(curved);
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }

  /// 构建占位页面
  static Widget buildPlaceholder(String title) {
    return Scaffold(
      body: Center(child: Text('$title 页面开发中...', style: TextStyle(fontSize: AppTheme.metrics.fontSize22))),
    );
  }
}

// 向后兼容 - 导出一个全局 goRouter 实例
final goRouter = AppRoutes.createRouter();

abstract class AppRouteData extends GoRouteData {
  const AppRouteData();

  /// 标题
  String get title;

  /// 侧边栏图标路径
  String? get sidebarIcon;

  /// 侧边栏标签
  String get sidebarLabel => title;

  /// 侧边栏提示
  String? get sidebarTooltip => sidebarLabel;

  /// 侧边栏排序
  int? get sidebarOrder => null;

  /// 侧边栏徽章数量
  int? get sidebarBadgeCount => null;

  /// 权限
  Permission? get permission => AppRouteData.routePermission;

  /// 路由权限
  static Permission routePermission = Permission.viewDashboard;
}
