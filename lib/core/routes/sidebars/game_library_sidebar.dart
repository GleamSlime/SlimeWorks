part of '../app_sidebars.dart';

final SidebarGroup gameLibrarySidebarGroup = SidebarGroup(
  id: 'game-library',
  title: '游戏',
  permission: Permission.accessGameLibrary,
  items: <SidebarMenuItem>[
    SidebarMenuItem(route: const GameHomeRoute()),
    SidebarMenuItem(route: const GameLibraryRoute()),
    SidebarMenuItem(route: const GameCategoriesRoute()),
    SidebarMenuItem(route: const GameStatsRoute()),
  ],
);
