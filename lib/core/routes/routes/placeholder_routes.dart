part of '../app_routes.dart';

/// 占位路由：Datasource、Clearwater、CloudWord、Distributed、RequestHost
@TypedGoRoute<DatasourceRoute>(path: '/datasource')
class DatasourceRoute extends GoRouteData with $DatasourceRoute {
  const DatasourceRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DatasourceRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('数据源'));
  }
}

@TypedGoRoute<ClearwaterRoute>(path: '/clearwater')
class ClearwaterRoute extends GoRouteData with $ClearwaterRoute {
  const ClearwaterRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => ClearwaterRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('清水账'));
  }
}

@TypedGoRoute<CloudWordRoute>(path: '/cloud-word')
class CloudWordRoute extends GoRouteData with $CloudWordRoute {
  const CloudWordRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => CloudWordRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('云词间'));
  }
}

@TypedGoRoute<DistributedRoute>(path: '/distributed')
class DistributedRoute extends GoRouteData with $DistributedRoute {
  const DistributedRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => DistributedRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('分布式算'));
  }
}

@TypedGoRoute<RequestHostRoute>(path: '/request-host')
class RequestHostRoute extends GoRouteData with $RequestHostRoute {
  const RequestHostRoute();

  static const Permission routePermission = Permission.viewDashboard;
  Permission get permission => RequestHostRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('请求托管'));
  }
}
