import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

/// 图表数值的自适应小数位：数值越大位数越少，避免 Wh 下出现一长串无意义小数
String psFormatPowerValue(double v) {
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(0);
  if (a >= 100) return v.toStringAsFixed(1);
  if (a >= 1) return v.toStringAsFixed(2);
  return v.toStringAsFixed(3);
}

/// 浮层的时间标签：给后端的短标签补上"几号 + 周几"
///
/// hour/1day 区间只给 '15:00'，看不出是哪一天；7/15/30day 只给 '10-13'，缺周几。
/// 时刻型把日期顶在前面（'10-14 周三 15:00'），日期型往后挂周几（'10-14 周三'）。
/// 时间戳是秒；桩数据给 0 就原样返回，不编一句 1970 出来。
String psTooltipLabel(String label, int timestampSec) {
  if (timestampSec <= 0) return label;
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final d = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return label.contains(':')
      ? '$mm-$dd ${weekdays[d.weekday - 1]} $label'
      : '$label ${weekdays[d.weekday - 1]}';
}

/// 交互式趋势图（hover十字线 + tooltip）
class PsTrendChart extends StatefulWidget {
  const PsTrendChart({
    super.key,
    required this.buckets,
    required this.metric,
    required this.color,
    required this.unit,
    this.unitScale = 1.0,
    this.highlightIndex,
    this.pulse = 0,
    this.trigger,
  });

  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;
  final String unit;

  /// kWh → 展示单位的换算系数（余额/电费恒为 1）
  final double unitScale;

  /// 末端脉冲要落在哪个点上（一般是最后一个采样）
  final int? highlightIndex;

  /// 0~1：那个点上向外扩散的一圈涟漪。只在刷新那一刻推一次，
  /// 常驻脉冲会让停住的数据看着还在动。
  final double pulse;

  /// 变了就重播一次折线画入：换区间/换维度/换单位换的是整条线的数据，
  /// 轮询补一个点不该让已经定型的线重新长一遍
  final Object? trigger;

  @override
  State<PsTrendChart> createState() => _PsTrendChartState();
}

class _PsTrendChartState extends State<PsTrendChart>
    with SingleTickerProviderStateMixin {
  // 图表内边距，需与 _PsChartCanvas 保持一致
  static const double _padLeft = 44.0;
  static const double _padRight = 14.0;

  int? _hoverIndex;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.emphasis,
  );
  Object? _lastTrigger;

  @override
  void initState() {
    super.initState();
    _lastTrigger = widget.trigger;
    _reveal.forward();
  }

  @override
  void didUpdateWidget(PsTrendChart old) {
    super.didUpdateWidget(old);
    if (widget.trigger != _lastTrigger) {
      _lastTrigger = widget.trigger;
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  double _value(PowerStatBucket b) {
    switch (widget.metric) {
      case PowerChartMetric.consumption:
        return b.consumptionKwh * widget.unitScale;
      case PowerChartMetric.balance:
        return b.balanceYuan;
      case PowerChartMetric.cost:
        return b.costYuan;
    }
  }

  // 根据横坐标定位最近的数据点索引
  int _findNearestIndex(double localX, Size size) {
    final n = widget.buckets.length;
    if (n == 0) return -1;
    if (n == 1) return 0;
    final chartW = size.width - _padLeft - _padRight;
    final ratio = ((localX - _padLeft) / chartW).clamp(0.0, 1.0);
    return (ratio * (n - 1)).round();
  }

  // 计算数据点屏幕坐标（用于定位 tooltip）
  List<Offset> _computePoints(Size size, double minV, double maxV) {
    final padTop = 12.0;
    final padBottom = 26.0;
    final chartW = size.width - _padLeft - _padRight;
    final chartH = size.height - padTop - padBottom;
    final range = maxV - minV;
    final n = widget.buckets.length;
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = _padLeft + (n == 1 ? chartW / 2 : chartW * i / (n - 1));
      final normalized = range == 0 ? 0.5 : (maxV - _value(widget.buckets[i])) / range;
      points.add(Offset(x, padTop + chartH * normalized));
    }
    return points;
  }

  (double, double) _computeRange() {
    final values = widget.buckets.map(_value).toList();
    double maxV = values.reduce(math.max);
    double minV = values.reduce(math.min);
    if (widget.metric == PowerChartMetric.balance) {
      if (maxV == minV) {
        maxV = maxV + 1;
        minV = (minV - 1).clamp(0.0, double.infinity);
      }
    } else {
      minV = 0;
      if (maxV <= 0) maxV = 1;
    }
    return (minV, maxV);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onHover: (event) {
            final idx = _findNearestIndex(event.localPosition.dx, size);
            if (idx >= 0 && idx != _hoverIndex) {
              setState(() => _hoverIndex = idx);
            }
          },
          onExit: (_) {
            if (_hoverIndex != null) {
              setState(() => _hoverIndex = null);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _updateHover(d.localPosition.dx, size),
            onPanUpdate: (d) => _updateHover(d.localPosition.dx, size),
            onTapDown: (d) => _updateHover(d.localPosition.dx, size),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: _PsChartCanvas(
                      buckets: widget.buckets,
                      metric: widget.metric,
                      color: widget.color,
                      // 轴标签走 role 派生而不是裸 TextStyle：裸构造丢 fontFamily，
                      // 项目自带字体不生效，出图里整排数字直接是豆腐块
                      labelStyle: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize9,
                        color:
                            (theme.textTheme.bodySmall?.color ?? s.textTertiary)
                                .withAlpha(120),
                      ),
                      // 数据点外圈要挖出卡片表面那层底，不能写死白：暗色下白圈会
                      // 在深灰卡上变成一圈"亮斑"
                      surfaceColor: s.surface,
                      gridColor: theme.dividerColor.withAlpha(40),
                      hoverIndex: _hoverIndex,
                      unitScale: widget.unitScale,
                      highlightIndex: widget.highlightIndex,
                      pulse: widget.pulse,
                      reveal: Curves.easeOutCubic.transform(_reveal.value),
                    ),
                  ),
                ),
                if (_hoverIndex != null &&
                    _hoverIndex! < widget.buckets.length)
                  _buildTooltip(context, size, theme, m),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateHover(double localX, Size size) {
    final idx = _findNearestIndex(localX, size);
    if (idx >= 0 && idx != _hoverIndex) {
      setState(() => _hoverIndex = idx);
    }
  }

  Widget _buildTooltip(
    BuildContext context,
    Size size,
    ThemeData theme,
    ThemeMetrics m,
  ) {
    final s = AppSemantic.of(context);
    final idx = _hoverIndex!;
    final (minV, maxV) = _computeRange();
    final points = _computePoints(size, minV, maxV);
    final p = points[idx];
    final bucket = widget.buckets[idx];

    String metricLabel;
    String valueText;
    double currentValue;
    double? prevValue;
    bool isUpGood = true; // 上升为正面（绿）还是负面（红）
    switch (widget.metric) {
      case PowerChartMetric.consumption:
        metricLabel = '耗电量';
        currentValue = _value(bucket);
        valueText = '${psFormatPowerValue(currentValue)} ${widget.unit}';
        // 耗电量上升=多用电=负面（红），下降=省电=正面（绿）
        isUpGood = false;
      case PowerChartMetric.balance:
        metricLabel = '余额';
        currentValue = _value(bucket);
        valueText = '${psFormatPowerValue(currentValue)} ${widget.unit}';
        // 余额上升=正面（绿），下降=负面（红）
        isUpGood = true;
      case PowerChartMetric.cost:
        metricLabel = '电费';
        currentValue = _value(bucket);
        valueText = '${psFormatPowerValue(currentValue)} ${widget.unit}';
        // 电费上升=负面（红），下降=正面（绿）
        isUpGood = false;
    }
    // 取上一个数据点对比
    if (idx > 0) {
      prevValue = _value(widget.buckets[idx - 1]);
    }

    // 环比百分比
    String? changeText;
    // 环比是一枚状态徽标：整条角色（水洗底 + 底上字）一起给，别只挑个色值
    AppStatusRole? changeRole;
    if (prevValue != null && prevValue.abs() > 0.0001) {
      final change = currentValue - prevValue;
      final pct = (change / prevValue.abs()) * 100;
      if (pct.abs() < 0.01) {
        changeText = '持平';
        changeRole = s.neutral;
      } else {
        final arrow = pct > 0 ? '↑' : '↓';
        changeText = '$arrow ${pct.abs().toStringAsFixed(1)}%';
        // 上升且上升为好 → 成功色；上升且上升为坏 → 危险色
        final isUp = pct > 0;
        final isGood = isUp == isUpGood;
        changeRole = isGood ? s.success : s.danger;
      }
    } else if (prevValue != null && prevValue.abs() <= 0.0001) {
      changeText = '新增';
      changeRole = s.info;
    }

    // 不再用 TextPainter 估宽：估少一点，数值就被行内的压缩规则挤成 "0.0…"，
    // 而 monospace 的真实字宽还受 textScaler/字体回退影响，估算注定不准。
    // 改成让内容按自然宽度排布，定位交给 CustomSingleChildLayout 用实测尺寸夹紧。
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: PsTooltipLayoutDelegate(anchor: p),
          child: ConstrainedBox(
            // 太短的读数（如 "0.000 kWh"）也给 tooltip 一个体面的最小宽度，
            // 免得只剩一枚孤零零的小标签。
            constraints: const BoxConstraints(minWidth: 96.0),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: m.kSpace10,
                vertical: m.kSpace8,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(248),
                borderRadius: m.radius8,
                border: Border.all(color: widget.color.withAlpha(120), width: AppTheme.metrics.strokeHairline),
                boxShadow: [
                  BoxShadow(
                    color: s.shadowKey.withAlpha(60),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    psTooltipLabel(bucket.label, bucket.timestamp),
                    style: TextStyle(
                      fontSize: m.fontSize11,
                      color: theme.colorScheme.onSurface.withAlpha(160),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(height: m.kSpace4),
                  // 不收 Expanded/Flexible：父约束是无界的，flex 子项在无限宽下会
                  // 直接断言失败；自然宽度下也不会有任何东西被截断。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: m.kSpace8,
                        height: m.kSpace8,
                        decoration: BoxDecoration(
                          color: widget.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      Text(
                        valueText,
                        style: TextStyle(
                          fontSize: m.fontSize13,
                          fontWeight: FontWeight.w700,
                          color: widget.color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (changeText != null && changeRole != null) ...[
                        SizedBox(width: m.kSpace8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace6,
                            vertical: m.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: changeRole.color.withAlpha(20),
                            borderRadius: m.radius4,
                          ),
                          child: Text(
                            changeText,
                            style: TextStyle(
                              fontSize: m.fontSize10,
                              fontWeight: FontWeight.w700,
                              color: changeRole.onContainer,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    metricLabel,
                    style: TextStyle(
                      fontSize: m.fontSize10,
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把 tooltip 摆到锚点上方，越界时翻转或夹紧。
///
/// 尺寸由 child 自己量出来（getConstraintsForChild 松绑约束），所以这里的
/// childSize 就是真实渲染尺寸，不存在"估宽估少了把文字挤断"的可能。
/// 柱状带那侧共用这一份定位，两套浮层才不会一个翻面一个溢出。
class PsTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  const PsTooltipLayoutDelegate({required this.anchor});

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      // loosen 只松掉 min，maxHeight 还留着画布那一档高度：浮层三行字比画布高
      // 就会被顶成一记 "overflowed by 26 pixels"（字阶一放大最容易撞到）。
      // 浮层本来就该盖在图表外面（父 Stack 是 Clip.none），高度这档不给上限。
      // 不能写 copyWith(maxHeight: null)——那是"保持原值"，不是无穷。
      BoxConstraints(maxWidth: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double left = anchor.dx - childSize.width / 2;
    if (left < 2) left = 2;
    if (left + childSize.width > size.width - 2) {
      left = size.width - childSize.width - 2;
    }
    double top = anchor.dy - childSize.height - 10;
    if (top < 2) top = anchor.dy + 10;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(PsTooltipLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// 悬停浮层的外壳：柱状带和 hero 迷你趋势共用一枚
///
/// 两处各写一套的话，一轮之后就是一个有阴影一个没边框。数值那档的颜色
/// 由调用方给（数据身份色），外壳只负责面、边、字阶。
class PsChartTooltip extends StatelessWidget {
  const PsChartTooltip({
    super.key,
    required this.label,
    required this.valueText,
    required this.color,
    this.note,
  });

  final String label;
  final String valueText;
  final Color color;

  /// 第三行的小字（均值 / 环比之类），不给就不占位
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return ConstrainedBox(
      // 读数再短也给它一个体面宽度，别只剩一枚孤零零的小标签
      constraints: const BoxConstraints(minWidth: 96.0),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace10,
          vertical: m.kSpace8,
        ),
        decoration: BoxDecoration(
          color: s.surface.withAlpha(248),
          borderRadius: m.radius8,
          border: Border.all(color: color.withAlpha(120), width: m.strokeHairline),
          boxShadow: [
            BoxShadow(
              color: s.shadowKey.withAlpha(60),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: m.fontSize11,
                color: p.ink.withAlpha(150),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: m.kSpace4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: m.kSpace8,
                  height: m.kSpace8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                SizedBox(width: m.kSpace6),
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: m.fontSize13,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              SizedBox(height: m.kSpace4),
              Text(
                note!,
                style: TextStyle(
                  fontSize: m.fontSize10,
                  color: p.ink.withAlpha(120),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PsChartCanvas extends CustomPainter {
  _PsChartCanvas({
    required this.buckets,
    required this.metric,
    required this.color,
    required this.labelStyle,
    required this.gridColor,
    required this.surfaceColor,
    this.hoverIndex,
    this.unitScale = 1.0,
    this.highlightIndex,
    this.pulse = 0,
    this.reveal = 1,
  });

  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;

  /// 轴标签样式：由 build 侧从主题字阶派生，画布里不再裸构造 TextStyle
  final TextStyle labelStyle;
  final Color gridColor;

  /// 卡片表面色：数据点那圈"挖空"要用它，写死白在暗色下就是一圈亮斑
  final Color surfaceColor;
  final int? hoverIndex;

  /// kWh → 展示单位的换算系数（余额/电费恒为 1）
  final double unitScale;
  final int? highlightIndex;
  final double pulse;

  /// 0~1：折线画到横轴的哪个位置。只裁折线，网格和轴标签不动。
  final double reveal;

  double _value(PowerStatBucket b) {
    switch (metric) {
      case PowerChartMetric.consumption:
        return b.consumptionKwh * unitScale;
      case PowerChartMetric.balance:
        return b.balanceYuan;
      case PowerChartMetric.cost:
        return b.costYuan;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    const padLeft = 44.0;
    const padRight = 14.0;
    const padTop = 12.0;
    const padBottom = 26.0;
    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padTop - padBottom;
    if (chartW <= 0 || chartH <= 0) return;

    final values = buckets.map(_value).toList();
    double maxV = values.reduce(math.max);
    double minV = values.reduce(math.min);
    if (metric == PowerChartMetric.balance) {
      // 余额范围按数据自适应
      if (maxV == minV) {
        maxV = maxV + 1;
        minV = (minV - 1).clamp(0.0, double.infinity);
      }
    } else {
      // 耗电量/电费从0开始
      minV = 0;
      if (maxV <= 0) maxV = 1;
    }
    final range = maxV - minV;

    // 网格 + Y轴标签
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = AppTheme.metrics.strokeUltraThin;
    for (int i = 0; i <= 4; i++) {
      final y = padTop + chartH * i / 4;
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + chartW, y), gridPaint);
      final v = maxV - range * i / 4;
      _drawText(
        canvas,
        psFormatPowerValue(v),
        Offset(2, y - 6),
        labelStyle,
      );
    }

    // 计算坐标点
    final points = <Offset>[];
    for (int i = 0; i < buckets.length; i++) {
      final x = padLeft +
          (buckets.length == 1 ? chartW / 2 : chartW * i / (buckets.length - 1));
      final normalized = range == 0 ? 0.5 : (maxV - values[i]) / range;
      final y = padTop + chartH * normalized;
      points.add(Offset(x, y));
    }

    // X轴标签（最多8个）
    final labelCount = math.min(buckets.length, 8);
    final step =
        buckets.length > 1 ? (buckets.length - 1) / (labelCount - 1) : 0.0;
    for (int i = 0; i < labelCount; i++) {
      final idx = buckets.length > 1 ? (i * step).round() : 0;
      final x = buckets.length > 1
          ? padLeft + chartW * i / (labelCount - 1)
          : padLeft + chartW / 2;
      _drawText(
        canvas,
        buckets[idx].label,
        Offset(x - 14, padTop + chartH + 8),
        labelStyle,
      );
    }

    // 渐变填充区域：折线 → 右下角 → 左下角 → 回到折线起点，闭合出一条沿底边的带。
    // 不能用 addPolygon：它会 moveTo(points.first) 另起一条子路径，把前面那个
    // "从底边起步"的点甩在另一条子路径里，之后的 lineTo/close 于是接在折线尾巴上，
    // 闭合线变成从右下角斜着拉回左上角第一个点——屏幕上就是一块大三角。
    // 画入动画只裁折线这一段：网格和轴标签从第一帧就该在
    final clipping = reveal < 1;
    if (clipping) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, 0, padLeft + chartW * reveal, size.height),
      );
    }
    if (points.length >= 2) {
      final baseY = padTop + chartH;
      final fillPath = Path()
        ..moveTo(points.first.dx, baseY)
        ..lineTo(points.first.dx, points.first.dy);
      for (final pt in points.skip(1)) {
        fillPath.lineTo(pt.dx, pt.dy);
      }
      fillPath
        ..lineTo(points.last.dx, baseY)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(80), color.withAlpha(0)],
        ).createShader(Rect.fromLTWH(padLeft, padTop, chartW, chartH));
      canvas.drawPath(fillPath, fillPaint);
    }

    // 折线
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppTheme.metrics.strokeRegular
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (points.length >= 2) {
      canvas.drawPoints(ui.PointMode.polygon, points, linePaint);
    }

    // 数据点（默认小点）
    final dotPaint = Paint()..color = color;
    final ringPaint = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.fill;
    for (final p in points) {
      canvas.drawCircle(p, 3, ringPaint);
      canvas.drawCircle(p, 2, dotPaint);
    }

    // 末端涟漪：从最新那个点向外扩一圈就收住，标记"这是刚进来的读数"
    if (highlightIndex != null &&
        highlightIndex! < points.length &&
        pulse > 0 &&
        pulse < 1) {
      final hp = points[highlightIndex!];
      final eased = Curves.easeOut.transform(pulse);
      canvas.drawCircle(
        hp,
        AppTheme.metrics.kSpace6 + AppTheme.metrics.kSpace40 * eased,
        Paint()
          ..color = color.withAlpha((150 * (1 - pulse)).round().clamp(0, 255))
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppTheme.metrics.strokeHairline,
      );
    }

    if (clipping) canvas.restore();

    // 十字线 + 高亮点（hover 时）
    if (hoverIndex != null && hoverIndex! < points.length) {
      final hp = points[hoverIndex!];
      final crossPaint = Paint()
        ..color = color.withAlpha(140)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      // 垂直十字线
      canvas.drawLine(
        Offset(hp.dx, padTop),
        Offset(hp.dx, padTop + chartH),
        crossPaint,
      );
      // 水平十字线
      canvas.drawLine(
        Offset(padLeft, hp.dy),
        Offset(padLeft + chartW, hp.dy),
        crossPaint,
      );
      // 高亮光晕
      final haloPaint = Paint()
        ..color = color.withAlpha(50)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 9, haloPaint);
      canvas.drawCircle(hp, 5, ringPaint);
      canvas.drawCircle(hp, 3.5, dotPaint);
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _PsChartCanvas old) =>
      old.buckets != buckets ||
      old.metric != metric ||
      old.color != color ||
      old.surfaceColor != surfaceColor ||
      old.hoverIndex != hoverIndex ||
      old.unitScale != unitScale ||
      old.highlightIndex != highlightIndex ||
      old.pulse != pulse ||
      old.reveal != reveal;
}
