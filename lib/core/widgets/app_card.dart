import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_zone.dart';
import 'package:slime_works/core/theme/app_atmosphere.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 统一可交互容器：悬停时改变**状态层**而非缩放。
///
/// 为什么不用缩放做 hover 反馈：`CuePressable` 的 1.04 放大适合图标这类
/// 小面积元素；用在卡片上会让整排内容抖动、相邻卡片互相重叠，是"廉价感"
/// 的主要来源。工具类界面通行做法是底色 + 描边提亮，位移只留给按压瞬间。
///
/// 水洗画在内容**之上**（Stack 顶层），不是之下：画在下面的话，子节点那层
/// 不透明卡片底色会把它整个盖掉，hover 永远看不见——这正是原来的 bug。
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
    // 状态层：悬停用中性水洗，按压用强调色水洗。两者都必须是**半透明**的，
    // 因为它画在内容之上——实心色会把卡片里的文字整个盖掉。
    final Color wash = !_interactive
        ? Colors.transparent
        : _pressed
        ? (widget.pressColor ?? s.accent.withValues(alpha: 0.12))
        : _hovered
        ? (widget.hoverColor ?? s.surfaceHover)
        : Colors.transparent;

    final surface = MouseRegion(
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
        child: Stack(
          children: [
            // 底色在内容之下
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.defaultColor,
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
            widget.child,
            // 状态层在内容之上；不吃事件，点击仍然落到下面的内容
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  decoration: BoxDecoration(
                    color: wash,
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // 事件源放在 Hoverable 上：卡片/列表行里图标往往只占 16px，点在文字上时
    // 也该让整行的图标一起描一次，否则读起来像"按了没反应"。
    return StrokeZone(enabled: _interactive, child: surface);
  }
}

/// 标准卡片容器
///
/// 收敛点：项目原本有 95 处手写 `BoxShadow`、三套卡片圆角。统一为
/// 「玻璃材质：着色 + 发丝描边 + 顶缘高光 + 同色相投影」，并让投影跟随明暗主题。
///
/// **这里故意不挂 `BackdropFilter`**：AppCard 是全站最密的容器（一屏几十张），
/// 真磨砂的预算（同屏 ≤8，§7.4）会被它一个组件花光。它透出背后氛围层靠的是
/// 着色本身半透明，不是模糊——需要真磨砂的那几张 Hero 卡另走 [GlassSurface]。
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

  /// true 时投影抬一档（用于浮在列表之上的强调块）
  final bool elevated;
  final bool selected;
  final bool hoverable;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? color;
  final Clip clipBehavior;

  /// 玻璃材质配方：着色 + 发丝描边 + 同色相投影。
  ///
  /// 页面里那些自己写了 `Container(decoration:)` 的卡不必换成 [AppCard]——
  /// 只把 `decoration` 换成这个，材质就并进同一条口径了。配 [edgeHighlight]
  /// 一起用才完整：没有顶缘那道高光，半透明卡压在柔彩底上会读成"贴了块塑料片"。
  static BoxDecoration glassDecoration(
    BuildContext context, {
    BorderRadius? borderRadius,
    Color? color,
    Color? borderColor,
    bool selected = false,
    bool lifted = false,
  }) {
    final s = AppSemantic.of(context);
    final a = AppAtmosphere.of(context);
    return BoxDecoration(
      color: color ?? (selected ? s.accentContainer : s.glassTint),
      borderRadius: borderRadius ?? AppTheme.metrics.radiusCard,
      border: Border.all(
        color: selected
            ? s.accentContainerBorder
            : (borderColor ?? s.glassBorder),
        width: scaleW(selected ? 1.4 : 1),
      ),
      boxShadow: a.cardShadow(lifted: lifted),
    );
  }

  /// 顶缘高光：两端 alpha 收到 0、左右各内缩半个圆角，否则高光会戳出圆角外成一截直线。
  static Widget edgeHighlight(BuildContext context, BorderRadius radius) {
    final a = AppAtmosphere.of(context);
    return Positioned(
      left: radius.topLeft.x * 0.6,
      right: radius.topRight.x * 0.6,
      top: 0,
      child: IgnorePointer(
        child: Container(
          height: AppTheme.metrics.strokeUltraThin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(radius.topLeft.x),
            ),
            gradient: LinearGradient(
              colors: [
                a.glassHighlight.withAlpha(0),
                a.glassHighlight,
                a.glassHighlight.withAlpha(0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final radius = borderRadius ?? m.radiusCard;

    final decoration = glassDecoration(
      context,
      borderRadius: radius,
      color: color,
      borderColor: borderColor,
      selected: selected,
      lifted: elevated,
    );

    final content = Padding(
      padding: padding ?? EdgeInsets.all(m.kSpace16),
      child: child,
    );

    Widget card;
    if (!hoverable && onTap == null) {
      card = DecoratedBox(decoration: decoration, child: content);
    } else {
      card = Hoverable(
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

    return Stack(
      children: [card, edgeHighlight(context, radius)],
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
  final StrokeIcon? icon;

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
              child: DrawIcon(icon!, size: m.iconSize16, color: accent),
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
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize18,
                    weight: FontWeight.w600,
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
      thickness: AppTheme.metrics.strokeHairline,
      indent: indent,
      endIndent: endIndent,
      color: s.hairline,
    );
  }
}
