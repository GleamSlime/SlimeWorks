import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:slime_works/components/window/collapsible_sidebar.dart';

/// 平台检测工具类
class PlatformUtil {
  /// 是否是桌面平台 (macOS 或 Windows)
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows;

  /// 是否是移动平台 (iOS 或 Android)
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
}

/// 桌面布局页面
/// 仅用于 macOS 和 Windows 平台
class DesktopLayout extends StatelessWidget {
  final Widget child;
  final List<SidebarGroup>? sidebarGroups;
  final String title;
  final Widget? appBarActions;
  final bool showAppBar;

  const DesktopLayout({
    super.key,
    required this.child,
    this.sidebarGroups,
    this.title = '史莱姆工坊',
    this.appBarActions,
    this.showAppBar = true,
  });

  /// 获取默认的侧边栏分组配置
  static List<SidebarGroup> getDefaultSidebarGroups() {
    return [
      // 第一组：主要功能（无标题）
      SidebarGroup(
        items: [
          SidebarMenuItem(
            icon: Icons.dashboard_outlined,
            label: '概览',
            route: '/dashboard',
          ),
          SidebarMenuItem(
            icon: Icons.account_tree_outlined,
            label: '数据捕获',
            route: '/datasource',
          ),
          SidebarMenuItem(
            icon: Icons.water_drop_outlined,
            label: '流水账',
            route: '/clearwater',
          ),
          SidebarMenuItem(
            icon: Icons.cloud_outlined,
            label: '阿里云',
            children: [
              SidebarMenuItem(
                icon: Icons.storage_outlined,
                label: 'OSS存储',
                route: '/aliyun/oss',
              ),
              SidebarMenuItem(
                icon: Icons.dns_outlined,
                label: 'DNS管理',
                route: '/aliyun/dns',
              ),
            ],
          ),
          SidebarMenuItem(
            icon: Icons.build_circle_outlined,
            label: '工具箱',
            children: [
              SidebarMenuItem(
                icon: Icons.video_library_outlined,
                label: '视频工具',
                route: '/tools/video',
              ),
              SidebarMenuItem(
                icon: Icons.image_outlined,
                label: '图片工具',
                route: '/tools/image',
              ),
            ],
          ),
          SidebarMenuItem(
            icon: Icons.video_library_outlined,
            label: '媒体库',
            route: '/media-library',
          ),
        ],
      ),

      // 第二组：收藏
      SidebarGroup(
        title: '收藏',
        items: [
          SidebarMenuItem(
            icon: Icons.note_outlined,
            label: '笔记',
            route: '/favorites/notes',
            badge: 61,
          ),
          SidebarMenuItem(
            icon: Icons.fingerprint_outlined,
            label: '账密',
            route: '/favorites/accounts',
            badge: 37,
          ),
          SidebarMenuItem(
            icon: Icons.folder_outlined,
            label: '文件',
            route: '/favorites/files',
          ),
          SidebarMenuItem(
            icon: Icons.image_outlined,
            label: '图片',
            route: '/favorites/images',
          ),
        ],
      ),

      // 第三组：插件
      SidebarGroup(
        title: '插件',
        items: [
          SidebarMenuItem(
            icon: Icons.cloud_queue_outlined,
            label: '云访问',
            route: '/plugins/cloud-access',
          ),
          SidebarMenuItem(
            icon: Icons.share_outlined,
            label: '分布式',
            route: '/plugins/distributed',
          ),
        ],
      ),

      // 第四组：设置（无标题）
      SidebarGroup(
        items: [
          SidebarMenuItem(
            icon: Icons.info_outline,
            label: '关于',
            route: '/about',
          ),
          SidebarMenuItem(
            icon: Icons.settings_outlined,
            label: '设置',
            route: '/settings',
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 如果不是桌面平台，直接返回子组件
    if (!PlatformUtil.isDesktop) {
      return child;
    }

    final theme = Theme.of(context);
    final groups = sidebarGroups ?? getDefaultSidebarGroups();

    return Scaffold(
      body: Row(
        children: [
          // 左侧：可收起的侧边栏
          CollapsibleSidebar(groups: groups),

          // 右侧：主内容区域
          Expanded(
            child: Column(
              children: [
                // 顶部应用栏 (可选)
                if (showAppBar)
                  Container(
                    height: 56.h,
                    decoration: BoxDecoration(
                      color:
                          theme.appBarTheme.backgroundColor ??
                          theme.colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Text(title, style: theme.textTheme.titleLarge),
                        const Spacer(),
                        if (appBarActions != null) appBarActions!,
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),

                // 主内容
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
