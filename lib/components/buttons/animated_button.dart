import 'package:flutter/material.dart';
import 'package:slime_works/components/animations/state_transition_animation.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/theme/app_motion.dart';

class AnimatedButton extends StatelessWidget {
  final void Function()? onTap;

  // All params forwarded to StateTransitionAnimation
  final StrokeIcon? icon;
  final String? label;
  final StrokeIcon? hoverIcon;
  final bool enableScaleAnimation;
  final Duration animationDuration;

  // style
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final double? iconSize;
  final Color? iconColor;
  final double? spacing;
  final bool? loading;

  const AnimatedButton({
    super.key,
    this.onTap,
    this.icon,
    this.label,
    this.hoverIcon,
    this.enableScaleAnimation = true,
    // 默认档跟内层 StateTransitionAnimation 同一条：手写的 400ms 会把内层已经
    // 收好的 emphasis 顶掉，两处必须是一个数，否则同一动作两页不同速。
    this.animationDuration = AppMotion.emphasis,
    this.height,
    this.padding,
    this.decoration,
    this.textStyle,
    this.iconSize,
    this.iconColor,
    this.spacing,
    this.loading = false,
  });

  void _handleTap() {
    if (loading == true) return;
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: loading == true ? SystemMouseCursors.noDrop : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: StateTransitionAnimation(
          icon: icon,
          label: label,
          hoverIcon: hoverIcon,
          enableScaleAnimation: enableScaleAnimation,
          animationDuration: animationDuration,
          height: height,
          padding: padding,
          decoration: decoration,
          textStyle: textStyle,
          iconSize: iconSize,
          spacing: spacing,
          iconColor: iconColor,
          loading: loading,
        ),
      ),
    );
  }
}
