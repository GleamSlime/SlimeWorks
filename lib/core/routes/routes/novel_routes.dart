part of '../app_routes.dart';

/// 书籍相关路由：NovelLibrary、NovelReader
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
    return CustomTransitionPage(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 400),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      child: BindingWidget(child: NovelReaderPage(novel: $extra)),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // 配合 Hero 的淡入动画
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }
}
