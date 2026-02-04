part of '../app_routes.dart';

@TypedGoRoute<CollectionLibraryRoute>(path: '/collection/library')
class CollectionLibraryRoute extends AppRouteData with $CollectionLibraryRoute {
  const CollectionLibraryRoute();

  @override
  String get title => '书库';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectLibrary;

  static const Permission routePermission = Permission.accessCollection;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CollectionLibraryScreen());
  }
}

@TypedGoRoute<CollectionPictureRoute>(path: '/collection/picture')
class CollectionPictureRoute extends AppRouteData with $CollectionPictureRoute {
  const CollectionPictureRoute();

  @override
  String get title => '图库';

  @override
  String get sidebarLabel => title;

  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  static const Permission routePermission = Permission.accessCollection;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CollectionPictureScreen());
  }
}
