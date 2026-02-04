import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/pages/backup/demo.dart';

part 'demo_routes.g.dart';

@TypedGoRoute<GooeyDemoRoute>(path: '/gooey-demo')
class GooeyDemoRoute extends GoRouteData {
  const GooeyDemoRoute();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return const MaterialPage(child: GooeyDropdownDemo());
  }
}
