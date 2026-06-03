part of '../app_routes.dart';

class MangaHomeRoute extends AppRouteData with $MangaHomeRoute {
  const MangaHomeRoute();

  @override
  String get title => 'Manga';

  @override
  String get sidebarLabel => 'Manga';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  @override
  String get sidebarGroupId => 'core';

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const MangaHomeScreen());
  }
}

@TypedGoRoute<MangaComicDetailRoute>(path: '/manga/comic/:comicId')
class MangaComicDetailRoute extends AppRouteData with $MangaComicDetailRoute {
  const MangaComicDetailRoute({required this.comicId});

  final String comicId;

  @override
  String get title => '漫画详情';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, MangaComicDetailScreen(comicId: comicId));
  }
}

@TypedGoRoute<MangaSearchRoute>(path: '/manga/search')
class MangaSearchRoute extends AppRouteData with $MangaSearchRoute {
  const MangaSearchRoute({this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  String get title => '搜索漫画';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      MangaSearchScreen(keyword: keyword, category: category),
    );
  }
}

@TypedGoRoute<MangaReaderRoute>(path: '/manga/read/:comicId/:epsOrder')
class MangaReaderRoute extends AppRouteData with $MangaReaderRoute {
  const MangaReaderRoute({required this.comicId, required this.epsOrder, this.epsTitle = ''});

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  String get title => '漫画阅读';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      MangaReaderScreen(comicId: comicId, epsOrder: epsOrder, epsTitle: epsTitle),
    );
  }
}

class MangaDownloadsRoute extends AppRouteData with $MangaDownloadsRoute {
  const MangaDownloadsRoute();

  @override
  String get title => '下载管理';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  @override
  String get sidebarGroupId => 'manga';

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const MangaDownloadsScreen());
  }
}

@TypedGoRoute<MangaHistoryRoute>(path: '/manga/history')
class MangaHistoryRoute extends AppRouteData with $MangaHistoryRoute {
  const MangaHistoryRoute();

  @override
  String get title => '观看记录';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessManga;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const MangaHistoryScreen());
  }
}
