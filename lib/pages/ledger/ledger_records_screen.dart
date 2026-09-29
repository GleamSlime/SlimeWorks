import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_records_viewmodel.dart';

/// 全部流水：搜索 + 四组筛选 + 按天分组 + 触底续读。
///
/// 筛选只改 ViewModel 里的一个 [LedgerFilter]，界面不自己缓存结果——
/// 条件一变就重查第一页，列表回到顶部由 ListView 的自然行为承担。
class LedgerRecordsScreen extends BasePage<LedgerRecordsViewModel> {
  const LedgerRecordsScreen({super.key});

  @override
  State<LedgerRecordsScreen> createState() => _LedgerRecordsScreenState();
}

class _LedgerRecordsScreenState extends BasePageState<LedgerRecordsViewModel, LedgerRecordsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  @override
  bool get showAppBar => false;

  @override
  LedgerRecordsViewModel createViewModel() => LedgerRecordsViewModel();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// 触底前 600 逻辑像素就开始下一页，滚到底才取会看到空白等一下
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      viewModel.loadMore();
    }
  }

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
        message: '同样的金额和日期已经记过一次了，仍要记下来吗？',
        confirmLabel: '仍然记录',
      );
      if (keep) await viewModel.save(edited, ignoreDuplicate: true);
    }
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

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '全部流水',
        // 筛选条不进工具槽：桌面端那一格是无宽度的横向滚动区，Expanded 在这种
        // 约束下直接断言失败；它本来也该贴着列表，而不是贴着窗口标题。
        toolbar: const LedgerTabs(current: '/ledger/records'),
        toolbarHeight: m.kSpace44,
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => viewModel.reload(),
          ),
          SizedBox(width: m.kSpace8),
          Padding(
            padding: EdgeInsets.only(right: m.kSpace12),
            child: ToolIconButton(icon: StrokeIcons.add, tooltip: '记一笔', onPressed: _openEditor),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          _FilterBar(
            vm: viewModel,
            search: _search,
            onSearch: (value) => viewModel.setKeyword(value),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: viewModel.reload,
              child: Obx(() => _buildList(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final groups = viewModel.groups;
    return LedgerStateView(
      error: viewModel.errorMessage,
      empty: groups.isEmpty,
      emptyTitle: viewModel.isFiltered ? '没有符合条件的流水' : '还没有流水',
      emptyIcon: StrokeIcons.list,
      onRetry: viewModel.reload,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
        itemCount: groups.length + 1,
        itemBuilder: (context, index) {
          if (index == groups.length) {
            return Padding(
              padding: EdgeInsets.only(top: m.kSpace12),
              child: Center(
                child: viewModel.hasMore
                    ? AppLoading(
                        message: viewModel.loadingMore.value ? '继续读取…' : '上拉加载更多',
                        size: m.iconSize18,
                      )
                    : Text(
                        '共 ${viewModel.totalCount.value} 笔',
                        style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
                      ),
              ),
            );
          }
          final day = groups[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LedgerDayHeader(
                date: day.date,
                income: day.income,
                expense: day.expense,
                count: day.txs.length,
              ),
              AppCard(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace6),
                child: Column(
                  children: <Widget>[
                    for (final tx in day.txs)
                      LedgerTxTile(
                        tx: tx,
                        onTap: () => _openEditor(tx),
                        onLongPress: () => _confirmDelete(tx),
                      ),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace12),
            ],
          );
        },
      ),
    );
  }
}

/// 一行筛选器：时间 / 方向 / 账户 / 类别 + 搜索框
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.vm, required this.search, required this.onSearch});

  final LedgerRecordsViewModel vm;
  final TextEditingController search;
  final ValueChanged<String> onSearch;

  // 读值必须发生在 Obx 自己的 builder 里：父层包 Obx 只构造本组件不算订阅，
  // GetX 会直接报 improper use，整条工具栏被 ErrorWidget 顶掉。
  @override
  Widget build(BuildContext context) => Obx(() => _content(context, vm.filter.value));

  Widget _content(BuildContext context, LedgerFilter filter) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final narrow = ledgerNarrow(context);
    final pills = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _FilterPill(
            label: vm.filterLabel,
            icon: StrokeIcons.calendarMonth,
            active: filter.startDate.isNotEmpty || filter.endDate.isNotEmpty,
            items: <PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'month:this', child: Text('本月')),
              const PopupMenuItem(value: 'month:last', child: Text('上月')),
              const PopupMenuItem(value: 'month:quarter', child: Text('近三个月')),
              const PopupMenuItem(value: 'month:all', child: Text('全部时间')),
            ],
            onSelected: (value) => _pickRange(value),
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: switch (filter.direction) {
              'expense' => '只看支出',
              'income' => '只看收入',
              _ => '收支',
            },
            icon: StrokeIcons.exchange,
            active: filter.direction.isNotEmpty,
            items: const <PopupMenuEntry<String>>[
              PopupMenuItem(value: '', child: Text('收支都要')),
              PopupMenuItem(value: 'expense', child: Text('只看支出')),
              PopupMenuItem(value: 'income', child: Text('只看收入')),
            ],
            onSelected: vm.setDirection,
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: filter.accountId > 0
                ? _nameOfAccount(context, filter.accountId)
                : '账户',
            icon: StrokeIcons.accountBalanceWallet,
            active: filter.accountId > 0,
            items: <PopupMenuEntry<String>>[
              const PopupMenuItem(value: '0', child: Text('全部账户')),
              for (final a in vm.accounts)
                PopupMenuItem(value: '${a.id}', child: Text(a.name)),
            ],
            onSelected: (value) => vm.setAccount(int.tryParse(value) ?? 0),
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: filter.categoryId > 0
                ? _nameOfCategory(context, filter.categoryId)
                : '类别',
            icon: StrokeIcons.category,
            active: filter.categoryId > 0,
            items: <PopupMenuEntry<String>>[
              const PopupMenuItem(value: '0', child: Text('全部类别')),
              for (final c in vm.categories)
                PopupMenuItem(value: '${c.id}', child: Text(c.name)),
            ],
            onSelected: (value) => vm.setCategory(int.tryParse(value) ?? 0),
          ),
          if (vm.isFiltered) ...<Widget>[
            SizedBox(width: m.kSpace6),
            TextButton.icon(
              onPressed: () {
                search.clear();
                vm.clearFilters();
              },
              icon: DrawIcon(StrokeIcons.close, size: m.iconSize14, color: s.textTertiary),
              label: Text('清空', style: AppTextStyles.caption(context)),
            ),
          ],
        ],
      ),
    );
    final searchField = TextField(
      controller: search,
      onSubmitted: onSearch,
      style: AppTextStyles.body(context),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜商户/备注',
        prefixIcon: DrawIcon(StrokeIcons.search, size: m.iconSize16, color: s.textTertiary),
        prefixIconConstraints: BoxConstraints(minWidth: m.kSpace32),
        contentPadding: EdgeInsets.zero,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace4),
      // 窄屏搜索框单独占一行：挤在胶囊旁边只剩 80 宽，输入什么都看不见
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                pills,
                SizedBox(height: m.kSpace6),
                searchField,
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: pills),
                SizedBox(width: m.kSpace8),
                SizedBox(width: scaleW(200), child: searchField),
              ],
            ),
    );
  }

  String _nameOfAccount(BuildContext context, int id) {
    for (final a in vm.accounts) {
      if (a.id == id) return a.name;
    }
    return '账户';
  }

  String _nameOfCategory(BuildContext context, int id) {
    for (final c in vm.categories) {
      if (c.id == id) return c.name;
    }
    return '类别';
  }

  void _pickRange(String value) {
    final now = DateTime.now();
    switch (value) {
      case 'month:this':
        vm.setMonth(ledgerMonthOf(now));
      case 'month:last':
        vm.setMonth(ledgerMonthShift(ledgerMonthOf(now), -1));
      case 'month:quarter':
        vm.applyFilter(
          vm.filter.value.copyWith(
            startDate: ledgerMonthStart(ledgerMonthShift(ledgerMonthOf(now), -2)),
            endDate: ledgerMonthEnd(ledgerMonthOf(now)),
          ),
        );
      default:
        vm.applyFilter(vm.filter.value.copyWith(startDate: '', endDate: ''));
    }
  }
}

/// 一个筛选胶囊：点开是菜单，选中态靠描边和底色区分
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final StrokeIcon icon;
  final bool active;
  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return PopupMenuButton<String>(
      tooltip: label,
      color: s.surfaceRaised,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        height: m.kSpace32,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
        decoration: BoxDecoration(
          color: active ? s.accentContainer : s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(color: active ? s.accentContainerBorder : s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(icon, size: m.iconSize14, color: active ? s.accentText : s.textSecondary),
            SizedBox(width: m.kSpace4),
            Text(
              label,
              style: AppTextStyles.caption(context).copyWith(
                color: active ? s.accentText : s.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
