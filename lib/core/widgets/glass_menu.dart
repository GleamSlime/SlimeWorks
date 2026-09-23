import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 桌面端紧凑菜单项：图标 + 文案，可选选中态与危险态。
///
/// Material 默认 48 高的菜单行是给触屏定的，在桌面工具软件里显得极松——五项目的
/// 菜单能撑开小半屏。而且各调用点为了一个勾选记号各自手搓
/// `Row(Icon(check) + SizedBox(占位) + Text)`，图标槽宽度还不一致，同一层菜单里
/// 文字对不齐。行高、槽宽、字号在这里一次定死。
///
/// 用法和 [PopupMenuItem] 完全一样（它就是个 PopupMenuItem），因此
/// [PopupMenuButton]、`showMenu` 都能直接放。
class GlassMenuItem<T> extends PopupMenuItem<T> {
  GlassMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled,
    required String label,
    IconData? icon,
    bool destructive = false,
    bool selected = false,
  }) : super(
         // 30 是"能看清图标又不挤"的下限档：比 Material 的 48 紧，比原生菜单松。
         height: scaleW(30),
         padding: EdgeInsets.symmetric(
           horizontal: AppTheme.metrics.kSpace4,
           vertical: AppTheme.metrics.kSpace2,
         ),
         child: _GlassMenuRow(
           label: label,
           icon: icon,
           destructive: destructive,
           selected: selected,
           enabled: enabled,
         ),
       );
}

class _GlassMenuRow extends StatefulWidget {
  const _GlassMenuRow({
    required this.label,
    required this.icon,
    required this.destructive,
    required this.selected,
    required this.enabled,
  });

  final String label;
  final IconData? icon;
  final bool destructive;
  final bool selected;
  final bool enabled;

  @override
  State<_GlassMenuRow> createState() => _GlassMenuRowState();
}

class _GlassMenuRowState extends State<_GlassMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final label = widget.label;
    final icon = widget.icon;
    // 危险项整行染色（图标+文字），比只在文案后面加个红叉更能阻止误点。
    // 常规项和禁用项一律留 null：颜色交给主题的 labelTextStyle。这里一旦自己染色，
    // Text 的 style 会盖掉 DefaultTextStyle，禁用项就看不出被禁用了。
    final Color? foreground = !widget.enabled
        ? null
        : widget.destructive
        ? s.danger.color
        : widget.selected
        ? s.accent
        : null;
    final iconColor =
        foreground ?? (widget.enabled ? s.textPrimary : s.textDisabled);
    // 图标槽固定宽度：没有图标的条目也要留位，否则同一菜单里文字会参差。
    final slot = m.iconSize16 + m.kSpace8;

    return MouseRegion(
      // Material 自带的菜单悬停层高亮薄到几乎看不见，在半透明浮层上更是等于没有反馈。
      // 这里自己画一颗水洗药丸；键盘聚焦仍由外层 InkWell 的高亮负责。
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace6,
          vertical: m.kSpace4,
        ),
        decoration: BoxDecoration(
          // 不能用 surfaceHover：那是一层 17% 的**白**水洗，设计给比白更暗的表面用，
          // 而菜单底就是白——叠上去等于没有反馈。改成半透明强调色，明暗两侧都看得见，
          // 且不覆盖浮层自身的透明度。
          color: _hovered
              ? s.accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: m.radiusControl,
        ),
        child: Row(
          children: [
            SizedBox(
              width: slot,
              child: widget.selected
                  ? Icon(
                      Icons.check_rounded,
                      size: m.iconSize16,
                      color: s.accent,
                    )
                  : icon == null
                  ? null
                  : Icon(icon, size: m.iconSize16, color: iconColor),
            ),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
