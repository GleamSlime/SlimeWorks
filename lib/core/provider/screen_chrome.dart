import 'package:flutter/material.dart';

@immutable
class ScreenChromeData {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? toolbar;
  final double? toolbarHeight;
  final Widget? bottomBar;
  final double? bottomBarHeight;
  final bool enableMobileImmersiveMode;
  final bool mobileBodyHandlesInsets;
  final EdgeInsets mobileImmersivePadding;

  /// 移动端顶部 AppBar 背景色（null 则使用主题 appBarTheme.backgroundColor）
  final Color? mobileAppBarColor;

  const ScreenChromeData({
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.toolbar,
    this.toolbarHeight,
    this.titleWidget,
    this.bottomBar,
    this.bottomBarHeight,
    this.enableMobileImmersiveMode = false,
    this.mobileBodyHandlesInsets = false,
    this.mobileImmersivePadding = EdgeInsets.zero,
    this.mobileAppBarColor,
  });

  static const ScreenChromeData empty = ScreenChromeData();

  bool get hasLeading => leading != null;

  bool get hasActions => actions.isNotEmpty;

  bool get hasToolbar => toolbar != null && (toolbarHeight ?? 0) > 0;

  bool get hasBottomBar => bottomBar != null && (bottomBarHeight ?? 0) > 0;
}

@immutable
class ScreenChromeEntry {
  final Object? owner;
  final ScreenChromeData data;

  const ScreenChromeEntry({this.owner, this.data = ScreenChromeData.empty});

  const ScreenChromeEntry.empty() : owner = null, data = ScreenChromeData.empty;
}
