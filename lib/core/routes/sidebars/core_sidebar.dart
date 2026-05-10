part of '../app_sidebars.dart';

const SidebarGroup coreSidebarGroup = SidebarGroup(
  id: 'code',
  sort: 30,
  permission: Permission.accessCollection,
  items: [
    SidebarMenuItem(route: DashboardRoute()),
    SidebarMenuItem(route: CaptureRoute()),
    SidebarMenuItem(route: LanTransferRoute()),
    // 将 PicACG 放到“互传”组下方，便于查找
    SidebarMenuItem(route: PicAcgHomeRoute()),
  ],
);
