import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';

class DesktopLayout extends StatefulWidget {
  final Widget child;

  const DesktopLayout({super.key, required this.child});

  static List<SidebarGroup> getDefaultSidebarGroups() {
    return buildSidebarGroupsFromRoutes();
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
    if ((!Platform.isMacOS && !Platform.isWindows)) {
      return MobileLayout(child: widget.child);
    }

    return Obx(() {
      final provider = getIt<DesktopScreenProvider>();
      final isMobile = provider.isMobile.value;

      if (isMobile) {
        return MobileLayout(child: widget.child);
      }

      return _DesktopShell(sidebar: _sidebar, child: widget.child);
    });
  }
}

class _DesktopShell extends StatelessWidget {
  final Widget sidebar;
  final Widget child;

  const _DesktopShell({required this.sidebar, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isImmersive = getIt<DesktopScreenProvider>().desktopImmersiveMode.value;
      if (isImmersive) {
        // 沉浸模式：不显示侧边栏和顶部栏
        return child;
      }
      return Row(
        children: [
          sidebar,
          Expanded(
            child: Column(
              children: [
                const DesktopTopBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class MobileLayout extends StatelessWidget {
  final Widget child;

  const MobileLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sidebarExpandScale = getIt<DesktopScreenProvider>().sidebarExpandScale.value;

      return Stack(
        children: [
          // 内容区（侧边栏展开时缩放）
          AnimatedScale(
            scale: sidebarExpandScale,
            duration: sidebarExpandScale == 1.0 || sidebarExpandScale == 0.9
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            child: child,
          ),
          // 侧边栏悬浮层（由 CollapsibleSidebar 自行管理展开/收起）
          CollapsibleSidebar(groups: DesktopLayout.getDefaultSidebarGroups()),
        ],
      );
    });
  }
}
