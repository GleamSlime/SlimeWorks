import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class DesktopLayout extends StatefulWidget {
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
      //       SidebarMenuItem(icon: Assets.image.svg.menuAggregation, label: '书籍库测试', route: '/novel-library'),
      //     ],
      //   ),
      demoSidebarGroup,

      // // 第四组：系统
      bottomSidebarGroup,
    ];
  }

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
  late final Widget _sidebar = RepaintBoundary(
    child: CollapsibleSidebar(groups: DesktopLayout.getDefaultSidebarGroups()),
  );

  @override
  Widget build(BuildContext context) {
    /// -----------------------------
    /// 移动端
    /// -----------------------------
    if ((!Platform.isMacOS && !Platform.isWindows)) {
      return MobileLayout(child: widget.child);
    }

    /// -----------------------------
    /// 桌面端
    /// -----------------------------

    return DesktopScaffold(
      child: Obx(() {
        final provider = getIt<DesktopScreenProvider>();
        final isMobile = provider.isMobile.value;

        if (isMobile) {
          return MobileLayout(child: widget.child);
        }

        return _DesktopShell(sidebar: _sidebar, child: widget.child);
      }),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  final Widget sidebar;
  final Widget child;

  const _DesktopShell({required this.sidebar, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        sidebar,
        Expanded(
          child: Column(
            children: [
              const _DesktopTopBar(),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chrome = getIt<DesktopScreenProvider>().screenChrome.value.data;

      return Container(
        padding: EdgeInsets.only(
          left: AppTheme.metrics.kSpace12,
          right: AppTheme.metrics.kSpace16,
          top: AppTheme.metrics.kSpace4,
        ),
        height: scaleW(60),
        child: Row(
          children: [
            if (chrome.hasLeading) chrome.leading!,
            if (chrome.hasLeading) SizedBox(width: AppTheme.metrics.kSpace12),
            const Spacer(),
            if (chrome.hasActions)
              Row(
                spacing: AppTheme.metrics.kSpace12,
                mainAxisSize: MainAxisSize.min,
                children: chrome.actions,
              ),
            if (chrome.hasActions && chrome.hasToolbar) SizedBox(width: AppTheme.metrics.kSpace12),
            if (chrome.hasToolbar)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    height: chrome.toolbarHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Center(child: chrome.toolbar!),
                    ),
                  ),
                ),
              ),
            if (Platform.isWindows) ...[
              SizedBox(width: AppTheme.metrics.kSpace12),
              const WindowsWindowButtons(),
            ],
          ],
        ),
      );
    });
  }
}

class MobileLayout extends StatelessWidget {
  final Widget child;

  MobileLayout({super.key, required this.child});

  final DesktopScreenProvider desktopScreen = getIt<DesktopScreenProvider>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chrome = desktopScreen.screenChrome.value.data;
      final title = chrome.title ?? desktopScreen.title.value;
      final sidebarExpandScale = desktopScreen.sidebarExpandScale.value;
      final bool showToolbar = chrome.hasToolbar && sidebarExpandScale >= 1.0;

      return Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(scaleW(showToolbar ? 75 : 50)),
          child: AppBar(
            leading: chrome.leading,
            centerTitle: true,
            title: chrome.titleWidget ?? Text(title),
            actions: chrome.hasActions ? chrome.actions : null,
            actionsPadding: EdgeInsets.zero,
            bottom: showToolbar
                ? PreferredSize(
                    preferredSize: Size.fromHeight(
                      chrome.toolbarHeight ?? AppTheme.metrics.kSpace24,
                    ),
                    child: SizedBox(
                      height: chrome.toolbarHeight ?? AppTheme.metrics.kSpace24,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: chrome.toolbar ?? const SizedBox.shrink(),
                      ),
                    ),
                  )
                : null,
          ),
        ),
        body: Stack(
          children: [
            AnimatedScale(
              scale: sidebarExpandScale,
              duration: const Duration(milliseconds: 120),
              child: child,
            ),
            CollapsibleSidebar(groups: DesktopLayout.getDefaultSidebarGroups()),
          ],
        ),
      );
    });
  }
}
