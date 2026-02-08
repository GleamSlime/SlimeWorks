part of '../app_routes.dart';

@TypedGoRoute<GooeyDemoRoute>(path: '/gooey-demo')
class GooeyDemoRoute extends AppRouteData with $GooeyDemoRoute {
  const GooeyDemoRoute();

  @override
  String get title => '粘连面板测试';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuAbout;

  static const Permission routePermission = Permission.accessDemo;

  @override
  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return const MaterialPage(child: GooeyDropdownDemoPage());
  }
}

@TypedGoRoute<ViewModelDemoRoute>(path: '/viewmodel-demo')
class ViewModelDemoRoute extends AppRouteData with $ViewModelDemoRoute {
  const ViewModelDemoRoute();

  @override
  String get title => 'View Model 示例';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuAbout;

  static const Permission routePermission = Permission.accessDemo;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ViewModelDemoScreenPage());
  }
}
