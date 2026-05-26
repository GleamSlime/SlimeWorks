import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/core/routes/app_routes.dart';

/// 从路由元数据自动生成侧边栏分组
List<SidebarGroup> buildSidebarGroupsFromRoutes() {
  final shellRoutes = <AppRouteData>[
    const DashboardRoute(),
    const CaptureRoute(),
    const ToolsRoute(),
    const SentryLogRoute(),
    const AliyunDdnsRoute(),
    const LanTransferRoute(),
    const PicAcgHomeRoute(),
    const CollectionPictureRoute(),
    const CollectionLibraryRoute(),
    const GameHomeRoute(),
    const GameLibraryRoute(),
    const AboutRoute(),
    const SettingsRoute(),
  ];

  final groupMap = <String, List<AppRouteData>>{};
  for (final route in shellRoutes) {
    if (!route.showInSidebar) continue;
    final groupId = route.sidebarGroupId ?? 'default';
    groupMap.putIfAbsent(groupId, () => []).add(route);
  }

  final groupConfigs = <String, _GroupConfig>{
    'core': _GroupConfig(id: 'core', sort: 10, permission: Permission.viewDashboard),
    'collection': _GroupConfig(
      id: 'collection',
      title: '收藏夹',
      sort: 20,
      permission: Permission.accessCollection,
    ),
    'game-library': _GroupConfig(
      id: 'game-library',
      title: '游戏',
      sort: 30,
      permission: Permission.accessGameLibrary,
    ),
    'picacg': _GroupConfig(id: 'picacg', sort: 40, permission: Permission.accessPicAcg),
    'tools': _GroupConfig(id: 'tools', title: '工具', sort: 45, permission: Permission.accessTools),
    'bottom': _GroupConfig(id: 'bottom', sort: 90, permission: Permission.accessSettings),
  };

  final groups = <SidebarGroup>[];
  for (final entry in groupMap.entries) {
    final config = groupConfigs[entry.key] ?? _GroupConfig(id: entry.key, sort: 50);
    if (config.permission != null && !RoleManager.canAccess(config.permission!)) continue;

    groups.add(
      SidebarGroup(
        id: config.id,
        title: config.title,
        sort: config.sort,
        permission: config.permission,
        items: entry.value.map((route) => SidebarMenuItem(route: route)).toList(),
      ),
    );
  }

  groups.sort((a, b) => (a.sort ?? 50).compareTo(b.sort ?? 50));

  return groups;
}

class _GroupConfig {
  final String id;
  final String? title;
  final int? sort;
  final Permission? permission;

  const _GroupConfig({required this.id, this.title, this.sort, this.permission});
}
