part of '../app_sidebars.dart';

/// PicACG 侧边栏分组

const SidebarGroup picacgSidebarGroup = SidebarGroup(
  id: 'picacg',
  sort: 50,
  permission: Permission.accessPicAcg,
  items: [SidebarMenuItem(route: PicAcgHomeRoute())],
);
