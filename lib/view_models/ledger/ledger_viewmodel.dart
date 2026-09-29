import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 流水账首页：本月概览 + 最近流水 + 待确认入口。
///
/// 月份游标是这一页唯一的时间口径，切月只重读本页需要的三段数据，
/// 不连带刷新类别/账户（它们变得很少）。
class LedgerViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  final RxString month = ledgerMonthOf(DateTime.now()).obs;
  final Rx<LedgerSummary> summary = const LedgerSummary().obs;
  final RxList<LedgerTx> recent = <LedgerTx>[].obs;
  final RxList<LedgerDayRow> dayRows = <LedgerDayRow>[].obs;
  final RxList<LedgerCategoryRow> topCategories = <LedgerCategoryRow>[].obs;
  final RxInt pendingCount = 0.obs;
  final RxBool busy = false.obs;

  /// 记账表单要用的下拉数据，进页面取一次就够
  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;

  String get monthLabel {
    final parts = month.value.split('-');
    if (parts.length != 2) return month.value;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  LedgerFilter get _monthFilter => LedgerFilter(
    startDate: ledgerMonthStart(month.value),
    endDate: ledgerMonthEnd(month.value),
    status: kLedgerStatusPosted,
  );

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await reload();
    super.onInitAsync();
  }

  @override
  Future<void> reload() async {
    busy.value = true;
    try {
      await Future.wait([_loadChoices(), _loadMonth(), _loadPendingCount()]);
      clearError();
    } catch (e) {
      setError('读取账本失败: $e');
    } finally {
      busy.value = false;
    }
  }

  Future<void> _loadChoices() async {
    accounts.assignAll(await _service.listAccounts());
    categories.assignAll(await _service.listCategories());
  }

  Future<void> _loadMonth() async {
    final filter = _monthFilter;
    summary.value = await _service.statsSummary(filter);
    dayRows.assignAll(await _service.statsByDay(filter));
    topCategories.assignAll(await _service.statsByCategory(filter));
    recent.assignAll(
      await _service.listTransactions(
        const LedgerFilter(status: kLedgerStatusPosted, limit: 12),
      ),
    );
  }

  Future<void> _loadPendingCount() async {
    pendingCount.value = await _service.pendingCount();
  }

  void shiftMonth(int delta) {
    month.value = ledgerMonthShift(month.value, delta);
    _loadMonth();
  }

  /// 直接跳到某个月（日期选择器给的是 DateTime，页面已经折成 "YYYY-MM"）
  Future<void> goToMonth(String value) async {
    if (value == month.value) return;
    month.value = value;
    await _loadMonth();
  }

  bool get canGoNextMonth =>
      month.value.compareTo(ledgerMonthOf(DateTime.now())) < 0;

  /// 默认账户/类别：表单打开时不必让用户从头选
  LedgerAccount? get defaultAccount => accounts.isEmpty ? null : accounts.first;

  LedgerCategory? categoryFor(String name) {
    for (final c in categories) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// 记一笔：先问一次软查重，命中时交给页面弹确认，而不是直接写库
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
      clearError();
      return LedgerSaveResult.saved;
    } catch (e) {
      setError('保存流水失败: $e');
      return LedgerSaveResult.failed;
    }
  }

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

  /// 手动跑一次某条邮箱规则，返回 Rust 侧的中文概况
  Future<String> checkRuleNow(int ruleId) async {
    try {
      final text = await _service.checkRule(ruleId);
      await reload();
      return text;
    } catch (e) {
      setError('收取邮件账单失败: $e');
      rethrow;
    }
  }
}
