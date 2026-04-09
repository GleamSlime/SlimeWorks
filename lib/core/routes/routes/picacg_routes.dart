part of '../app_routes.dart';

/// PicACG 漫画平台路由定义

@TypedGoRoute<PicacgHomeRoute>(path: '/picacg')
class PicacgHomeRoute extends AppRouteData with $PicacgHomeRoute {
  const PicacgHomeRoute();

  @override
  String get title => 'PicACG';

  @override
  String get sidebarLabel => 'PicACG';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicacg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const PicacgHomeScreen());
  }
}

@TypedGoRoute<PicacgComicDetailRoute>(path: '/picacg/comic/:comicId')
class PicacgComicDetailRoute extends AppRouteData with $PicacgComicDetailRoute {
  const PicacgComicDetailRoute({required this.comicId});

  final String comicId;

  @override
  String get title => '漫画详情';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicacg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, PicacgComicDetailScreen(comicId: comicId));
  }
}

@TypedGoRoute<PicacgSearchRoute>(path: '/picacg/search')
class PicacgSearchRoute extends AppRouteData with $PicacgSearchRoute {
  const PicacgSearchRoute({this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  String get title => '搜索漫画';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicacg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      PicacgSearchScreen(keyword: keyword, category: category),
    );
  }
}

@TypedGoRoute<PicacgReaderRoute>(path: '/picacg/read/:comicId/:epsOrder')
class PicacgReaderRoute extends AppRouteData with $PicacgReaderRoute {
  const PicacgReaderRoute({required this.comicId, required this.epsOrder, this.epsTitle = ''});

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  String get title => '漫画阅读';

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessPicacg;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(
      context,
      state,
      PicacgReaderScreen(comicId: comicId, epsOrder: epsOrder, epsTitle: epsTitle),
    );
  }
}
