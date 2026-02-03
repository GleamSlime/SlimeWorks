part of '../app_routes.dart';

/// 工具类路由：ImageTools、ImageToolbox、MediaLibrary
@TypedGoRoute<ImageToolsRoute>(path: '/image-tools')
class ImageToolsRoute extends GoRouteData with $ImageToolsRoute {
  const ImageToolsRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具'));
  }
}

@TypedGoRoute<ImageToolboxRoute>(path: '/image-toolbox')
class ImageToolboxRoute extends GoRouteData with $ImageToolboxRoute {
  const ImageToolboxRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ImageToolboxRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具盒'));
  }
}

@TypedGoRoute<MediaLibraryRoute>(path: '/media-library')
class MediaLibraryRoute extends GoRouteData with $MediaLibraryRoute {
  const MediaLibraryRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => MediaLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('媒体库'));
  }
}
