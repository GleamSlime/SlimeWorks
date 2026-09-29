import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 一组柱：一根支出 + 一根收入，加一个轴标签
class LedgerBarGroup {
  const LedgerBarGroup({required this.label, required this.income, required this.expense});

  /// 轴标签（"9月" / "28"）
  final String label;
  final double income;
  final double expense;
}

/// 收支双柱图（月度趋势、日趋势共用）
///
/// 项目没有图表依赖，这里就是全部实现：一条基线 + 两组圆头柱 + 最大值刻度。
/// 柱宽按组数自适应，12 个月和 31 天在同一套代码里不需要分支。
class LedgerBarChart extends StatelessWidget {
  const LedgerBarChart({
    super.key,
    required this.groups,
    this.height,
    this.highlightIndex,
  });

  final List<LedgerBarGroup> groups;

  /// 不给就用默认档：桌面 180 / 窄屏 150
  final double? height;

  /// 高亮某一组（首页里代表"今天"）
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final viz = AppVizSet.of(context);
    final box = height ?? (ledgerNarrow(context) ? m.kSpace14 * 10 : m.kSpace16 * 11);

    return SizedBox(
      height: box,
      child: groups.isEmpty
          ? Center(child: Text('这段时间还没有流水', style: AppTextStyles.caption(context)))
          : TweenAnimationBuilder<double>(
              // 进场从基线长出来：数字先给、形状后到，读起来像"账在动"
              tween: Tween<double>(begin: 0, end: 1),
              duration: AppMotion.slow,
              curve: AppMotion.decelerate,
              builder: (context, progress, _) {
                final maxValue = groups
                    .map((g) => math.max(g.income, g.expense))
                    .fold<double>(0, (a, b) => a > b ? a : b);
                return CustomPaint(
                  size: Size.infinite,
                  painter: _BarPainter(
                    groups: groups,
                    maxValue: maxValue <= 0 ? 1 : maxValue,
                    progress: progress,
                    expenseColor: viz.lagoon.base,
                    incomeColor: s.success.color,
                    dimExpenseColor: viz.lagoon.base.withValues(
                      alpha: s.isDark ? 0.32 : 0.22,
                    ),
                    dimIncomeColor: s.success.color.withValues(alpha: s.isDark ? 0.32 : 0.22),
                    baselineColor: s.hairline,
                    radius: scaleW(3),
                    highlightIndex: highlightIndex,
                    labelStyle: AppTextStyles.caption(context).copyWith(
                      color: s.textTertiary,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.groups,
    required this.maxValue,
    required this.progress,
    required this.expenseColor,
    required this.incomeColor,
    required this.dimExpenseColor,
    required this.dimIncomeColor,
    required this.baselineColor,
    required this.radius,
    required this.highlightIndex,
    this.labelStyle,
  });

  final List<LedgerBarGroup> groups;
  final double maxValue;
  final double progress;
  final Color expenseColor;
  final Color incomeColor;
  final Color dimExpenseColor;
  final Color dimIncomeColor;
  final Color baselineColor;
  final double radius;
  final int? highlightIndex;

  /// 轴标签的字；null 就不画标签（只留柱）
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (groups.isEmpty) return;
    final style = labelStyle;
    final labelBand = style == null ? 0.0 : scaleW(14);
    final baseline = size.height - labelBand - scaleW(1);
    final line = Paint()
      ..color = baselineColor
      ..strokeWidth = scaleW(1);
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), line);

    final slot = size.width / groups.length;
    // 一组里两根柱占槽位的六成，留四成呼吸；槽位越窄呼吸比例越要收，否则柱子会贴在一起
    final fillRatio = slot > scaleW(26) ? 0.6 : 0.74;
    final barWidth = math.max(scaleW(2), slot * fillRatio / 2.6);
    final usableHeight = baseline - scaleW(6);

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final dimmed = highlightIndex != null && highlightIndex != i;
      final center = slot * (i + 0.5);
      _drawBar(
        canvas,
        center - barWidth,
        group.expense,
        usableHeight,
        dimmed ? dimExpenseColor : expenseColor,
        barWidth,
      );
      _drawBar(
        canvas,
        center + barWidth * 0.15,
        group.income,
        usableHeight,
        dimmed ? dimIncomeColor : incomeColor,
        barWidth,
      );
    }
    if (style != null) _paintLabels(canvas, size, slot, baseline, style);
  }

  /// 标签按槽位抽稀：31 天全标就糊成一整条，只留每隔几根的一个
  void _paintLabels(
    Canvas canvas,
    Size size,
    double slot,
    double baseline,
    TextStyle style,
  ) {
    final every = math.max(1, (scaleW(34) / slot).ceil());
    for (var i = 0; i < groups.length; i++) {
      final label = groups[i].label;
      if (label.isEmpty || i % every != 0) continue;
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final center = slot * (i + 0.5);
      // 两端的标签贴着边会被裁掉，往里收到画布内
      final left = math.min(
        math.max(0.0, center - painter.width / 2),
        math.max(0.0, size.width - painter.width),
      );
      painter.paint(canvas, Offset(left, baseline + scaleW(3)));
    }
  }

  void _drawBar(
    Canvas canvas,
    double left,
    double value,
    double usableHeight,
    Color color,
    double width,
  ) {
    if (value <= 0) return;
    final h = (value / maxValue) * usableHeight * progress;
    if (h <= 0) return;
    final rect = Rect.fromLTWH(left, usableHeight - h + scaleW(3), width, h);
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect, topLeft: Radius.circular(radius), topRight: Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress ||
      old.maxValue != maxValue ||
      old.highlightIndex != highlightIndex ||
      old.expenseColor != expenseColor ||
      old.incomeColor != incomeColor ||
      old.baselineColor != baselineColor ||
      !identical(old.labelStyle, labelStyle) ||
      !identical(old.groups, groups);
}

/// 环图扇区的顺序：金额从大到小。
///
/// 页面画"哪一类花了多少"的图例时必须用同一份顺序，
/// 否则图例的色块和环上的扇区会对不上。
List<LedgerCategoryRow> ledgerDonutOrder(List<LedgerCategoryRow> rows) =>
    [...rows]..sort((a, b) => b.total.compareTo(a.total));

/// 类别占比环图
class LedgerDonutChart extends StatelessWidget {
  const LedgerDonutChart({
    super.key,
    required this.rows,
    required this.total,
    this.selectedId,
    this.onSelect,
    this.size,
  });

  final List<LedgerCategoryRow> rows;

  /// 环中心显示的合计数
  final double total;
  final int? selectedId;
  final ValueChanged<int>? onSelect;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final palette = ledgerVizPalette(context);
    final box = size ?? m.kSpace56 * 2;
    // 只排一次：扇区绘制和点击命中必须用同一份顺序，否则点中的是隔壁那块
    final sorted = ledgerDonutOrder(rows);

    return SizedBox(
      width: box,
      height: box,
      child: GestureDetector(
        onTapDown: sorted.isEmpty || onSelect == null
            ? null
            : (detail) {
                final index = _sliceAt(detail.localPosition, box, sorted);
                if (index != null) onSelect!(sorted[index].categoryId);
              },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AppMotion.emphasis,
          curve: AppMotion.decelerate,
          builder: (context, progress, _) => CustomPaint(
            size: Size(box, box),
            painter: _DonutPainter(
              rows: sorted,
              palette: palette,
              progress: progress,
              selectedId: selectedId,
              trackColor: s.surfaceHover,
            ),
            child: Center(
              // 中心字得收在环洞里：合计一到六位数，不加约束就是横着压到环上
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box * 0.6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('合计', style: AppTextStyles.overline(context)),
                      SizedBox(height: m.kSpace2),
                      Text(
                        '¥${formatLedgerAmount(total)}',
                        style: AppTextStyles.cardTitle(context),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 命中测试：按按下点相对圆心的角度落在哪个扇区
  int? _sliceAt(Offset local, double box, List<LedgerCategoryRow> ordered) {
    final center = Offset(box / 2, box / 2);
    final angle =
        (math.atan2(local.dy - center.dy, local.dx - center.dx) + math.pi / 2) % (math.pi * 2);
    final sum = ordered.fold<double>(0, (a, b) => a + b.total);
    if (sum <= 0) return null;
    var sweepSum = 0.0;
    for (var i = 0; i < ordered.length; i++) {
      final sweep = ordered[i].total / sum * math.pi * 2;
      if (angle >= sweepSum && angle < sweepSum + sweep) return i;
      sweepSum += sweep;
    }
    return null;
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.rows,
    required this.palette,
    required this.progress,
    required this.selectedId,
    required this.trackColor,
  });

  final List<LedgerCategoryRow> rows;
  final List<Color> palette;
  final double progress;
  final int? selectedId;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
    final stroke = side * 0.17;
    final ring = Rect.fromLTWH(
      rect.left + stroke / 2,
      rect.top + stroke / 2,
      rect.width - stroke,
      rect.height - stroke,
    );
    final total = rows.fold<double>(0, (a, b) => a + b.total);
    if (total <= 0) {
      canvas.drawArc(ring, 0, math.pi * 2, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor);
      return;
    }

    var start = -math.pi / 2;
    // 缝隙按"环上 1.5 像素"折算成弧度：直接拿像素当角度减，等于每块之间空出
    // 六十度，小扇区（3%、2%）会被整个减没。
    final gap = (side - stroke) > 0 ? scaleW(1.5) / ((side - stroke) / 2) : 0.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final fullSweep = row.total / total * math.pi * 2;
      final sweep = math.max(0.0, fullSweep * progress - gap);
      final dim = selectedId != null && selectedId != row.categoryId;
      canvas.drawArc(
        ring,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = dim ? stroke * 0.8 : stroke
          ..color = palette[i % palette.length].withValues(alpha: dim ? 0.3 : 1),
      );
      start += fullSweep * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.selectedId != selectedId ||
      !identical(old.rows, rows);
}

/// 图表身份色板：类别超过 7 个时把同一支色往中性色压一档再复用。
///
/// 只有 [AppVizSet] 这一处出处，不在页面里另调颜色。
List<Color> ledgerVizPalette(BuildContext context) {
  final s = AppSemantic.of(context);
  final viz = AppVizSet.of(context);
  final base = <Color>[
    viz.lagoon.base,
    viz.mint.base,
    viz.amber.base,
    viz.lilac.base,
    viz.coral.base,
    viz.sky.base,
    viz.sea.base,
  ];
  return <Color>[
    ...base,
    // 第二轮：压暗同一支，占比条还能分出层，又不引入新色相
    for (final color in base) Color.lerp(color, s.textTertiary, 0.45)!,
  ];
}
