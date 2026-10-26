import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/widgets/atmosphere_backdrop.dart';
import 'package:slime_works/components/window/window_backdrop.dart';

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
      final contentAlpha = WindowGlass.contentAlpha;
      if (isImmersive) {
        // 沉浸模式：不显示侧边栏和顶部栏，整窗都是内容区。
        return _ContentSurface(alpha: contentAlpha, child: child);
      }
      return Row(
        children: [
          sidebar,
          Expanded(
            // 侧栏把手压在内容区左缘上：侧栏内部有滚动条，Row 里内容区又后画
            child: Stack(
              children: [
                // 内容区必须 Positioned.fill：Stack 给非定位子件的是松约束，
                // 宽度就会按内容自己收缩，不再是铺满这一格
                Positioned.fill(
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
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: const SidebarResizeStrip(),
                ),
              ],
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
/// 会直接压在桌面上。
///
/// v2 起这一层不再是纯色 `canvas`，而是**全站唯一的氛围层出处**（柔彩对角底 +
/// 四团色团）。`alpha < 255`（内容区要透出桌面）时整层一起降不透明度，
/// 不是只把基色调透——那样色团会盖过基色、层次倒挂。
class _ContentSurface extends StatelessWidget {
  const _ContentSurface({required this.child, this.alpha = 255, this.layered = true});

  final Widget child;
  final int alpha;

  /// false = 移动端/窄窗：只留单层对角渐变
  final bool layered;

  @override
  Widget build(BuildContext context) {
    return AtmosphereBackdrop(
      layered: layered,
      opacity: alpha / 255,
      child: child,
    );
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
        // 窄窗/移动端：颜色语言保留、四团色团裁掉（§8），整窗仍不透明
        layered: false,
        child: Stack(
          children: [
            // 内容区（侧边栏展开时缩放）
            AnimatedScale(
              scale: sidebarExpandScale,
              duration: sidebarExpandScale == 1.0 || sidebarExpandScale == 0.9
                  ? AppMotion.base
                  : Duration.zero,
              curve: AppMotion.decelerate,
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
