import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 面包屑的一级：`label` 是显示文字，`onTap` 为 null 表示这一级不可回跳
/// （当前页就是这种：它已经是用户站着的地方，点自己没有意义）。
@immutable
class BreadcrumbEntry {
  const BreadcrumbEntry(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;

  bool get navigable => onTap != null;
}

/// 层级导航：`A / B / 当前项`
///
/// 只有 **多于一级** 时才该出现——单级标题和它是同一个格子里的互斥关系，
/// 调用方拿到的只有一项时应直接退回标题渲染。
///
/// 宽度不够时折叠**中间**层级为 `…`，首尾两级永不折叠。
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({super.key, required this.entries});

  /// 最后一项是当前页
  final List<BreadcrumbEntry> entries;

  /// 折叠标记：不是真实层级，只占一格
  static const BreadcrumbEntry _ellipsis = BreadcrumbEntry('…');

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = _collapseToWidth(context, constraints.maxWidth);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace6),
                  // 分隔符不吃字号族：它是标点不是文字，用户把界面字号调到 2.0
                  // 时斜杠跟着变粗，只会把各级之间的间距撑散。
                  // 底色必须从行标题那个 role 复制，不能另起一个裸 TextStyle——
                  // 裸的没有 fontFamily，会落到环境默认字上（离屏出图直接是个豆腐块），
                  // 而 _measure 量的是 role 的宽度，量和画对不上，折叠判定的宽度就白算了。
                  child: Text(
                    '/',
                    style: AppTextStyles.rowTitle(context).copyWith(
                      color: s.textDisabled,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              Flexible(
                child: _Crumb(
                  entry: visible[i],
                  isCurrent: i == visible.length - 1,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 按可用宽度决定露出哪几级
  ///
  /// 文字宽度用 `TextPainter` 量，不用 `length × 系数`——中文和 Latin 差着倍数，
  /// 这套界面两种都有。首级告诉你在哪个模块、末级告诉你在看什么，这两条信息
  /// 丢了面包屑就白挂，所以折叠只吃中间层级。
  List<BreadcrumbEntry> _collapseToWidth(BuildContext context, double maxWidth) {
    // 只有首尾两级时中间没东西可折
    if (entries.length <= 2 || maxWidth.isInfinite) return entries;

    final gap = AppTheme.metrics.kSpace6 * 2 + _measure(context, '/');

    bool fits(List<BreadcrumbEntry> list) {
      var sum = gap * (list.length - 1);
      for (final e in list) {
        sum += _measure(context, e.label);
      }
      return sum <= maxWidth;
    }

    if (fits(entries)) return entries;

    for (var tail = 1; tail < entries.length; tail++) {
      final candidate = <BreadcrumbEntry>[
        entries.first,
        _ellipsis,
        ...entries.sublist(entries.length - tail),
      ];
      if (fits(candidate)) return candidate;
    }
    return <BreadcrumbEntry>[entries.first, _ellipsis, entries.last];
  }

  double _measure(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AppTextStyles.rowTitle(context)),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// 一级面包屑：可点的才有水洗药丸，当前页只是一段文字
class _Crumb extends StatelessWidget {
  const _Crumb({required this.entry, required this.isCurrent});

  final BreadcrumbEntry entry;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final style = AppTextStyles.rowTitle(context).copyWith(
      color: isCurrent ? s.textPrimary : s.textSecondary,
      fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
    );

    final label = Text(
      entry.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    if (isCurrent || !entry.navigable) return label;

    return _WashButton(onTap: entry.onTap!, padding: m.kSpace4, child: label);
  }
}

/// 悬停水洗药丸：和侧栏菜单项同一套反馈——同一形状改底色，不叠描边不叠投影
class _WashButton extends StatefulWidget {
  const _WashButton({
    required this.onTap,
    required this.padding,
    required this.child,
  });

  final VoidCallback onTap;
  final double padding;
  final Widget child;

  @override
  State<_WashButton> createState() => _WashButtonState();
}

class _WashButtonState extends State<_WashButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final bg = _pressed
        ? s.surfaceActive
        : _hovered
              ? s.surfaceHover
              : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          // 反馈类必须 ≤160ms，再长就不叫跟手，叫卡了一下才理人
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: EdgeInsets.symmetric(
            horizontal: widget.padding,
            vertical: AppTheme.metrics.kSpace2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppTheme.metrics.radiusControl,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
