import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 统一可交互容器：悬停时改变**底色**而非缩放。
///
/// 为什么不用缩放做 hover 反馈：`CuePressable` 的 1.04 放大适合图标这类
/// 小面积元素；用在卡片上会让整排内容抖动、相邻卡片互相重叠，是"廉价感"
/// 的主要来源。工具类界面通行做法是底色 + 描边提亮，位移只留给按压瞬间。
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.borderRadius,
    this.hoverColor,
    this.pressColor,
    this.defaultColor = Colors.transparent,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// 悬停高亮的圆角，需与外层卡片一致，否则会出现方角光斑
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? pressColor;
  final Color defaultColor;
  final bool enabled;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final color = !_interactive
        ? widget.defaultColor
        : _pressed
        ? (widget.pressColor ?? s.surfaceActive)
        : _hovered
        ? (widget.hoverColor ?? s.surfaceHover)
        : widget.defaultColor;

    return MouseRegion(
      cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: _interactive ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onTapDown: _interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _interactive ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          decoration: BoxDecoration(color: color, borderRadius: widget.borderRadius),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 标准卡片容器
///
/// 收敛点：项目原本有 95 处手写 `BoxShadow`、三套卡片圆角。统一为
/// 「表面色 + 发丝描边 + 极浅投影」，并让投影跟随明暗主题。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevated = false,
    this.selected = false,
    this.hoverable = true,
    this.borderRadius,
    this.borderColor,
    this.color,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// true 时叠加投影（用于浮在列表之上的强调块）
  final bool elevated;
  final bool selected;
  final bool hoverable;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? color;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final radius = borderRadius ?? m.radiusCard;

    final decoration = BoxDecoration(
      color: color ?? (selected ? s.surfaceActive : s.surface),
      borderRadius: radius,
      border: Border.all(
        color: selected ? s.accentContainerBorder : (borderColor ?? s.hairline),
        width: scaleW(selected ? 1.4 : 1),
      ),
      boxShadow: elevated ? s.elevation(Elevation.card) : null,
    );

    final content = Padding(
      padding: padding ?? EdgeInsets.all(m.kSpace16),
      child: child,
    );

    if (!hoverable && onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }

    return Hoverable(
      onTap: onTap,
      borderRadius: radius,
      hoverColor: s.surfaceHover,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        decoration: decoration,
        child: content,
      ),
    );
  }
}

/// 统计数字卡（原 `_StatCardHover` / `_StatChip` / `StatCard` 等 6 种实现的统一体）
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.tone,
    this.onTap,
  });

  final String label;
  final String value;

  /// 数值下方的一行补充说明
  final String? hint;
  final IconData? icon;

  /// 语义着色（成功/警告/危险…）；为 null 时用中性色
  final AppStatusRole? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final accent = tone?.color ?? s.textPrimary;

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(
        horizontal: m.kSpace16,
        vertical: m.kSpace14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 无色调时用"浮起"而不是"下沉"：暗色下 surfaceSunken 与画布同色，
                // 落在卡片上会像一个挖空的黑洞。
                color: (tone?.container ?? s.surfaceHover),
                borderRadius: m.radius8,
              ),
              child: Icon(icon, size: m.iconSize16, color: accent),
            ),
            SizedBox(width: m.kSpace12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: m.fontSize18,
                    fontWeight: FontWeight.w600,
                    color: s.textPrimary,
                    height: 1.2,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: m.kSpace2),
                Text(
                  hint ?? label,
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一分割线：比 Material 默认更克制（发丝线 + 可选左右缩进）
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.indent = 0, this.endIndent = 0, this.spacing});

  final double indent;
  final double endIndent;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Divider(
      height: spacing ?? scaleW(1),
      thickness: scaleW(1),
      indent: indent,
      endIndent: endIndent,
      color: s.hairline,
    );
  }
}
