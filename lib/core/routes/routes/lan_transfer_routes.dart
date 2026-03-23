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
