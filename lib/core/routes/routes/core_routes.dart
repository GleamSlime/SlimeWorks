part of '../app_routes.dart';

/// 核心路由：Dashboard、Settings
@TypedGoRoute<DashboardRoute>(path: '/dashboard')
class DashboardRoute extends GoRouteData with $DashboardRoute {
  const DashboardRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DashboardRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const DashboardScreen());
  }
}

@TypedGoRoute<SettingsRoute>(path: '/settings')
class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  static const Permission routePermission = Permission.accessSettings;
  Permission get permission => SettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SettingsPage());
  }
}
