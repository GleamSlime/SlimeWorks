import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/window/screen_top_bar.dart';

/// 把一块"看起来就是标题栏"的区域纳入窗口拖拽：按住拖动窗口、双击最大化/还原。
///
/// **为什么必须有这一层**（Windows 独有的坑）：
///
/// macOS 用的是 `TitleBarStyle.hidden` + `fullSizeContentView`：系统标题栏其实
/// 还在，只是透明——鼠标按在那条区域里由 AppKit 自己拖窗口，跟 Flutter 的命中
/// 测试毫无关系。所以 macOS 上"抓顶栏哪一处都能拖"是系统给的，不是我们画的。
///
/// Windows 没有这个原生兜底，无边框窗口里**只有 Flutter 自己发起的拖拽**
/// （`ScreenTopBar` → `windowManager.startDragging()` → `SC_MOVE`）。而 Flutter
/// 的命中解析是"同层最上面命中即止"：`ScreenTopBar` 是一条压在页面树**之下**的
/// 透明带，只有**纯空白像素**能落到它上面；标题文字（`RenderParagraph` 的
/// `hitTestSelf` 返回 true）、返回键、面包屑、工具栏都会吃掉命中。于是 Windows
/// 上"抓住标题文字那一带拖"毫无反应，macOS 却照常能拖——同一份 Dart 代码，
/// 两种表现。
///
/// 这一层把手势挂到**祖先**位置（`Listener` 只旁听指针，不参与手势竞技），
/// 所以控件照旧先拿到按下：单击返回、点面包屑跳转、悬停提示都不受影响；只有
/// 指针真的移动超过阈值，才把这次按住翻译成拖窗口，并当场作废这个指针序列
/// （否则底下的点击识别器会一直等一个永远不会回来的 up，下次按下的判定被带偏）。
class WindowDragRegion extends StatefulWidget {
  const WindowDragRegion({
    super.key,
    required this.child,
    this.doubleTapToMaximize = false,
  });

  final Widget child;

  /// 双击这一格是否最大化/还原。
  ///
  /// 只在**这一格里没有任何可点控件**时才该开：双击识别器会把单击压到
  /// 双击超时（约 300ms）之后才放行，这一格里有可点的面包屑/按钮时，用户
  /// 点一下会明显觉得"慢半拍"。侧栏头部（连点 logo 回概览）同理不开。
  final bool doubleTapToMaximize;

  /// 自己实现拖窗口只在 Windows/Linux 上需要。
  ///
  /// macOS 有系统标题栏兜底，这里再挂一层只会和 AppKit 抢同一次按下，
  /// 白冒一份风险，所以直接放行。
  static bool get supported =>
      debugForceSupportedForTest ?? (Platform.isWindows || Platform.isLinux);

  /// 测试用开关：在 macOS 上跑用例时把这条通路打开，否则拖拽分支永远走不到
  @visibleForTesting
  static bool? debugForceSupportedForTest;

  /// 起拖阈值：太小会把点击抖成拖窗口，太大又像"卡一下才跟手"。
  static const double kDragSlop = 5;

  @override
  State<WindowDragRegion> createState() => _WindowDragRegionState();
}

class _WindowDragRegionState extends State<WindowDragRegion> {
  /// 本次按下的起点；一旦起拖或抬起就清空
  Offset? _pressOrigin;

  /// 本次按下是否已经交出去拖窗口了
  bool _handedOver = false;

  void _onPointerDown(PointerDownEvent event) {
    // 只认鼠标左键：右键/中键拖窗口是反常行为
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    _pressOrigin = event.position;
    _handedOver = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_handedOver) return;
    final Offset? origin = _pressOrigin;
    if (origin == null) return;
    if ((event.position - origin).distance < WindowDragRegion.kDragSlop) {
      return;
    }
    _pressOrigin = null;
    _handedOver = true;
    // 先把这个指针序列在 Flutter 侧作废，再交给系统：startDragging 之后这个
    // 指针的 up 不会再回到 Flutter，留着会让底下的点击识别器一直挂着等。
    GestureBinding.instance.cancelPointer(event.pointer);
    windowManager.startDragging();
  }

  void _onPointerRelease(PointerEvent event) {
    _pressOrigin = null;
    _handedOver = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowDragRegion.supported) return widget.child;

    final Widget listener = Listener(
      // translucent：这一格的空白处也算标题栏（文字之间、右侧留白都能拖）。
      // 它不会挡住兄弟控件——命中结果里只是多挂一条本层记录。
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerRelease,
      onPointerCancel: _onPointerRelease,
      child: widget.child,
    );

    // 不需要双击时才不挂 GestureDetector：空的双击识别器也会参与手势竞技，
    // 白白在每次按下时走一遍竞技流程。
    if (!widget.doubleTapToMaximize) return listener;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: ScreenTopBar.handleDoubleTap,
      child: listener,
    );
  }
}
