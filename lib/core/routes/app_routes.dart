import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/pages/capture_screen_page.dart';
import 'package:slime_works/pages/collection/library/collection_library_screen.dart';
import 'package:slime_works/pages/collection/picture/collection_picture_screen.dart';
import 'package:slime_works/pages/demo/gooey_dropdown_demo_page.dart';
import 'package:slime_works/pages/demo/viewmodel_demo_page.dart';
import 'package:slime_works/pages/motion_lab/motion_lab_screen.dart';
import 'package:slime_works/pages/interaction_lab/interaction_lab_screen.dart';
import 'package:slime_works/pages/novel_library/novel_library_page.dart';
import 'package:slime_works/pages/novel_reader/novel_reader_page.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/core/widgets/breadcrumb.dart';
import 'package:slime_works/core/widgets/binding_widget.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/pages/theme_preview_screen.dart';
import 'package:slime_works/pages/style_showcase_screen.dart';
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
import 'package:slime_works/pages/power_stats/power_stats_screen.dart';
import 'package:slime_works/pages/music_player/music_player_screen.dart';
import 'package:slime_works/pages/ncm_decrypt/ncm_decrypt_screen.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/power_stats_service.dart';
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
    TypedGoRoute<NcmDecryptRoute>(path: '/ncm-decrypt'),
    TypedGoRoute<PowerStatsRoute>(path: '/power-stats'),

    // 以下页面过去不在外壳里（整窗都是内容、没有侧边栏）。
    // 侧栏改成全局后它们也进外壳，进入时按默认隐藏态处理，见 kSidebarDefaultHiddenPaths。
    TypedGoRoute<NovelLibraryRoute>(path: '/novel-library'),
    TypedGoRoute<NovelReaderRoute>(path: '/novel-reader'),
    TypedGoRoute<ModuleManagementRoute>(path: '/module-management'),
    TypedGoRoute<ThemePreviewRoute>(path: '/theme-preview'),
    TypedGoRoute<HttpBridgeTestRoute>(path: '/http-bridge-test'),
    TypedGoRoute<WebSocketTestRoute>(path: '/websocket-test'),
    TypedGoRoute<ImageToolsRoute>(path: '/image-tools'),
    TypedGoRoute<ImageToolboxRoute>(path: '/image-toolbox'),
    TypedGoRoute<MediaLibraryRoute>(path: '/media-library'),
    TypedGoRoute<DatasourceRoute>(path: '/datasource'),
    TypedGoRoute<ClearwaterRoute>(path: '/clearwater'),
    TypedGoRoute<CloudWordRoute>(path: '/cloud-word'),
    TypedGoRoute<DistributedRoute>(path: '/distributed'),
    TypedGoRoute<RequestHostRoute>(path: '/request-host'),
    TypedGoRoute<GooeyDemoRoute>(path: '/gooey-demo'),
    TypedGoRoute<ViewModelDemoRoute>(path: '/viewmodel-demo'),
    TypedGoRoute<MotionLabRoute>(path: '/motion-lab'),
    TypedGoRoute<InteractionLabRoute>(path: '/interaction-lab'),
    TypedGoRoute<LanChatRoute>(path: '/lan-chat'),
    TypedGoRoute<MangaComicDetailRoute>(path: '/manga/comic/:comicId'),
    TypedGoRoute<MangaSearchRoute>(path: '/manga/search'),
    TypedGoRoute<MangaReaderRoute>(path: '/manga/read/:comicId/:epsOrder'),
    TypedGoRoute<MangaHistoryRoute>(path: '/manga/history'),
    TypedGoRoute<GameDetailRoute>(path: '/game/detail/:gameId'),
    TypedGoRoute<GameCategoryDetailRoute>(path: '/game/category/:categoryId'),
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

  /// 已知路由清单：权限检查、侧栏分组、外壳面包屑三处共用这一份。
  ///
  /// 分开放三份的话，新页面很容易只登记进其中一处——症状是"能打开但侧栏没有"
  /// 或"侧栏有但面包屑断了一级"。
  static final List<GoRouteData> knownRoutes = <GoRouteData>[
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
    const NcmDecryptRoute(),
    const PowerStatsRoute(),

    const NovelReaderRoute(),
    const MangaComicDetailRoute(comicId: ''),
    const MangaSearchRoute(),
    const MangaReaderRoute(comicId: '', epsOrder: 0),
    const MangaHistoryRoute(),
    const GameDetailRoute(gameId: ''),
    const GameCategoryDetailRoute(categoryId: ''),
    const LanChatRoute(peerId: '', peerName: ''),
  ];

  /// 反查一个真实路径对应的路由声明（参数化路径按前缀匹配，最长者胜）
  static AppRouteData? routeAt(String location) {
    AppRouteData? best;
    var bestLen = -1;
    for (final r in knownRoutes) {
      if (r is! AppRouteData) continue;
      final base = r.location.endsWith('/')
          ? r.location.substring(0, r.location.length - 1)
          : r.location;
      if (base.isEmpty) continue;
      if (location == base || location.startsWith('$base/')) {
        if (base.length > bestLen) {
          best = r;
          bestLen = base.length;
        }
      }
    }
    return best;
  }

  /// 由路由元数据拼面包屑：`父链 / 当前项`。
  ///
  /// 只有一级时返回 null——顶栏退回单级标题。"概览"上面再挂一个"概览"
  /// 比不挂更吵，而且那一格本来就是互斥的同一格。
  ///
  /// [leafLabel] 是页面自己报出的名字（详情页的实体名，如某个游戏标题）。
  /// 静态路由在那种位置上的名字是废话——"游戏详情"不如"寂静之海"有用，所以给它盖掉。
  static List<BreadcrumbEntry>? breadcrumbFor(
    String location, {
    void Function(String routeLocation)? navigate,
    String? leafLabel,
  }) {
    final current = routeAt(location);
    if (current == null) return null;

    final trail = <AppRouteData>[current];
    final visited = <String>{current.location};
    var parent = _parentOf(current);
    while (parent != null && visited.add(parent.location)) {
      trail.insert(0, parent);
      parent = _parentOf(parent);
    }
    if (trail.length < 2) return null;

    final named = leafLabel != null && leafLabel.isNotEmpty;
    return <BreadcrumbEntry>[
      for (var i = 0; i < trail.length; i++)
        BreadcrumbEntry(
          // 上级一律取侧栏里的叫法：层级是从侧栏来的，两处名字不一样就白挂了
          (i == trail.length - 1 && named) ? leafLabel : trail[i].sidebarLabel,
          // 当前页不可点：它已经是用户站着的地方
          onTap: i == trail.length - 1 || navigate == null
              ? null
              : () => navigate(trail[i].location),
        ),
    ];
  }

  static AppRouteData? _parentOf(AppRouteData route) {
    final parent = route.sidebarParent;
    if (parent == null) return null;
    return routeAt(parent);
  }

  static GoRouter createRouter() {
    if (router != null) return router!;

    final controller = Get.put(SidebarController());

    final routeConstructors = knownRoutes;

    router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        ...$appRoutes,
        GoRoute(
          path: '/style-showcase',
          // 非 typed 路由进不了上面的 ShellRoute，手动包同一层外壳
          builder: (context, state) =>
              const DesktopLayout(child: StyleShowcaseScreen()),
        ),
      ],
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
          // 历史上没有侧栏的页面进来就落在隐藏态，离开时恢复（见 SidebarController）
          controller.applyVisibilityForPath(
            path,
            defaultHidden: sidebarDefaultHidden(path),
          );
        });

        return null;
      },
    );
    return router!;
  }

  // 退场一律取进场的下一档（原来 220/180、320/260 里的 180 和 260 不在节奏上）
  static const Duration kTransitionDuration = AppMotion.base;
  static const Duration kReverseTransitionDuration = AppMotion.fast;
  static const Duration kSlowTransitionDuration = AppMotion.slow;
  static const Duration kSlowReverseTransitionDuration = AppMotion.base;

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

  /// 侧栏那一行的图标；null 表示这一项不进侧栏。
  StrokeIcon? get sidebarIcon;

  String get sidebarLabel => title;

  String? get sidebarTooltip => sidebarLabel;

  int? get sidebarOrder => null;

  /// 侧栏里的父项 location。
  ///
  /// 非空表示这一项不占顶层行，而是挂在父项下、展开时用连接线成组；
  /// 同时它也是面包屑反查上级的唯一依据——导航层级和路径层级必须是同一份数据，
  /// 各写一遍迟早对不上。
  String? get sidebarParent => null;

  int? get sidebarBadgeCount => null;

  Widget? sidebarBadgeWidget(BuildContext context) => null;

  Widget? sidebarStatusWidget(BuildContext context) => null;

  String? get sidebarGroupId => null;

  bool get showInSidebar => sidebarIcon != null;

  /// 是否仅桌面端显示（移动端隐藏侧边栏入口）
  bool get desktopOnly => false;

  Permission? get permission => AppRouteData.routePermission;

  static Permission routePermission = Permission.viewDashboard;
}
