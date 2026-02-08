part of '../app_sidebars.dart';

final SidebarGroup coreSidebarGroup = SidebarGroup(
  id: 'code',
  sort: 30,
  permission: Permission.accessCollection,
  items: [
    SidebarMenuItem(route: const DashboardRoute()),
    SidebarMenuItem(route: const CaptureRoute()),
  ],
);
