part of '../app_routes.dart';

class MusicPlayerRoute extends AppRouteData with $MusicPlayerRoute {
  const MusicPlayerRoute();

  @override
  String get title => '播放器';

  @override
  String get sidebarLabel => title;

  // 使用媒体库图标，运行 build_runner 后可改为 menuMusicPlayer
  @override
  String get sidebarIcon => Assets.image.svg.menuCollectPictures;

  @override
  String get sidebarGroupId => 'music';

  static const Permission routePermission = Permission.accessCollection;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const MusicPlayerScreen());
  }
}
