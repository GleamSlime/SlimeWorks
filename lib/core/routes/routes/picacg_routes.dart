part of '../app_routes.dart';

/// PicACG 漫画平台路由定义

@TypedGoRoute<PicAcgHomeRoute>(path: '/picacg')
class PicAcgHomeRoute extends AppRouteData with $PicAcgHomeRoute {
  const PicAcgHomeRoute();

  @override
  String get title => 'PicACG';

  @override
  String get sidebarLabel => 'PicACG';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const PicAcgHomeScreen());
  }
}

@TypedGoRoute<PicAcgComicDetailRoute>(path: '/picacg/comic/:comicId')
class PicAcgComicDetailRoute extends AppRouteData with $PicAcgComicDetailRoute {
  const PicAcgComicDetailRoute({required this.comicId});

  final String comicId;

  @override
  String get title => '漫画详情';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, PicAcgComicDetailScreen(comicId: comicId));
  }
}

@TypedGoRoute<PicAcgSearchRoute>(path: '/picacg/search')
class PicAcgSearchRoute extends AppRouteData with $PicAcgSearchRoute {
  const PicAcgSearchRoute({this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  String get title => '搜索漫画';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      PicAcgSearchScreen(keyword: keyword, category: category),
    );
  }
}

@TypedGoRoute<PicAcgReaderRoute>(path: '/picacg/read/:comicId/:epsOrder')
class PicAcgReaderRoute extends AppRouteData with $PicAcgReaderRoute {
  const PicAcgReaderRoute({required this.comicId, required this.epsOrder, this.epsTitle = ''});

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  String get title => '漫画阅读';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      PicAcgReaderScreen(comicId: comicId, epsOrder: epsOrder, epsTitle: epsTitle),
    );
  }
}

@TypedGoRoute<PicAcgDownloadsRoute>(path: '/picacg/downloads')
class PicAcgDownloadsRoute extends AppRouteData with $PicAcgDownloadsRoute {
  const PicAcgDownloadsRoute();

  @override
  String get title => '下载管理';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const PicAcgDownloadsScreen());
  }
}

@TypedGoRoute<PicAcgHistoryRoute>(path: '/picacg/history')
class PicAcgHistoryRoute extends AppRouteData with $PicAcgHistoryRoute {
  const PicAcgHistoryRoute();

  @override
  String get title => '观看记录';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicAcg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const PicAcgHistoryScreen());
  }
}
