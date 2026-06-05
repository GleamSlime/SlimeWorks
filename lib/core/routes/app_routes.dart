import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/utils/logger.dart';

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
import 'package:slime_works/pages/game_library/home/game_hub_screen.dart';
import 'package:slime_works/pages/game_library/library/game_library_screen.dart';
import 'package:slime_works/pages/game_library/detail/game_detail_screen.dart';
import 'package:slime_works/pages/game_library/categories/game_categories_screen.dart';
import 'package:slime_works/pages/game_library/categories/game_category_detail_screen.dart';
import 'package:slime_works/pages/game_library/stats/game_stats_screen.dart';
import 'package:slime_works/pages/game_library/settings/game_settings_screen.dart';
import 'package:slime_works/pages/manga/manga_home_screen.dart';
import 'package:slime_works/pages/manga/manga_comic_detail_screen.dart';
import 'package:slime_works/pages/manga/manga_history_screen.dart';
import 'package:slime_works/pages/manga/search/manga_search_screen.dart';
import 'package:slime_works/pages/manga/reader/manga_reader_screen.dart';
import 'package:slime_works/pages/manga/manga_downloads_screen.dart';
import 'package:slime_works/pages/about/about_page.dart';
import 'package:slime_works/pages/tools/tools_screen.dart';
import 'package:slime_works/pages/sentry_log/sentry_log_screen.dart';
import 'package:slime_works/pages/aliyun_ddns/aliyun_ddns_screen.dart';
import 'package:slime_works/pages/music_player/music_player_screen.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';

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
part 'routes/manga_routes.dart';
part 'routes/game_library_routes.dart';
part 'routes/music_player_routes.dart';

const Loggers _logger = Loggers(name: '路由');

/// 路由路径常量
class Routes {
  Routes._();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();

/// 带侧边栏的 ShellRoute
@TypedShellRoute<AppShellRouteData>(
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<DashboardRoute>(path: '/dashboard'),
    TypedGoRoute<CaptureRoute>(path: '/capture'),
    TypedGoRoute<CollectionLibraryRoute>(path: '/collection/library'),
    TypedGoRoute<CollectionPictureRoute>(path: '/collection/picture'),
    TypedGoRoute<GameHomeRoute>(path: '/game/home'),
    TypedGoRoute<GameLibraryRoute>(path: '/game/library'),
    TypedGoRoute<GameCategoriesRoute>(path: '/game/categories'),
    TypedGoRoute<GameStatsRoute>(path: '/game/stats'),
    TypedGoRoute<GameSettingsRoute>(path: '/game/settings'),
    TypedGoRoute<MangaHomeRoute>(path: '/manga'),
    TypedGoRoute<MangaDownloadsRoute>(path: '/manga/downloads'),
    TypedGoRoute<MusicPlayerRoute>(path: '/music'),
    TypedGoRoute<LanTransferRoute>(path: '/lan-transfer'),
    TypedGoRoute<SettingsRoute>(path: '/settings'),
    TypedGoRoute<AboutRoute>(path: '/about'),
    TypedGoRoute<ToolsRoute>(path: '/tools'),
    TypedGoRoute<SentryLogRoute>(path: '/sentry-log'),
    TypedGoRoute<AliyunDdnsRoute>(path: '/aliyun'),
  ],
)
class AppShellRouteData extends ShellRouteData {
  const AppShellRouteData();

  static final GlobalKey<NavigatorState> $navigatorKey = shellNavigatorKey;

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return DesktopLayout(child: navigator);
  }
}

/// 应用路由配置
class AppRoutes {
  AppRoutes._();

  static GoRouter? router;

  static GoRouter createRouter() {
    if (router != null) return router!;

    final controller = Get.put(SidebarController());

    final routeConstructors = <GoRouteData>[
      const DashboardRoute(),
      const CaptureRoute(),
      const CollectionLibraryRoute(),
      const CollectionPictureRoute(),
      const GameHomeRoute(),
      const GameLibraryRoute(),
      const GameCategoriesRoute(),
      const GameStatsRoute(),
      const GameSettingsRoute(),
      const MangaHomeRoute(),
      const MangaDownloadsRoute(),
      const MusicPlayerRoute(),
      const LanTransferRoute(),
      const SettingsRoute(),
      const AboutRoute(),
      const ToolsRoute(),
      const SentryLogRoute(),
      const AliyunDdnsRoute(),

      const NovelReaderRoute(),
      const MangaComicDetailRoute(comicId: ''),
      const MangaSearchRoute(),
      const MangaReaderRoute(comicId: '', epsOrder: 0),
      const MangaHistoryRoute(),
      const GameDetailRoute(gameId: ''),
      const GameCategoryDetailRoute(categoryId: ''),
      const LanChatRoute(peerId: '', peerName: ''),
    ];

    router = GoRouter(
      initialLocation: '/dashboard',
      routes: $appRoutes,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: true,
      redirect: (context, state) {
        final path = state.uri.path;
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
            _logger.info('[路由] 无权限访问 $path (需要 $permission)，重定向到 /dashboard');
            return '/dashboard';
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selectedRoute.value = path;
        });

        return null;
      },
    );
    return router!;
  }

  static const Duration kTransitionDuration = Duration(milliseconds: 220);
  static const Duration kReverseTransitionDuration = Duration(milliseconds: 180);
  static const Duration kSlowTransitionDuration = Duration(milliseconds: 320);
  static const Duration kSlowReverseTransitionDuration = Duration(milliseconds: 260);

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
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          ),
        );
      },
    );
  }

  static Widget _defaultTransitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final scale = Tween(begin: 0.985, end: 1.0).animate(curved);
    return ColoredBox(
      // color: Theme.of(context).scaffoldBackgroundColor,
      color: Colors.transparent,
      child: FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }

  static Widget buildPlaceholder(String title) {
    return Scaffold(
      body: Center(
        child: Text('$title 页面开发中...', style: TextStyle(fontSize: AppTheme.metrics.fontSize22)),
      ),
    );
  }
}

final goRouter = AppRoutes.createRouter();

abstract class AppRouteData extends GoRouteData {
  const AppRouteData();

  String get title;

  String? get sidebarIcon;

  String get sidebarLabel => title;

  String? get sidebarTooltip => sidebarLabel;

  int? get sidebarOrder => null;

  int? get sidebarBadgeCount => null;

  Widget? sidebarBadgeWidget(BuildContext context) => null;

  Widget? sidebarStatusWidget(BuildContext context) => null;

  String? get sidebarGroupId => null;

  bool get showInSidebar => sidebarIcon != null;

  Permission? get permission => AppRouteData.routePermission;

  static Permission routePermission = Permission.viewDashboard;
}
