import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

/// 页面 Chrome 管理器
///
/// - **桌面端宽屏**：将 [ScreenChromeData] 注册到 [DesktopScreenProvider]，
///   由全局顶部栏统一渲染，直接返回 [child]。
/// - **移动端**或**桌面端窄屏**：使用标准 [Scaffold] + [AppBar] 在页面内直接渲染
///   顶部栏与底部栏，彻底避免全局状态带来的页面切换时序问题。
class ScreenChrome extends StatefulWidget {
  final ScreenChromeData data;
  final Widget child;

  const ScreenChrome({super.key, required this.data, required this.child});

  @override
  State<ScreenChrome> createState() => _ScreenChromeState();
}

class _ScreenChromeState extends State<ScreenChrome> {
  final Object _owner = Object();
  late final DesktopScreenProvider _desktopScreen = getIt<DesktopScreenProvider>();

  /// 是否使用本地 Scaffold 渲染（移动端 或 桌面端窄屏模式）
  bool get _useLocalChrome {
    if (Platform.isAndroid || Platform.isIOS) return true;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return getIt<DesktopScreenProvider>().isMobile.value;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _schedulePublishChrome();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePublishChrome();
  }

  @override
  void didUpdateWidget(covariant ScreenChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePublishChrome();
  }

  @override
  void dispose() {
    if (!_useLocalChrome) {
      final desktopScreen = _desktopScreen;
      final owner = _owner;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        desktopScreen.clearScreenChrome(owner: owner);
      });
    }
    super.dispose();
  }

  void _publishChrome() {
    if (!mounted) return;
    _desktopScreen.setScreenChrome(widget.data, owner: _owner);
  }

  void _schedulePublishChrome() {
    if (_useLocalChrome) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishChrome();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_useLocalChrome) {
      return _buildMobileWidget(context);
    }
    return widget.child;
  }

  /// 移动端：将 [ScreenChromeData] 转为标准 [Scaffold]，AppBar / BottomBar 由
  /// Flutter 框架正确处理安全区域和布局。
  Widget _buildMobileWidget(BuildContext context) {
    final data = widget.data;

    final bool hasAppBar =
        data.hasLeading ||
        data.title != null ||
        data.titleWidget != null ||
        data.hasActions ||
        data.hasToolbar;

    PreferredSizeWidget? appBar;
    if (hasAppBar) {
      appBar = AppBar(
        leading: data.hasLeading ? data.leading : null,
        automaticallyImplyLeading: !data.hasLeading,
        title: data.titleWidget ?? (data.title != null ? Text(data.title!) : null),
        actions: data.hasActions ? data.actions : null,
        bottom: data.hasToolbar
            ? PreferredSize(
                preferredSize: Size.fromHeight(data.toolbarHeight ?? 48.0),
                child: data.toolbar!,
              )
            : null,
      );
    }

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: data.hasBottomBar ? data.bottomBar : null,
      body: widget.child,
    );
  }
}
