import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/custom_bar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/gen/assets.gen.dart';

/// 桌面布局页面
/// 仅用于 macOS 和 Windows 平台
class DesktopLayout extends StatelessWidget {
  final Widget child;
  final List<SidebarGroup>? sidebarGroups;
  final String title;
  final Widget? appBarActions;
  final bool showAppBar;

  const DesktopLayout({super.key, required this.child, this.sidebarGroups, this.title = '史莱姆工坊', this.appBarActions, this.showAppBar = true});

  /// 获取默认的侧边栏分组配置
  static List<SidebarGroup> getDefaultSidebarGroups() {
    return [
      // 第一组：主要功能（无标题）
      SidebarGroup(
        items: [
          SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '概览', route: '/dashboard'),
          SidebarMenuItem(icon: Assets.image.svg.menuCapture, label: '数据捕获', route: '/capture'),
          SidebarMenuItem(icon: Assets.image.svg.menuBill, label: '流水账', route: '/clearwater'),
          SidebarMenuItem(
            icon: Assets.image.svg.menuAli,
            label: '阿里云',
            children: [
              SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'OSS存储', route: '/aliyun/oss'),
              SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'DNS管理', route: '/aliyun/dns'),
            ],
          ),
          SidebarMenuItem(
            icon: Assets.image.svg.menuTools,
            label: '工具箱',
            children: [
              SidebarMenuItem(icon: Assets.image.svg.menuToolsVideo, label: '视频工具', route: '/tools/video'),
              SidebarMenuItem(icon: Assets.image.svg.menuToolsPictures, label: '图片工具', route: '/tools/image'),
            ],
          ),
          SidebarMenuItem(icon: Assets.image.svg.menuMediaLibrary, label: '媒体库', route: '/media-library'),
          SidebarMenuItem(icon: Assets.image.svg.menuCollectFile, label: '小说库', route: '/novel-library'),
        ],
      ),

      // 第二组：收藏
      SidebarGroup(
        title: '收藏',
        items: [
          SidebarMenuItem(icon: Assets.image.svg.menuCollectNote, label: '笔记', route: '/favorites/notes', badge: 61),
          SidebarMenuItem(icon: Assets.image.svg.menuCollectCredentials, label: '账密', route: '/favorites/accounts', badge: 37),
          SidebarMenuItem(icon: Assets.image.svg.menuCollectFile, label: '文件', route: '/favorites/files'),
          SidebarMenuItem(icon: Assets.image.svg.menuCollectPictures, label: '图片', route: '/favorites/images'),
        ],
      ),

      // 第三组：插件
      SidebarGroup(
        title: '插件',
        items: [
          SidebarMenuItem(icon: Assets.image.svg.menuCloudAccess, label: '云访问', route: '/plugins/cloud-access'),
          SidebarMenuItem(icon: Assets.image.svg.menuDistributed, label: '分布式', route: '/plugins/distributed'),
          SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '主题测试', route: '/theme-preview'),
          SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'WS测试', route: '/websocket-test'),
        ],
      ),

      // 第四组：系统
      SidebarGroup(
        title: '系统',
        items: [
          SidebarMenuItem(icon: Assets.image.svg.menuTools, label: '模块管理', route: '/module-management'),
          SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '设置', route: '/settings'),
        ],
      ),

      // 第四组：设置（无标题）
      SidebarGroup(
        items: [
          SidebarMenuItem(icon: Assets.image.svg.menuAbout, label: '关于', route: '/about'),
          SidebarMenuItem(icon: Assets.image.svg.menuSetting, label: '设置', route: '/settings'),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = sidebarGroups ?? getDefaultSidebarGroups();
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // 如果不是桌面平台，返回移动端布局
    if (!PlatformUtil.isDesktop) {
      return Scaffold(
        appBar: showAppBar
            ? AppBar(
                title: Text(title),
                leading: IconButton(
                  icon: Icon(Icons.menu),
                  onPressed: () {
                    final controller = Get.find<SidebarController>();
                    controller.openSidebar();
                  },
                ),
                // actions: appBarActions != null ? [appBarActions!] : null,
              )
            : null,
        body: Stack(
          children: [
            child,
            CollapsibleSidebar(groups: groups),
          ],
        ),
      );
    }

    // 桌面端：检查是否是小窗口模式（需要移动端布局）
    if (isMobile) {
      return Scaffold(
        body: _MobileLayout(showAppBar: showAppBar, title: title, appBarActions: appBarActions, child: child, groups: groups),
      );
    }

    // 桌面端正常布局
    return Scaffold(
      body: DesktopScaffold(
        child: Row(
          children: [
            CollapsibleSidebar(groups: groups),
            Expanded(
              child: Column(
                children: [
                  if (showAppBar)
                    SizedBox(
                      height: scaleH(80),
                      child: Row(
                        children: [
                          SizedBox(width: AppThemeCommon.kSpace16),
                          Text(title, style: TextStyle(fontSize: AppThemeCommon.fontSize18)),
                          const Spacer(),
                          if (appBarActions != null) appBarActions!,
                          SizedBox(width: AppThemeCommon.kSpace16),
                          if (Platform.isWindows) ...[WindowsWindowButtons(), SizedBox(width: AppThemeCommon.kSpace16)],
                        ],
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 移动端/小窗口布局组件
class _MobileLayout extends StatelessWidget {
  final bool showAppBar;
  final String title;
  final Widget? appBarActions;
  final Widget child;
  final List<SidebarGroup> groups;

  const _MobileLayout({required this.showAppBar, required this.title, this.appBarActions, required this.child, required this.groups});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 主内容区域
        Column(
          children: [
            if (showAppBar)
              Stack(
                children: [
                  if (Platform.isMacOS)
                    Padding(
                      padding: EdgeInsets.only(top: AppThemeCommon.kSpace10),
                      child: Transform.scale(scale: 0.8, alignment: Alignment.centerLeft, child: const MacWindowButtons()),
                    ),
                  Container(
                    height: scaleW(60),
                    padding: EdgeInsets.symmetric(horizontal: AppThemeCommon.kSpace12),
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.menu, size: AppThemeCommon.fontSize24),
                          onPressed: () {
                            final controller = Get.find<SidebarController>();
                            controller.openSidebar();
                          },
                        ),
                        SizedBox(width: AppThemeCommon.kSpace8),
                        Text(title, style: TextStyle(fontSize: AppThemeCommon.fontSize18)),
                        const Spacer(),
                        if (appBarActions != null) appBarActions!,
                        if (Platform.isWindows) ...[WindowsWindowButtons(), SizedBox(width: AppThemeCommon.kSpace16)],
                      ],
                    ),
                  ),
                ],
              ),
            Expanded(child: child),
          ],
        ),

        // 侧边栏（放在最顶层以确保手势优先级）
        CollapsibleSidebar(groups: groups),
      ],
    );
  }
}
