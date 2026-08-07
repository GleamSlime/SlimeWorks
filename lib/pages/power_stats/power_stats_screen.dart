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
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart' show PlatformUtil;
import 'package:slime_works/view_models/power_stats_viewmodel.dart';

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
              color: LightColors.yellow.withAlpha(30),
              borderRadius: m.radius20,
              border: Border.all(color: LightColors.yellow.withAlpha(80), width: 1),
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
                    : Icon(
                        Icons.bolt_rounded,
                        size: m.iconSize14,
                        color: LightColors.orange,
                      ),
                SizedBox(width: m.kSpace6),
                Text(
                  '抓取',
                  style: TextStyle(
                    fontSize: m.fontSize12,
                    fontWeight: FontWeight.w600,
                    color: LightColors.orange,
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
                    LightColors.yellow.withAlpha(25),
                    LightColors.orange.withAlpha(15),
                  ]
                : [
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                    theme.colorScheme.surfaceContainerHighest.withAlpha(30),
                  ],
          ),
          borderRadius: m.radius12,
          border: Border.all(
            color: enabled
                ? LightColors.yellow.withAlpha(60)
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
                    ? LightColors.yellow.withAlpha(30)
                    : theme.colorScheme.onSurface.withAlpha(8),
                borderRadius: m.radius10,
              ),
              child: Icon(
                Icons.electric_bolt_rounded,
                size: m.iconSize24,
                color: enabled ? LightColors.orange : theme.colorScheme.onSurface.withAlpha(50),
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
                            color: LightColors.green.withAlpha(20),
                            borderRadius: m.radius4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: m.kSpace4,
                                height: m.kSpace4,
                                decoration: BoxDecoration(
                                  color: LightColors.green,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: LightColors.green.withAlpha(80),
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
                                  color: LightColors.green,
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
                activeThumbColor: LightColors.orange,
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
                  LightColors.orange,
                ),
                _buildMetricChip(
                  theme,
                  m,
                  '余额',
                  PowerChartMetric.balance,
                  LightColors.blue,
                ),
                _buildMetricChip(
                  theme,
                  m,
                  '电费',
                  PowerChartMetric.cost,
                  LightColors.red,
                ),
              ],
            ),
          ),
        ),
      ],
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
    final crossCount = isNarrow ? 2 : 4;
    return Obx(() {
      final kwh = _viewModel.currentKwh.value;
      final yuan = _viewModel.currentYuan.value;
      final price = _viewModel.price.value;
      final lastUpdate = _viewModel.summary['last_update'] as String? ??
          _viewModel.lastFetch.value;
      final minuteCons = _viewModel.getSummaryConsumption('minute_consumption');

      final cards = <_SummaryCardData>[
        _SummaryCardData(
          icon: Icons.bolt_rounded,
          label: '剩余电量',
          value: kwh.toStringAsFixed(2),
          unit: 'kWh',
          color: LightColors.yellow,
        ),
        _SummaryCardData(
          icon: Icons.account_balance_wallet_rounded,
          label: '剩余金额',
          value: yuan.toStringAsFixed(2),
          unit: '元',
          color: LightColors.blue,
        ),
        _SummaryCardData(
          icon: Icons.local_offer_rounded,
          label: '综合单价',
          value: price.toStringAsFixed(2),
          unit: '元/kWh',
          color: LightColors.purple,
        ),
        _SummaryCardData(
          icon: Icons.timer_rounded,
          label: '分钟耗电',
          value: minuteCons.toStringAsFixed(3),
          unit: 'kWh',
          color: LightColors.green,
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
                child: Icon(data.icon, size: m.iconSize12, color: data.color),
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
      switch (metric) {
        case PowerChartMetric.consumption:
          title = '耗电量趋势';
          unit = 'kWh';
          color = LightColors.orange;
          // 耗电量：所有桶累加
          sumValue = buckets.fold<double>(0, (s, b) => s + b.consumptionKwh);
          sumText = '${sumValue.toStringAsFixed(2)}$unit';
        case PowerChartMetric.balance:
          title = '余额变化';
          unit = '元';
          color = LightColors.blue;
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
          color = LightColors.red;
          sumValue = buckets.fold<double>(0, (s, b) => s + b.costYuan);
          sumText = '${sumValue.toStringAsFixed(2)}$unit';
      }

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
                  child: Icon(Icons.show_chart_rounded, size: m.iconSize12, color: color),
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
              child: buckets.isEmpty
                  ? _buildEmptyChart(theme, m)
                  : _InteractivePowerChart(
                      buckets: buckets,
                      metric: metric,
                      color: color,
                      unit: unit,
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildEmptyChart(ThemeData theme, ThemeMetrics m) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.insights_rounded,
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
      final dims = <_DimensionData>[
        _DimensionData(
          title: '小时',
          consumption: _viewModel.getSummaryConsumption('hour_consumption'),
          cost: _viewModel.getSummaryCost('hour_cost'),
          icon: Icons.hourglass_bottom_rounded,
        ),
        _DimensionData(
          title: '1天',
          consumption: _viewModel.getSummaryConsumption('day_consumption'),
          cost: _viewModel.getSummaryCost('day_cost'),
          icon: Icons.today_rounded,
        ),
        _DimensionData(
          title: '7天',
          consumption: _viewModel.getSummaryConsumption('week_consumption'),
          cost: _viewModel.getSummaryCost('week_cost'),
          icon: Icons.date_range_rounded,
        ),
        _DimensionData(
          title: '15天',
          consumption: _viewModel.getSummaryConsumption('fifteen_day_consumption'),
          cost: _viewModel.getSummaryCost('fifteen_day_cost'),
          icon: Icons.calendar_month_rounded,
        ),
        _DimensionData(
          title: '16天',
          consumption: _viewModel.getSummaryConsumption('sixteen_day_consumption'),
          cost: 0,
          icon: Icons.calendar_view_week_rounded,
          costHidden: true,
        ),
        _DimensionData(
          title: '30天',
          consumption: _viewModel.getSummaryConsumption('thirty_day_consumption'),
          cost: _viewModel.getSummaryCost('thirty_day_cost'),
          icon: Icons.calendar_today_rounded,
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
            itemBuilder: (context, i) => _buildDimensionCard(theme, m, dims[i]),
          ),
        ],
      );
    });
  }

  Widget _buildDimensionCard(ThemeData theme, ThemeMetrics m, _DimensionData data) {
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
              Icon(data.icon, size: m.iconSize12, color: theme.colorScheme.primary),
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
                data.consumption.toStringAsFixed(3),
                style: TextStyle(
                  fontSize: m.fontSize18,
                  fontWeight: FontWeight.w700,
                  color: LightColors.orange,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(width: m.kSpace4),
              Text(
                'kWh',
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
                Icon(Icons.tune_rounded, size: m.iconSize14, color: theme.colorScheme.primary),
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
                  child: TextField(
                    controller: _meterIdController,
                    decoration: InputDecoration(
                      labelText: '电表号',
                      hintText: '输入电表号 (如 19501609994)',
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.numbers_rounded,
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
                    onTap: () {
                      final val = _meterIdController.text.trim();
                      if (val.isNotEmpty) {
                        _viewModel.saveMeterId(val);
                        _viewModel.fetchOnce();
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace16,
                        vertical: m.kSpace12,
                      ),
                      child: Text(
                        '保存并抓取',
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
                      icon: Icon(Icons.stop_circle_outlined, size: m.iconSize14),
                      label: const Text('停止轮询'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _viewModel.meterId.value.isEmpty
                          ? null
                          : () => _viewModel.startPolling(),
                      icon: Icon(Icons.play_circle_outline, size: m.iconSize14),
                      label: const Text('启动轮询'),
                    ),
                  ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewModel.clearLogs(),
                    icon: Icon(Icons.delete_outline_rounded, size: m.iconSize14),
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
                Icon(Icons.history_rounded, size: m.iconSize14, color: theme.colorScheme.primary),
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
                              color: success ? LightColors.green : LightColors.red,
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
                                    : LightColors.red,
                              ),
                            ),
                          ),
                          if (success && kwh > 0) ...[
                            SizedBox(width: m.kSpace8),
                            Text(
                              '${kwh.toStringAsFixed(2)} kWh',
                              style: TextStyle(
                                fontSize: m.fontSize11,
                                color: LightColors.yellow,
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
  final IconData icon;
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
  final IconData icon;
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
class _InteractivePowerChart extends StatefulWidget {
  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;
  final String unit;

  const _InteractivePowerChart({
    required this.buckets,
    required this.metric,
    required this.color,
    required this.unit,
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
        return b.consumptionKwh;
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
                        theme.textTheme.bodySmall?.color ?? Colors.grey,
                    gridColor: theme.dividerColor.withAlpha(40),
                    hoverIndex: _hoverIndex,
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
        currentValue = bucket.consumptionKwh;
        valueText = '${currentValue.toStringAsFixed(3)} ${widget.unit}';
        // 耗电量上升=多用电=负面（红），下降=省电=正面（绿）
        isUpGood = false;
      case PowerChartMetric.balance:
        metricLabel = '余额';
        currentValue = bucket.balanceYuan;
        valueText = '${currentValue.toStringAsFixed(2)} ${widget.unit}';
        // 余额上升=正面（绿），下降=负面（红）
        isUpGood = true;
      case PowerChartMetric.cost:
        metricLabel = '电费';
        currentValue = bucket.costYuan;
        valueText = '${currentValue.toStringAsFixed(2)} ${widget.unit}';
        // 电费上升=负面（红），下降=正面（绿）
        isUpGood = false;
    }
    // 取上一个数据点对比
    if (idx > 0) {
      final prev = widget.buckets[idx - 1];
      switch (widget.metric) {
        case PowerChartMetric.consumption:
          prevValue = prev.consumptionKwh;
        case PowerChartMetric.balance:
          prevValue = prev.balanceYuan;
        case PowerChartMetric.cost:
          prevValue = prev.costYuan;
      }
    }

    // 环比百分比
    String? changeText;
    Color? changeColor;
    if (prevValue != null && prevValue.abs() > 0.0001) {
      final change = currentValue - prevValue;
      final pct = (change / prevValue.abs()) * 100;
      if (pct.abs() < 0.01) {
        changeText = '持平';
        changeColor = theme.colorScheme.onSurface.withAlpha(140);
      } else {
        final arrow = pct > 0 ? '↑' : '↓';
        changeText = '$arrow ${pct.abs().toStringAsFixed(1)}%';
        // 上升且上升为好 → 绿；上升且上升为坏 → 红
        final isUp = pct > 0;
        final isGood = isUp == isUpGood;
        changeColor = isGood ? LightColors.green : LightColors.red;
      }
    } else if (prevValue != null && prevValue.abs() <= 0.0001) {
      changeText = '新增';
      changeColor = LightColors.blue;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: bucket.label,
        style: TextStyle(
          fontSize: m.fontSize11,
          color: theme.colorScheme.onSurface.withAlpha(160),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final labelW = tp.width;

    final tp2 = TextPainter(
      text: TextSpan(
        text: valueText,
        style: TextStyle(
          fontSize: m.fontSize13,
          fontWeight: FontWeight.w700,
          color: widget.color,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final valueW = tp2.width;

    // 加宽：取最大内容宽度，并设置最小宽度
    final innerW = math.max(math.max(labelW, valueW), 96.0);
    final tooltipW = innerW + m.kSpace20 + m.kSpace8;
    final tooltipH = changeText != null ? 72.0 : 60.0;

    // tooltip 定位：优先在数据点上方，越界时翻转/夹紧
    double left = p.dx - tooltipW / 2;
    if (left < 2) left = 2;
    if (left + tooltipW > size.width - 2) {
      left = size.width - tooltipW - 2;
    }
    double top = p.dy - tooltipH - 10;
    if (top < 2) top = p.dy + 10;

    return Positioned(
      left: left,
      top: top,
      width: tooltipW,
      child: IgnorePointer(
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
                color: Colors.black.withAlpha(60),
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
              Row(
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
                  Expanded(
                    child: Text(
                      valueText,
                      style: TextStyle(
                        fontSize: m.fontSize13,
                        fontWeight: FontWeight.w700,
                        color: widget.color,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (changeText != null && changeColor != null) ...[
                    SizedBox(width: m.kSpace8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace6,
                        vertical: m.kSpace2,
                      ),
                      decoration: BoxDecoration(
                        color: changeColor.withAlpha(20),
                        borderRadius: m.radius4,
                      ),
                      child: Text(
                        changeText,
                        style: TextStyle(
                          fontSize: m.fontSize10,
                          fontWeight: FontWeight.w700,
                          color: changeColor,
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
    );
  }
}

class _ChartCanvas extends CustomPainter {
  final List<PowerStatBucket> buckets;
  final PowerChartMetric metric;
  final Color color;
  final Color textColor;
  final Color gridColor;
  final int? hoverIndex;

  _ChartCanvas({
    required this.buckets,
    required this.metric,
    required this.color,
    required this.textColor,
    required this.gridColor,
    this.hoverIndex,
  });

  double _value(PowerStatBucket b) {
    switch (metric) {
      case PowerChartMetric.consumption:
        return b.consumptionKwh;
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
        _formatValue(v),
        Offset(2, y - 6),
        TextStyle(color: textColor.withAlpha(120), fontSize: 9),
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
        TextStyle(color: textColor.withAlpha(120), fontSize: 9),
      );
    }

    // 渐变填充区域
    if (points.length >= 2) {
      final fillPath = Path()
        ..moveTo(points.first.dx, padTop + chartH)
        ..addPolygon(points, false)
        ..lineTo(points.last.dx, padTop + chartH)
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
      ..color = Colors.white
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

  String _formatValue(double v) {
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
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
      old.hoverIndex != hoverIndex;
}
