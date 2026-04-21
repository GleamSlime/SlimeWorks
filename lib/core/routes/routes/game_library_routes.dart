part of '../app_routes.dart';

@TypedGoRoute<GameHomeRoute>(path: '/game/home')
class GameHomeRoute extends AppRouteData with $GameHomeRoute {
  const GameHomeRoute();

  @override
  String get title => '游戏主页';

  @override
  String get sidebarLabel => '游戏主页';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameHomeRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameLibraryHomeScreen());
  }
}

@TypedGoRoute<GameLibraryRoute>(path: '/game/library')
class GameLibraryRoute extends AppRouteData with $GameLibraryRoute {
  const GameLibraryRoute();

  @override
  String get title => '游戏库';

  @override
  String get sidebarLabel => '游戏库';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameLibraryScreen());
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
    return AppRoutes.buildPage(context, state, GameDetailScreen(gameId: gameId));
  }
}

@TypedGoRoute<GameCategoriesRoute>(path: '/game/categories')
class GameCategoriesRoute extends AppRouteData with $GameCategoriesRoute {
  const GameCategoriesRoute();

  @override
  String get title => '分类管理';

  @override
  String get sidebarLabel => '游戏分类';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

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

@TypedGoRoute<GameStatsRoute>(path: '/game/stats')
class GameStatsRoute extends AppRouteData with $GameStatsRoute {
  const GameStatsRoute();

  @override
  String get title => '游玩统计';

  @override
  String get sidebarLabel => '游戏统计';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameStatsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameStatsScreen());
  }
}

@TypedGoRoute<GameSettingsRoute>(path: '/game/settings')
class GameSettingsRoute extends AppRouteData with $GameSettingsRoute {
  const GameSettingsRoute();

  @override
  String get title => '游戏设置';

  @override
  String get sidebarLabel => '游戏设置';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameSettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameSettingsScreen());
  }
}
