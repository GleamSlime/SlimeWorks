import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 流水页：多维筛选 + 月/日两级分组 + 列表与日历双页型 + 分页续读。
///
/// 筛选条件分两拨，这一点必须说清楚：
/// - **后端拨**（时间区间、收支方向、账户、类别、关键词、来源、状态）真的进 SQL，
///   所以它们能作用于全部流水，分页与合计都是准的。
/// - **本地拨**（记账类型、标签、金额区间）库里连列都还没有，只能在已读到的
///   那一页上再筛一遍。所以 [hasClientFilters] 为真时界面要写明"仅在本页筛"，
///   不能让用户以为筛出来的就是全部。
class LedgerRecordsViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  static const int _pageSize = 80;

  final Rx<LedgerFilter> filter = const LedgerFilter(
    status: kLedgerStatusPosted,
  ).obs;
  final RxList<LedgerTx> items = <LedgerTx>[].obs;
  final RxInt totalCount = 0.obs;
  final Rx<LedgerSummary> rangeSummary = const LedgerSummary().obs;
  final RxBool loadingMore = false.obs;

  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;
  final RxList<LedgerTag> tags = <LedgerTag>[].obs;

  /// 当前挂着的区间预设，胶囊要把它原样标回来
  final Rx<LedgerRangePreset> preset = LedgerRangePreset.all.obs;
  final Rx<LedgerPeriod> period = const LedgerPeriod(
    startDate: '',
    endDate: '',
    title: '全部',
  ).obs;

  /// 点中只看的那一天。日历那一档的区间仍然是后端条件，这天只是本地再收一刀，
  /// 所以摘掉它不用重新查询，也不会把区间弄丢。
  final RxString dayFocus = ''.obs;

  /// 页型：列表 / 日历。日历只负责"看哪天有钱动"，点某天回到列表并按那天过滤
  final RxBool calendarMode = false.obs;
  final RxString calendarMonth = ledgerMonthOf(DateTime.now()).obs;
  final RxList<LedgerDayRow> dayRows = <LedgerDayRow>[].obs;

  int _loaded = 0;

  bool get hasMore => _loaded < totalCount.value;

  /// 后端还不认识这几项，筛的是已经读进内存的那部分
  bool get hasClientFilters =>
      filter.value.txType.isNotEmpty ||
      filter.value.tagIds.isNotEmpty ||
      filter.value.minAmount > 0 ||
      filter.value.maxAmount > 0;

  /// 后端条件命中的那一页，再过一遍本地条件（含日历点选的那一天）
  List<LedgerTx> get visibleItems {
    final f = filter.value;
    final day = dayFocus.value;
    if (!hasClientFilters && day.isEmpty) return items.toList(growable: false);
    return items
        .where((tx) {
          if (day.isNotEmpty && tx.billDate != day) return false;
          if (f.txType.isNotEmpty && tx.effectiveType != f.txType) return false;
          if (f.tagIds.isNotEmpty && !tx.tagIds.any((id) => f.tagIds.contains(id))) {
            return false;
          }
          if (f.minAmount > 0 && tx.amount < f.minAmount) return false;
          if (f.maxAmount > 0 && tx.amount > f.maxAmount) return false;
          return true;
        })
        .toList(growable: false);
  }

  /// 按天分组；日期倒序，组内按发生时间倒序
  List<LedgerDayGroup> get groups {
    final map = <String, List<LedgerTx>>{};
    for (final tx in visibleItems) {
      map.putIfAbsent(tx.dateLabel, () => <LedgerTx>[]).add(tx);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map(
          (date) => LedgerDayGroup(
            date: date,
            txs: map[date]!,
            income: map[date]!.where((t) => t.isIncome).fold(0.0, (a, b) => a + b.amount),
            expense: map[date]!.where((t) => !t.isIncome).fold(0.0, (a, b) => a + b.amount),
          ),
        )
        .toList(growable: false);
  }

  /// 月分组：跨月区间要看到"这个月一共花了多少"，而不是只有一堆日组
  List<LedgerMonthGroup> get monthGroups {
    final map = <String, List<LedgerDayGroup>>{};
    for (final day in groups) {
      final month = day.date.substring(0, 7);
      map.putIfAbsent(month, () => <LedgerDayGroup>[]).add(day);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((month) {
      final days = map[month]!;
      return LedgerMonthGroup(
        month: month,
        days: days,
        income: days.fold(0.0, (a, d) => a + d.income),
        expense: days.fold(0.0, (a, d) => a + d.expense),
        count: days.fold(0, (a, d) => a + d.txs.length),
      );
    }).toList(growable: false);
  }

  String get filterLabel => period.value.shortLabel;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    accounts.assignAll(await _service.listAccounts());
    categories.assignAll(await _service.listCategories());
    // 标签仓库这一轮还在 Dart 侧：后端建表前只能筛已读到的那一页
    tags.assignAll(await LedgerStubStore.instance.listTags());
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      items.clear();
      _loaded = 0;
      await Future.wait([_loadPage(reset: true), _loadMeta()]);
      if (calendarMode.value) await _loadCalendar();
      clearError();
    } catch (e) {
      setError('读取流水失败: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> _loadMeta() async {
    final f = filter.value;
    totalCount.value = await _service.countTransactions(f);
    rangeSummary.value = await _service.statsSummary(
      f.copyWith(limit: 0, offset: 0),
    );
  }

  Future<void> _loadPage({bool reset = false}) async {
    final page = await _service.listTransactions(
      filter.value.copyWith(limit: _pageSize, offset: reset ? 0 : _loaded),
    );
    if (reset) {
      items.assignAll(page);
      _loaded = page.length;
    } else {
      items.addAll(page);
      _loaded += page.length;
    }
  }

  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore) return;
    loadingMore.value = true;
    try {
      await _loadPage();
    } catch (e) {
      setError('加载更多失败: $e');
    } finally {
      loadingMore.value = false;
    }
  }

  // ── 区间 ──────────────────────────────────────────────────────────────────

  /// 预设区间。[billDay] 只有"上一账单周期"用得到，其余预设忽略它
  Future<void> setPreset(LedgerRangePreset next, {int billDay = 1}) async {
    if (next == LedgerRangePreset.custom) return;
    final p = ledgerPeriodOf(next, billDay: billDay);
    period.value = p;
    preset.value = next;
    await applyFilter(
      filter.value.copyWith(startDate: p.startDate, endDate: p.endDate),
    );
  }

  Future<void> setCustomRange(DateTime start, DateTime end) async {
    final s = ledgerDateOf(start);
    final e = ledgerDateOf(end.isBefore(start) ? start : end);
    period.value = LedgerPeriod(
      startDate: s,
      endDate: e,
      title: '$s ~ $e',
      preset: LedgerRangePreset.custom,
    );
    preset.value = LedgerRangePreset.custom;
    await applyFilter(filter.value.copyWith(startDate: s, endDate: e));
  }

  // ── 其它维度 ──────────────────────────────────────────────────────────────

  Future<void> setMonth(String month) async {
    // 从别处跳到某个月时，区间胶囊要跟着改口，不能还写着"全部时间"
    final p = LedgerPeriod(
      startDate: ledgerMonthStart(month),
      endDate: ledgerMonthEnd(month),
      title: month,
      preset: LedgerRangePreset.custom,
    );
    period.value = p;
    preset.value = LedgerRangePreset.custom;
    await applyFilter(filter.value.copyWith(startDate: p.startDate, endDate: p.endDate));
  }

  Future<void> setDirection(String direction) =>
      applyFilter(filter.value.copyWith(direction: direction));

  Future<void> setAccount(int accountId) =>
      applyFilter(filter.value.copyWith(accountId: accountId));

  Future<void> setCategory(int categoryId) =>
      applyFilter(filter.value.copyWith(categoryId: categoryId));

  Future<void> setTxType(String txType) =>
      applyFilter(filter.value.copyWith(txType: txType));

  Future<void> setTags(List<int> tagIds) =>
      applyFilter(filter.value.copyWith(tagIds: tagIds));

  Future<void> setAmountRange(double min, double max) =>
      applyFilter(filter.value.copyWith(minAmount: min, maxAmount: max));

  Future<void> setKeyword(String keyword) =>
      applyFilter(filter.value.copyWith(keyword: keyword.trim()));

  /// 0 表示"全部"，回到无过滤态；区间也一并清掉，"清空"就该真的清空
  Future<void> clearFilters() async {
    period.value = const LedgerPeriod(startDate: '', endDate: '', title: '全部');
    preset.value = LedgerRangePreset.all;
    dayFocus.value = '';
    filter.value = const LedgerFilter(status: kLedgerStatusPosted);
    await reload();
  }

  Future<void> applyFilter(LedgerFilter next) async {
    if (next.json == filter.value.json) return;
    filter.value = next;
    await reload();
  }

  bool get isFiltered =>
      !filter.value.isEmpty ||
      filter.value.startDate.isNotEmpty ||
      filter.value.endDate.isNotEmpty ||
      dayFocus.value.isNotEmpty;

  // ── 日历页型 ──────────────────────────────────────────────────────────────

  Future<void> setCalendarMode(bool on) async {
    if (calendarMode.value == on) return;
    calendarMode.value = on;
    if (!on) return;
    // 列表已经筛到某个月，切日历就该落在那个月，而不是跳回这个月
    final start = period.value.startDate;
    if (start.length >= 7) calendarMonth.value = start.substring(0, 7);
    await _loadCalendar();
  }

  Future<void> shiftCalendarMonth(int delta) async {
    calendarMonth.value = ledgerMonthShift(calendarMonth.value, delta);
    await _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    final month = calendarMonth.value;
    final rows = await _service.statsByDay(
      filter.value.copyWith(
        startDate: ledgerMonthStart(month),
        endDate: ledgerMonthEnd(month),
        limit: 0,
        offset: 0,
      ),
    );
    dayRows.assignAll(rows);
  }

  /// 日历里点某一天：切回列表并只看这天。再点同一天等于取消
  void focusDay(String date) {
    dayFocus.value = dayFocus.value == date ? '' : date;
    calendarMode.value = false;
  }

  LedgerDayRow dayRowOf(String date) =>
      dayRows.firstWhere((r) => r.billDate == date, orElse: () => const LedgerDayRow());

  // ── 增删改 ────────────────────────────────────────────────────────────────

  Future<bool> deleteTx(int id) async {
    try {
      await _service.deleteTransaction(id);
      await reload();
      return true;
    } catch (e) {
      setError('删除流水失败: $e');
      return false;
    }
  }

  Future<LedgerSaveResult> save(LedgerTx tx, {bool ignoreDuplicate = false}) async {
    try {
      if (!ignoreDuplicate) {
        final dup = await _service.checkDuplicate(
          merchant: tx.merchant,
          amount: tx.amount,
          billDate: tx.billDate,
          accountId: tx.accountId,
        );
        if (dup.duplicated) return LedgerSaveResult.duplicate;
      }
      if (tx.id > 0) {
        await _service.updateTransaction(tx);
      } else {
        await _service.addTransaction(tx);
      }
      await reload();
      return LedgerSaveResult.saved;
    } catch (e) {
      setError('保存流水失败: $e');
      return LedgerSaveResult.failed;
    }
  }
}

/// 列表里的一天：组头要显示当日收支
class LedgerDayGroup {
  const LedgerDayGroup({
    required this.date,
    required this.txs,
    required this.income,
    required this.expense,
  });

  final String date;
  final List<LedgerTx> txs;
  final double income;
  final double expense;

  double get net => income - expense;
}

/// 列表里的一个月：跨月区间要先看到本月总账，再往下看每天
class LedgerMonthGroup {
  const LedgerMonthGroup({
    required this.month,
    required this.days,
    required this.income,
    required this.expense,
    required this.count,
  });

  final String month;
  final List<LedgerDayGroup> days;
  final double income;
  final double expense;
  final int count;

  double get net => income - expense;

  /// "2026-03" → "2026 年 3 月"
  String get title {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    return '${parts[0]} 年 ${int.tryParse(parts[1]) ?? 0} 月';
  }
}
