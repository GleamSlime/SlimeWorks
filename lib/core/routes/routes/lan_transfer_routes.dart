part of '../app_routes.dart';

/// 局域网传输路由
@TypedGoRoute<LanTransferRoute>(path: '/lan-transfer')
class LanTransferRoute extends GoRouteData {
  const LanTransferRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => LanTransferRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LanTransferScreen());
  }
}
