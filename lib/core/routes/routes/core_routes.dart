part of '../app_routes.dart';

/// 核心路由：Dashboard、Settings
@TypedGoRoute<DashboardRoute>(path: '/dashboard')
class DashboardRoute extends AppRouteData with $DashboardRoute {
  const DashboardRoute();

  @override
  String get title => '概览';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuDistributed;

  static const Permission routePermission = Permission.viewDashboard;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const DashboardScreen());
  }
}

@TypedGoRoute<AboutRoute>(path: '/settings')
class AboutRoute extends AppRouteData with $AboutRoute {
  const AboutRoute();

  @override
  String get title => '关于';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuAbout;

  static const Permission routePermission = Permission.viewDashboard;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('关于'));
  }
}

@TypedGoRoute<SettingsRoute>(path: '/settings')
class SettingsRoute extends AppRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  String get title => '设置';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuSetting;

  static const Permission routePermission = Permission.accessSettings;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SettingsPage());
  }
}
