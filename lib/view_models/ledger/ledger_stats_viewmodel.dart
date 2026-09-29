import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 统计页：月度趋势 + 分类占比 + 商户排行。
///
/// 收支两个方向分开看（`direction` 游标），因为占比图把 12 个月的收入和
/// 一个月的支出混在一张饼里没有任何意义。
class LedgerStatsViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  final RxString month = ledgerMonthOf(DateTime.now()).obs;
  final RxString direction = kLedgerDirectionExpense.obs;
  final RxInt trendMonths = 12.obs;

  final Rx<LedgerSummary> summary = const LedgerSummary().obs;
  final RxList<LedgerMonthRow> monthRows = <LedgerMonthRow>[].obs;
  final RxList<LedgerCategoryRow> categoryRows = <LedgerCategoryRow>[].obs;
  final RxList<LedgerMerchantRow> merchantRows = <LedgerMerchantRow>[].obs;
  final RxList<LedgerDayRow> dayRows = <LedgerDayRow>[].obs;
  final RxInt selectedCategory = 0.obs;

  String get monthLabel {
    final parts = month.value.split('-');
    if (parts.length != 2) return month.value;
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  bool get isExpense => direction.value == kLedgerDirectionExpense;
  String get directionLabel => isExpense ? '支出' : '收入';

  /// 占比图的分母：当前方向本月的合计
  double get categoryTotal =>
      categoryRows.isEmpty ? 0.0 : categoryRows.map((r) => r.total).reduce((a, b) => a + b);

  /// 选中某一类时，页面用它把其余扇区压暗
  double shareOf(LedgerCategoryRow row) {
    final total = categoryTotal;
    return total <= 0 ? 0 : row.total / total;
  }

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      await Future.wait([_loadMonth(), _loadTrend()]);
      clearError();
    } catch (e) {
      setError('读取统计失败: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> _loadMonth() async {
    final start = ledgerMonthStart(month.value);
    final end = ledgerMonthEnd(month.value);
    final filter = LedgerFilter(
      startDate: start,
      endDate: end,
      direction: direction.value,
      status: kLedgerStatusPosted,
    );
    // 汇总卡不受方向游标影响：收入和支出同时给出，才看得出结余
    summary.value = await _service.statsSummary(
      LedgerFilter(startDate: start, endDate: end, status: kLedgerStatusPosted),
    );
    categoryRows.assignAll(await _service.statsByCategory(filter));
    merchantRows.assignAll(await _service.statsByMerchant(filter, top: 10));
    dayRows.assignAll(
      await _service.statsByDay(
        LedgerFilter(startDate: start, endDate: end, status: kLedgerStatusPosted),
      ),
    );
  }

  Future<void> _loadTrend() async {
    monthRows.assignAll(await _service.statsByMonth(months: trendMonths.value));
  }

  void shiftMonth(int delta) {
    month.value = ledgerMonthShift(month.value, delta);
    selectedCategory.value = 0;
    _loadMonth();
  }

  /// 直接跳到某个月：日期选择器给的是 DateTime，页面已经折成 "YYYY-MM"
  void goToMonth(String value) {
    if (value == month.value) return;
    month.value = value;
    selectedCategory.value = 0;
    _loadMonth();
  }

  void setDirection(String value) {
    if (direction.value == value) return;
    direction.value = value;
    selectedCategory.value = 0;
    _loadMonth();
  }

  void setTrendMonths(int count) {
    if (trendMonths.value == count) return;
    trendMonths.value = count;
    _loadTrend();
  }

  void toggleCategory(int categoryId) {
    selectedCategory.value = selectedCategory.value == categoryId ? 0 : categoryId;
  }

  bool get canGoNextMonth => month.value.compareTo(ledgerMonthOf(DateTime.now())) < 0;
}
