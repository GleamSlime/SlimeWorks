import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_chart.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_widgets.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

/// 分时段用量柱状带
///
/// 柱以**区间均值**为基线：高于均值向上画绿，低于均值向下画粉，
/// 这样既复用了"零线上下两色"的读法，又不用假造负数用电量。
/// 最高的那根是峰值柱，换成蓝紫渐变并在顶上挂一枚徽章。
class PsTapeCard extends StatefulWidget {
  const PsTapeCard({
    super.key,
    required this.buckets,
    required this.metric,
    required this.unit,
    required this.trigger,
    this.height,
  });

  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final PowerUnit unit;

  /// 变了就重播一次生长
  final Object? trigger;
  final double? height;

  @override
  State<PsTapeCard> createState() => _PsTapeCardState();
}

class _PsTapeCardState extends State<PsTapeCard>
    with SingleTickerProviderStateMixin {
  static const Duration _grow = Duration(milliseconds: 460);
  static const Duration _gap = Duration(milliseconds: 45);
  /// 与主趋势图同一口径：浮点累加的噪声在人眼里就是 0
  static const double _zeroEps = 0.0001;

  late final AnimationController _c = AnimationController(vsync: this);
  Object? _last;
  int? _focus;
  List<String> _prevLabels = const [];
  /// 从这根柱子开始才生长，之前的已经定过型
  int _from = 0;

  @override
  void initState() {
    super.initState();
    _last = widget.trigger;
    _sync(full: true);
  }

  @override
  void didUpdateWidget(PsTapeCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// 决定这一轮到底该不该动、动哪几根
  ///
  /// 换区间/换维度是整条带换数据 → 全部重长；轮询只是末尾补了一段 → 只长新来的
  /// 那几根。判据用 label 的公共前缀：前缀内的柱子上一轮已经画过了，再长一遍
  /// 就是"整屏跟着抖"，而真实发生的只有末尾。
  void _sync({bool full = false}) {
    final labels = [for (final b in _shown()) b.label];
    final prev = _prevLabels;
    _prevLabels = labels;
    final n = labels.length;
    if (n == 0) {
      _c.stop();
      _from = 0;
      return;
    }
    final triggerChanged = widget.trigger != _last;
    _last = widget.trigger;
    if (full || triggerChanged) {
      _replay(0, n);
      return;
    }
    int common = 0;
    while (common < n && common < prev.length && prev[common] == labels[common]) {
      common++;
    }
    if (common < n) _replay(common, n);
  }

  void _replay(int from, int n) {
    _from = from;
    _c.duration = _grow + _gap * math.max(0, n - 1 - from);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _rawOf(PowerStatBucket b) => switch (widget.metric) {
    PowerChartMetric.consumption => b.consumptionKwh,
    PowerChartMetric.balance => b.balanceYuan,
    PowerChartMetric.cost => b.costYuan,
  };

  double _valueOf(PowerStatBucket b) => switch (widget.metric) {
    PowerChartMetric.consumption => b.consumptionKwh * widget.unit.factor,
    PowerChartMetric.balance => b.balanceYuan,
    PowerChartMetric.cost => b.costYuan * widget.unit.factor,
  };

  /// 真正要画的段：表没走的时段读数是 0，画出来就是基线上一排扁胶囊，
  /// 全是噪声。余额是"存量"，0 也是有效读数，所以那一档不过滤。
  List<PowerStatBucket> _shown() {
    final all = widget.buckets;
    if (widget.metric == PowerChartMetric.balance) return all;
    return [for (final b in all) if (_rawOf(b).abs() > _zeroEps) b];
  }

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final buckets = _shown();
    final values = buckets.map(_valueOf).toList();
    final mean = values.isEmpty
        ? 0.0
        : values.reduce((a, b) => a + b) / values.length;
    final maxAbs = values.isEmpty
        ? 1.0
        : math.max(
            values.map((v) => (v - mean).abs()).fold(0.0, math.max),
            1e-9,
          );
    var peakIndex = -1;
    for (int i = 0; i < values.length; i++) {
      if (peakIndex < 0 || values[i] > values[peakIndex]) peakIndex = i;
    }
    final above = values.where((v) => v >= mean).length;
    final below = values.length - above;
    final focus = _focus != null && _focus! < buckets.length ? _focus! : null;

    return PsGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PsSectionLabel('分时段用量'),
              const Spacer(),
              PsPill(label: '$above 高', color: p.green, dense: true),
              SizedBox(width: m.kSpace6),
              PsPill(label: '$below 低', color: p.rose, dense: true),
              if (peakIndex >= 0) ...[
                SizedBox(width: m.kSpace6),
                PsPill(
                  label: '峰值',
                  color: p.accent,
                  filled: true,
                  dense: true,
                ),
              ],
            ],
          ),
          SizedBox(height: m.kSpace14),
          SizedBox(
            height: widget.height ?? scaleW(150),
            child: buckets.isEmpty
                ? Center(
                    child: Text(
                      '暂无采样',
                      style: TextStyle(
                        fontSize: m.fontSize12,
                        color: p.ink.withAlpha(110),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final size = Size(box.maxWidth, box.maxHeight);
                      final geom = _TapeGeom(size: size, count: buckets.length);
                      void pick(double dx) {
                        final i = (dx / geom.slot).floor().clamp(
                          0,
                          buckets.length - 1,
                        );
                        if (i != _focus) setState(() => _focus = i);
                      }

                      return MouseRegion(
                        onHover: (e) => pick(e.localPosition.dx),
                        onExit: (_) {
                          if (_focus != null) setState(() => _focus = null);
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => pick(d.localPosition.dx),
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (context, _) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CustomPaint(
                                  size: size,
                                  painter: _TapePainter(
                                    values: values,
                                    mean: mean,
                                    maxAbs: maxAbs,
                                    peakIndex: peakIndex,
                                    focus: focus,
                                    from: _from,
                                    geom: geom,
                                    elapsed:
                                        _c.value * _c.duration!.inMilliseconds,
                                    palette: p,
                                  ),
                                ),
                                if (focus != null)
                                  // 悬停浮层：只报"这一段是多少、比均值差多少"，
                                  // 锚在柱头上方，越界由委托自己翻面/夹紧
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomSingleChildLayout(
                                        delegate: PsTooltipLayoutDelegate(
                                          anchor: geom.anchorOf(
                                            focus,
                                            values[focus],
                                            mean,
                                            maxAbs,
                                          ),
                                        ),
                                        child: PsChartTooltip(
                                          label: psTooltipLabel(
                                            buckets[focus].label,
                                            buckets[focus].timestamp,
                                          ),
                                          valueText:
                                              '${psFormatPowerValue(values[focus])} ${widget.unit.label}',
                                          color: values[focus] >= mean
                                              ? p.green
                                              : p.rose,
                                          note:
                                              '均值 ${psFormatPowerValue(mean)}',
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: m.kSpace12),
          // 悬停的读数交给柱头那枚浮层，底行只留常驻的汇总，不再随焦点换字
          Row(
            children: [
              Text(
                '共 ${buckets.length} 段',
                style: TextStyle(
                  fontSize: m.fontSize11,
                  color: p.ink.withAlpha(140),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '均值 ${psFormatPowerValue(mean)}   '
                '峰值 ${peakIndex >= 0 ? psFormatPowerValue(values[peakIndex]) : '—'}',
                style: TextStyle(
                  fontSize: m.fontSize11,
                  color: p.ink.withAlpha(140),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 柱状带的几何：painter 和悬停浮层用的是同一套数，写两份必然对不上
class _TapeGeom {
  const _TapeGeom({required this.size, required this.count});

  final Size size;
  final int count;

  double get slot => count == 0 ? size.width : size.width / count;
  double get barW => math.min(slot * 0.55, scaleW(14));
  double get baseY => size.height * 0.62;
  double get upRoom => baseY - scaleW(18);
  double get downRoom => size.height - baseY - scaleW(6);

  double cx(int i) => slot * i + slot / 2;

  /// 满高（生长动画收敛后的那根柱子有多高）
  double fullOf(double v, double mean, double maxAbs) =>
      ((v - mean).abs() / maxAbs) * (v >= mean ? upRoom : downRoom);

  /// 浮层锚点：钉在柱头外侧，动画途中也用满高，免得跟着柱子一起上下跳
  Offset anchorOf(int i, double v, double mean, double maxAbs) {
    final h = fullOf(v, mean, maxAbs);
    final y = v >= mean ? baseY - h - scaleW(8) : baseY + h + scaleW(8);
    return Offset(cx(i), y);
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({
    required this.values,
    required this.mean,
    required this.maxAbs,
    required this.peakIndex,
    required this.focus,
    required this.from,
    required this.geom,
    required this.elapsed,
    required this.palette,
  });

  final List<double> values;
  final double mean;
  final double maxAbs;
  final int peakIndex;
  final int? focus;

  /// 这根之前的柱子已经定过型，一律按满高画
  final int from;
  final _TapeGeom geom;
  final double elapsed;
  final PowerStatsPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final p = palette;
    final n = values.length;
    final barW = geom.barW;
    final baseY = geom.baseY;

    // 基线
    canvas.drawLine(
      Offset(0, baseY),
      Offset(size.width, baseY),
      Paint()
        ..color = p.baseline
        ..strokeWidth = AppTheme.metrics.strokeHairline,
    );

    for (int i = 0; i < n; i++) {
      // 错峰生长：第 i 根比本轮起点那根晚 (i-from)×45ms 起步
      final local = i < from
          ? 1.0
          : ((elapsed - (i - from) * 45) / 460).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final t = Curves.easeOutCubic.transform(local);
      final delta = values[i] - mean;
      final aboveMean = delta >= 0;
      final h = geom.fullOf(values[i], mean, maxAbs) * t;
      final cx = geom.cx(i);
      final rect = aboveMean
          ? Rect.fromLTWH(cx - barW / 2, baseY - h, barW, h)
          : Rect.fromLTWH(cx - barW / 2, baseY, barW, h);
      if (rect.height < 0.6) continue;

      final isPeak = i == peakIndex && aboveMean;
      final paint = Paint()
        ..color = isPeak
            ? p.accent
            : (aboveMean
                  ? p.green.withAlpha(focus == i ? 255 : 175)
                  : p.rose.withAlpha(focus == i ? 255 : 190));
      if (isPeak) {
        paint.shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [p.accent, p.violet],
        ).createShader(rect);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barW / 2)),
        paint,
      );

      if (isPeak) {
        // 峰值柱顶上：一团径向光 + 一枚挂徽章
        final topY = baseY - h;
        canvas.drawCircle(
          Offset(cx, topY),
          barW * 2.4,
          Paint()
            ..shader = RadialGradient(
              colors: [p.accent.withAlpha(70), p.accent.withAlpha(0)],
            ).createShader(
              Rect.fromCircle(center: Offset(cx, topY), radius: barW * 2.4),
            ),
        );
        final badge = scaleW(17);
        canvas.drawCircle(
          Offset(cx, topY - badge),
          badge / 2,
          Paint()..shader = p.peakBar().createShader(
            Rect.fromCircle(center: Offset(cx, topY - badge), radius: badge / 2),
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TapePainter old) =>
      old.values != values ||
      old.mean != mean ||
      old.maxAbs != maxAbs ||
      old.peakIndex != peakIndex ||
      old.focus != focus ||
      old.from != from ||
      old.elapsed != elapsed;
}

/// 一个已入场的峰值时段
@immutable
class PsTopSlot {
  const PsTopSlot({
    required this.label,
    required this.value,
    required this.share,
    required this.unit,
  });

  final String label;
  final double value;

  /// 占区间合计的比例 0~1
  final double share;
  final String unit;
}

/// 峰值时段 TOP5：五个槽位，空槽留问号
///
/// 槽位是**按名次**排的（占比最高的在 #1），所以新数据进来时某槽可能整块换脸，
/// 用 [PsStagger] 的 trigger 重播那一下弹入，比整屏重播更贴近"有人补位进来"。
class PsTopSlotsCard extends StatelessWidget {
  const PsTopSlotsCard({
    super.key,
    required this.slots,
    required this.total,
    required this.unit,
    this.trigger,
  });

  final List<PsTopSlot> slots;
  final double total;
  final String unit;
  final Object? trigger;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    return PsGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PsSectionLabel(
                '峰值时段',
                trailing: Text(
                  '${slots.length}/5',
                  style: TextStyle(
                    fontSize: m.fontSize11,
                    color: p.ink.withAlpha(130),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(),
              PsRollingNumber(
                value: total,
                majorStyle: TextStyle(
                  fontSize: scaleW(22),
                  fontWeight: FontWeight.w800,
                  color: p.accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                prefix: '+',
                suffix: ' $unit',
              ),
            ],
          ),
          SizedBox(height: m.kSpace14),
          // 五个槽等高、底缘线各自贴底：Row 里没有"和最高兄弟对齐"这一档，
          // 而槽高写死 scaleW(150) 又会和卡内其余尺寸（走 AppTheme.metrics）
          // 长成两套比例，窄窗口下必然溢出。用 IntrinsicHeight 让兄弟拉平，
          // 槽自己只声明下限。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < 5; i++) ...[
                  if (i > 0) SizedBox(width: m.kSpace10),
                  Expanded(
                    child: _Slot(
                      index: i,
                      slot: i < slots.length ? slots[i] : null,
                      trigger: trigger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.index, required this.slot, this.trigger});

  final int index;
  final PsTopSlot? slot;
  final Object? trigger;

  @override
  Widget build(BuildContext context) {
    final data = slot;
    final body = data == null ? _empty(context) : _filled(context, data);
    return PsStagger(
      // 只有真的补进内容才播，空槽不该闪一下问号
      index: data == null ? 0 : index,
      trigger: data == null ? null : '$trigger-$index-${data.label}',
      child: AnimatedSwitcher(
        duration: AppMotion.base,
        switchInCurve: AppMotion.decelerate,
        switchOutCurve: AppMotion.accelerate,
        child: KeyedSubtree(key: ValueKey(data?.label ?? '#empty'), child: body),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    return Container(
      constraints: BoxConstraints(minHeight: scaleW(150)),
      decoration: BoxDecoration(
        color: p.slotRest,
        borderRadius: m.radius12,
        border: Border.all(color: p.glassBorder, width: m.strokeUltraThin),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: m.kSpace10, top: m.kSpace8),
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  fontSize: m.fontSize10,
                  color: p.ink.withAlpha(90),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SizedBox(height: m.kSpace10),
          Container(
            width: scaleW(26),
            height: scaleW(26),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: p.ink.withAlpha(45),
                width: m.strokeUltraThin,
              ),
            ),
            child: Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontSize: m.fontSize12,
                  color: p.ink.withAlpha(80),
                ),
              ),
            ),
          ),
          SizedBox(height: m.kSpace14),
          Text(
            '· · ·',
            style: TextStyle(fontSize: m.fontSize12, color: p.ink.withAlpha(70)),
          ),
        ],
      ),
    );
  }

  Widget _filled(BuildContext context, PsTopSlot data) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    return Container(
      constraints: BoxConstraints(minHeight: scaleW(150)),
      padding: EdgeInsets.symmetric(
        horizontal: m.kSpace8,
        vertical: m.kSpace10,
      ),
      decoration: BoxDecoration(
        color: p.glassTint,
        borderRadius: m.radius12,
        border: Border.all(color: p.glassBorder, width: m.strokeUltraThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              '#${index + 1}',
              style: TextStyle(
                fontSize: m.fontSize10,
                color: p.ink.withAlpha(110),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(height: m.kSpace6),
          Container(
            width: scaleW(30),
            height: scaleW(30),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.accent, p.violet],
              ),
            ),
            child: Center(
              child: DrawIcon(
                StrokeIcons.bolt,
                size: m.iconSize14,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: m.fontSize12,
              fontWeight: FontWeight.w800,
              color: p.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '${(data.share * 100).toStringAsFixed(0)}% 占比',
            style: TextStyle(
              fontSize: m.fontSize10,
              color: p.ink.withAlpha(140),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: m.kSpace6),
          Text(
            psFormatPowerValue(data.value),
            style: TextStyle(
              fontSize: scaleW(17),
              fontWeight: FontWeight.w800,
              color: p.green,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          // 底缘那条身份下划线：宽度按占比推进
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace2),
            child: PsGradientBar(
              value: data.share.clamp(0.0, 1.0),
              gradient: p.underline(),
              height: scaleW(3),
            ),
          ),
        ],
      ),
    );
  }
}
