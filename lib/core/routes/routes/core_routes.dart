part of '../app_routes.dart';

class DashboardRoute extends AppRouteData with $DashboardRoute {
  const DashboardRoute();

  @override
  String get title => '概览';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuDistributed;

  @override
  String get sidebarGroupId => 'core';

  static const Permission routePermission = Permission.viewDashboard;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const DashboardScreen());
  }
}

class AboutRoute extends AppRouteData with $AboutRoute {
  const AboutRoute();

  @override
  String get title => '关于（${AppInfoService.versionWithBuild}）';

  @override
  String get sidebarLabel => '关于';

  @override
  Widget? sidebarStatusWidget(BuildContext context) => Text(
    AppInfoService.versionWithBuild,
    style: TextStyle(
      fontSize: AppTheme.metrics.fontSize10,
      color: Theme.of(context).colorScheme.tertiary,
    ),
  );

  @override
  String get sidebarIcon => Assets.image.svg.menuAbout;

  @override
  String get sidebarGroupId => 'bottom';

  static const Permission routePermission = Permission.viewDashboard;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const AboutPage());
  }
}

class SettingsRoute extends AppRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  String get title => '设置';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuSetting;

  @override
  String get sidebarGroupId => 'bottom';

  static const Permission routePermission = Permission.accessSettings;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const SettingsPage());
  }
}
