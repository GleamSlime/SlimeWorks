import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/theme/app_semantics.dart';

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

/// macOS 上内容底色的玻璃不透明度。
///
/// 只有 macOS 有原生 behindWindow 振动层可以透；其它平台窗口本身不透明，
/// 留半透明只会和窗口底色混色，拿不到磨砂。正文密度远高于侧栏，所以这里
/// 给的值更高（更实），先把正文对比度守住。
const int kContentGlassAlphaMacOS = 180;

class _DesktopShell extends StatelessWidget {
  final Widget sidebar;
  final Widget child;

  const _DesktopShell({required this.sidebar, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isImmersive = getIt<DesktopScreenProvider>().desktopImmersiveMode.value;
      final contentAlpha = Platform.isMacOS ? kContentGlassAlphaMacOS : 255;
      if (isImmersive) {
        // 沉浸模式：不显示侧边栏和顶部栏，整窗都是内容区。
        return _ContentSurface(alpha: contentAlpha, child: child);
      }
      return Row(
        children: [
          sidebar,
          Expanded(
            child: _ContentSurface(
              alpha: contentAlpha,
              child: Column(
                children: [
                  const DesktopTopBar(),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// 内容区底色。
///
/// macOS 上根 Material 已经改成透明以便透出原生振动层，所以内容区必须自己铺
/// 一层底色——页面基类 BasePage 的 Scaffold 也是 transparent，完全不铺的话文字
/// 会直接压在桌面上。alpha=255 时就是原来的实心底。
class _ContentSurface extends StatelessWidget {
  const _ContentSurface({required this.child, this.alpha = 255});

  final Widget child;
  final int alpha;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppSemantic.of(context).canvas.withAlpha(alpha), child: child);
  }
}

class MobileLayout extends StatelessWidget {
  final Widget child;

  const MobileLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sidebarExpandScale = getIt<DesktopScreenProvider>().sidebarExpandScale.value;

      // 这个分支里侧栏是浮在内容之上的，不是贴在桌面之上，所以整窗都要不透明；
      // 否则窄窗口下根 Material 一透明，正文就直接压在桌面背景上了。
      return _ContentSurface(
        child: Stack(
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
        ),
      );
    });
  }
}
