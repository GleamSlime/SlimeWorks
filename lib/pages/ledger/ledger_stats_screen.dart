import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/pages/ledger/components/ledger_charts.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_stats_viewmodel.dart';

/// 统计页：类别占比环图 + 月度双柱趋势 + 商户排行。
///
/// 收支两个方向分开看：把 12 个月的收入和一个月的支出塞进同一张饼，
/// 得出的百分比没有任何意义，所以方向游标放在最上面，占比卡跟着它走。
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
        toolbar: const LedgerTabs(current: '/ledger/stats'),
        toolbarHeight: m.kSpace44,
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

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final parts = viewModel.month.value.split('-');
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(int.parse(parts.first), int.parse(parts.last), 1),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) viewModel.goToMonth(ledgerMonthOf(picked));
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    final categories = viewModel.categoryRows;
    final trend = viewModel.monthRows;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: LedgerMonthStrip(
                monthLabel: viewModel.monthLabel,
                canGoNext: viewModel.canGoNextMonth,
                onPrevious: () => viewModel.shiftMonth(-1),
                onNext: () => viewModel.shiftMonth(1),
                onPickMonth: _pickMonth,
              ),
            ),
            _DirectionSwitch(
              expense: viewModel.isExpense,
              onChanged: viewModel.setDirection,
            ),
          ],
        ),
        SizedBox(height: m.kSpace12),
        LedgerStateView(
          error: viewModel.errorMessage,
          empty: categories.isEmpty && trend.isEmpty,
          emptyTitle: '还没有可统计的流水',
          emptyIcon: StrokeIcons.chartPie,
          onRetry: viewModel.reload,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CategoryCard(
                rows: categories,
                total: viewModel.categoryTotal,
                selectedId: viewModel.selectedCategory.value,
                onSelect: viewModel.toggleCategory,
                directionLabel: viewModel.directionLabel,
                monthLabel: viewModel.monthLabel,
                wide: !ledgerNarrow(context),
              ),
              SizedBox(height: m.kSpace16),
              _TrendCard(
                rows: trend,
                months: viewModel.trendMonths.value,
                onSelect: viewModel.setTrendMonths,
              ),
              if (viewModel.merchantRows.isNotEmpty) ...[
                SizedBox(height: m.kSpace16),
                _MerchantCard(rows: viewModel.merchantRows),
              ],
            ],
          ),
        ),
      ],
    );
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

/// 类别占比：环图 + 图例。点扇区或图例都会把其余部分压暗。
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.onSelect,
    required this.directionLabel,
    required this.monthLabel,
    required this.wide,
  });

  final List<LedgerCategoryRow> rows;
  final double total;
  final int selectedId;
  final ValueChanged<int> onSelect;
  final String directionLabel;
  final String monthLabel;

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
          Text('$monthLabel$directionLabel构成', style: AppTextStyles.sectionTitle(context)),
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

/// 月度趋势：双柱 + 跨度切换。最后一组高亮，它代表"本月"。
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.rows, required this.months, required this.onSelect});

  final List<LedgerMonthRow> rows;
  final int months;
  final ValueChanged<int> onSelect;

  static const List<int> _spans = <int>[6, 12, 24];

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    // 接口只回有账的月份，中间空掉的月份按月份序列补成空格子
    final keys = rows.map((row) => row.month).toList()..sort();
    final byMonth = <String, LedgerMonthRow>{for (final row in rows) row.month: row};
    final series = <LedgerMonthRow>[
      for (final key in ledgerMonthSpan(keys.isEmpty ? '' : keys.first, keys.isEmpty ? '' : keys.last))
        byMonth[key] ?? LedgerMonthRow(month: key),
    ];
    final groups = <LedgerBarGroup>[
      for (final row in series)
        LedgerBarGroup(label: row.shortLabel, income: row.income, expense: row.expense),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('月度趋势', style: AppTextStyles.sectionTitle(context))),
              for (final span in _spans)
                Padding(
                  padding: EdgeInsets.only(left: m.kSpace6),
                  child: TagChip(
                    label: '近$span月',
                    selected: months == span,
                    onTap: () => onSelect(span),
                  ),
                ),
            ],
          ),
          SizedBox(height: m.kSpace16),
          LedgerBarChart(groups: groups, highlightIndex: series.isEmpty ? null : series.length - 1),
          SizedBox(height: m.kSpace8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(series.isEmpty ? '' : series.first.month, style: AppTextStyles.caption(context)),
              const _BarLegend(),
              Text(series.isEmpty ? '' : series.last.month, style: AppTextStyles.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 双柱图的图例：颜色与柱子的出处一致（支出用流水账身份色，收入用成功色）
class _BarLegend extends StatelessWidget {
  const _BarLegend();

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context);
    final m = AppTheme.metrics;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LegendItem(label: '支出', color: viz.lagoon.base),
        SizedBox(width: m.kSpace12),
        _LegendItem(label: '收入', color: s.success.color),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: m.kSpace8,
          height: m.kSpace8,
          decoration: BoxDecoration(color: color, borderRadius: m.radius2),
        ),
        SizedBox(width: m.kSpace4),
        Text(label, style: AppTextStyles.caption(context)),
      ],
    );
  }
}

/// 商户排行：钱花在了谁身上。条长按第一名归一化，绝对值仍在右侧给出。
class _MerchantCard extends StatelessWidget {
  const _MerchantCard({required this.rows});

  final List<LedgerMerchantRow> rows;

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
          Text('商户排行', style: AppTextStyles.sectionTitle(context)),
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
