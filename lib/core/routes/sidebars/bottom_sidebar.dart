part of '../app_sidebars.dart';

final SidebarGroup bottomSidebarGroup = SidebarGroup(
  id: 'collection',
  sort: 30,
  permission: Permission.accessSettings,
  items: [
    SidebarMenuItem(route: const AboutRoute()),
    SidebarMenuItem(route: const SettingsRoute()),
  ],
);
