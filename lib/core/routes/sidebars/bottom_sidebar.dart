part of '../app_sidebars.dart';

const SidebarGroup bottomSidebarGroup = SidebarGroup(
  id: 'collection',
  sort: 30,
  permission: Permission.accessSettings,
  items: [
    SidebarMenuItem(route: AboutRoute()),
    SidebarMenuItem(route: SettingsRoute()),
  ],
);
