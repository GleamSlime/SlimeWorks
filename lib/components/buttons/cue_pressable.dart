import 'dart:io';

import 'package:cue/cue.dart';
import 'package:flutter/material.dart';

/// 通用可交互容器，集成 Cue 动画库，提供：
/// - 桌面/平板：悬停放大反馈（`Cue.onHover`）
/// - 全平台：点击轻微缩放反馈（`Cue.onToggle` + GestureDetector）
///
/// 适合代替原先手动管理的 AnimatedScale + GestureDetector 组合。
///
/// 示例用法：
/// ```dart
/// CuePressable(
///   onTap: () => doSomething(),
///   child: Container(
///     padding: const EdgeInsets.all(12),
///     child: const Text('点击我'),
///   ),
/// )
/// ```
class CuePressable extends StatefulWidget {
  /// 点击回调（可为 null，此时按钮视觉上禁用）
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 子组件
  final Widget child;

  /// 悬停时放大比例（仅桌面/Web，默认 1.04）
  final double hoverScale;

  /// 点击时缩小比例（默认 0.95）
  final double pressScale;

  /// 动画弹性风格（默认 `.interactive()`）
  final CueMotion? motion;

  /// 点击动效的 motion（默认 `.snappy()`）
  final CueMotion? pressMotion;

  /// 命中测试行为
  final HitTestBehavior? behavior;

  const CuePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.hoverScale = 1.04,
    this.pressScale = 0.95,
    this.motion,
    this.pressMotion,
    this.behavior,
  });

  @override
  State<CuePressable> createState() => _CuePressableState();
}

class _CuePressableState extends State<CuePressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool useHover = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    // 内层：点击缩放
    Widget pressLayer = Cue.onToggle(
      toggled: _pressed,
      motion: widget.pressMotion ?? const CueMotion.snappy(),
      acts: [Act.scale(to: widget.pressScale)],
      child: widget.child,
    );

    // 外层：悬停放大（仅桌面）
    if (useHover) {
      pressLayer = Cue.onHover(
        motion: widget.motion ?? const CueMotion.smooth(),
        acts: [Act.scale(to: widget.hoverScale)],
        child: pressLayer,
      );
    }

    return GestureDetector(
      behavior: widget.behavior ?? HitTestBehavior.opaque,
      onTapDown: widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: pressLayer,
    );
  }
}
