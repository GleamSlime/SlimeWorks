part of '../app_sidebars.dart';

final SidebarGroup collectionSidebarGroup = SidebarGroup(
  id: 'collection',
  title: '收藏夹',
  permission: Permission.accessCollection,
  items: [
    // SidebarMenuItem(icon: Assets.image.svg.menuCollectNote, label: '笔记', route: '/favorites/notes', badge: 61),
    // SidebarMenuItem(icon: Assets.image.svg.menuCollectCredentials, label: '账密', route: '/favorites/accounts', badge: 37),
    // SidebarMenuItem(icon: Assets.image.svg.menuCollectFile, label: '文件', route: '/favorites/files'),
    SidebarMenuItem(route: const CollectionPictureRoute()),
    SidebarMenuItem(route: const CollectionLibraryRoute()),
  ],
);
