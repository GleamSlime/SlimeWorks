part of '../app_routes.dart';

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
    return AppRoutes.buildPage(context, state, const CollectionPictureScreen());
  }
}

@TypedGoRoute<SentryLogRoute>(path: '/sentry-log')
class SentryLogRoute extends AppRouteData with $SentryLogRoute {
  const SentryLogRoute();

  @override
  String get title => '日志';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuLog;

  @override
  String get sidebarGroupId => 'tools';

  static const Permission routePermission = Permission.accessSentryLog;
  @override
  Permission get permission => SentryLogRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SentryLogScreen());
  }
}

class ToolsRoute extends AppRouteData with $ToolsRoute {
  const ToolsRoute();

  @override
  String get title => '工具';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuTools;

  @override
  String get sidebarGroupId => 'tools';

  static const Permission routePermission = Permission.accessTools;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ToolsScreen());
  }
}
