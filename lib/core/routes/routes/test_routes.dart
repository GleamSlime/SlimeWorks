part of '../app_routes.dart';

/// 测试页面路由：HttpBridgeTest、WebSocketTest、ThemePreview
@TypedGoRoute<ThemePreviewRoute>(path: '/theme-preview')
class ThemePreviewRoute extends GoRouteData with $ThemePreviewRoute {
  const ThemePreviewRoute();

  static const Permission routePermission = Permission.accessThemePreview;
  Permission get permission => ThemePreviewRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ThemePreviewScreen());
  }
}

@TypedGoRoute<HttpBridgeTestRoute>(path: '/http-bridge-test')
class HttpBridgeTestRoute extends GoRouteData with $HttpBridgeTestRoute {
  const HttpBridgeTestRoute();

  static const Permission routePermission = Permission.accessHttpBridgeTest;
  Permission get permission => HttpBridgeTestRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const HttpBridgeTestPage());
  }
}

@TypedGoRoute<WebSocketTestRoute>(path: '/websocket-test')
class WebSocketTestRoute extends GoRouteData with $WebSocketTestRoute {
  const WebSocketTestRoute();

  static const Permission routePermission = Permission.accessWebSocketTest;
  Permission get permission => WebSocketTestRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const WebSocketTestPage());
  }
}
