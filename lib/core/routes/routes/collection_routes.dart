part of '../app_routes.dart';

class CollectionLibraryRoute extends AppRouteData with $CollectionLibraryRoute {
  const CollectionLibraryRoute();

  @override
  String get title => '书库';

  @override
  String get sidebarLabel => title;

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.assetMenuCollectLibrary;

  @override
  String get sidebarGroupId => 'collection';

  static const Permission routePermission = Permission.accessCollection;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CollectionLibraryScreen());
  }
}

class CollectionPictureRoute extends AppRouteData with $CollectionPictureRoute {
  const CollectionPictureRoute();

  @override
  String get title => '媒体库';

  @override
  String get sidebarLabel => title;

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.assetMenuCollectPictures;

  @override
  String get sidebarGroupId => 'collection';

  static const Permission routePermission = Permission.accessCollection;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const CollectionPictureScreen());
  }
}
