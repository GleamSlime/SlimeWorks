part of '../app_routes.dart';

@TypedGoRoute<GooeyDemoRoute>(path: '/gooey-demo')
class GooeyDemoRoute extends GoRouteData {
  const GooeyDemoRoute();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return const MaterialPage(child: GooeyDropdownDemo());
  }
}
