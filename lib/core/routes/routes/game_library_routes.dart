part of '../app_routes.dart';

@TypedGoRoute<GameHomeRoute>(path: '/game/home')
class GameHomeRoute extends AppRouteData with $GameHomeRoute {
  const GameHomeRoute();

  @override
  String get title => '游戏主页';

  @override
  String get sidebarLabel => '游戏主页';

  @override
  String get sidebarIcon => Assets.image.svg.menuAggregation;

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
  String get sidebarIcon => Assets.image.svg.menuCollectLibrary;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    // 被游戏详情页覆盖时用 secondaryAnimation 淡出，避免透明详情页叠在列表上
    return CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      arguments: state.extra,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      child: const GameLibraryScreen(),
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        // 自身淡入
        final Animation<double> fadeIn = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        // 被详情页压栈时淡出
        final Animation<double> fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeIn),
        );
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
    return CustomTransitionPage<void>(
      key: state.pageKey,
      name: state.name,
      arguments: state.extra,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      child: GameDetailScreen(gameId: gameId),
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        // 纯淡入：封面背景已在 push 前由列表页预设，列表页同步通过 secondaryAnimation 淡出，
        // 视觉上是封面背景 + 详情内容交叉淡入，不会看到列表叠加其下
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          ),
          child: child,
        );
      },
    );
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
  String get sidebarIcon => Assets.image.svg.menuCollectFile;

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
  String get sidebarIcon => Assets.image.svg.menuBill;

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
  String get sidebarIcon => Assets.image.svg.menuSetting;

  static const Permission routePermission = Permission.accessGameLibrary;

  @override
  Permission get permission => GameSettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const GameSettingsScreen());
  }
}
