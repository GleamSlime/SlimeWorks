import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_zone.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 语义色调档位
enum Tone { neutral, success, warning, danger, info, accent }

/// 在一帧内解析出某个语义色的具体颜色
Color resolveToneColor(AppSemantic s, Tone tone) => switch (tone) {
  Tone.neutral => s.neutral.color,
  Tone.success => s.success.color,
  Tone.warning => s.warning.color,
  Tone.danger => s.danger.color,
  Tone.info => s.info.color,
  Tone.accent => s.accentText,
};

AppStatusRole? resolveToneRole(AppSemantic s, Tone tone) => switch (tone) {
  Tone.neutral => s.neutral,
  Tone.success => s.success,
  Tone.warning => s.warning,
  Tone.danger => s.danger,
  Tone.info => s.info,
  Tone.accent => null,
};

/// 状态胶囊（成功/警告/失败/进行中…）
///
/// 取代散落的 `Colors.green` / `Colors.orange` / `Colors.red` 裸用（合计 259 处）。
/// 关键点：容器底与文字色都从同一语义角色派生，因此同一个"成功"标签
/// 在明暗两套主题下浓度一致，而不是各页自己 withAlpha 一个看不准的数。
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.tone = Tone.neutral,
    this.icon,
    this.showDot = false,
    this.dense = false,
    this.onTap,
  });

  final String label;
  final Tone tone;
  final StrokeIcon? icon;

  /// 仅用一个圆点表示状态，不带图标
  final bool showDot;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final role = resolveToneRole(s, tone);
    final color = resolveToneColor(s, tone);
    final container = role?.container ?? s.surfaceSunken;
    final border = role?.containerBorder ?? s.hairline;
    final fg = role?.onContainer ?? color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? m.kSpace6 : m.kSpace8,
          vertical: dense ? scaleW(1.5) : m.kSpace2,
        ),
        decoration: BoxDecoration(
          color: container,
          borderRadius: m.radiusPill,
          border: Border.all(color: border, width: scaleW(1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: scaleW(6),
                height: scaleW(6),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: m.kSpace6),
            ],
            if (icon != null) ...[
              // 状态胶囊在列表里成排出现，只播入场，不跟点击重播
              DrawIcon(
                icon!,
                size: dense ? m.iconSize12 : m.iconSize13,
                color: fg,
                trigger: StrokeTrigger.appear,
              ),
              SizedBox(width: m.kSpace4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? m.fontSize11 : m.fontSize12,
                fontWeight: FontWeight.w500,
                color: fg,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 普通标签（分类、作者、标记）
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.onTap,
    this.onRemoved,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onRemoved;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace10,
          vertical: m.kSpace4,
        ),
        decoration: BoxDecoration(
          color: selected ? s.accentContainer : s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(
            color: selected ? s.accentContainerBorder : s.hairline,
            width: scaleW(1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: m.fontSize12,
                fontWeight: FontWeight.w500,
                color: selected ? s.accentText : s.textSecondary,
                height: 1.35,
              ),
            ),
            if (onRemoved != null) ...[
              SizedBox(width: m.kSpace4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemoved,
                child: DrawIcon(
                  StrokeIcons.close,
                  size: m.iconSize12,
                  color: s.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 计数徽标（未读数、条目数）
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.tone = Tone.accent,
    this.max = 99,
  });

  final int count;
  final Tone tone;
  final int max;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final role = resolveToneRole(s, tone);
    final text = count > max ? '$max+' : '$count';
    return Container(
      constraints: BoxConstraints(minWidth: scaleW(17)),
      height: scaleW(17),
      padding: EdgeInsets.symmetric(horizontal: m.kSpace5),
      decoration: BoxDecoration(
        color: role?.container ?? s.accentContainer,
        borderRadius: m.radiusPill,
        border: Border.all(
          color: role?.containerBorder ?? s.accentContainerBorder,
          width: scaleW(1),
        ),
      ),
      // 不能写 Container(alignment:)：它内部用 Align，会吃掉父级给的最大宽度，
      // 在 Wrap/Row 里表现为角标横向拉满整行。widthFactor 才是贴内容的写法。
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: m.fontSize10,
            fontWeight: FontWeight.w600,
            color: resolveToneColor(s, tone),
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// 状态圆点：用于"在线/离线""运行中"这类极简指示
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.tone = Tone.success, this.size, this.pulsing = false});

  final Tone tone;
  final double? size;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final d = size ?? scaleW(8);
    final color = resolveToneColor(s, tone);
    if (!pulsing) {
      return Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return _PulseDot(color: color, size: d);
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: widget.size + widget.size * t,
                  height: widget.size + widget.size * t,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: (1 - t) * 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 键值对行（详情面板里大量重复的"标签: 值"写法）
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.copyable = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: scaleW(88),
            child: Text(
              label,
              style: AppTextStyles.caption(context),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: m.fontSize12,
                fontWeight: FontWeight.w500,
                color: valueColor ?? s.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图标按钮（工具栏小方按钮，统一尺寸与悬停态）
class ToolIconButton extends StatelessWidget {
  const ToolIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.size,
    this.color,
  });

  final StrokeIcon icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final btn = IconButton(
      onPressed: onPressed,
      icon: DrawIcon(
        icon,
        size: size ?? m.iconSize18,
        color: onPressed == null
            ? s.textDisabled
            : color ?? (selected ? s.accent : s.textSecondary),
      ),
      style: IconButton.styleFrom(
        backgroundColor: selected ? s.accentContainer : Colors.transparent,
        padding: EdgeInsets.all(m.kSpace6),
      ),
    );
    final zone = StrokeZone(
      // 工具按钮是"指针在不在"比"点没点"更值得反馈的一类：悬停即描一次
      child: btn,
    );
    return tooltip == null ? zone : Tooltip(message: tooltip!, child: zone);
  }
}
