part of '../app_routes.dart';

/// 业务功能路由：ModuleManagement

@TypedGoRoute<ModuleManagementRoute>(path: '/module-management')
class ModuleManagementRoute extends GoRouteData with $ModuleManagementRoute {
  const ModuleManagementRoute();

  static const Permission routePermission = Permission.manageModules;
  Permission get permission => ModuleManagementRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const ModuleManagementScreen());
  }
}
