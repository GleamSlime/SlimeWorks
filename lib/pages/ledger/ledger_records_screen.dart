import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_records_viewmodel.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 全部流水：多维筛选 + 月/日两级分组 + 列表与日历双页型 + 触底续读。
///
/// 筛选条件全部落在 ViewModel 的一个 [LedgerFilter] 上，界面不自己缓存结果——
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

  /// 行上的三个动作。长按出菜单而不是滑动：滑动手势要和竖向滚动、下拉刷新
  /// 抢同一块区域，做不好就是"想滚动结果删了一笔"，代价比省一次点击大。
  Future<void> _rowActions(LedgerTx tx) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppSemantic.of(context).surfaceRaised,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in <(String, StrokeIcon, String)>[
              ('copy', StrokeIcons.copy, '再记一笔同样的'),
              ('edit', StrokeIcons.edit, '编辑'),
              ('delete', StrokeIcons.delete, '删除'),
            ])
              ListTile(
                leading: DrawIcon(entry.$2, size: AppTheme.metrics.iconSize18),
                title: Text(entry.$3),
                onTap: () => Navigator.of(ctx).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await _openEditor(tx.asDraft);
      case 'edit':
        await _openEditor(tx);
      case 'delete':
        await _confirmDelete(tx);
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
        toolbar: ledgerBottomNavMode(context)
            ? null
            : const LedgerTabs(current: '/ledger/records'),
        toolbarHeight: m.kSpace44,
        bottomBar: LedgerBottomNav(current: '/ledger/records', onAdd: _openEditor),
        bottomBarHeight: m.kSpace56,
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
            onSearch: viewModel.setKeyword,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: viewModel.reload,
              child: Obx(() => viewModel.calendarMode.value
                  ? _buildCalendar(context)
                  : _buildList(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final m = AppTheme.metrics;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(m.kSpace12, m.kSpace8, m.kSpace12, m.kSpace32),
      child: ConstrainedBox(
        // 宽屏不铺满：日历拉成 1400 宽的一格一天就没法看了
        constraints: const BoxConstraints(maxWidth: 560),
        child: Center(
          child: LedgerCalendarMonth(
            month: viewModel.calendarMonth.value,
            rows: List<LedgerDayRow>.of(viewModel.dayRows),
            focused: viewModel.dayFocus.value,
            onPickDay: viewModel.focusDay,
            onShiftMonth: viewModel.shiftCalendarMonth,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final m = AppTheme.metrics;
    final months = viewModel.monthGroups;
    return LedgerStateView(
      error: viewModel.errorMessage,
      empty: months.isEmpty,
      emptyTitle: viewModel.isFiltered ? '没有符合条件的流水' : '还没有流水',
      emptyIcon: StrokeIcons.list,
      onRetry: viewModel.reload,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
        // 尾部一格：续读提示 + 只在本地筛时的说明
        itemCount: months.length + 1,
        itemBuilder: (context, index) {
          if (index == months.length) return _Tail(vm: viewModel);
          final month = months[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 单月区间不用重复报月份，日组头已经够密了
              if (months.length > 1)
                LedgerMonthHeader(
                  title: month.title,
                  income: month.income,
                  expense: month.expense,
                  count: month.count,
                ),
              for (final day in month.days) ...<Widget>[
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
                          onLongPress: () => _rowActions(tx),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: m.kSpace12),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 列表尾巴：还有多少笔、以及"这几项是本地筛的"那句实话
class _Tail extends StatelessWidget {
  const _Tail({required this.vm});

  final LedgerRecordsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace12),
      child: Column(
        children: <Widget>[
          if (vm.hasClientFilters)
            Text(
              '类型/标签/金额这几项后端还没建列，是在已读到的 ${vm.items.length} 笔里筛的',
              style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
              textAlign: TextAlign.center,
            ),
          SizedBox(height: m.kSpace6),
          if (vm.hasMore)
            AppLoading(
              message: vm.loadingMore.value ? '继续读取…' : '上拉加载更多',
              size: m.iconSize18,
            )
          else
            Text(
              '共 ${vm.totalCount.value} 笔',
              style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
            ),
        ],
      ),
    );
  }
}

/// 一行筛选器：区间 / 收支 / 类型 / 账户 / 类别 / 标签 / 金额 + 页型 + 搜索
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.vm, required this.search, required this.onSearch});

  final LedgerRecordsViewModel vm;
  final TextEditingController search;
  final Future<void> Function(String) onSearch;

  // 读值必须发生在 Obx 自己的 builder 里：父层包 Obx 只构造本组件不算订阅，
  // GetX 会直接报 improper use，整条工具栏被 ErrorWidget 顶掉。
  @override
  Widget build(BuildContext context) => Obx(() => _content(context, vm.filter.value));

  Widget _content(BuildContext context, LedgerFilter filter) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final narrow = ledgerNarrow(context);
    final tags = filter.tagIds;
    final pills = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _FilterPill(
            label: _rangeLabel(),
            icon: StrokeIcons.calendarMonth,
            active: !vm.period.value.isAll,
            items: <PopupMenuEntry<String>>[
              for (final p in LedgerRangePreset.values)
                PopupMenuItem(value: p.name, child: Text(kLedgerRangeLabels[p] ?? p.name)),
            ],
            onSelected: (value) => _pickRange(context, value),
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
            label: filter.txType.isEmpty
                ? '类型'
                : ledgerTxTypeLabel(filter.txType),
            icon: ledgerUiIconOf('filter'),
            active: filter.txType.isNotEmpty,
            items: <PopupMenuEntry<String>>[
              const PopupMenuItem(value: '', child: Text('全部类型')),
              for (final t in kLedgerTxTypes)
                PopupMenuItem(value: t, child: Text(ledgerTxTypeLabel(t))),
            ],
            onSelected: vm.setTxType,
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: _accountName(vm.accounts, filter.accountId),
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
            label: _categoryName(vm.categories, filter.categoryId),
            icon: StrokeIcons.category,
            active: filter.categoryId > 0,
            items: <PopupMenuEntry<String>>[
              const PopupMenuItem(value: '0', child: Text('全部类别')),
              for (final c in vm.categories)
                PopupMenuItem(value: '${c.id}', child: Text(c.name)),
            ],
            onSelected: (value) => vm.setCategory(int.tryParse(value) ?? 0),
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: tags.isEmpty ? '标签' : '标签 ${tags.length}',
            icon: ledgerUiIconOf('tag'),
            active: tags.isNotEmpty,
            items: const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'pick', child: Text('挑选标签')),
            ],
            onSelected: (_) => _pickTags(context),
          ),
          SizedBox(width: m.kSpace6),
          _FilterPill(
            label: filter.minAmount > 0 || filter.maxAmount > 0
                ? '${filter.minAmount > 0 ? _y(filter.minAmount) : '不限'} ~ '
                      '${filter.maxAmount > 0 ? _y(filter.maxAmount) : '不限'}'
                : '金额',
            icon: StrokeIcons.money,
            active: filter.minAmount > 0 || filter.maxAmount > 0,
            items: const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'pick', child: Text('设定区间')),
              PopupMenuItem(value: 'clear', child: Text('不限金额')),
            ],
            onSelected: (value) async {
              if (value == 'clear') {
                await vm.setAmountRange(0, 0);
              } else {
                await _pickAmount(context);
              }
            },
          ),
          if (vm.dayFocus.value.isNotEmpty) ...<Widget>[
            SizedBox(width: m.kSpace6),
            LedgerTagChip(
              label: '只看 ${ledgerDateLabel(vm.dayFocus.value)}',
              onTap: () => vm.focusDay(vm.dayFocus.value),
            ),
          ],
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
          SizedBox(width: m.kSpace6),
          // 页型切换放在胶囊行的末尾：它换的是"怎么看"，不是"看哪些"
          _ViewToggle(
            calendar: vm.calendarMode.value,
            onChanged: (value) => vm.setCalendarMode(value),
          ),
        ],
      ),
    );
    final searchField = AppTextField(
      controller: search,
      onSubmitted: onSearch,
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

  static String _y(double amount) => '¥${amount.toStringAsFixed(0)}';

  /// 区间胶囊的文案。自定义只报日期——"自定义 · 3.1-3.31"里前三个字没信息量
  String _rangeLabel() {
    final p = vm.period.value;
    if (p.isAll) return '全部时间';
    if (p.preset == LedgerRangePreset.custom) return p.shortLabel;
    return '${kLedgerRangeLabels[p.preset]} · ${p.shortLabel}';
  }

  static String _accountName(List<LedgerAccount> rows, int id) {
    if (id == 0) return '账户';
    return rows.firstWhereOrNull((a) => a.id == id)?.name ?? '账户';
  }

  static String _categoryName(List<LedgerCategory> rows, int id) {
    if (id == 0) return '类别';
    return rows.firstWhereOrNull((c) => c.id == id)?.name ?? '类别';
  }

  Future<void> _pickRange(BuildContext context, String name) async {
    final preset = LedgerRangePreset.values.firstWhere(
      (p) => p.name == name,
      orElse: () => LedgerRangePreset.all,
    );
    if (preset == LedgerRangePreset.custom) {
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
      return;
    }
    await vm.setPreset(preset);
  }

  Future<void> _pickTags(BuildContext context) async {
    final picked = await showLedgerTagPicker(
      context,
      selected: vm.filter.value.tagIds.toSet(),
      title: '按标签筛',
    );
    if (picked != null) await vm.setTags(picked);
  }

  Future<void> _pickAmount(BuildContext context) async {
    final current = vm.filter.value;
    final m = AppTheme.metrics;
    final min = TextEditingController(
      text: current.minAmount > 0 ? current.minAmount.toStringAsFixed(0) : '',
    );
    final max = TextEditingController(
      text: current.maxAmount > 0 ? current.maxAmount.toStringAsFixed(0) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('金额区间'),
        content: Row(
          children: <Widget>[
            Expanded(child: LedgerInput(min, hint: '最低', keyboardType: TextInputType.number)),
            SizedBox(width: m.kSpace12),
            const Text('~'),
            SizedBox(width: m.kSpace12),
            Expanded(child: LedgerInput(max, hint: '最高', keyboardType: TextInputType.number)),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('就这么筛')),
        ],
      ),
    );
    final lo = double.tryParse(min.text.trim()) ?? 0;
    final hi = double.tryParse(max.text.trim()) ?? 0;
    min.dispose();
    max.dispose();
    if (ok == true) await vm.setAmountRange(lo, hi);
  }
}

/// 列表 / 日历两态
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.calendar, required this.onChanged});

  final bool calendar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      height: m.kSpace32,
      padding: EdgeInsets.symmetric(horizontal: m.kSpace2),
      decoration: BoxDecoration(
        color: s.surfaceSunken,
        borderRadius: m.radiusPill,
        border: Border.all(color: s.hairline),
      ),
      child: Row(
        children: <Widget>[
          _Segment(
            icon: StrokeIcons.list,
            tooltip: '列表',
            selected: !calendar,
            onTap: () => onChanged(false),
          ),
          _Segment(
            icon: StrokeIcons.calendarViewWeek,
            tooltip: '日历',
            selected: calendar,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final StrokeIcon icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: m.radiusPill,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
          decoration: BoxDecoration(
            color: selected ? s.accentContainer : Colors.transparent,
            borderRadius: m.radiusPill,
          ),
          child: DrawIcon(
            icon,
            size: m.iconSize14,
            color: selected ? s.accentText : s.textTertiary,
          ),
        ),
      ),
    );
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
