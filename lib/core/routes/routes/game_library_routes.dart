part of '../app_routes.dart';

class GameHomeRoute extends AppRouteData with $GameHomeRoute {
  const GameHomeRoute();

  @override
  String get title => '游戏';

  @override
  String get sidebarLabel => '游戏';

  @override
  String get sidebarIcon => Assets.image.svg.menuGame;

  @override
  String get sidebarGroupId => 'game-library';

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameHomeRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameHubScreen());
  }
}

class GameLibraryRoute extends AppRouteData with $GameLibraryRoute {
  const GameLibraryRoute();

  @override
  String get title => '游戏库';

  @override
  String get sidebarLabel => '游戏库';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectLibrary;

  @override
  String get sidebarGroupId => 'game-library';

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      arguments: state.extra,
      transitionDuration: AppRoutes.kTransitionDuration,
      reverseTransitionDuration: AppRoutes.kTransitionDuration,
      child: const GameLibraryScreen(),
      transitionsBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final Animation<double> fadeIn = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final Animation<double> fadeOut = Tween<double>(
              begin: 1.0,
              end: 0.0,
            ).animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic));
            return FadeTransition(
              opacity: fadeIn,
              child: FadeTransition(opacity: fadeOut, child: child),
            );
          },
    );
  }
}

@TypedGoRoute<GameDetailRoute>(path: '/game/detail/:gameId')
class GameDetailRoute extends AppRouteData with $GameDetailRoute {
  const GameDetailRoute({required this.gameId});

  final String gameId;

  @override
  String get title => '游戏详情';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameDetailRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildFadePage(context, state, GameDetailScreen(gameId: gameId));
  }
}

class GameCategoriesRoute extends AppRouteData with $GameCategoriesRoute {
  const GameCategoriesRoute();

  @override
  String get title => '分类管理';

  @override
  String get sidebarLabel => '游戏分类';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectFile;

  @override
  bool get showInSidebar => false;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameCategoriesRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameCategoriesScreen());
  }
}

@TypedGoRoute<GameCategoryDetailRoute>(path: '/game/category/:categoryId')
class GameCategoryDetailRoute extends AppRouteData with $GameCategoryDetailRoute {
  const GameCategoryDetailRoute({required this.categoryId});

  final String categoryId;

  @override
  String get title => '分类详情';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameCategoryDetailRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, GameCategoryDetailScreen(categoryId: categoryId));
  }
}

class GameStatsRoute extends AppRouteData with $GameStatsRoute {
  const GameStatsRoute();

  @override
  String get title => '游玩统计';

  @override
  String get sidebarLabel => '游戏统计';

  @override
  String get sidebarIcon => Assets.image.svg.menuBill;

  @override
  bool get showInSidebar => false;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameStatsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameStatsScreen());
  }
}

class GameSettingsRoute extends AppRouteData with $GameSettingsRoute {
  const GameSettingsRoute();

  @override
  String get title => '游戏设置';

  @override
  String get sidebarLabel => '游戏设置';

  @override
  String get sidebarIcon => Assets.image.svg.menuSetting;

  @override
  bool get showInSidebar => false;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameSettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameSettingsScreen());
  }
}
