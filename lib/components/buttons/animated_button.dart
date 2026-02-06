import 'package:flutter/material.dart';
import 'package:slime_works/components/animations/state_transition_animation.dart';

class AnimatedButton extends StatelessWidget {
  final void Function()? onTap;

  // All params forwarded to StateTransitionAnimation
  final String? svg;
  final String? label;
  final String? hoverSvg;
  final bool enableScaleAnimation;
  final Duration animationDuration;

  // style
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final double? svgSize;
  final Color? svgColor;
  final double? spacing;
  final bool? loading;

  const AnimatedButton({
    super.key,
    this.onTap,
    this.svg,
    this.label,
    this.hoverSvg,
    this.enableScaleAnimation = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.height,
    this.padding,
    this.decoration,
    this.textStyle,
    this.svgSize,
    this.svgColor,
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
          svg: svg,
          label: label,
          hoverSvg: hoverSvg,
          enableScaleAnimation: enableScaleAnimation,
          animationDuration: animationDuration,
          height: height,
          padding: padding,
          decoration: decoration,
          textStyle: textStyle,
          svgSize: svgSize,
          spacing: spacing,
          svgColor: svgColor,
          loading: loading,
        ),
      ),
    );
  }
}
