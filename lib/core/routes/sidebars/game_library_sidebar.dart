part of '../app_sidebars.dart';

const SidebarGroup gameLibrarySidebarGroup = SidebarGroup(
  id: 'game-library',
  title: '游戏',
  permission: Permission.accessGameLibrary,
  items: <SidebarMenuItem>[
    SidebarMenuItem(route: GameHomeRoute()),
    SidebarMenuItem(route: GameLibraryRoute()),
    SidebarMenuItem(route: GameCategoriesRoute()),
    SidebarMenuItem(route: GameStatsRoute()),
  ],
);
