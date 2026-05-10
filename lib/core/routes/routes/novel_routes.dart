part of '../app_routes.dart';

/// 书籍相关路由：NovelLibrary、NovelReader
@TypedGoRoute<NovelLibraryRoute>(path: '/novel-library')
class NovelLibraryRoute extends GoRouteData with $NovelLibraryRoute {
  const NovelLibraryRoute();

  static const Permission routePermission = Permission.accessNovelLibrary;
  Permission get permission => NovelLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const NovelLibraryPage());
  }
}

@TypedGoRoute<NovelReaderRoute>(path: '/novel-reader')
class NovelReaderRoute extends GoRouteData with $NovelReaderRoute {
  const NovelReaderRoute({this.$extra});

  final NovelMetadata? $extra;

  static const Permission routePermission = Permission.accessNovelReader;
  Permission get permission => NovelReaderRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildFadePage(context, state, NovelReaderPage(novel: $extra));
  }
}
