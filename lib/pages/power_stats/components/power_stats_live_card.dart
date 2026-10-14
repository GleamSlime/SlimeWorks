import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_chart.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_widgets.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

/// 一次抓取/结算事件
///
/// [id] 唯一即触发一轮动画；同 id 重复 rebuild 不会重播。
@immutable
class PsFetchEvent {
  const PsFetchEvent({
    required this.id,
    required this.title,
    required this.detail,
    required this.amount,
    this.ok = true,
  });

  final int id;
  final String title;

  /// 左侧说明文案
  final String detail;

  /// 右侧大字数值（由调用方算好，不从这里反解）
  final String amount;
  final bool ok;
}

/// 实时电表卡：主曲线 + 已用进度 + 事件横幅
///
/// 一条 [AnimationController] 同时驱动横幅擦入、卡描边发光、曲线末端涟漪，
/// 保证这三下是"同一个动作"而不是三个各走各的钟。
class PsLiveMeterCard extends StatefulWidget {
  const PsLiveMeterCard({
    super.key,
    required this.meterName,
    required this.isLocal,
    required this.buckets,
    required this.metric,
    required this.onMetricChanged,
    required this.unit,
    required this.onUnitChanged,
    required this.metricColor,
    required this.usedRatio,
    required this.headlineValue,
    required this.headlineLabel,
    required this.headlineUnit,
    required this.subTitle,
    required this.subValue,
    this.event,
    this.chartHeight,
    this.emptyState,
    this.chartTrigger,
  });

  final String meterName;
  final bool isLocal;
  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final ValueChanged<PowerChartMetric> onMetricChanged;
  final PowerUnit unit;
  final ValueChanged<PowerUnit> onUnitChanged;
  final Color metricColor;

  /// 0~1：本区间已消耗占起始余额的比例
  final double usedRatio;
  final double headlineValue;
  final String headlineLabel;
  final String headlineUnit;
  final String subTitle;
  final String subValue;
  final PsFetchEvent? event;
  final double? chartHeight;

  /// 无采样时的占位；不给就用一句光秃秃的"暂无采样"
  final Widget? emptyState;

  /// 变了就让主曲线重画一遍（换区间/换维度/换单位）
  final Object? chartTrigger;

  @override
  State<PsLiveMeterCard> createState() => _PsLiveMeterCardState();
}

class _PsLiveMeterCardState extends State<PsLiveMeterCard>
    with SingleTickerProviderStateMixin {
  // 擦入 160 / 驻留 700 / 收势 300，总 1160ms
  static const Duration _wipe = Duration(milliseconds: 160);
  static const Duration _hold = Duration(milliseconds: 700);
  static const Duration _out = Duration(milliseconds: 300);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _wipe + _hold + _out,
  );
  int? _lastEventId;

  @override
  void initState() {
    super.initState();
    _lastEventId = widget.event?.id;
    if (_lastEventId != null) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(PsLiveMeterCard old) {
    super.didUpdateWidget(old);
    if (widget.event?.id != _lastEventId) {
      _lastEventId = widget.event?.id;
      if (widget.event != null) _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 横幅可见度：0→1 擦入，停在 1，再 1→0 收势
  double _bannerT(double t) {
    final inEnd = _wipe.inMilliseconds / _c.duration!.inMilliseconds;
    final outStart = 1 - _out.inMilliseconds / _c.duration!.inMilliseconds;
    if (t <= inEnd) {
      return AppMotion.decelerate.transform(t / inEnd);
    }
    if (t >= outStart) {
      return 1 - AppMotion.accelerate.transform((t - outStart) / (1 - outStart));
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final event = widget.event;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final bt = event == null ? 0.0 : _bannerT(_c.value);
        return PsGlassCard(
          glow: bt,
          glowColor: event != null && !event.ok ? p.rose : p.accent,
          padding: EdgeInsets.fromLTRB(
            m.kSpace16,
            m.kSpace14,
            m.kSpace16,
            m.kSpace16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Opacity(
                    opacity: 1 - bt * 0.65,
                    child: _header(context),
                  ),
                  if (event != null && bt > 0)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, box) => Align(
                          alignment: Alignment.centerRight,
                          // 右缘钉住、左缘长出来。widthFactor 在这条链上裁不动：
                          // Positioned.fill 给的是紧约束，Align 缩不回 bt 宽，
                          // 擦入等于直接全开。所以外层自己给宽，里面那层再靠
                          // Stack 的 centerRight 把整宽横幅的右半截顶到可见区。
                          child: SizedBox(
                            width: box.maxWidth * bt,
                            child: ClipRect(
                              key: const ValueKey('ps-banner-wipe'),
                              child: Stack(
                                alignment: Alignment.centerRight,
                                children: [
                                  SizedBox(
                                    width: box.maxWidth,
                                    child: _Banner(event: event, opacity: bt),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: m.kSpace12),
              SizedBox(
                height: widget.chartHeight ?? scaleW(240),
                child: widget.buckets.isEmpty
                    ? (widget.emptyState ??
                          const Center(child: Text('暂无采样')))
                    : PsTrendChart(
                        buckets: widget.buckets,
                        metric: widget.metric,
                        color: widget.metricColor,
                        unit: widget.unit.label,
                        unitScale: widget.unit.factor,
                        highlightIndex: widget.buckets.length - 1,
                        pulse: event == null ? 0 : _c.value,
                        trigger: widget.chartTrigger,
                      ),
              ),
              SizedBox(height: m.kSpace14),
              Row(
                children: [
                  SizedBox(
                    width: scaleW(56),
                    child: PsSectionLabel(
                      '已用',
                      color: p.ink.withAlpha(140),
                    ),
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: PsGradientBar(
                      value: widget.usedRatio,
                      gradient: p.progress(),
                    ),
                  ),
                  SizedBox(width: m.kSpace10),
                  SizedBox(
                    width: scaleW(48),
                    child: Text(
                      '${(widget.usedRatio * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: m.fontSize12,
                        fontWeight: FontWeight.w700,
                        color: p.accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.kSpace12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PsSectionLabel(
                          widget.headlineLabel,
                          color: p.ink.withAlpha(140),
                        ),
                        SizedBox(height: m.kSpace4),
                        PsRollingNumber(
                          value: widget.headlineValue,
                          majorStyle: TextStyle(
                            fontSize: scaleW(34),
                            fontWeight: FontWeight.w800,
                            color: p.green,
                            height: 1.05,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          minorStyle: TextStyle(
                            fontSize: scaleW(20),
                            fontWeight: FontWeight.w700,
                            color: p.green.withAlpha(170),
                            height: 1.05,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          flashColor: p.accent,
                          prefix: widget.headlineUnit == '元' ? '¥' : '',
                          suffix: widget.headlineUnit == '元' ? '' : widget.headlineUnit,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.subTitle,
                        style: TextStyle(
                          fontSize: m.fontSize11,
                          color: p.ink.withAlpha(140),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: m.kSpace4),
                      Text(
                        widget.subValue,
                        style: TextStyle(
                          fontSize: scaleW(26),
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final switcher = _MetricSwitch(
      metric: widget.metric,
      unit: widget.unit,
      onMetricChanged: widget.onMetricChanged,
      onUnitChanged: widget.onUnitChanged,
    );
    // 六枚切换胶囊本身就要 ~320 逻辑像素，和"图标+表名+本地徽标"挤在同一行
    // 时窄屏必溢出。掉到一行放不下就把切换整组换到第二行，表名那行照旧。
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= scaleW(640);
        // 徽标要贴着表名，所以和表名算一组
        final titleRow = Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.accent, p.violet],
                ),
                borderRadius: m.radius8,
              ),
              child: DrawIcon(
                StrokeIcons.electricBolt,
                size: m.iconSize16,
                color: Colors.white,
              ),
            ),
            SizedBox(width: m.kSpace10),
            Flexible(
              child: Text(
                widget.meterName.isEmpty ? '未配置电表' : widget.meterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: scaleW(20),
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                  letterSpacing: scaleW(-0.2),
                ),
              ),
            ),
            SizedBox(width: m.kSpace8),
            PsPill(
              label: widget.isLocal ? '本地' : '远程节点',
              color: widget.isLocal ? p.teal : p.violet,
              dense: true,
            ),
          ],
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              SizedBox(height: m.kSpace10),
              switcher,
            ],
          );
        }
        // 表名那一段用 Expanded 吃满，切换整组才贴右。之前是 Flexible(表名)
        // + Spacer 两个 flex 孩子对半分自由宽度，表名那半用不完也白占着，
        // 切换胶囊就被顶到卡片正中。
        return Row(
          children: [
            Expanded(child: titleRow),
            SizedBox(width: m.kSpace16),
            switcher,
          ],
        );
      },
    );
  }
}

/// 维度 + 单位切换：视频里那枚 "SHORT 14x" 徽标的位置
class _MetricSwitch extends StatelessWidget {
  const _MetricSwitch({
    required this.metric,
    required this.unit,
    required this.onMetricChanged,
    required this.onUnitChanged,
  });

  final PowerChartMetric metric;
  final PowerUnit unit;
  final ValueChanged<PowerChartMetric> onMetricChanged;
  final ValueChanged<PowerUnit> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final viz = AppVizSet.of(context);
    final m = AppTheme.metrics;
    final items = <(PowerChartMetric, String, Color)>[
      (PowerChartMetric.consumption, '耗电量', viz.amber.base),
      (PowerChartMetric.balance, '余额', viz.sky.base),
      (PowerChartMetric.cost, '电费', viz.coral.base),
    ];
    // 六枚胶囊横向合计约 250 逻辑像素，窄屏给到它的宽度只有 190：
    // Row 只能溢出，Wrap 才会自己换行。分隔条留作最后一个元素，
    // 换行时它跟着单位组一起落到第二行。
    return Wrap(
      spacing: m.kSpace6,
      runSpacing: m.kSpace4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (value, label, color) in items)
          _Choice(
            label: label,
            selected: metric == value,
            color: color,
            onTap: () => onMetricChanged(value),
          ),
        SizedBox(
          width: m.kSpace4,
          child: Container(
            width: m.kSpace1,
            height: scaleW(16),
            color: p.ink.withAlpha(40),
          ),
        ),
        for (final u in PowerUnit.values)
          _Choice(
            label: u.label,
            selected: unit == u,
            color: p.violet,
            dense: true,
            onTap: () => onUnitChanged(u),
          ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? m.kSpace8 : m.kSpace10,
          vertical: dense ? m.kSpace2 : m.kSpace4,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(p.isDark ? 60 : 40) : p.chipRest,
          borderRadius: m.radiusPill,
          border: Border.all(
            color: selected ? color : p.chipRestBorder,
            width: m.strokeUltraThin,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: dense ? m.fontSize10 : m.fontSize11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? color : p.ink.withAlpha(150),
          ),
        ),
      ),
    );
  }
}

/// 事件横幅：青→蓝→紫渐变条，压在卡头之上
class _Banner extends StatelessWidget {
  const _Banner({required this.event, required this.opacity});

  final PsFetchEvent event;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final p = PowerStatsPalette.of(context);
    final m = AppTheme.metrics;
    final gradient = event.ok
        ? p.banner()
        : LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [p.rose, p.orange],
          );
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        height: scaleW(44),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: m.radius12,
        ),
        child: Row(
          children: [
            Text(
              event.title,
              style: TextStyle(
                fontSize: m.fontSize13,
                fontWeight: FontWeight.w800,
                letterSpacing: scaleW(1),
                color: Colors.white,
              ),
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Text(
                event.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: m.fontSize12,
                  color: Colors.white.withAlpha(225),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              event.amount,
              style: TextStyle(
                fontSize: scaleW(24),
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
