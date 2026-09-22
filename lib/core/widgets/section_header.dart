import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 小节标题
///
/// 项目中原先是这一角色最严重的重复源：仅在设置模块就有 7 份签名相同、
/// 实现各异的写法，加上其他模块共约 12 份。统一到此组件后，标题的字阶、
/// 上下间距、是否带说明行、是否可折叠都由一处控制。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.icon,
    this.dense = false,
    this.padding,
    this.collapsible = false,
    this.expanded = true,
    this.onToggleExpanded,
  });

  final String title;

  /// 标题下方的一行解释；为空则不占位
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final IconData? icon;

  /// dense 用于卡片内部的小标题，regular 用于页面分节
  final bool dense;
  final EdgeInsetsGeometry? padding;

  final bool collapsible;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    final effectivePadding =
        padding ??
        EdgeInsets.only(
          bottom: dense ? m.kSpace8 : m.kSpace12,
          top: dense ? 0 : m.kSpace4,
        );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? m.iconSize14 : m.iconSize16, color: s.textTertiary),
          SizedBox(width: m.kSpace8),
        ],
        if (leading != null) ...[leading!, SizedBox(width: m.kSpace8)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: dense
                    ? AppTextStyles.cardTitle(context)
                    : AppTextStyles.sectionTitle(context),
              ),
              if (subtitle != null) ...[
                SizedBox(height: m.kSpace3),
                Text(
                  subtitle!,
                  style: AppTextStyles.caption(context),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[SizedBox(width: m.kSpace12), trailing!],
        if (collapsible)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleExpanded,
            child: Padding(
              padding: EdgeInsets.only(left: m.kSpace6),
              child: AnimatedRotation(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                turns: expanded ? 0 : -0.25,
                child: Icon(
                  Icons.expand_more,
                  size: m.iconSize18,
                  color: s.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );

    return Padding(padding: effectivePadding, child: row);
  }
}

/// 分组标签（全大写小字，用于侧栏分组、密集表单的段落名）
class OverlineLabel extends StatelessWidget {
  const OverlineLabel(this.text, {super.key, this.spacing});

  final String text;

  /// 与上方内容的间距；为 null 时走页面默认节奏
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: spacing ?? m.kSpace20, bottom: m.kSpace8),
      child: Text(text.toUpperCase(), style: AppTextStyles.overline(context)),
    );
  }
}
