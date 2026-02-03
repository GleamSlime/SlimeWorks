import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/pages/novel_library/novel_library_page.dart';
import 'package:slime_works/pages/novel_reader/novel_reader_page.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

part 'learn_routes.g.dart';

@TypedGoRoute<NovelLibraryRoute>(path: '/novel-library')
class NovelLibraryRoute extends GoRouteData with $NovelLibraryRoute {
  const NovelLibraryRoute();

  static const Permission routePermission = Permission.accessNovelLibrary;
  Permission get permission => NovelLibraryRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const NovelLibraryPage());
  }
}

@TypedGoRoute<NovelReaderRoute>(path: '/novel-reader')
class NovelReaderRoute extends GoRouteData with $NovelReaderRoute {
  const NovelReaderRoute({this.$extra});

  final NovelMetadata? $extra;

  static const Permission routePermission = Permission.accessNovelReader;
  Permission get permission => NovelReaderRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, NovelReaderPage(novel: $extra));
  }
}
