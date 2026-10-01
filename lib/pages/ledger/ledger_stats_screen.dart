import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/pages/ledger/components/ledger_charts.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_stats_viewmodel.dart';

/// 统计页：区间预设 + 聚合轴趋势三线 + 类别占比环 + 商户排行 + 净资产曲线。
///
/// 区间和聚合轴是这一页的两个自由度，其余卡片都跟着区间走；方向游标只影响
/// 占比与趋势，不影响净资产——钱进口袋这件事本来就不分收支。
class LedgerStatsScreen extends BasePage<LedgerStatsViewModel> {
  const LedgerStatsScreen({super.key});

  @override
  State<LedgerStatsScreen> createState() => _LedgerStatsScreenState();
}

class _LedgerStatsScreenState
    extends BasePageState<LedgerStatsViewModel, LedgerStatsScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerStatsViewModel createViewModel() => LedgerStatsViewModel();

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '记账统计',
        toolbar: ledgerBottomNavMode(context)
            ? null
            : const LedgerTabs(current: '/ledger/stats'),
        toolbarHeight: m.kSpace44,
        bottomBar: LedgerBottomNav(current: '/ledger/stats', onAdd: () => ledgerQuickAdd(context)),
        bottomBarHeight: m.kSpace56,
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => viewModel.reload(),
          ),
          SizedBox(width: m.kSpace12),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: viewModel.reload,
        child: Obx(() => _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        _RangeBar(vm: viewModel),
        SizedBox(height: m.kSpace12),
        LedgerStateView(
          error: viewModel.errorMessage,
          // 只看这一区间的笔数：轴上的格子是按日期铺满的，一根流水没有也照样有
          // 31 格，用 axisRows 判空等于永远不空
          empty: viewModel.summary.value.count == 0,
          emptyTitle: '这段时间还没有流水',
          emptyIcon: StrokeIcons.chartPie,
          onRetry: viewModel.reload,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SummaryCard(vm: viewModel),
              SizedBox(height: m.kSpace16),
              _TrendCard(vm: viewModel),
              SizedBox(height: m.kSpace16),
              _CategoryCard(
                rows: viewModel.categoryRows,
                total: viewModel.categoryTotal,
                selectedId: viewModel.selectedCategory.value,
                onSelect: viewModel.toggleCategory,
                directionLabel: viewModel.directionLabel,
                rangeLabel: viewModel.rangeLabel,
                wide: !ledgerNarrow(context),
              ),
              if (viewModel.merchantRows.isNotEmpty) ...<Widget>[
                SizedBox(height: m.kSpace16),
                _MerchantCard(rows: viewModel.merchantRows, directionLabel: viewModel.directionLabel),
              ],
              SizedBox(height: m.kSpace16),
              _AssetCard(vm: viewModel),
            ],
          ),
        ),
      ],
    );
  }
}

/// 区间预设 + 方向游标。
///
/// 预设做成明面上的胶囊而不是菜单：这一页所有卡片都被它牵着，藏起来等于让用户
/// 以为自己看的是"全部"。
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.vm});

  final LedgerStatsViewModel vm;

  static const List<LedgerRangePreset> _presets = <LedgerRangePreset>[
    LedgerRangePreset.last30,
    LedgerRangePreset.thisMonth,
    LedgerRangePreset.lastMonth,
    LedgerRangePreset.thisQuarter,
    LedgerRangePreset.thisYear,
    LedgerRangePreset.all,
    LedgerRangePreset.custom,
  ];

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final preset in _presets) ...<Widget>[
                      TagChip(
                        label: kLedgerRangeLabels[preset] ?? preset.name,
                        selected: vm.preset.value == preset,
                        onTap: () => _pick(context, preset),
                      ),
                      SizedBox(width: m.kSpace6),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(width: m.kSpace8),
            _DirectionSwitch(
              expense: vm.isExpense,
              onChanged: vm.setDirection,
            ),
          ],
        ),
        SizedBox(height: m.kSpace6),
        Text(vm.rangeLabel, style: AppTextStyles.caption(context)),
      ],
    );
  }

  Future<void> _pick(BuildContext context, LedgerRangePreset preset) async {
    if (preset != LedgerRangePreset.custom) {
      await vm.setPreset(preset);
      return;
    }
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (start == null || !context.mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: start,
      lastDate: now,
    );
    if (end != null) await vm.setCustomRange(start, end);
  }
}

/// 支/收两档：做成胶囊而不是开关，因为这是"看哪一面"的选择
class _DirectionSwitch extends StatelessWidget {
  const _DirectionSwitch({required this.expense, required this.onChanged});

  final bool expense;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      children: <Widget>[
        TagChip(
          label: '支出',
          selected: expense,
          onTap: () => onChanged(kLedgerDirectionExpense),
        ),
        SizedBox(width: m.kSpace6),
        TagChip(
          label: '收入',
          selected: !expense,
          onTap: () => onChanged(kLedgerDirectionIncome),
        ),
      ],
    );
  }
}

/// 区间汇总：三个数字 + 笔数，先给结论再给图
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.vm});

  final LedgerStatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = vm.summary.value;
    final viz = AppVizSet.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 区间那句话区间条下面已经写着，这里再抄一行就成了满屏的 "3.1 - 3.31"
          _StatTrio(
            cells: <_StatItem>[
              _StatItem(
                label: '收入',
                amount: s.income,
                tone: AppSemantic.of(context).success.color,
              ),
              _StatItem(label: '支出', amount: s.expense),
              _StatItem(label: '结余', amount: s.net, tone: s.net < 0 ? viz.coral.base : null),
            ],
          ),
          SizedBox(height: m.kSpace8),
          Text('${s.count} 笔', style: AppTextStyles.caption(context)),
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem({required this.label, required this.amount, this.tone});

  final String label;
  final double amount;
  final Color? tone;
}

/// 一组并列的数字：宽处横着排，窄处叠成"标签……金额"三行。
///
/// 手机上一格只有 100 来逻辑像素，"¥12,320.00" 会被省略号截成 "¥12,3…"，
/// 而这几格要回答的恰恰是精确到分的数，缩不得。
class _StatTrio extends StatelessWidget {
  const _StatTrio({required this.cells});

  final List<_StatItem> cells;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth / cells.length >= scaleW(132)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final cell in cells)
                Expanded(
                  child: _StatCell(
                    label: cell.label,
                    amount: cell.amount,
                    tone: cell.tone,
                  ),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final cell in cells)
              Padding(
                padding: EdgeInsets.only(bottom: m.kSpace8),
                child: _StatCell(
                  label: cell.label,
                  amount: cell.amount,
                  tone: cell.tone,
                  inline: true,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.amount,
    this.tone,
    this.inline = false,
  });

  final String label;
  final double amount;
  final Color? tone;

  /// 窄屏档：标签和金额同一行，金额独占整行宽度才不会被截断
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final value = Text(
      '¥${formatLedgerAmount(amount)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.metric(context).copyWith(color: tone ?? s.textPrimary),
    );
    if (inline) {
      return Row(
        children: <Widget>[
          Text(label, style: AppTextStyles.caption(context)),
          SizedBox(width: m.kSpace8),
          Expanded(child: value),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppTextStyles.caption(context)),
        SizedBox(height: m.kSpace4),
        value,
      ],
    );
  }
}

/// 趋势三线：收入 / 支出 / 结余。
///
/// 结余单独一条而不是"看两根柱子的高低差"：眼睛比不了两根柱子之间那点距离，
/// 却一眼看得出第三条线有没有掉到 0 轴下面。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.vm});

  final LedgerStatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final viz = AppVizSet.of(context);
    final rows = vm.axisRows;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('收支趋势', style: AppTextStyles.sectionTitle(context))),
              _AxisPicker(axis: vm.axis.value, onChanged: vm.setAxis),
            ],
          ),
          SizedBox(height: m.kSpace4),
          Text(vm.rangeLabel, style: AppTextStyles.caption(context)),
          SizedBox(height: m.kSpace12),
          LedgerLineChart(
            labels: vm.axisLabels,
            series: <LedgerLineSeries>[
              LedgerLineSeries(
                label: '收入',
                color: s.success.color,
                values: vm.axisIncome,
              ),
              LedgerLineSeries(
                label: '支出',
                color: viz.lagoon.base,
                values: vm.axisExpense,
              ),
              LedgerLineSeries(
                label: '结余',
                color: viz.amber.base,
                values: vm.axisNet,
              ),
            ],
          ),
          SizedBox(height: m.kSpace8),
          _LineLegend(
            items: <(String, Color)>[
              ('收入', s.success.color),
              ('支出', viz.lagoon.base),
              ('结余', viz.amber.base),
            ],
          ),
          if (rows.isNotEmpty) ...<Widget>[
            SizedBox(height: m.kSpace6),
            Text(
              _busiest(context),
              style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  /// 最忙那一格的说法：按日时横轴刻度只剩一个"28"，句子得说全"3月28日"
  String _busiest(BuildContext context) {
    final top = vm.busiestBucket;
    if (top == null) return '';
    final value = vm.isExpense ? top.expense : top.income;
    if (value <= 0) return '这段时间没有$directionWord';
    final label = vm.axis.value == LedgerAxis.day ? ledgerDateLabel(top.date) : top.label;
    return '最忙的是$label：$directionWord ¥${formatLedgerAmount(value)}';
  }

  String get directionWord => vm.isExpense ? '支出' : '收入';
}

/// 聚合轴：五档全给。区间和轴不匹配时（比如"全部"按日）图会糊，但用户有权糊着看
class _AxisPicker extends StatelessWidget {
  const _AxisPicker({required this.axis, required this.onChanged});

  final LedgerAxis axis;
  final ValueChanged<LedgerAxis> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return PopupMenuButton<LedgerAxis>(
      tooltip: '聚合轴',
      color: s.surfaceRaised,
      initialValue: axis,
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<LedgerAxis>>[
        for (final entry in kLedgerAxisLabels.entries)
          PopupMenuItem<LedgerAxis>(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        height: m.kSpace24,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
        decoration: BoxDecoration(
          color: s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(color: s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(kLedgerAxisLabels[axis] ?? '', style: AppTextStyles.caption(context)),
            SizedBox(width: m.kSpace4),
            DrawIcon(StrokeIcons.expandMore, size: m.iconSize12, color: s.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 折线图图例：线色取自各自画刷的同一处出处
class _LineLegend extends StatelessWidget {
  const _LineLegend({required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Wrap(
      spacing: m.kSpace12,
      runSpacing: m.kSpace4,
      children: <Widget>[
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: m.kSpace14,
                height: m.kSpace2,
                decoration: BoxDecoration(color: item.$2, borderRadius: m.radius2),
              ),
              SizedBox(width: m.kSpace6),
              Text(item.$1, style: AppTextStyles.caption(context)),
            ],
          ),
      ],
    );
  }
}

/// 类别占比：环图 + 图例。点扇区或图例都会把其余部分压暗。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.onSelect,
    required this.directionLabel,
    required this.rangeLabel,
    required this.wide,
  });

  final List<LedgerCategoryRow> rows;
  final double total;
  final int selectedId;
  final ValueChanged<int> onSelect;
  final String directionLabel;
  final String rangeLabel;

  /// 宽屏图例与环左右并排，窄屏改成上下叠
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    // 顺序与色板必须和环图内部同源，否则图例色块对不上扇区
    final ordered = ledgerDonutOrder(rows);
    final palette = ledgerVizPalette(context);
    final donut = LedgerDonutChart(
      rows: ordered.where((r) => r.total > 0).toList(growable: false),
      total: total,
      selectedId: selectedId == 0 ? null : selectedId,
      onSelect: onSelect,
    );

    final legend = <Widget>[
      for (var i = 0; i < ordered.length; i++)
        _LegendRow(
          row: ordered[i],
          tint: palette[i % palette.length],
          share: total <= 0 ? 0 : ordered[i].total / total,
          dimmed: selectedId != 0 && selectedId != ordered[i].categoryId,
          onTap: () => onSelect(ordered[i].categoryId),
        ),
      if (selectedId != 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onSelect(selectedId),
            child: const Text('看全部类别'),
          ),
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('$rangeLabel$directionLabel构成', style: AppTextStyles.sectionTitle(context)),
          SizedBox(height: m.kSpace16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                donut,
                SizedBox(width: m.kSpace24),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      // 图例拉到整张卡那么宽，名字和金额之间就只剩一段没人看的空白
                      constraints: BoxConstraints(maxWidth: scaleW(480)),
                      child: Column(children: legend),
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(child: donut),
                SizedBox(height: m.kSpace16),
                ...legend,
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.row,
    required this.tint,
    required this.share,
    required this.dimmed,
    required this.onTap,
  });

  final LedgerCategoryRow row;
  final Color tint;
  final double share;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: m.radius8,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: m.kSpace6),
          child: Row(
            children: <Widget>[
              Container(
                width: m.kSpace8,
                height: m.kSpace8,
                decoration: BoxDecoration(color: tint, borderRadius: m.radius4),
              ),
              SizedBox(width: m.kSpace10),
              Expanded(
                child: Text(
                  row.categoryName.isEmpty ? '未分类' : row.categoryName,
                  style: AppTextStyles.rowTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${row.count} 笔', style: AppTextStyles.caption(context)),
              SizedBox(width: m.kSpace10),
              SizedBox(
                width: scaleW(44),
                child: Text(
                  '${(share * 100).toStringAsFixed(0)}%',
                  style: AppTextStyles.caption(context).copyWith(color: tint),
                  textAlign: TextAlign.end,
                ),
              ),
              SizedBox(width: m.kSpace10),
              Text(
                '¥${formatLedgerAmount(row.total)}',
                style: AppTextStyles.cardTitle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 商户排行：钱花在了谁身上。条长按第一名归一化，绝对值仍在右侧给出。
class _MerchantCard extends StatelessWidget {
  const _MerchantCard({required this.rows, required this.directionLabel});

  final List<LedgerMerchantRow> rows;
  final String directionLabel;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final palette = ledgerVizPalette(context);
    final max = rows.first.total <= 0 ? 1.0 : rows.first.total;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('商户排行$directionLabel', style: AppTextStyles.sectionTitle(context)),
          SizedBox(height: m.kSpace12),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: m.kSpace12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: m.kSpace20,
                        child: Text('${i + 1}', style: AppTextStyles.caption(context)),
                      ),
                      Expanded(
                        child: Text(
                          rows[i].merchant.isEmpty ? '未填商户' : rows[i].merchant,
                          style: AppTextStyles.rowTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${rows[i].count} 次', style: AppTextStyles.caption(context)),
                      SizedBox(width: m.kSpace10),
                      Text(
                        '¥${formatLedgerAmount(rows[i].total)}',
                        style: AppTextStyles.body(context).copyWith(color: s.textPrimary),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace6),
                  LayoutBuilder(
                    builder: (context, box) => Stack(
                      children: <Widget>[
                        Container(
                          height: m.kSpace4,
                          decoration: BoxDecoration(
                            color: s.surfaceHover,
                            borderRadius: m.radiusPill,
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: (rows[i].total / max).clamp(0.0, 1.0),
                          child: Container(
                            height: m.kSpace4,
                            decoration: BoxDecoration(
                              color: palette[i % palette.length],
                              borderRadius: m.radiusPill,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 净资产曲线：当前余额往回倒推，每个月末一个点。
///
/// 上面那三个数是实时算出来的真数（各账户余额相加），下面这条线才是回推的，
/// 所以卡片里必须写明它不算什么：转账、余额调整、外币换算都不在里面。
class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.vm});

  final LedgerStatsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final viz = AppVizSet.of(context);
    final points = vm.assetPoints;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('净资产', style: AppTextStyles.sectionTitle(context)),
          SizedBox(height: m.kSpace12),
          _StatTrio(
            cells: <_StatItem>[
              _StatItem(label: '资产', amount: vm.assetNow),
              _StatItem(label: '负债', amount: vm.liabilityNow),
              _StatItem(
                label: '净资产',
                amount: vm.netWorthNow,
                tone: vm.netWorthNow < 0 ? viz.coral.base : s.success.color,
              ),
            ],
          ),
          SizedBox(height: m.kSpace16),
          LedgerLineChart(
            // 窗口只有 12 个月，月份名撞不了车，刻度就不用补年份
            labels: <String>[for (final point in points) ledgerMonthTick(point.date)],
            series: <LedgerLineSeries>[
              LedgerLineSeries(
                label: '净资产',
                color: viz.lagoon.base,
                values: <double>[for (final point in points) point.netWorth],
              ),
            ],
            emptyText: '还没有可回推的月份',
          ),
          SizedBox(height: m.kSpace8),
          Text(
            vm.assetLabel.isEmpty
                ? '曲线按"当前余额 − 之后各月净收支"回推，转账与余额调整不在其中'
                : '曲线按"当前余额 − 之后各月净收支"回推；${vm.assetLabel}',
            style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }
}
