import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/node/node_switcher_button.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/power_stats_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';
import 'package:slime_works/pages/power_stats/power_stats_theme.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_widgets.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_chart.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_hero.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_live_card.dart';
import 'package:slime_works/pages/power_stats/components/power_stats_tape.dart';

/// 电力统计页
///
/// 版式是"柔彩渐变底 + 玻璃卡"这一套：页面底负责颜色，卡片只负责承载数据，
/// 所有动画都由**数据到达**那一刻驱动（滚动数字 / 事件横幅 / 柱状带生长），
/// 数据没变就静止，不做持续的假跳变。
///
/// 配色分工：表面、渐变、动效色走本页试验色板 [PowerStatsPalette]；
/// "这条线/这张卡报的是哪个维度"的身份色仍走全局 [AppVizSet]，两处同源才认得出是同一档。
class PowerStatsScreen extends StatefulWidget {
  const PowerStatsScreen({super.key});

  @override
  State<PowerStatsScreen> createState() => _PowerStatsScreenState();
}

class _PowerStatsScreenState extends State<PowerStatsScreen>
    with TickerProviderStateMixin {
  late PowerStatsViewModel _viewModel;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;
  NodeSettingsService? _nodeService;

  final TextEditingController _meterIdController = TextEditingController();

  StreamSubscription? _nodeListSub;
  StreamSubscription? _nodeConnectivitySub;
  StreamSubscription? _currentNodeSub;
  StreamSubscription? _lastFetchSub;
  Timer? _realtimeRefreshTimer;

  /// 抓取事件：只有真的拿到一条新读数才推一个自增 id，动画跟着数据走。
  /// 组件按 id 变化起钟，同 id 的重复 rebuild 不会重播。
  PsFetchEvent? _fetchEvent;
  int _eventId = 0;
  String _lastEventKey = '';
  double? _prevYuan;

  @override
  void initState() {
    super.initState();
    _viewModel = Get.put(PowerStatsViewModel());
    _nodeService = GetIt.instance.get<NodeSettingsService>();

    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppMotion.decelerate,
    );

    _nodeListSub = _nodeService!.remoteNodes.listen((_) {
      if (mounted) setState(() {});
    });
    _nodeConnectivitySub = _nodeService!.nodeConnectivity.listen((_) {
      if (mounted) setState(() {});
    });
    _currentNodeSub = _viewModel.currentNodeId.listen((_) {
      if (mounted) setState(() {});
    });
    _lastFetchSub = _viewModel.lastFetch.listen((_) {
      if (mounted) _emitFetchEvent();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.refreshAll();
      _entranceController.forward();
      _meterIdController.text = _viewModel.meterId.value;
      // 实时数据刷新：定时同步图表（轮询模式下数据持续更新）
      _realtimeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && !_viewModel.isFetching.value) {
          _viewModel.refreshAggregated();
        }
      });
    });
  }

  @override
  void dispose() {
    _realtimeRefreshTimer?.cancel();
    _nodeListSub?.cancel();
    _nodeConnectivitySub?.cancel();
    _currentNodeSub?.cancel();
    _lastFetchSub?.cancel();
    _entranceController.dispose();
    _meterIdController.dispose();
    try {
      Get.delete<PowerStatsViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final p = PowerStatsPalette.of(context);
    final isNarrow = PlatformUtil.isMobile || MediaQuery.of(context).size.width < 720;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '电力统计',
        actions: [
          _buildNodeSwitcher(context),
          SizedBox(width: m.kSpace8),
          _buildFetchButton(context),
          SizedBox(width: m.kSpace8),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _buildBackground(p)),
          Positioned.fill(
            child: FadeTransition(
              opacity: _entranceAnimation,
              child: Obx(() {
                if (!_viewModel.isConfigLoaded.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SingleChildScrollView(
                  padding: EdgeInsets.all(m.kSpace16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PsStagger(
                        index: 0,
                        child: PsGlassCard(child: _buildHero(context)),
                      ),
                      SizedBox(height: m.kSpace12),
                      PsStagger(index: 1, child: _buildStatusStrip(m, isNarrow)),
                      SizedBox(height: m.kSpace12),
                      PsStagger(index: 2, child: _buildLiveCard(m, isNarrow)),
                      SizedBox(height: m.kSpace12),
                      PsStagger(index: 3, child: _buildTape(m, isNarrow)),
                      SizedBox(height: m.kSpace12),
                      PsStagger(index: 4, child: _buildTopSlots()),
                      SizedBox(height: m.kSpace16),
                      PsStagger(
                        index: 5,
                        child: _buildDimensionGrid(context, m),
                      ),
                      SizedBox(height: m.kSpace16),
                      PsStagger(index: 6, child: _buildConfigCard(context, m)),
                      SizedBox(height: m.kSpace12),
                      PsStagger(index: 7, child: _buildLogCard(context, m)),
                      SizedBox(height: m.kSpace8),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 页面底：对角柔彩基色 + 四角色团。色板只交分层数据
  /// （见 [PowerStatsPalette.backgroundLayers]），叠放这件事留在这儿。
  /// IgnorePointer 保证这层纯装饰永远不参与命中。
  Widget _buildBackground(PowerStatsPalette p) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final d in p.backgroundLayers) DecoratedBox(decoration: d),
        ],
      ),
    );
  }

  // ── 顶部节点切换 ────────────────────────────────────────────────────────
  Widget _buildNodeSwitcher(BuildContext context) {
    if (_nodeService == null) return const SizedBox.shrink();
    return NodeSwitcherButton(
      nodeService: _nodeService!,
      currentNodeId: _viewModel.currentNodeId.value,
      availabilityChecker: _viewModel.checkNodePowerStatsAvailable,
      onNodeSelected: (nodeId) => _viewModel.switchNode(nodeId),
    );
  }

  Widget _buildFetchButton(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Obx(
      () => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: m.radius20,
          onTap: _viewModel.isFetching.value
              ? null
              : () async {
                  await _viewModel.fetchOnce();
                  // 手动抓取后补推一次：失败时 last_fetch 可能压根没动，
                  // 只靠监听会让人点了却没有任何交代
                  if (mounted) _emitFetchEvent();
                },
          child: Container(
            height: m.kSpace32,
            padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
            decoration: BoxDecoration(
              color: s.warning.color.withAlpha(30),
              borderRadius: m.radius20,
              border: Border.all(
                color: s.warning.color.withAlpha(80),
                width: AppTheme.metrics.strokeHairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewModel.isFetching.value
                    ? SizedBox(
                        width: m.iconSize14,
                        height: m.iconSize14,
                        child: CircularProgressIndicator(
                          strokeWidth: AppTheme.metrics.strokeRegular,
                        ),
                      )
                    : DrawIcon(
                        StrokeIcons.bolt,
                        size: m.iconSize14,
                        color: s.warning.color,
                      ),
                SizedBox(width: m.kSpace6),
                Text(
                  '抓取',
                  style: TextStyle(
                    fontSize: m.fontSize12,
                    fontWeight: FontWeight.w600,
                    color: s.warning.onContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero：账户余额 + 迷你趋势 + 时间范围滑轨 ──────────────────────────
  Widget _buildHero(BuildContext context) {
    final buckets = _viewModel.buckets;
    final yuan = _balanceYuan;
    // 余额是"越用越少"的存量，区间变化取末值减初值；单桶谈不上变化
    final delta = buckets.length >= 2
        ? buckets.last.balanceYuan - buckets.first.balanceYuan
        : 0.0;
    final dayCost = _viewModel.getSummaryCost('day_cost');
    return PsHeroPanel(
      balanceYuan: yuan,
      deltaYuan: delta,
      // 按日均电费折算可用天数；日花费为 0（还没攒够样本）时不编造天数
      daysLeft: dayCost > 0 ? yuan / dayCost : null,
      sparkline: [
        for (final b in buckets)
          PsSparkPoint(psTooltipLabel(b.label, b.timestamp), b.balanceYuan),
      ],
      ranges: PowerStatsRange.all,
      selectedRange: _viewModel.selectedRange.value,
      onRangeChanged: (key) => _viewModel.setRange(key),
      liveLabel: _clockOf(_viewModel.lastFetch.value),
      isLive: _viewModel.isPolling.value,
      // 换区间换的是整条线，也要重画一次；轮询补一个点同样重走一遍入场
      rolledTrigger: '${_viewModel.selectedRange.value}|${_viewModel.lastFetch.value}',
    );
  }

  // ── 状态条：持久化说明 + 三个常驻小指标 ────────────────────────────────
  Widget _buildStatusStrip(ThemeMetrics m, bool isNarrow) {
    // 小指标是并列数据身份，沿用全局 viz 色板；页面底和玻璃面才走本页色板
    final viz = AppVizSet.of(context);
    final p = PowerStatsPalette.of(context);
    return Obx(() {
      final enabled = _viewModel.isEnabled.value;
      final unit = _viewModel.selectedUnit.value;
      final desc = _viewModel.isLocal
          ? (enabled
                ? '本地定时统计 - 每${_viewModel.intervalSecs.value}秒抓取一次'
                : '本地模式 - 数据持久化到数据库')
          : '远程节点模式 - 数据由节点服务持久化';

      final items = <_SummaryCardData>[
        _SummaryCardData(
          icon: StrokeIcons.timer,
          label: '分钟耗电',
          value: _viewModel.getSummaryConsumption('minute_consumption'),
          unit: unit.label,
          // 电量这一档的身份色与下面的维度网格、图表折线同源
          color: viz.mint.base,
          format: unit.format,
        ),
        _SummaryCardData(
          icon: StrokeIcons.money,
          label: '单价',
          value: _viewModel.price.value,
          unit: '元/度',
          color: viz.sky.base,
          format: (v) => v.toStringAsFixed(3),
        ),
        _SummaryCardData(
          icon: StrokeIcons.barChart,
          label: '采样条数',
          value: _viewModel.sampleCount.value.toDouble(),
          unit: '条',
          color: viz.lilac.base,
          format: (v) => v.toStringAsFixed(0),
        ),
      ];

      final stats = <Widget>[
        for (final d in items) _buildMiniStat(m, d),
      ];

      return PsGlassCard(
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace14,
          vertical: m.kSpace12,
        ),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDescText(p, desc),
                  SizedBox(height: m.kSpace10),
                  Wrap(
                    spacing: m.kSpace14,
                    runSpacing: m.kSpace8,
                    children: stats,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildDescText(p, desc)),
                  SizedBox(width: m.kSpace14),
                  ...stats,
                ],
              ),
      );
    });
  }

  Widget _buildDescText(PowerStatsPalette p, String desc) {
    final m = AppTheme.metrics;
    return Text(
      desc,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: m.fontSize12, color: p.ink.withAlpha(150)),
    );
  }

  Widget _buildMiniStat(ThemeMetrics m, _SummaryCardData data) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        DrawIcon(data.icon, size: m.iconSize12, color: data.color),
        SizedBox(width: m.kSpace6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PsSectionLabel(data.label, color: data.color.withAlpha(200)),
            SizedBox(height: m.kSpace2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                PsRollingNumber(
                  value: data.value,
                  majorStyle: TextStyle(
                    fontSize: m.fontSize16,
                    fontWeight: FontWeight.w800,
                    color: data.color,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  formatMajor: data.format,
                ),
                SizedBox(width: m.kSpace4),
                Text(
                  data.unit,
                  style: TextStyle(
                    fontSize: m.fontSize10,
                    color: data.color.withAlpha(160),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 实时电表卡：主曲线 + 已用进度 + 抓取事件横幅 ───────────────────────
  Widget _buildLiveCard(ThemeMetrics m, bool isNarrow) {
    // 折线颜色即"这条线画的是哪个维度"的身份，与卡内维度切换 chip 同源
    final viz = AppVizSet.of(context);
    final metric = _viewModel.selectedMetric.value;
    final unit = _viewModel.selectedUnit.value;
    final buckets = _viewModel.buckets;
    final sumText = _metricSummary(metric, buckets, unit);

    // 图表只画有值的采样桶：这类"流量"型指标（耗电量/电费）绝大多数桶是 0，
    // 留着会把曲线压成一地锯齿，也撑不满纵轴。余额是"存量"，0 也是有效读数，不过滤。
    // 上面的合计/区间变化仍用完整 buckets，过滤不能影响它们。
    final chartBuckets = switch (metric) {
      PowerChartMetric.balance => buckets,
      // 全是 0 时退回原始桶：空图比一条 0 平线更难读
      _ => _withoutZeroBuckets(buckets, metric),
    };

    final startBalance = buckets.isEmpty ? 0.0 : buckets.first.balanceYuan;
    final used = startBalance - _balanceYuan;

    return PsLiveMeterCard(
      meterName: _viewModel.meterName.value,
      isLocal: _viewModel.isLocal,
      buckets: chartBuckets,
      metric: metric,
      onMetricChanged: (v) => _viewModel.setMetric(v),
      unit: unit,
      onUnitChanged: (v) => _viewModel.setUnit(v),
      metricColor: switch (metric) {
        PowerChartMetric.consumption => viz.amber.base,
        PowerChartMetric.balance => viz.sky.base,
        PowerChartMetric.cost => viz.coral.base,
      },
      // 已用占比按"这个区间开头还有多少钱"算，和折线画的是同一件事
      usedRatio: startBalance > 0 ? (used / startBalance).clamp(0.0, 1.0) : 0.0,
      headlineValue: unit.fromKwh(_balanceKwh),
      headlineLabel: '剩余电量 · ${_rangeLabel()}',
      headlineUnit: unit.label,
      subTitle: '区间合计',
      subValue: sumText,
      event: _fetchEvent,
      emptyState: _buildEmptyChart(),
      chartTrigger: _shapeTick(metric),
      chartHeight: isNarrow ? scaleW(196) : scaleW(252),
    );
  }

  /// 区间合计的文案：只有电量维度吃用户选的计量单位，余额/电费固定按元展示
  String _metricSummary(
    PowerChartMetric metric,
    List<PowerStatBucket> buckets,
    PowerUnit unit,
  ) {
    switch (metric) {
      case PowerChartMetric.consumption:
        // 耗电量：所有桶累加
        final sum = buckets.fold<double>(0, (s, b) => s + b.consumptionKwh);
        return '${unit.format(sum)}${unit.label}';
      case PowerChartMetric.balance:
        // 余额：末值 - 首值（区间变化量）
        if (buckets.length >= 2) {
          final d = buckets.last.balanceYuan - buckets.first.balanceYuan;
          return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)}元';
        }
        if (buckets.length == 1) {
          return '${buckets.first.balanceYuan.toStringAsFixed(2)}元';
        }
        return '0.00元';
      case PowerChartMetric.cost:
        final sum = buckets.fold<double>(0, (s, b) => s + b.costYuan);
        return '${sum.toStringAsFixed(2)}元';
    }
  }

  String _rangeLabel() {
    final r = PowerStatsRange.all.firstWhere(
      (e) => e.key == _viewModel.selectedRange.value,
      orElse: () => const PowerStatsRange('1day', '1天'),
    );
    return r.label;
  }

  /// 过滤掉数值为 0 的采样桶，让趋势线只反映真实发生的用量。
  ///
  /// 阈值取 0.0001：浮点累加的噪声（0.0000001 度）在人眼里就是 0，
  /// 但精确相等判不掉，会留下一条肉眼看不见的锯齿。
  List<PowerStatBucket> _withoutZeroBuckets(
    List<PowerStatBucket> buckets,
    PowerChartMetric metric,
  ) {
    final nonZero = buckets.where((b) {
      final v = metric == PowerChartMetric.consumption
          ? b.consumptionKwh
          : b.costYuan;
      return v.abs() > 0.0001;
    }).toList();
    return nonZero.isEmpty ? buckets : nonZero;
  }

  Widget _buildEmptyChart() {
    final m = AppTheme.metrics;
    final p = PowerStatsPalette.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DrawIcon(
            StrokeIcons.insights,
            size: m.iconSize40,
            color: p.ink.withAlpha(50),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '暂无统计数据',
            style: TextStyle(fontSize: m.fontSize12, color: p.ink.withAlpha(120)),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '点击右上角"抓取"开始采集',
            style: TextStyle(fontSize: m.fontSize11, color: p.ink.withAlpha(90)),
          ),
        ],
      ),
    );
  }

  // ── 分时段柱状带 ────────────────────────────────────────────────────────
  Widget _buildTape(ThemeMetrics m, bool isNarrow) {
    final metric = _viewModel.selectedMetric.value;
    return PsTapeCard(
      buckets: _viewModel.buckets,
      metric: metric,
      unit: _viewModel.selectedUnit.value,
      trigger: _shapeTick(metric),
      height: isNarrow ? scaleW(126) : scaleW(152),
    );
  }

  // ── 峰值时段 TOP5 ───────────────────────────────────────────────────────
  Widget _buildTopSlots() {
    final unit = _viewModel.selectedUnit.value;
    final buckets = _viewModel.buckets;
    // TOP5 的名次恒按"哪个时段最费电"排：换到余额/电费维度时占比语义会失真，
    // 而"峰值时段"这个名字本身说的就是用量
    final values = [for (final b in buckets) b.consumptionKwh * unit.factor];
    final total = values.fold<double>(0, (s, v) => s + (v > 0 ? v : 0));
    final ranked = <int>[
      for (int i = 0; i < values.length; i++) i,
    ]..sort((a, b) => values[b].compareTo(values[a]));

    final slots = <PsTopSlot>[];
    for (int i = 0; i < 5; i++) {
      final idx = i < ranked.length ? ranked[i] : -1;
      // 没数据的名次**不给占位对象**：卡片按"槽里没有 slot"渲染成带问号的空槽，
      // 硬塞一个 label 为空的 PsTopSlot 会变成一张没有字的花玻璃
      if (total <= 0 || idx < 0 || values[idx] <= 0) break;
      slots.add(
        PsTopSlot(
          label: buckets[idx].label,
          value: values[idx],
          share: values[idx] / total,
          unit: unit.label,
        ),
      );
    }

    return PsTopSlotsCard(
      slots: slots,
      total: total,
      unit: unit.label,
      trigger: _rangeTick(),
    );
  }

  /// 图表"形状"变了就整条重播一次入场：换区间/换维度/换单位换的都是整套数据。
  /// 故意不含 lastFetch —— 轮询往末尾补一段是"长出一根"，不是"全部重来"。
  Object _shapeTick(PowerChartMetric metric) =>
      '${_viewModel.selectedRange.value}|$metric|${_viewModel.selectedUnit.value.label}';

  /// TOP5 的名次恒按用量排，只有区间和计量单位会动它的形状
  Object _rangeTick() =>
      '${_viewModel.selectedRange.value}|${_viewModel.selectedUnit.value.label}';

  // ── 维度卡片网格（小时/1天/7天/15天/16天/30天）────────────────────────
  Widget _buildDimensionGrid(BuildContext context, ThemeMetrics m) {
    final p = PowerStatsPalette.of(context);
    return Obx(() {
      final unit = _viewModel.selectedUnit.value;
      final dims = <_DimensionData>[
        _DimensionData(
          title: '小时',
          consumption: _viewModel.getSummaryConsumption('hour_consumption'),
          cost: _viewModel.getSummaryCost('hour_cost'),
          icon: StrokeIcons.hourglassBottom,
        ),
        _DimensionData(
          title: '1天',
          consumption: _viewModel.getSummaryConsumption('day_consumption'),
          cost: _viewModel.getSummaryCost('day_cost'),
          icon: StrokeIcons.today,
        ),
        _DimensionData(
          title: '7天',
          consumption: _viewModel.getSummaryConsumption('week_consumption'),
          cost: _viewModel.getSummaryCost('week_cost'),
          icon: StrokeIcons.dateRange,
        ),
        _DimensionData(
          title: '15天',
          consumption: _viewModel.getSummaryConsumption('fifteen_day_consumption'),
          cost: _viewModel.getSummaryCost('fifteen_day_cost'),
          icon: StrokeIcons.calendarMonth,
        ),
        _DimensionData(
          title: '16天',
          consumption: _viewModel.getSummaryConsumption('sixteen_day_consumption'),
          cost: 0,
          icon: StrokeIcons.calendarViewWeek,
          costHidden: true,
        ),
        _DimensionData(
          title: '30天',
          consumption: _viewModel.getSummaryConsumption('thirty_day_consumption'),
          cost: _viewModel.getSummaryCost('thirty_day_cost'),
          icon: StrokeIcons.calendarToday,
        ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: m.kSpace4, bottom: m.kSpace8),
            child: PsSectionLabel('耗电量维度统计', color: p.ink.withAlpha(180)),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final spacing = m.kSpace12;
              // 一张卡至少要够"数字 + 单位 + 那行约等于多少钱"，宽了就再塞一列。
              // 上限是维度个数——六个维度摆七列只会多出一列空的。
              int columns =
                  ((box.maxWidth + spacing) / (scaleW(150) + spacing)).floor();
              if (columns < 1) columns = 1;
              if (columns > dims.length) columns = dims.length;
              final itemW = (box.maxWidth - spacing * (columns - 1)) / columns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  // 高度钉一档：列数变多时卡片变窄而不是变矮，省下的竖直空白才是真的
                  childAspectRatio: itemW / scaleW(122),
                ),
                itemCount: dims.length,
                itemBuilder: (context, i) => _buildDimensionCard(m, unit, dims[i]),
              );
            },
          ),
        ],
      );
    });
  }

  Widget _buildDimensionCard(
    ThemeMetrics m,
    PowerUnit unit,
    _DimensionData data,
  ) {
    final p = PowerStatsPalette.of(context);
    // 这些卡片报的都是耗电量，沿用图表里"电量=amber"这一身份
    final viz = AppVizSet.of(context);
    return PsGlassCard(
      padding: EdgeInsets.fromLTRB(
        m.kSpace12,
        m.kSpace12,
        m.kSpace12,
        m.kSpace10,
      ),
      radius: m.radius14,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  DrawIcon(data.icon, size: m.iconSize12, color: p.violet),
                  SizedBox(width: m.kSpace6),
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  PsRollingNumber(
                    value: data.consumption,
                    majorStyle: TextStyle(
                      fontSize: m.fontSize18,
                      fontWeight: FontWeight.w800,
                      color: viz.amber.base,
                      height: 1.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    formatMajor: unit.format,
                  ),
                  SizedBox(width: m.kSpace4),
                  Text(
                    unit.label,
                    style: TextStyle(
                      fontSize: m.fontSize10,
                      color: p.ink.withAlpha(110),
                    ),
                  ),
                ],
              ),
              // 没有电费可报的那一档也要把这一行占住：Column 是 spaceBetween，
              // 少一个孩子就会把上面那排数字甩到底边上，一排六张卡片就它对不齐
              Text(
                data.costHidden ? ' ' : '≈ ${data.cost.toStringAsFixed(2)} 元',
                style: TextStyle(
                  fontSize: m.fontSize11,
                  color: p.ink.withAlpha(130),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          // 底缘那条身份下划线：长度就是"这个窗口占 30 天总量的比例"
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PsGradientBar(
              value: _dimensionShare(data.consumption),
              gradient: p.underline(),
              height: m.strokeBold,
            ),
          ),
        ],
      ),
    );
  }

  /// 该维度相对 30 天总量的占比，只用来定下划线那根条的长度
  double _dimensionShare(double consumption) {
    final total = _viewModel.getSummaryConsumption('thirty_day_consumption');
    if (total <= 0) return 0;
    return (consumption / total).clamp(0.0, 1.0);
  }

  // ── 配置卡片 ────────────────────────────────────────────────────────────
  Widget _buildConfigCard(BuildContext context, ThemeMetrics m) {
    if (!_viewModel.isLocal) return const SizedBox.shrink();
    final s = AppSemantic.of(context);
    final p = PowerStatsPalette.of(context);
    return Obx(() {
      final enabled = _viewModel.isEnabled.value;
      return PsGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 定时统计总开关：页头横幅折进这张卡之后，它理当和其余采集项待在一起
                Container(
                  width: m.kSpace24,
                  height: m.kSpace24,
                  decoration: BoxDecoration(
                    color: enabled
                        ? s.warning.color.withAlpha(30)
                        : p.ink.withAlpha(10),
                    borderRadius: m.radius6,
                  ),
                  child: DrawIcon(
                    StrokeIcons.electricBolt,
                    size: m.iconSize12,
                    color: enabled ? s.warning.color : p.ink.withAlpha(80),
                  ),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '采集配置',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: enabled,
                  onChanged: (v) => _viewModel.toggleEnabled(v),
                  activeThumbColor: s.warning.color,
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            // 表号输入
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _meterIdController,
                    decoration: InputDecoration(
                      labelText: '电表号',
                      hintText: '输入电表号 (如 19501609994)',
                      isDense: true,
                      prefixIcon: DrawIcon(
                        StrokeIcons.numbers,
                        size: m.iconSize16,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: m.kSpace8),
                Material(
                  color: p.accent,
                  borderRadius: m.radius8,
                  child: InkWell(
                    borderRadius: m.radius8,
                    onTap: () async {
                      final val = _meterIdController.text.trim();
                      if (val.isEmpty) return;
                      // 保存即开轮询：Rust 侧的调度器起来后第一件事就是抓一次，
                      // 这里再 fetchOnce 就成了对同一张电表页的重复请求。
                      await _viewModel.saveMeterId(val);
                      _viewModel.refreshAll();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace16,
                        vertical: m.kSpace12,
                      ),
                      child: Text(
                        '保存表号',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            // 轮询间隔
            Row(
              children: [
                Text(
                  '轮询间隔',
                  style: TextStyle(
                    fontSize: m.fontSize12,
                    color: p.ink.withAlpha(150),
                  ),
                ),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Slider(
                    value: _viewModel.intervalSecs.value.toDouble(),
                    min: 30,
                    max: 300,
                    divisions: 9,
                    label: '${_viewModel.intervalSecs.value}秒',
                    onChanged: (v) {
                      _viewModel.intervalSecs.value = v.toInt();
                    },
                    onChangeEnd: (v) {
                      _viewModel.saveIntervalSecs(v.toInt());
                    },
                  ),
                ),
                SizedBox(width: m.kSpace8),
                SizedBox(
                  width: m.kSpace48,
                  child: Text(
                    '${_viewModel.intervalSecs.value}s',
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      fontWeight: FontWeight.w600,
                      color: p.accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace8),
            Row(
              children: [
                if (_viewModel.isPolling.value)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _viewModel.stopPolling(),
                      icon: DrawIcon(StrokeIcons.stopCircle, size: m.iconSize14),
                      label: const Text('停止轮询'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _viewModel.meterId.value.isEmpty
                          ? null
                          : () => _viewModel.startPolling(),
                      icon: DrawIcon(
                        StrokeIcons.playCircleOutline,
                        size: m.iconSize14,
                      ),
                      label: const Text('启动轮询'),
                    ),
                  ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewModel.clearLogs(),
                    icon: DrawIcon(StrokeIcons.deleteOutline, size: m.iconSize14),
                    label: const Text('清空日志'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ── 日志卡片 ────────────────────────────────────────────────────────────
  Widget _buildLogCard(BuildContext context, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    final p = PowerStatsPalette.of(context);
    // 抓到的小时读数沿用"电量=amber"这套身份，跟上面的卡片与图表对齐
    final viz = AppVizSet.of(context);
    return Obx(() {
      final logs = _viewModel.logs;
      return PsGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrawIcon(StrokeIcons.history, size: m.iconSize14, color: p.violet),
                SizedBox(width: m.kSpace8),
                Text(
                  '抓取日志',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} 条',
                  style: TextStyle(
                    fontSize: m.fontSize12,
                    color: p.ink.withAlpha(110),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            if (logs.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace24),
                  child: Text(
                    '暂无日志',
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      color: p.ink.withAlpha(100),
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.35,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, color: p.ink.withAlpha(20)),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final success = log['success'] as bool? ?? false;
                    final ts = log['timestamp'] as String? ?? '';
                    final msg = log['message'] as String? ?? '';
                    final kwh = (log['kwh'] as num?)?.toDouble() ?? 0.0;
                    // 日志按时间正序存，读的人却要先看刚发生的那次，
                    // 所以给最后一条加重一档字色，省得从头滚到尾找
                    final isLatest = i == logs.length - 1;
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: m.kSpace6),
                      child: Row(
                        children: [
                          Container(
                            width: m.kSpace6,
                            height: m.kSpace6,
                            decoration: BoxDecoration(
                              color: success ? s.success.color : s.danger.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: m.kSpace8),
                          SizedBox(
                            width: m.kSpace80,
                            child: Text(
                              ts.split(' ').lastOrNull ?? ts,
                              style: TextStyle(
                                fontSize: m.fontSize11,
                                color: p.ink.withAlpha(isLatest ? 190 : 110),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          SizedBox(width: m.kSpace8),
                          Expanded(
                            child: Text(
                              msg,
                              style: TextStyle(
                                fontSize: m.fontSize12,
                                color: success
                                    ? p.ink.withAlpha(isLatest ? 230 : 170)
                                    : s.danger.color,
                              ),
                            ),
                          ),
                          if (success && kwh > 0) ...[
                            SizedBox(width: m.kSpace8),
                            Text(
                              '${kwh.toStringAsFixed(2)} kWh',
                              style: TextStyle(
                                fontSize: m.fontSize11,
                                color: viz.amber.to,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    });
  }

  // ── 派生数据 ────────────────────────────────────────────────────────────

  /// 远程节点进程重启后 status 的内存态会归零，而 summary 走节点数据库仍有值；
  /// 谁有值用谁，免得卡片停在 0.000 而下面图表却有数据
  double get _balanceYuan {
    final live = _viewModel.currentYuan.value;
    if (live > 0) return live;
    return (_viewModel.summary['current_yuan'] as num?)?.toDouble() ?? 0.0;
  }

  double get _balanceKwh {
    final live = _viewModel.currentKwh.value;
    if (live > 0) return live;
    return (_viewModel.summary['current_kwh'] as num?)?.toDouble() ?? 0.0;
  }

  String _clockOf(String ts) {
    if (ts.isEmpty) return '尚未抓取';
    return ts.split(' ').lastOrNull ?? ts;
  }

  /// 拿到一条新读数就推一个抓取事件：横幅擦入、曲线末端涟漪、卡外发光同步起。
  ///
  /// 判重键带上 last_result 而不只是时间戳——抓取失败时 Rust 不一定更新 last_fetch，
  /// 但失败原因一定变，否则失败那一下没有任何视觉交代。
  void _emitFetchEvent() {
    final ts = _viewModel.lastFetch.value;
    final result = _viewModel.lastResult.value;
    if (ts.isEmpty && result.isEmpty) return;
    final key = '$ts|$result';
    if (key == _lastEventKey) return;
    _lastEventKey = key;

    // 失败判据走 last_result 的固定前缀：这个串是 Rust 侧 status.last_result
    // 写死的两种格式之一，不是自由文本
    final ok = !result.startsWith('抓取失败');
    final yuan = _balanceYuan;

    // 右侧那个大字报"这一次掉了多少钱"：电表余额只减不增，
    // 第一次没有参照就退回显示当前余额
    final prev = _prevYuan;
    _prevYuan = yuan;
    final String amount;
    if (!ok) {
      // 右侧那格报的是"这一次入账多少"，失败就是没有数额可报。
      // 写"失败"和标题重一句话，写"未入账"才补出信息量
      amount = '未入账';
    } else if (prev == null) {
      amount = '¥${yuan.toStringAsFixed(2)}';
    } else {
      final spent = prev - yuan;
      amount = spent.abs() < 0.005
          ? '±0'
          : '${spent > 0 ? '-' : '+'}¥${spent.abs().toStringAsFixed(2)}';
    }

    setState(() {
      _fetchEvent = PsFetchEvent(
        id: ++_eventId,
        title: ok ? '抓取成功' : '抓取失败',
        // 成功时左侧报"什么时候抓的"就够了：last_result 的正文本身以
        // "抓取成功"开头，再贴一遍就是和标题重复一句话。失败同理，
        // 把 "抓取失败: " 剃掉只留原因
        detail: ok
            ? ts
            : result.replaceFirst(RegExp(r'^抓取失败[:：]?\s*'), ''),
        amount: amount,
        ok: ok,
      );
    });
  }
}

// ── 数据模型 ────────────────────────────────────────────────────────────────
class _SummaryCardData {
  final StrokeIcon icon;
  final String label;

  /// 原始值：电量一律存 kWh，展示换算交给 [format]
  final double value;
  final String unit;
  final Color color;

  /// 滚动数字的取值→文本换算：单位切换后同一个数要换个写法，所以格式必须是纯函数
  final String Function(double) format;
  const _SummaryCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.format,
  });
}

class _DimensionData {
  final String title;
  final double consumption;
  final double cost;
  final StrokeIcon icon;
  final bool costHidden;
  const _DimensionData({
    required this.title,
    required this.consumption,
    required this.cost,
    required this.icon,
    this.costHidden = false,
  });
}
