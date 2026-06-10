part of '../app_routes.dart';

class CaptureRoute extends AppRouteData with $CaptureRoute {
  const CaptureRoute();

  @override
  String get title => '屏幕捕获';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuCapture;

  @override
  String get sidebarGroupId => 'core';

  @override
  bool get desktopOnly => true;

  static const Permission routePermission = Permission.accessCapture;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CaptureScreen());
  }
}
