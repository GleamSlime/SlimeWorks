part of '../app_sidebars.dart';

final SidebarGroup coreSidebarGroup = SidebarGroup(
  id: 'code',
  sort: 30,
  permission: Permission.accessCollection,
  items: [
    SidebarMenuItem(route: const DashboardRoute()),
    SidebarMenuItem(route: const CaptureRoute()),
    SidebarMenuItem(route: const LanTransferRoute()),
    // 将 PicACG 放到“互传”组下方，便于查找
    SidebarMenuItem(route: const PicAcgHomeRoute()),
  ],
);
