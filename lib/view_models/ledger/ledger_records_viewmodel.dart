import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 流水页：多维筛选 + 按天分组 + 分页续读。
///
/// 筛选条件全部落在 `LedgerFilter` 上，改动即重查第一页；
/// "加载更多"只追加，不重置游标，避免列表滚回顶部。
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

  int _loaded = 0;

  bool get hasMore => _loaded < totalCount.value;

  /// 按天分组给列表用；日期倒序，组内按发生时间倒序
  List<LedgerDayGroup> get groups {
    final map = <String, List<LedgerTx>>{};
    for (final tx in items) {
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

  String get filterLabel {
    final f = filter.value;
    if (f.startDate.isNotEmpty && f.startDate == f.endDate) return f.startDate;
    if (f.startDate.isNotEmpty && f.endDate.isNotEmpty) return '${f.startDate} ~ ${f.endDate}';
    if (f.startDate.isNotEmpty) return '${f.startDate} 起';
    if (f.endDate.isNotEmpty) return '${f.endDate} 止';
    return '全部时间';
  }

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    accounts.assignAll(await _service.listAccounts());
    categories.assignAll(await _service.listCategories());
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      items.clear();
      _loaded = 0;
      await Future.wait([_loadPage(reset: true), _loadMeta()]);
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

  void setMonth(String month) => applyFilter(
    filter.value.copyWith(startDate: ledgerMonthStart(month), endDate: ledgerMonthEnd(month)),
  );

  void setDirection(String direction) => applyFilter(filter.value.copyWith(direction: direction));

  void setAccount(int accountId) => applyFilter(filter.value.copyWith(accountId: accountId));

  void setCategory(int categoryId) => applyFilter(filter.value.copyWith(categoryId: categoryId));

  void setKeyword(String keyword) => applyFilter(filter.value.copyWith(keyword: keyword.trim()));

  /// 0 表示"全部"，回到无过滤态
  void clearFilters() {
    filter.value = const LedgerFilter(status: kLedgerStatusPosted);
    reload();
  }

  void applyFilter(LedgerFilter next) {
    if (next.json == filter.value.json) return;
    filter.value = next;
    reload();
  }

  bool get isFiltered =>
      filter.value.startDate.isNotEmpty ||
      filter.value.endDate.isNotEmpty ||
      filter.value.direction.isNotEmpty ||
      filter.value.accountId > 0 ||
      filter.value.categoryId > 0 ||
      filter.value.keyword.isNotEmpty;

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
