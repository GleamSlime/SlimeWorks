import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/routes/role_manager.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class DesktopLayout extends StatelessWidget {
  final Widget child;

  const DesktopLayout({super.key, required this.child});

  /// 获取默认的侧边栏配置
  static List<SidebarGroup> getDefaultSidebarGroups() {
    return [
      coreSidebarGroup,
      collectionSidebarGroup,
      // 第一组：主要功能
      // SidebarGroup(
      //   items: [
      //     SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '概览', route: '/dashboard'),
      //     SidebarMenuItem(icon: Assets.image.svg.menuCapture, label: '数据捕获', route: '/capture'),
      //     SidebarMenuItem(icon: Assets.image.svg.menuBill, label: '流水账', route: '/clearwater'),
      //     SidebarMenuItem(
      //       icon: Assets.image.svg.menuAli,
      //       label: '阿里云',
      //       children: [
      //         SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'OSS存储', route: '/aliyun/oss'),
      //         SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'DNS管理', route: '/aliyun/dns'),
      //       ],
      //     ),
      //     SidebarMenuItem(
      //       icon: Assets.image.svg.menuTools,
      //       label: '工具箱',
      //       children: [
      //         SidebarMenuItem(icon: Assets.image.svg.menuToolsVideo, label: '视频工具', route: '/tools/video'),
      //         SidebarMenuItem(icon: Assets.image.svg.menuToolsPictures, label: '图片工具', route: '/tools/image'),
      //       ],
      //     ),
      //     SidebarMenuItem(icon: Assets.image.svg.menuMediaLibrary, label: '媒体库', route: '/media-library'),
      //   ],
      // ),

      // // 第二组：收藏
      // SidebarGroup(
      //   title: '收藏',
      //   items: [
      //     SidebarMenuItem(icon: Assets.image.svg.menuCollectNote, label: '笔记', route: '/favorites/notes', badge: 61),
      //     SidebarMenuItem(icon: Assets.image.svg.menuCollectCredentials, label: '账密', route: '/favorites/accounts', badge: 37),
      //     SidebarMenuItem(icon: Assets.image.svg.menuCollectFile, label: '文件', route: '/favorites/files'),
      //     SidebarMenuItem(icon: Assets.image.svg.menuCollectPictures, label: '图片', route: '/favorites/images'),
      //   ],
      // ),

      // // 第三组：插件
      // SidebarGroup(
      //   title: '插件',
      //   items: [
      //     SidebarMenuItem(icon: Assets.image.svg.menuTools, label: '模块管理', route: '/module-management'),
      //     SidebarMenuItem(icon: Assets.image.svg.menuCloudAccess, label: '云访问', route: '/plugins/cloud-access'),
      //     SidebarMenuItem(icon: Assets.image.svg.menuDistributed, label: '分布式', route: '/plugins/distributed'),
      //   ],
      // ),

      // // 第四组：测试
      // if (kDebugMode)
      //   SidebarGroup(
      //     title: '测试',
      //     items: [
      //       SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '主题测试', route: '/theme-preview'),
      //       SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'WS测试', route: '/websocket-test'),
      //       SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: 'HTTP测试', route: '/http-bridge-test'),
      //       SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '小说库测试', route: '/novel-library'),
      //     ],
      //   ),

      // // 第四组：系统
      bottomSidebarGroup,
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 只在桌面平台显示完整布局
    if ((!Platform.isMacOS && !Platform.isWindows)) {
      return Stack(
        children: [
          child,
          CollapsibleSidebar(groups: getDefaultSidebarGroups()),
        ],
      );
    }

    ThemeData theme = Theme.of(context);

    return DesktopScaffold(
      child: Obx(
        () => getIt<DesktopScreenProvider>().isMobile.value
            ? Stack(
                children: [
                  child,
                  CollapsibleSidebar(groups: getDefaultSidebarGroups()),
                ],
              )
            : Row(
                children: [
                  CollapsibleSidebar(groups: getDefaultSidebarGroups()),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.only(right: AppTheme.metrics.kSpace20, top: AppTheme.metrics.kSpace4),
                          height: scaleW(60),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: theme.appBarTheme.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(10))],
                                ),
                                child: Obx(() => getIt<DesktopScreenProvider>().screenHeadToolsWidget.value),
                              ),
                              if (Platform.isWindows) const WindowsWindowButtons(),
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
