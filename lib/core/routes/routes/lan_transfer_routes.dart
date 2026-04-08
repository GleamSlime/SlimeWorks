part of '../app_routes.dart';

/// 局域网传输路由
@TypedGoRoute<LanTransferRoute>(path: '/lan-transfer')
class LanTransferRoute extends AppRouteData with $LanTransferRoute {
  const LanTransferRoute();

  @override
  String get title => '局域网传输';

  @override
  String get sidebarLabel => '互传';

  @override
  String get sidebarIcon => Assets.image.svg.menuCloudAccess;

  static const Permission routePermission = Permission.viewDashboard;

  @override
  Permission get permission => LanTransferRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LanTransferScreen());
  }
}

/// 局域网聊天页路由（与指定设备的传输会话）
/// [peerId] 对端设备 ID，[peerName] 对端设备名称（均作为 URL query 参数传递）
@TypedGoRoute<LanChatRoute>(path: '/lan-chat')
class LanChatRoute extends GoRouteData with $LanChatRoute {
  final String peerId;
  final String peerName;

  const LanChatRoute({required this.peerId, required this.peerName});

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return MaterialPage(
      child: LanChatScreen(peerDeviceId: peerId, peerDeviceName: peerName),
    );
  }
}
