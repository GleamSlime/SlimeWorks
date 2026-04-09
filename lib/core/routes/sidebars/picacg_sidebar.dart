part of '../app_sidebars.dart';

/// PicACG 侧边栏分组

final SidebarGroup picacgSidebarGroup = SidebarGroup(
  id: 'picacg',
  sort: 50,
  permission: Permission.accessPicacg,
  items: [SidebarMenuItem(route: const PicacgHomeRoute())],
);
