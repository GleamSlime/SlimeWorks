part of '../app_routes.dart';

/// 流水账模块的路由。
///
/// 顶层只有"流水账"一格，其余五页挂在它下面（`sidebarParent`）——
/// 它们之间靠页内的胶囊 tab 互跳，侧栏再平铺六格会把"账本"读成六个功能。
class LedgerRoute extends AppRouteData with $LedgerRoute {
  const LedgerRoute();

  @override
  String get title => '流水账';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.assetMenuBill;

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerScreen());
  }
}

class LedgerRecordsRoute extends AppRouteData with $LedgerRecordsRoute {
  const LedgerRecordsRoute();

  @override
  String get title => '流水明细';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.list;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerRecordsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerRecordsScreen());
  }
}

class LedgerStatsRoute extends AppRouteData with $LedgerStatsRoute {
  const LedgerStatsRoute();

  @override
  String get title => '记账统计';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.chartPie;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerStatsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerStatsScreen());
  }
}

class LedgerPendingRoute extends AppRouteData with $LedgerPendingRoute {
  const LedgerPendingRoute();

  @override
  String get title => '待确认账单';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.inbox;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerPendingRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerPendingScreen());
  }
}

class LedgerSettingsRoute extends AppRouteData with $LedgerSettingsRoute {
  const LedgerSettingsRoute();

  @override
  String get title => '账单邮箱';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.mail;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerSettingsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerSettingsScreen());
  }
}

class LedgerAccountsRoute extends AppRouteData with $LedgerAccountsRoute {
  const LedgerAccountsRoute();

  @override
  String get title => '账户';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.category;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerAccountsRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerAccountsScreen());
  }
}

/// 分类与标签：类别的两级树和标签分组都在这一页
class LedgerOrganizeRoute extends AppRouteData with $LedgerOrganizeRoute {
  const LedgerOrganizeRoute();

  @override
  String get title => '分类与标签';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.label;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerOrganizeRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerOrganizeScreen());
  }
}

/// 模板与定时记账：常记的那几笔存成模板，到点自动照模板记
class LedgerTemplatesRoute extends AppRouteData with $LedgerTemplatesRoute {
  const LedgerTemplatesRoute();

  @override
  String get title => '模板与定时';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.eventRepeat;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerTemplatesRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerTemplatesScreen());
  }
}

/// 导入与导出：账本进出都从这一页走，读写的都是 Rust 的真账
class LedgerDataRoute extends AppRouteData with $LedgerDataRoute {
  const LedgerDataRoute();

  @override
  String get title => '导入与导出';

  @override
  StrokeIcon get sidebarIcon => StrokeIcons.assetLibraryImport;

  @override
  String get sidebarParent => '/ledger';

  @override
  String get sidebarGroupId => 'ledger';

  static const Permission routePermission = Permission.accessLedger;

  @override
  Permission get permission => LedgerDataRoute.routePermission;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return AppRoutes.buildPage(context, state, const LedgerDataScreen());
  }
}
