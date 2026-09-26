import 'dart:io';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/core/routes/app_routes.dart';

/// 历史上没有侧边栏的页面。侧栏全局化后它们并入外壳，但进入时默认落在
/// 隐藏态——只剩内容区左缘一根指示条，阅读/工具类页面的沉浸感才和过去一致。
/// 已登记进侧栏条目的页面（动效实验室、漫画历史）不算：从侧栏点进去
/// 又被立刻藏起来，等于自相矛盾。
const Set<String> kSidebarDefaultHiddenPaths = {
  '/novel-library',
  '/novel-reader',
  '/module-management',
  '/theme-preview',
  '/http-bridge-test',
  '/websocket-test',
  '/image-tools',
  '/image-toolbox',
  '/media-library',
  '/datasource',
  '/clearwater',
  '/cloud-word',
  '/distributed',
  '/request-host',
  '/gooey-demo',
  '/viewmodel-demo',
  '/lan-chat',
  '/manga/comic',
  '/manga/search',
  '/manga/read',
  '/game/detail',
  '/game/category',
  '/style-showcase',
};

/// 按路径段前缀匹配：参数化路径（/manga/read/x/1 等）也算命中。
/// 用 `'$base/'` 而不是裸前缀，否则 '/game/category' 会误伤 '/game/categories'。
bool sidebarDefaultHidden(String location) => kSidebarDefaultHiddenPaths.any(
  (base) => location == base || location.startsWith('$base/'),
);

/// 从路由元数据自动生成侧边栏分组
List<SidebarGroup> buildSidebarGroupsFromRoutes() {
  final isMobilePlatform = Platform.isAndroid || Platform.isIOS;

  // 侧栏只认这一份名单：showInSidebar 的含义是"能从侧栏点到"，
  // 顶层项和展开后的子项都算，具体站哪一层由 sidebarParent 决定。
  final shellRoutes = <AppRouteData>[
    const DashboardRoute(),
    const CaptureRoute(),
    const ToolsRoute(),
    const SentryLogRoute(),
    const AliyunDdnsRoute(),
    const PowerStatsRoute(),
    const LanTransferRoute(),
    const MangaHomeRoute(),
    const MusicPlayerRoute(),
    const CollectionPictureRoute(),
    const CollectionLibraryRoute(),
    const GameLibraryRoute(),
    const AboutRoute(),
    const SettingsRoute(),
    const MotionLabRoute(),

    const GameCategoriesRoute(),
    const GameStatsRoute(),
    const GameSettingsRoute(),
    const MangaHistoryRoute(),
  ];

  bool visible(AppRouteData route) {
    if (route.desktopOnly && isMobilePlatform) return false;
    if (route.permission != null && !RoleManager.canAccess(route.permission!)) return false;
    return true;
  }

  // 顶层 = 进侧栏且没有父级；有父级的按 sidebarParent 归到父项下面。
  // 层级只从路由元数据读一份：侧栏和面包屑各写一遍迟早对不上。
  final parents = shellRoutes.where(
    (r) => r.showInSidebar && r.sidebarParent == null && visible(r),
  );
  // 父级没进侧栏（被权限挡了、或者压根没列进来）时，子项退回顶层。
  // 静默丢掉的话症状是"某个页面从侧栏消失了"，很难往层级元数据上想。
  final parentLocations = parents.map((r) => r.location).toSet();
  final topLevel = shellRoutes.where(
    (r) =>
        r.showInSidebar &&
        visible(r) &&
        (r.sidebarParent == null || !parentLocations.contains(r.sidebarParent)),
  );

  List<SidebarMenuItem> childrenOf(AppRouteData parent) => shellRoutes
      .where(
        (r) =>
            r.sidebarParent == parent.location &&
            r.showInSidebar &&
            visible(r),
      )
      .map((r) => SidebarMenuItem(route: r))
      .toList();

  final groupMap = <String, List<SidebarMenuItem>>{};
  for (final route in topLevel) {
    final groupId = route.sidebarGroupId ?? 'default';
    groupMap.putIfAbsent(groupId, () => []).add(
      SidebarMenuItem(route: route, children: childrenOf(route).isEmpty ? null : childrenOf(route)),
    );
  }

  final groupConfigs = <String, _GroupConfig>{
    'core': _GroupConfig(id: 'core', sort: 10, permission: Permission.viewDashboard),
    'collection': _GroupConfig(
      id: 'collection',
      title: '收藏夹',
      sort: 20,
      permission: Permission.accessCollection,
    ),
    'music': _GroupConfig(id: 'music', sort: 42, permission: Permission.accessCollection),
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
        items: entry.value,
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
