import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 磨砂玻璃面板
///
/// 两层结构才能实现"透出背后内容"：
/// 1. 窗口本身透明（见 `MainFlutterWindow.swift` 挂 `NSVisualEffectView`）——
///    负责透出**桌面/窗口下方**的内容；
/// 2. 面板再叠一层局部 [BackdropFilter]——负责透出**同一 App 内**它下面的内容
///    （列表滚动到面板下方时能隐约看见，这是层次感的关键）。
///
/// 因此本组件对两者都成立：原生模糊未开启时退化为半透明色块，仍然可用。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur,
    this.tint,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.elevated = true,
    this.asPanel = false,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// 模糊半径；默认取语义层的 glassBlur
  final double? blur;

  /// 玻璃着色层；默认按明暗取（亮色偏白、暗色偏黑），不要写死 Colors.white
  final Color? tint;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool elevated;

  /// asPanel=true 时使用更透明的面板级着色（侧边栏这类常驻大色块）
  final bool asPanel;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final radius = borderRadius ?? (asPanel ? m.radiusPanel : m.radiusCard);
    final effectiveTint =
        tint ?? (asPanel ? s.glassPanelTint : s.glassTint);

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur ?? s.glassBlur,
          sigmaY: blur ?? s.glassBlur,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: effectiveTint,
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? s.glassBorder,
              width: scaleW(1),
            ),
            boxShadow: elevated ? s.elevation(Elevation.floating) : null,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// 顶/底部的毛玻璃吸附条（内容从其下方滚过时透出）
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.bottom,
  });

  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(scaleW(52) + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppGlass.blurMedium,
          sigmaY: AppGlass.blurMedium,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: s.glassTint,
            border: Border(bottom: BorderSide(color: s.hairline, width: scaleW(1))),
          ),
          child: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: centerTitle,
            leading: leading,
            title: title,
            actions: actions,
            bottom: bottom,
          ),
        ),
      ),
    );
  }
}

/// 浮层通用容器：把"毛玻璃 + 圆角 + 投影"这套浮层语言统一起来。
/// 用于命令面板、悬浮工具条、下拉浮窗。
class GlassFloat extends StatelessWidget {
  const GlassFloat({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return GlassSurface(
      asPanel: true,
      padding: padding ?? EdgeInsets.all(m.kSpace6),
      borderRadius: borderRadius ?? m.radiusOverlay,
      child: child,
    );
  }
}
