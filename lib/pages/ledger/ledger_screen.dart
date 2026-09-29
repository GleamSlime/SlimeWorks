import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/pages/ledger/components/ledger_charts.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_viewmodel.dart';

/// 流水账首页：本月结余 + 日趋势 + 分类 top + 最近几笔。
///
/// 刻意不做成"一整页列表"：记账 App 的第一屏要回答"这个月花到哪了"，
/// 明细是第二跳的事（`/ledger/records`）。
class LedgerScreen extends BasePage<LedgerViewModel> {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends BasePageState<LedgerViewModel, LedgerScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerViewModel createViewModel() => LedgerViewModel();

  Future<void> _openEditor([LedgerTx? tx]) async {
    final edited = await showLedgerTxEditor(
      context,
      initial: tx,
      accounts: viewModel.accounts,
      categories: viewModel.categories,
    );
    if (edited == null || !mounted) return;
    var result = await viewModel.save(edited);
    if (result == LedgerSaveResult.duplicate && mounted) {
      final keep = await showConfirmDialog(
        context,
        title: '像是同一笔',
        message: '同一天、同账户上已经有一笔 ${formatLedgerAmount(edited.amount)} 的记录了，仍要记下来吗？',
        confirmLabel: '仍然记录',
      );
      if (!keep) return;
      result = await viewModel.save(edited, ignoreDuplicate: true);
    }
    if (result == LedgerSaveResult.saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记下一笔')),
      );
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '流水账',
        toolbar: const LedgerTabs(current: '/ledger'),
        toolbarHeight: m.kSpace44,
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => viewModel.reload(),
          ),
          SizedBox(width: m.kSpace8),
          if (ledgerNarrow(context))
            ToolIconButton(icon: StrokeIcons.add, tooltip: '记一笔', onPressed: _openEditor)
          else
            Padding(
              padding: EdgeInsets.only(right: m.kSpace12),
              child: FilledButton.icon(
                onPressed: _openEditor,
                icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
                label: const Text('记一笔'),
              ),
            ),
        ],
      ),
      child: Obx(() => _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    final summary = viewModel.summary.value;
    return LedgerStateView(
      error: viewModel.errorMessage,
      empty: viewModel.recent.isEmpty && summary.count == 0,
      emptyTitle: '这个月还没有账',
      emptyIcon: StrokeIcons.creditCard,
      emptyAction: FilledButton.icon(
        onPressed: _openEditor,
        icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
        label: const Text('记第一笔'),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
        children: <Widget>[
          LedgerMonthStrip(
            monthLabel: viewModel.monthLabel,
            canGoNext: viewModel.canGoNextMonth,
            onPrevious: () => viewModel.shiftMonth(-1),
            onNext: () => viewModel.shiftMonth(1),
            onPickMonth: _pickMonth,
          ),
          SizedBox(height: m.kSpace12),
          _OverviewCard(
            summary: summary,
            dayRows: viewModel.dayRows,
            topCategories: viewModel.topCategories,
          ),
          if (viewModel.pendingCount.value > 0) ...[
            SizedBox(height: m.kSpace12),
            _PendingBanner(
              count: viewModel.pendingCount.value,
              onTap: () => const LedgerPendingRoute().go(context),
            ),
          ],
          SizedBox(height: m.kSpace20),
          SectionHeader(
            title: '最近流水',
            trailing: TextButton(
              onPressed: () => const LedgerRecordsRoute().go(context),
              child: const Text('全部流水'),
            ),
          ),
          AppCard(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace6),
            child: Column(
              children: <Widget>[
                for (final tx in viewModel.recent)
                  LedgerTxTile(
                    tx: tx,
                    onTap: () => _openEditor(tx),
                    onLongPress: () => _confirmDelete(tx),
                  ),
              ],
            ),
          ),
        ],
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
    if (picked != null) await viewModel.goToMonth(ledgerMonthOf(picked));
  }

  Future<void> _confirmDelete(LedgerTx tx) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这笔？',
      message: '${tx.merchant.isEmpty ? tx.note : tx.merchant}  ¥${formatLedgerAmount(tx.amount)}',
      confirmLabel: '删除',
    );
    if (ok) await viewModel.deleteTx(tx.id);
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.summary,
    required this.dayRows,
    required this.topCategories,
  });

  final LedgerSummary summary;
  final List<LedgerDayRow> dayRows;
  final List<LedgerCategoryRow> topCategories;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context);
    final m = AppTheme.metrics;
    final groups = <LedgerBarGroup>[
      for (final row in dayRows)
        LedgerBarGroup(label: row.billDate.substring(8), income: row.income, expense: row.expense),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('本月结余', style: AppTextStyles.overline(context)),
                    SizedBox(height: m.kSpace4),
                    Text(
                      '¥${formatLedgerAmount(summary.net.abs())}',
                      style: AppTextStyles.metric(context).copyWith(
                        color: summary.net < 0 ? s.danger.color : viz.lagoon.base,
                      ),
                    ),
                    SizedBox(height: m.kSpace4),
                    Text(
                      summary.net < 0 ? '支出超过了收入' : '${summary.count} 笔流水',
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ),
              ),
              _MiniAmount(label: '收入', value: summary.monthIncome, income: true),
              SizedBox(width: m.kSpace16),
              _MiniAmount(label: '支出', value: summary.monthExpense, income: false),
            ],
          ),
          SizedBox(height: m.kSpace16),
          SizedBox(
            height: m.kSpace56,
            child: LedgerBarChart(groups: groups),
          ),
          SizedBox(height: m.kSpace6),
          Text('每日支出', style: AppTextStyles.caption(context)),
          if (topCategories.isNotEmpty) ...[
            SizedBox(height: m.kSpace16),
            const AppDivider(),
            SizedBox(height: m.kSpace12),
            for (final row in topCategories.take(5))
              Padding(
                padding: EdgeInsets.only(bottom: m.kSpace10),
                child: _CategoryShare(
                  row: row,
                  total: summary.monthExpense,
                  tint: viz.lagoon.base,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MiniAmount extends StatelessWidget {
  const _MiniAmount({required this.label, required this.value, required this.income});

  final String label;
  final double value;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(label, style: AppTextStyles.overline(context)),
        SizedBox(height: m.kSpace4),
        Text(
          '¥${formatLedgerAmount(value)}',
          style: AppTextStyles.cardTitle(context).copyWith(
            fontSize: m.fontSize16,
            color: income ? s.success.color : s.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 分类占比的一行：名字 + 金额 + 一条按比例充能的细条
class _CategoryShare extends StatelessWidget {
  const _CategoryShare({required this.row, required this.total, required this.tint});

  final LedgerCategoryRow row;
  final double total;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final share = total <= 0 ? 0.0 : (row.total / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                row.categoryName.isEmpty ? '未分类' : row.categoryName,
                style: AppTextStyles.rowTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${(share * 100).toStringAsFixed(0)}%',
              style: AppTextStyles.caption(context).copyWith(color: tint),
            ),
            SizedBox(width: m.kSpace8),
            Text('¥${formatLedgerAmount(row.total)}', style: AppTextStyles.body(context)),
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
                widthFactor: share,
                child: Container(
                  height: m.kSpace4,
                  decoration: BoxDecoration(color: tint, borderRadius: m.radiusPill),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return AppCard(
      onTap: onTap,
      borderColor: s.warning.containerBorder,
      color: s.warning.container,
      padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
      child: Row(
        children: <Widget>[
          DrawIcon(StrokeIcons.mail, size: m.iconSize18, color: s.warning.color),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Text(
              '有 $count 笔邮件账单等你确认',
              style: AppTextStyles.body(context).copyWith(color: s.warning.onContainer),
            ),
          ),
          DrawIcon(StrokeIcons.chevronRight, size: m.iconSize16, color: s.warning.color),
        ],
      ),
    );
  }
}
