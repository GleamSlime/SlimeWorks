import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_chart.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_widgets.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

/// hero 迷你趋势的一个采样点
///
/// 带着 label 而不只是一个数：浮层要说"这段余额是多少"，
/// 只有数值的话那句时段名只能靠调用方另算一份，两处必然对不上。
class PsSparkPoint {
  const PsSparkPoint(this.label, this.value);

  final String label;
  final double value;
}

/// 顶部主指标区：余额大数字 + 迷你趋势线 + 时间范围滑轨
///
/// 三件事各自对应一个真实数据源，没有任何一条是装饰性假数据：
/// - 大数字 = 当前剩余金额，刷新时补间滚过去
/// - 趋势线 = 所选区间内的余额曲线
/// - 滑轨   = 时间范围档位，越过哪档亮哪档
class PsHeroPanel extends StatelessWidget {
  const PsHeroPanel({
    super.key,
    required this.balanceYuan,
    required this.deltaYuan,
    required this.daysLeft,
    required this.sparkline,
    required this.ranges,
    required this.selectedRange,
    required this.onRangeChanged,
    required this.liveLabel,
    required this.isLive,
    this.rolledTrigger,
  });

  final double balanceYuan;

  /// 相对区间起点的变化（余额是"越用越少"，掉钱用玫瑰色）
  final double deltaYuan;

  /// 按近期日均电费折算的可用天数；无数据为 null
  final double? daysLeft;

  final List<PsSparkPoint> sparkline;
  final List<PowerStatsRange> ranges;
  final String selectedRange;
  final ValueChanged<String> onRangeChanged;

  /// 右上角 LIVE 胶囊里的文案（上次抓取时间）
  final String liveLabel;
  final bool isLive;

  /// 变化一次触发一轮入场动画
  final Object? rolledTrigger;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final numberBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PsSectionLabel('账户余额'),
        SizedBox(height: m.kSpace6),
        PsRollingNumber(
          value: balanceYuan,
          majorStyle: TextStyle(
            fontSize: scaleW(52),
            fontWeight: FontWeight.w700,
            color: p.ink,
            height: 1.02,
            letterSpacing: scaleW(-1.5),
          ),
          minorStyle: TextStyle(
            fontSize: scaleW(24),
            fontWeight: FontWeight.w700,
            color: p.ink.withAlpha(120),
            height: 1.02,
          ),
          flashColor: p.accent,
          prefix: '¥',
        ),
        SizedBox(height: m.kSpace8),
        _DeltaLine(deltaYuan: deltaYuan, daysLeft: daysLeft),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: numberBlock),
            SizedBox(width: m.kSpace12),
            PsLivePill(label: liveLabel, isLive: isLive),
          ],
        ),
        SizedBox(height: m.kSpace16),
        // 趋势线通铺整行宽：写死一档固定宽度，宽屏下数字和线之间就是一大空洞
        LayoutBuilder(
          builder: (context, box) => _Sparkline(
            points: sparkline,
            rolledTrigger: rolledTrigger,
            width: box.maxWidth,
            height: scaleW(84),
          ),
        ),
        SizedBox(height: m.kSpace18),
        PsRangeTrack(
          ranges: ranges,
          selectedRange: selectedRange,
          onRangeChanged: onRangeChanged,
        ),
      ],
    );
  }
}

/// 变化量 + 折算可用天数
class _DeltaLine extends StatelessWidget {
  const _DeltaLine({required this.deltaYuan, required this.daysLeft});

  final double deltaYuan;
  final double? daysLeft;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final up = deltaYuan >= 0;
    final c = up ? p.green : p.rose;
    // 窄屏给这行的宽度连 65 像素都不够，Row 只会溢出；换 Wrap 让"约可用几天"
    // 自己掉到第二行，三角和金额那一组始终绑在一起不换行
    return Wrap(
      spacing: m.kSpace12,
      runSpacing: m.kSpace2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            CustomPaint(
              size: Size(scaleW(9), scaleW(9)),
              painter: _TrianglePainter(color: c, up: up),
            ),
            SizedBox(width: m.kSpace6),
            Text(
              '${up ? '+' : '-'}¥${deltaYuan.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: m.fontSize16,
                fontWeight: FontWeight.w700,
                color: c,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (daysLeft != null)
          Text(
            '约可用 ${daysLeft!.toStringAsFixed(1)} 天',
            style: TextStyle(
              fontSize: m.fontSize12,
              color: p.ink.withAlpha(140),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color, required this.up});

  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (up) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      old.color != color || old.up != up;
}

/// 迷你趋势线：渐变描边 + 端点光晕 + 悬停浮层
///
/// 端点那圈光只在刷新那一刻扩一次就收住——常驻脉冲会让静止的数据看着像在动。
class _Sparkline extends StatefulWidget {
  const _Sparkline({
    required this.points,
    required this.rolledTrigger,
    required this.width,
    required this.height,
  });

  final List<PsSparkPoint> points;
  final Object? rolledTrigger;
  final double width;
  final double height;

  @override
  State<_Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<_Sparkline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.emphasis,
  );
  Object? _last;
  int? _focus;

  @override
  void initState() {
    super.initState();
    _last = widget.rolledTrigger;
    _c.forward();
  }

  @override
  void didUpdateWidget(_Sparkline old) {
    super.didUpdateWidget(old);
    if (widget.rolledTrigger != _last) {
      _last = widget.rolledTrigger;
      _c.forward(from: 0);
    }
    // 换区间会把整条线换掉，焦点留在旧索引上会指着不相干的那一段
    if (old.points.length != widget.points.length && _focus != null) {
      setState(() => _focus = null);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final values = [for (final q in widget.points) q.value];
    // 一个点连不成线，也就没有"悬停在哪一段"可说；位置照样占着，免得 hero 高度跳
    if (values.length < 2) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    final geom = _SparkGeom.layout(
      size: Size(widget.width, widget.height),
      values: values,
    );
    final i = _focus;

    return MouseRegion(
      onHover: (e) {
        final idx = geom.pick(e.localPosition.dx);
        if (idx != _focus) setState(() => _focus = idx);
      },
      onExit: (_) {
        if (_focus != null) setState(() => _focus = null);
      },
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                // Stack 里给的是松约束，不写死 size 的话这块画布就是 0×0，
                // 折线根本没画过，悬停也只会落在第一个点上
                size: Size(widget.width, widget.height),
                painter: _SparklinePainter(
                  geom: geom,
                  gradient: p.spark(),
                  reveal: Curves.easeOutCubic.transform(_c.value),
                  accent: p.accent,
                  halo: 1 - _c.value,
                  focus: i,
                ),
              ),
            ),
            if (i != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomSingleChildLayout(
                    delegate: PsTooltipLayoutDelegate(anchor: geom.pointOf(i)),
                    child: _tooltip(p, i, values),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tooltip(PowerStatsPalette p, int i, List<double> values) {
    // 环比只有"前面还有一个点"才说得出口，第一点无从比起，就不编那句
    final d = i == 0 ? null : values[i] - values[i - 1];
    return PsChartTooltip(
      label: widget.points[i].label,
      valueText: '¥${values[i].toStringAsFixed(2)}',
      color: p.accent,
      note: d == null
          ? null
          : '较上一点 ${d >= 0 ? '+' : '-'}¥${d.abs().toStringAsFixed(2)}',
    );
  }
}

/// 折线几何：画线、命中判定、浮层锚点必须算同一套数，写两份必然错开半格
class _SparkGeom {
  const _SparkGeom(this.pts);

  factory _SparkGeom.layout({required Size size, required List<double> values}) {
    final pad = scaleW(6);
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    double minV = 0, range = 0;
    if (values.isNotEmpty) {
      minV = values.reduce(math.min);
      range = values.reduce(math.max) - minV;
    }
    final n = values.length;
    return _SparkGeom([
      for (int i = 0; i < n; i++)
        Offset(
          n < 2 ? pad + w / 2 : pad + w * i / (n - 1),
          // 满量程时落在正中，免得一条平线贴着底或顶
          pad + h * (1 - (range == 0 ? 0.5 : (values[i] - minV) / range)),
        ),
    ]);
  }

  final List<Offset> pts;

  Offset pointOf(int i) => pts[i];

  /// 最近的一个点：迷你趋势没有网格可指，只能按横坐标认领
  int pick(double dx) {
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < pts.length; i++) {
      final d = (pts[i].dx - dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.geom,
    required this.gradient,
    required this.reveal,
    required this.accent,
    required this.halo,
    this.focus,
  });

  final _SparkGeom geom;
  final LinearGradient gradient;

  /// 0~1，画到折线的哪个位置
  final double reveal;
  final Color accent;

  /// 端点光晕余量，1→0
  final double halo;

  /// 悬停落点，画一枚描边点指认浮层说的是哪一个
  final int? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = geom.pts;
    if (pts.length < 2) return;

    // 按 reveal 截断：入场时折线自己画出来
    final total = pts.length - 1;
    final drawn = math.max(1, (total * reveal).round());
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i <= drawn; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scaleW(2.4)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = gradient.createShader(Offset.zero & size);
    canvas.drawPath(line, stroke);

    final last = pts[drawn];
    final haloPaint = Paint()
      ..color = accent.withAlpha((110 * halo).round().clamp(0, 255));
    canvas.drawCircle(last, scaleW(6) + scaleW(12) * halo, haloPaint);
    canvas.drawCircle(last, scaleW(5), Paint()..color = Colors.white);
    canvas.drawCircle(last, scaleW(3.2), Paint()..color = accent);

    final f = focus;
    if (f != null && f < pts.length) {
      final q = pts[f];
      canvas.drawCircle(
        q,
        scaleW(4.6),
        Paint()..color = accent.withAlpha(210),
      );
      canvas.drawCircle(
        q,
        scaleW(7.5),
        Paint()
          ..color = accent.withAlpha(90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppTheme.metrics.strokeHairline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.geom != geom ||
      old.reveal != reveal ||
      old.halo != halo ||
      old.focus != focus ||
      old.gradient != gradient;
}

/// 右上角 LIVE 胶囊：绿点 + 上次抓取时间
///
/// 绿点的呼吸只在**轮询真的在跑**时播；关掉轮询还继续闪就是骗人。
class PsLivePill extends StatefulWidget {
  const PsLivePill({
    super.key,
    required this.label,
    required this.isLive,
  });

  final String label;
  final bool isLive;

  @override
  State<PsLivePill> createState() => _PsLivePillState();
}

class _PsLivePillState extends State<PsLivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.ambient,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.isLive) {
      _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didUpdateWidget(PsLivePill old) {
    super.didUpdateWidget(old);
    if (old.isLive != widget.isLive) _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final dot = widget.isLive ? p.green : p.ink.withAlpha(90);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: m.kSpace12,
        vertical: m.kSpace6,
      ),
      decoration: BoxDecoration(
        color: p.glassTint,
        borderRadius: m.radiusPill,
        border: Border.all(color: p.glassBorder, width: m.strokeUltraThin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Container(
              width: m.kSpace8,
              height: m.kSpace8,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dot.withAlpha(
                      (widget.isLive ? 150 * (1 - _c.value) : 60)
                          .round()
                          .clamp(0, 255),
                    ),
                    blurRadius: widget.isLive ? scaleW(2 + 8 * _c.value) : 0,
                    spreadRadius: widget.isLive ? scaleW(2 * _c.value) : 0,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: m.kSpace8),
          Text(
            widget.isLive ? 'LIVE' : '停止',
            style: TextStyle(
              fontSize: m.fontSize11,
              fontWeight: FontWeight.w700,
              letterSpacing: scaleW(0.8),
              color: dot,
            ),
          ),
          if (widget.label.isNotEmpty) ...[
            SizedBox(width: m.kSpace8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: m.fontSize12,
                fontWeight: FontWeight.w700,
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 时间范围滑轨：档位胶囊 + 渐变填充 + 游标
///
/// 未选中时轨道只亮到已越过的那一档，选中哪档就填到哪档，游标滑过去。
/// 点胶囊直接跳档——滑轨只是显示形态，不该要求用户去拖。
class PsRangeTrack extends StatelessWidget {
  const PsRangeTrack({
    super.key,
    required this.ranges,
    required this.selectedRange,
    required this.onRangeChanged,
  });

  final List<PowerStatsRange> ranges;
  final String selectedRange;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final selected = math.max(
      0,
      ranges.indexWhere((r) => r.key == selectedRange),
    );
    return Row(
      children: [
        const PsSectionLabel('区间'),
        SizedBox(width: m.kSpace12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = ranges.length;
              final chipW = scaleW(52);
              final trackH = scaleW(4);
              final thumb = scaleW(11);
              // 档位能走的距离是"轨长减一枚胶囊"，等分必须按这个距离算。
              // 早先用整宽等分再 clamp，窄屏上后两档会被挤到同一个位置上叠住。
              final span = math.max(0.0, constraints.maxWidth - chipW);
              final step = n > 1 ? span / (n - 1) : 0.0;
              // 填充与游标共用一条补间，才会看着是"同一根被推过去的针"
              return SizedBox(
                height: scaleW(30),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: n > 1 ? selected / (n - 1) : 0),
                  duration: AppMotion.base,
                  curve: AppMotion.decelerate,
                  builder: (context, t, _) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned(
                          left: chipW / 2,
                          right: chipW / 2,
                          top: (scaleW(30) - trackH) / 2,
                          child: SizedBox(
                            height: trackH,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: p.trackRest,
                                    borderRadius: m.radiusPill,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: t.clamp(0.0, 1.0),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: p.trackFill(),
                                        borderRadius: m.radiusPill,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          // 针心对齐档位心（胶囊中点），不然针总是偏右半个针宽
                          left: chipW / 2 + span * t - thumb / 2,
                          child: Container(
                            width: thumb,
                            height: thumb,
                            decoration: BoxDecoration(
                              color: p.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: scaleW(2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: p.accent.withAlpha(90),
                                  blurRadius: scaleW(8),
                                ),
                              ],
                            ),
                          ),
                        ),
                        for (int i = 0; i < n; i++)
                          Positioned(
                            left: step * i,
                            child: _RangeStop(
                              label: ranges[i].label,
                              active: i == selected,
                              passed: i < selected,
                              width: chipW,
                              onTap: () => onRangeChanged(ranges[i].key),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RangeStop extends StatelessWidget {
  const _RangeStop({
    required this.label,
    required this.active,
    required this.passed,
    required this.width,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool passed;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final c = active ? p.orange : (passed ? p.orange : p.ink);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
        width: width,
        height: scaleW(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active || passed
              ? (active ? p.orange : p.orange.withAlpha(90))
              : p.chipRest,
          borderRadius: m.radiusPill,
          border: Border.all(
            color: active || passed ? Colors.transparent : p.chipRestBorder,
            width: m.strokeUltraThin,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: p.orange.withAlpha(90),
                    blurRadius: scaleW(10),
                    offset: Offset(0, scaleW(2)),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: m.fontSize11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active || passed ? Colors.white : c.withAlpha(160),
          ),
        ),
      ),
    );
  }
}
