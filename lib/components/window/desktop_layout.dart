import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
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
          spacing: appMetrics.kSpace12,
          children: [
            if (chrome.hasLeading) chrome.leading!,
            // if (chrome.title != null || chrome.titleWidget != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    chrome.titleWidget ??
                    (chrome.title != null
                        ? Text(chrome.title!, style: Theme.of(context).textTheme.titleMedium)
                        : const SizedBox.shrink()),
              ),
            ),
            if (!chrome.hasLeading) const Spacer(),
            if (chrome.hasActions)
              Row(
                spacing: AppTheme.metrics.kSpace12,
                mainAxisSize: MainAxisSize.min,
                children: chrome.actions,
              ),
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
            if (Platform.isWindows) const WindowsWindowButtons(),
          ],
        ),
      );
    });
  }
}

class MobileLayout extends StatefulWidget {
  final Widget child;

  const MobileLayout({super.key, required this.child});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  static const Duration _kChromeAnimationDuration = Duration(milliseconds: 180);
  static const double _kTapSlop = 10;
  static const double _kDownSwipeThreshold = 18;

  final DesktopScreenProvider desktopScreen = getIt<DesktopScreenProvider>();
  Offset? _pointerDownPosition;
  Offset? _latestPointerPosition;

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.position;
    _latestPointerPosition = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _latestPointerPosition = event.position;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _latestPointerPosition = null;
  }

  void _handlePointerUp(PointerUpEvent event) {
    final Offset? start = _pointerDownPosition;
    final Offset end = _latestPointerPosition ?? event.position;
    _pointerDownPosition = null;
    _latestPointerPosition = null;

    if (start == null) {
      return;
    }

    final Offset delta = end - start;
    final ScreenChromeData chrome = desktopScreen.screenChrome.value.data;
    if (!chrome.enableMobileImmersiveMode) {
      return;
    }

    final bool isTap = delta.distance <= _kTapSlop;
    final bool isDownSwipe = delta.dy >= _kDownSwipeThreshold && delta.dy.abs() > delta.dx.abs();
    final bool isUpSwipe = delta.dy <= -_kDownSwipeThreshold && delta.dy.abs() > delta.dx.abs();
    final bool isImmersiveMode = desktopScreen.mobileImmersiveMode.value;

    if (isImmersiveMode) {
      if (isTap) {
        desktopScreen.setMobileImmersiveMode(false);
      }
      return;
    }

    if (isUpSwipe) {
      return;
    }
    if (isTap || isDownSwipe) {
      desktopScreen.setMobileImmersiveMode(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chrome = desktopScreen.screenChrome.value.data;
      final title = chrome.title ?? desktopScreen.title.value;
      final sidebarExpandScale = desktopScreen.sidebarExpandScale.value;
      final bool showToolbar = chrome.hasToolbar && sidebarExpandScale >= 1.0;
      final bool showBottomBar = chrome.hasBottomBar && sidebarExpandScale >= 1.0;
      final bool isImmersiveMode = desktopScreen.mobileImmersiveMode.value;
      final bool bodyHandlesInsets = chrome.mobileBodyHandlesInsets;
      final double safeTop = MediaQuery.paddingOf(context).top;
      final double safeBottom = MediaQuery.paddingOf(context).bottom;
      final double resolvedToolbarHeight = AppTheme.metrics.kSpace48;
      final double resolvedBottomHeight = showToolbar
          ? (chrome.toolbarHeight ?? AppTheme.metrics.kSpace24)
          : 0;
      final double chromeHeight = safeTop + resolvedToolbarHeight + resolvedBottomHeight;
      final double bottomBarHeight = showBottomBar
          ? (chrome.bottomBarHeight ?? (AppTheme.metrics.kSpace48 + AppTheme.metrics.kSpace8))
          : 0;
      final EdgeInsets immersivePadding = chrome.mobileImmersivePadding;
      final double contentTopPadding = bodyHandlesInsets
          ? 0
          : (isImmersiveMode ? safeTop + immersivePadding.top : chromeHeight);
      final double contentBottomPadding = bodyHandlesInsets
          ? 0
          : (isImmersiveMode ? safeBottom + immersivePadding.bottom : bottomBarHeight);

      return Scaffold(
        body: Stack(
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerUp,
              onPointerCancel: _handlePointerCancel,
              child: AnimatedPadding(
                duration: _kChromeAnimationDuration,
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(top: contentTopPadding, bottom: contentBottomPadding),
                child: Stack(
                  children: [
                    AnimatedScale(
                      scale: sidebarExpandScale,
                      duration: sidebarExpandScale == 1.0 || sidebarExpandScale == 0.9
                          ? const Duration(milliseconds: 200)
                          : Duration.zero,
                      curve: Curves.easeOutCubic,
                      child: widget.child,
                    ),
                    CollapsibleSidebar(groups: DesktopLayout.getDefaultSidebarGroups()),
                  ],
                ),
              ),
            ),
            _MobileChromeOverlay(
              chrome: chrome,
              title: title,
              showToolbar: showToolbar,
              isImmersiveMode: isImmersiveMode,
              toolbarHeight: resolvedToolbarHeight,
              bottomHeight: resolvedBottomHeight,
              animationDuration: _kChromeAnimationDuration,
            ),
            _MobileBottomOverlay(
              chrome: chrome,
              showBottomBar: showBottomBar,
              isImmersiveMode: isImmersiveMode,
              bottomBarHeight: bottomBarHeight,
              animationDuration: _kChromeAnimationDuration,
            ),
          ],
        ),
      );
    });
  }
}

class _MobileChromeOverlay extends StatelessWidget {
  final ScreenChromeData chrome;
  final String title;
  final bool showToolbar;
  final bool isImmersiveMode;
  final double toolbarHeight;
  final double bottomHeight;
  final Duration animationDuration;

  const _MobileChromeOverlay({
    required this.chrome,
    required this.title,
    required this.showToolbar,
    required this.isImmersiveMode,
    required this.toolbarHeight,
    required this.bottomHeight,
    required this.animationDuration,
  });

  @override
  Widget build(BuildContext context) {
    final double safeTop = MediaQuery.paddingOf(context).top;
    final double totalHeight = safeTop + toolbarHeight + bottomHeight;
    final ThemeData theme = Theme.of(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: isImmersiveMode,
        child: ClipRect(
          child: AnimatedContainer(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            height: isImmersiveMode ? 0 : totalHeight,
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: totalHeight,
              maxHeight: totalHeight,
              child: AnimatedSlide(
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                offset: isImmersiveMode ? const Offset(0, -1) : Offset.zero,
                child: Material(
                  color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
                  elevation: 4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SafeArea(
                        bottom: false,
                        child: SizedBox(
                          height: toolbarHeight,
                          child: AppBar(
                            primary: false,
                            toolbarHeight: toolbarHeight,
                            leading: chrome.leading,
                            centerTitle: true,
                            title: chrome.titleWidget ?? Text(title),
                            actions: chrome.hasActions ? chrome.actions : null,
                            actionsPadding: EdgeInsets.zero,
                            bottom: chrome.bottomBar != null
                                ? PreferredSize(
                                    preferredSize: Size.fromHeight(bottomHeight),
                                    child: chrome.bottomBar!,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      if (showToolbar)
                        SizedBox(
                          height: bottomHeight,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppTheme.metrics.kSpace12,
                              vertical: AppTheme.metrics.kSpace8,
                            ),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: chrome.toolbar ?? const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileBottomOverlay extends StatelessWidget {
  final ScreenChromeData chrome;
  final bool showBottomBar;
  final bool isImmersiveMode;
  final double bottomBarHeight;
  final Duration animationDuration;

  const _MobileBottomOverlay({
    required this.chrome,
    required this.showBottomBar,
    required this.isImmersiveMode,
    required this.bottomBarHeight,
    required this.animationDuration,
  });

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    final double totalHeight = bottomBarHeight + safeBottom;
    final ThemeData theme = Theme.of(context);

    // debugPrint(
    //   'Building MobileBottomOverlay: showBottomBar=$showBottomBar, isImmersiveMode=$isImmersiveMode, totalHeight=$totalHeight',
    // );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: isImmersiveMode || !showBottomBar,
        child: ClipRect(
          child: AnimatedContainer(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            height: showBottomBar && !isImmersiveMode ? totalHeight : 0,
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: totalHeight,
              maxHeight: totalHeight,
              child: AnimatedSlide(
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                offset: showBottomBar && !isImmersiveMode ? Offset.zero : const Offset(0, 1),
                child: Material(
                  color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
                  elevation: 8,
                  child: SizedBox(
                    height: totalHeight,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: safeBottom),
                      child: SizedBox(
                        height: bottomBarHeight,
                        child: chrome.bottomBar ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
