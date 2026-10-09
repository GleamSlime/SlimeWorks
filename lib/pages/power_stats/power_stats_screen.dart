import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/node/node_switcher_button.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/utils/size_utils.dart' show PlatformUtil;
import 'package:slime_works/view_models/power_stats_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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
  Timer? _realtimeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _viewModel = Get.put(PowerStatsViewModel());
    _nodeService = GetIt.instance.get<NodeSettingsService>();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
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
    final theme = Theme.of(context);
    final isNarrow = PlatformUtil.isMobile || MediaQuery.of(context).size.width < 720;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '电力统计',
        actions: [
          _buildNodeSwitcher(context, theme, m),
          SizedBox(width: m.kSpace8),
          _buildFetchButton(context, theme, m),
          SizedBox(width: m.kSpace8),
        ],
      ),
      child: FadeTransition(
        opacity: _entranceAnimation,
        child: Obx(() {
          if (!_viewModel.isConfigLoaded.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: EdgeInsets.all(m.kSpace16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderBanner(context, theme, m),
                SizedBox(height: m.kSpace16),
                _buildRangeSelector(context, theme, m, isNarrow),
                SizedBox(height: m.kSpace16),
                _buildSummaryGrid(context, theme, m, isNarrow),
                SizedBox(height: m.kSpace16),
                _buildChartCard(context, theme, m, isNarrow),
                SizedBox(height: m.kSpace16),
                _buildDimensionGrid(context, theme, m, isNarrow),
                SizedBox(height: m.kSpace16),
                _buildConfigCard(context, theme, m),
                SizedBox(height: m.kSpace16),
                _buildLogCard(context, theme, m),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── 顶部节点切换 ────────────────────────────────────────────────────────
  Widget _buildNodeSwitcher(BuildContext context, ThemeData theme, ThemeMetrics m) {
    if (_nodeService == null) return const SizedBox.shrink();
    return NodeSwitcherButton(
      nodeService: _nodeService!,
      currentNodeId: _viewModel.currentNodeId.value,
      availabilityChecker: _viewModel.checkNodePowerStatsAvailable,
      onNodeSelected: (nodeId) => _viewModel.switchNode(nodeId),
    );
  }

  Widget _buildFetchButton(BuildContext context, ThemeData theme, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    return Obx(
      () => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: m.radius20,
          onTap: _viewModel.isFetching.value
              ? null
              : () => _viewModel.fetchOnce(),
          child: Container(
            height: m.kSpace32,
            padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
            decoration: BoxDecoration(
              color: s.warning.color.withAlpha(30),
              borderRadius: m.radius20,
              border: Border.all(color: s.warning.color.withAlpha(80), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewModel.isFetching.value
                    ? SizedBox(
                        width: m.iconSize14,
                        height: m.iconSize14,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : DrawIcon(StrokeIcons.bolt,
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

  // ── 顶部状态横幅 ────────────────────────────────────────────────────────
  Widget _buildHeaderBanner(BuildContext context, ThemeData theme, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    return Obx(() {
      final enabled = _viewModel.isEnabled.value;
      final polling = _viewModel.isPolling.value;

      return Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? [
                    s.warning.color.withAlpha(25),
                    s.warning.color.withAlpha(15),
                  ]
                : [
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                    theme.colorScheme.surfaceContainerHighest.withAlpha(30),
                  ],
          ),
          borderRadius: m.radius12,
          border: Border.all(
            color: enabled
                ? s.warning.color.withAlpha(60)
                : theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
        child: Row(
          children: [
            // 闪电图标
            Container(
              width: m.kSpace44,
              height: m.kSpace44,
              decoration: BoxDecoration(
                color: enabled
                    ? s.warning.color.withAlpha(30)
                    : theme.colorScheme.onSurface.withAlpha(8),
                borderRadius: m.radius10,
              ),
              child: DrawIcon(StrokeIcons.electricBolt,
                size: m.iconSize24,
                color: enabled ? s.warning.color : theme.colorScheme.onSurface.withAlpha(50),
              ),
            ),
            SizedBox(width: m.kSpace14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _viewModel.meterName.value.isEmpty
                            ? '未配置电表'
                            : _viewModel.meterName.value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (polling) ...[
                        SizedBox(width: m.kSpace8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace6,
                            vertical: m.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: s.success.color.withAlpha(20),
                            borderRadius: m.radius4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: m.kSpace4,
                                height: m.kSpace4,
                                decoration: BoxDecoration(
                                  color: s.success.color,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: s.success.color.withAlpha(80),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: m.kSpace4),
                              Text(
                                '轮询中',
                                style: TextStyle(
                                  fontSize: m.fontSize10,
                                  color: s.success.onContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    _viewModel.isLocal
                        ? (enabled
                              ? '本地定时统计 - 每${_viewModel.intervalSecs.value}秒抓取一次'
                              : '本地模式 - 数据持久化到数据库')
                        : '远程节点模式 - 数据由节点服务持久化',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
            if (_viewModel.isLocal)
              Switch(
                value: enabled,
                onChanged: (v) => _viewModel.toggleEnabled(v),
                activeThumbColor: s.warning.color,
              ),
          ],
        ),
      );
    });
  }

  // ── 时间范围 + 维度切换 ────────────────────────────────────────────────
  Widget _buildRangeSelector(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isNarrow,
  ) {
    // 图表维度（耗电量/余额/电费）的身份色走 viz，不当状态色用
    final viz = AppVizSet.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 时间范围筛选
        Obx(
          () => Container(
            padding: EdgeInsets.symmetric(
              horizontal: m.kSpace6,
              vertical: m.kSpace6,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: m.radius12,
              border: Border.all(color: theme.dividerColor.withAlpha(40)),
            ),
            child: Wrap(
              spacing: m.kSpace4,
              runSpacing: m.kSpace4,
              children: PowerStatsRange.all.map((r) {
                final selected = _viewModel.selectedRange.value == r.key;
                return _buildRangeChip(theme, m, r.label, selected, () {
                  _viewModel.setRange(r.key);
                });
              }).toList(),
            ),
          ),
        ),
        SizedBox(height: m.kSpace8),
        // 维度切换（耗电量/余额/电费）
        Obx(
          () => Container(
            padding: EdgeInsets.symmetric(
              horizontal: m.kSpace6,
              vertical: m.kSpace6,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: m.radius12,
              border: Border.all(color: theme.dividerColor.withAlpha(40)),
            ),
            child: Wrap(
              spacing: m.kSpace4,
              runSpacing: m.kSpace4,
              children: [
                _buildMetricChip(
                  theme,
                  m,
                  '耗电量',
                  PowerChartMetric.consumption,
                  viz.amber.base,
                ),
                _buildMetricChip(
                  theme,
                  m,
                  '余额',
                  PowerChartMetric.balance,
                  viz.sky.base,
                ),
                _buildMetricChip(
                  theme,
                  m,
                  '电费',
                  PowerChartMetric.cost,
                  viz.coral.base,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: m.kSpace8),
        // 计量单位切换（Wh / kWh / MWh），统一作用于卡片与图表
        Obx(
          () => Container(
            padding: EdgeInsets.symmetric(
              horizontal: m.kSpace6,
              vertical: m.kSpace6,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: m.radius12,
              border: Border.all(color: theme.dividerColor.withAlpha(40)),
            ),
            child: Wrap(
              spacing: m.kSpace4,
              runSpacing: m.kSpace4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace8),
                  child: Text(
                    '计量单位',
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      color: theme.colorScheme.onSurface.withAlpha(120),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ...PowerUnit.values.map(
                  (u) => _buildUnitChip(context, theme, m, u),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitChip(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    PowerUnit unit,
  ) {
    final s = AppSemantic.of(context);
    final selected = _viewModel.selectedUnit.value == unit;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius8,
        onTap: () => _viewModel.setUnit(unit),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.kSpace12,
            vertical: m.kSpace6,
          ),
          decoration: BoxDecoration(
            color: selected
                ? s.warning.color.withAlpha(25)
                : Colors.transparent,
            borderRadius: m.radius8,
            border: Border.all(
              color: selected
                  ? s.warning.color.withAlpha(90)
                  : theme.dividerColor.withAlpha(40),
            ),
          ),
          child: Text(
            unit.label,
            style: TextStyle(
              fontSize: m.fontSize12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? s.warning.onContainer
                  : theme.colorScheme.onSurface.withAlpha(120),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRangeChip(
    ThemeData theme,
    ThemeMetrics m,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius8,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.kSpace14,
            vertical: m.kSpace8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withAlpha(20)
                : Colors.transparent,
            borderRadius: m.radius8,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withAlpha(80)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: m.fontSize12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricChip(
    ThemeData theme,
    ThemeMetrics m,
    String label,
    PowerChartMetric metric,
    Color color,
  ) {
    final selected = _viewModel.selectedMetric.value == metric;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius8,
        onTap: () => _viewModel.setMetric(metric),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: m.kSpace14,
            vertical: m.kSpace8,
          ),
          decoration: BoxDecoration(
            color: selected ? color.withAlpha(20) : Colors.transparent,
            borderRadius: m.radius8,
            border: Border.all(
              color: selected ? color.withAlpha(80) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: m.kSpace6,
                height: m.kSpace6,
                decoration: BoxDecoration(
                  color: selected ? color : theme.colorScheme.onSurface.withAlpha(40),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: m.kSpace6),
              Text(
                label,
                style: TextStyle(
                  fontSize: m.fontSize12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? color
                      : theme.colorScheme.onSurface.withAlpha(120),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 汇总卡片网格 ────────────────────────────────────────────────────────
  Widget _buildSummaryGrid(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isNarrow,
  ) {
    final crossCount = isNarrow ? 2 : 3;
    // 三张并排卡片是"并列数据身份"，走 viz 而不是状态角色
    final viz = AppVizSet.of(context);
    return Obx(() {
      final unit = _viewModel.selectedUnit.value;
      final summaryKwh = (_viewModel.summary['current_kwh'] as num?)?.toDouble() ?? 0.0;
      final summaryYuan = (_viewModel.summary['current_yuan'] as num?)?.toDouble() ?? 0.0;
      // 远程节点进程重启后 status 的内存态会归零，而 summary 走节点数据库仍有值；
      // 谁有值用谁，免得卡片停在 0.000 而下面图表却有数据
      final kwh = _viewModel.currentKwh.value > 0
          ? _viewModel.currentKwh.value
          : summaryKwh;
      final yuan = _viewModel.currentYuan.value > 0
          ? _viewModel.currentYuan.value
          : summaryYuan;
      final lastUpdate = _viewModel.summary['last_update'] as String? ??
          _viewModel.lastFetch.value;
      final minuteCons = _viewModel.getSummaryConsumption('minute_consumption');

      final cards = <_SummaryCardData>[
        _SummaryCardData(
          icon: StrokeIcons.bolt,
          label: '剩余电量',
          value: unit.format(kwh),
          unit: unit.label,
          // 原值 #FFCB3A 正是 amber 这组身份的渐变终点档，两档主题下同值
          color: viz.amber.to,
        ),
        _SummaryCardData(
          icon: StrokeIcons.accountBalanceWallet,
          label: '剩余金额',
          value: yuan.toStringAsFixed(2),
          unit: '元',
          color: viz.sky.base,
        ),
        _SummaryCardData(
          icon: StrokeIcons.timer,
          label: '分钟耗电',
          value: unit.format(minuteCons),
          unit: unit.label,
          color: viz.mint.base,
        ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lastUpdate.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: m.kSpace4, bottom: m.kSpace8),
              child: Text(
                '上次更新: $lastUpdate',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(100),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              crossAxisSpacing: m.kSpace12,
              mainAxisSpacing: m.kSpace12,
              childAspectRatio: isNarrow ? 1.1 : 1.4,
            ),
            itemCount: cards.length,
            itemBuilder: (context, i) => _buildSummaryCard(theme, m, cards[i]),
          ),
        ],
      );
    });
  }

  Widget _buildSummaryCard(ThemeData theme, ThemeMetrics m, _SummaryCardData data) {
    return Container(
      padding: EdgeInsets.all(m.kSpace14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: m.radius12,
        border: Border.all(color: theme.dividerColor.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: m.kSpace24,
                height: m.kSpace24,
                decoration: BoxDecoration(
                  color: data.color.withAlpha(20),
                  borderRadius: m.radius6,
                ),
                child: DrawIcon(data.icon, size: m.iconSize12, color: data.color),
              ),
              SizedBox(width: m.kSpace8),
              Expanded(
                child: Text(
                  data.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: m.kSpace8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                data.value,
                style: TextStyle(
                  fontSize: m.fontSize22,
                  fontWeight: FontWeight.w700,
                  color: data.color,
                  height: 1.1,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(width: m.kSpace4),
              Text(
                data.unit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(100),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 主图表卡片 ──────────────────────────────────────────────────────────
  Widget _buildChartCard(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isNarrow,
  ) {
    // 折线颜色即"这条线画的是哪个维度"的身份，与上面的维度切换 chip 同源
    final viz = AppVizSet.of(context);
    return Obx(() {
      final buckets = _viewModel.buckets;
      final metric = _viewModel.selectedMetric.value;
      final rangeLabel = PowerStatsRange.all
          .firstWhere(
            (r) => r.key == _viewModel.selectedRange.value,
            orElse: () => const PowerStatsRange('1day', '1天'),
          )
          .label;

      String title;
      String unit;
      Color color;
      double sumValue = 0;
      String sumText = '';
      // 只有电量维度吃用户选的计量单位，余额/电费固定按元展示
      double unitScale = 1;
      switch (metric) {
        case PowerChartMetric.consumption:
          final powerUnit = _viewModel.selectedUnit.value;
          title = '耗电量趋势';
          unit = powerUnit.label;
          unitScale = powerUnit.factor;
          color = viz.amber.base;
          // 耗电量：所有桶累加
          sumValue = buckets.fold<double>(0, (s, b) => s + b.consumptionKwh);
          sumText = '${powerUnit.format(sumValue)}${powerUnit.label}';
        case PowerChartMetric.balance:
          title = '余额变化';
          unit = '元';
          color = viz.sky.base;
          // 余额：末值 - 首值（区间变化量）
          if (buckets.length >= 2) {
            sumValue = buckets.last.balanceYuan - buckets.first.balanceYuan;
            final sign = sumValue >= 0 ? '+' : '';
            sumText = '$sign${sumValue.toStringAsFixed(2)}$unit';
          } else if (buckets.length == 1) {
            sumText = '${buckets.first.balanceYuan.toStringAsFixed(2)}$unit';
          }
        case PowerChartMetric.cost:
          title = '电费趋势';
          unit = '元';
          color = viz.coral.base;
          sumValue = buckets.fold<double>(0, (s, b) => s + b.costYuan);
          sumText = '${sumValue.toStringAsFixed(2)}$unit';
      }

      // 图表只画有值的采样桶：这类"流量"型指标（耗电量/电费）绝大多数桶是 0，
      // 留着会把曲线压成一地锯齿，也撑不满纵轴。余额是"存量"，0 也是有效读数，不过滤。
      // 上面的合计/区间变化仍用完整 buckets，过滤不能影响它们。
      final chartBuckets = switch (metric) {
        PowerChartMetric.balance => buckets,
        // 全是 0 时退回原始桶：空图比一条 0 平线更难读
        _ => _withoutZeroBuckets(buckets, metric),
      };

      return Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace24,
                  height: m.kSpace24,
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: m.radius6,
                  ),
                  child: DrawIcon(StrokeIcons.showChart, size: m.iconSize12, color: color),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '$title · $rangeLabel',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (sumText.isNotEmpty) ...[
                  SizedBox(width: m.kSpace8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: m.kSpace8,
                      vertical: m.kSpace2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(15),
                      borderRadius: m.radius6,
                      border: Border.all(color: color.withAlpha(50), width: 0.5),
                    ),
                    child: Text(
                      sumText,
                      style: TextStyle(
                        fontSize: m.fontSize12,
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (buckets.isNotEmpty)
                  Text(
                    '采样 ${_viewModel.aggregatedSampleCount.value} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100),
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
            SizedBox(height: m.kSpace16),
            SizedBox(
              height: isNarrow ? 200 : 260,
              child: chartBuckets.isEmpty
                  ? _buildEmptyChart(theme, m)
                  : _InteractivePowerChart(
                      buckets: chartBuckets,
                      metric: metric,
                      color: color,
                      unit: unit,
                      unitScale: unitScale,
                    ),
            ),
          ],
        ),
      );
    });
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

  Widget _buildEmptyChart(ThemeData theme, ThemeMetrics m) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DrawIcon(StrokeIcons.insights,
            size: m.iconSize40,
            color: theme.colorScheme.onSurface.withAlpha(30),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '暂无统计数据',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '点击右上角"抓取"开始采集',
            style: TextStyle(
              fontSize: m.fontSize11,
              color: theme.colorScheme.onSurface.withAlpha(60),
            ),
          ),
        ],
      ),
    );
  }

  // ── 维度卡片网格（小时/1天/7天/15天/30天）────────────────────────────
  Widget _buildDimensionGrid(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isNarrow,
  ) {
    final crossCount = isNarrow ? 2 : 3;
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
            child: Text(
              '耗电量维度统计',
              style: TextStyle(
                fontSize: m.fontSize13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withAlpha(180),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              crossAxisSpacing: m.kSpace12,
              mainAxisSpacing: m.kSpace12,
              childAspectRatio: isNarrow ? 1.5 : 1.8,
            ),
            itemCount: dims.length,
            itemBuilder: (context, i) =>
                _buildDimensionCard(context, theme, m, unit, dims[i]),
          ),
        ],
      );
    });
  }

  Widget _buildDimensionCard(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    PowerUnit unit,
    _DimensionData data,
  ) {
    // 这些卡片报的都是耗电量，沿用图表里"电量=amber"这一身份
    final viz = AppVizSet.of(context);
    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: m.radius12,
        border: Border.all(color: theme.dividerColor.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              DrawIcon(data.icon, size: m.iconSize12, color: theme.colorScheme.primary),
              SizedBox(width: m.kSpace6),
              Text(
                data.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                unit.format(data.consumption),
                style: TextStyle(
                  fontSize: m.fontSize18,
                  fontWeight: FontWeight.w700,
                  color: viz.amber.base,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(width: m.kSpace4),
              Text(
                unit.label,
                style: TextStyle(
                  fontSize: m.fontSize10,
                  color: theme.colorScheme.onSurface.withAlpha(100),
                ),
              ),
            ],
          ),
          if (!data.costHidden)
            Text(
              '≈ ${data.cost.toStringAsFixed(2)} 元',
              style: TextStyle(
                fontSize: m.fontSize11,
                color: theme.colorScheme.onSurface.withAlpha(120),
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  // ── 配置卡片 ────────────────────────────────────────────────────────────
  Widget _buildConfigCard(BuildContext context, ThemeData theme, ThemeMetrics m) {
    if (!_viewModel.isLocal) return const SizedBox.shrink();
    return Obx(() {
      return Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrawIcon(StrokeIcons.tune, size: m.iconSize14, color: theme.colorScheme.primary),
                SizedBox(width: m.kSpace8),
                Text(
                  '采集配置',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
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
                      prefixIcon: DrawIcon(StrokeIcons.numbers,
                        size: m.iconSize16,
                      ),
                    ),
                    style: TextStyle(fontSize: m.fontSize13, fontFamily: 'monospace'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: m.kSpace8),
                Material(
                  color: theme.colorScheme.primary,
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
                          color: theme.colorScheme.onPrimary,
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(140),
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
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
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
                      icon: DrawIcon(StrokeIcons.playCircleOutline, size: m.iconSize14),
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
  Widget _buildLogCard(BuildContext context, ThemeData theme, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    // 抓到的小时读数沿用"电量=amber"这套身份，跟上面的卡片与图表对齐
    final viz = AppVizSet.of(context);
    return Obx(() {
      final logs = _viewModel.logs;
      return Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrawIcon(StrokeIcons.history, size: m.iconSize14, color: theme.colorScheme.primary),
                SizedBox(width: m.kSpace8),
                Text(
                  '抓取日志',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(100),
                    fontFamily: 'monospace',
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(80),
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
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: theme.dividerColor.withAlpha(30),
                  ),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final success = log['success'] as bool? ?? false;
                    final ts = log['timestamp'] as String? ?? '';
                    final msg = log['message'] as String? ?? '';
                    final kwh = (log['kwh'] as num?)?.toDouble() ?? 0.0;
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
                                color: theme.colorScheme.onSurface.withAlpha(100),
                                fontFamily: 'monospace',
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
                                    ? theme.colorScheme.onSurface.withAlpha(180)
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
                                fontFamily: 'monospace',
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
}

// ── 数据模型 ────────────────────────────────────────────────────────────────
class _SummaryCardData {
  final StrokeIcon icon;
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _SummaryCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
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

// ── 交互式图表（hover十字线 + tooltip）──────────────────────────────────────

/// 图表数值的自适应小数位：数值越大位数越少，避免 Wh 下出现一长串无意义小数
String _formatPowerValue(double v) {
  final a = v.abs();
  if (a >= 1000) return v.toStringAsFixed(0);
  if (a >= 100) return v.toStringAsFixed(1);
  if (a >= 1) return v.toStringAsFixed(2);
  return v.toStringAsFixed(3);
}

class _InteractivePowerChart extends StatefulWidget {
  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;
  final String unit;
  /// kWh → 展示单位的换算系数（余额/电费恒为 1）
  final double unitScale;

  const _InteractivePowerChart({
    required this.buckets,
    required this.metric,
    required this.color,
    required this.unit,
    this.unitScale = 1.0,
  });

  @override
  State<_InteractivePowerChart> createState() => _InteractivePowerChartState();
}

class _InteractivePowerChartState extends State<_InteractivePowerChart> {
  // 图表内边距，需与 _ChartCanvas 保持一致
  static const double _padLeft = 44.0;
  static const double _padRight = 14.0;

  int? _hoverIndex;

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
                CustomPaint(
                  size: size,
                  painter: _ChartCanvas(
                    buckets: widget.buckets,
                    metric: widget.metric,
                    color: widget.color,
                    textColor:
                        theme.textTheme.bodySmall?.color ?? s.textTertiary,
                    // 数据点外圈要挖出卡片表面那层底，不能写死白：暗色下白圈会
                    // 在深灰卡上变成一圈"亮斑"
                    surfaceColor: s.surface,
                    gridColor: theme.dividerColor.withAlpha(40),
                    hoverIndex: _hoverIndex,
                    unitScale: widget.unitScale,
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
        valueText = '${_formatPowerValue(currentValue)} ${widget.unit}';
        // 耗电量上升=多用电=负面（红），下降=省电=正面（绿）
        isUpGood = false;
      case PowerChartMetric.balance:
        metricLabel = '余额';
        currentValue = _value(bucket);
        valueText = '${_formatPowerValue(currentValue)} ${widget.unit}';
        // 余额上升=正面（绿），下降=负面（红）
        isUpGood = true;
      case PowerChartMetric.cost:
        metricLabel = '电费';
        currentValue = _value(bucket);
        valueText = '${_formatPowerValue(currentValue)} ${widget.unit}';
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
          delegate: _TooltipLayoutDelegate(anchor: p),
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
                border: Border.all(color: widget.color.withAlpha(120), width: 1),
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
                    bucket.label,
                    style: TextStyle(
                      fontSize: m.fontSize11,
                      color: theme.colorScheme.onSurface.withAlpha(160),
                      fontFamily: 'monospace',
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
                          fontFamily: 'monospace',
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
                              fontFamily: 'monospace',
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
class _TooltipLayoutDelegate extends SingleChildLayoutDelegate {
  const _TooltipLayoutDelegate({required this.anchor});

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

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
  bool shouldRelayout(_TooltipLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _ChartCanvas extends CustomPainter {
  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;
  final Color textColor;
  final Color gridColor;

  /// 卡片表面色：数据点那圈"挖空"要用它，写死白在暗色下就是一圈亮斑
  final Color surfaceColor;
  final int? hoverIndex;
  /// kWh → 展示单位的换算系数（余额/电费恒为 1）
  final double unitScale;

  _ChartCanvas({
    required this.buckets,
    required this.metric,
    required this.color,
    required this.textColor,
    required this.gridColor,
    required this.surfaceColor,
    this.hoverIndex,
    this.unitScale = 1.0,
  });

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
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = padTop + chartH * i / 4;
      canvas.drawLine(Offset(padLeft, y), Offset(padLeft + chartW, y), gridPaint);
      final v = maxV - range * i / 4;
      _drawText(
        canvas,
        _formatPowerValue(v),
        Offset(2, y - 6),
        TextStyle(color: textColor.withAlpha(120), fontSize: AppTheme.metrics.fontSize9),
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
        TextStyle(color: textColor.withAlpha(120), fontSize: AppTheme.metrics.fontSize9),
      );
    }

    // 渐变填充区域：折线 → 右下角 → 左下角 → 回到折线起点，闭合出一条沿底边的带。
    // 不能用 addPolygon：它会 moveTo(points.first) 另起一条子路径，把前面那个
    // "从底边起步"的点甩在另一条子路径里，之后的 lineTo/close 于是接在折线尾巴上，
    // 闭合线变成从右下角斜着拉回左上角第一个点——屏幕上就是一块大三角。
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
      ..strokeWidth = 2
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
  bool shouldRepaint(covariant _ChartCanvas old) =>
      old.buckets != buckets ||
      old.metric != metric ||
      old.color != color ||
      old.surfaceColor != surfaceColor ||
      old.hoverIndex != hoverIndex ||
      old.unitScale != unitScale;
}
