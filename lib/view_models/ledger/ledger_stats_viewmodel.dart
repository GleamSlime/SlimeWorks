import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 统计页：自由区间 + 聚合轴趋势三线 + 类别占比 + 商户排行 + 净资产曲线。
///
/// 三条口径要先说清楚，否则图看着都对、意思全错：
/// - **趋势只有一个数据源**：`stats_by_day`。后端只认按日与按月两种粒度，
///   按周/季/年是拿到日行之后在 Dart 侧按键归并出来的。好处是换轴不重新查库，
///   而且方向游标（只看支出/只看收入）对每一条轴都成立——`stats_by_month` 不认
///   direction，用它画按月趋势就会出现"切了方向图却不变"的假象。
/// - **收支分开看**：占比环把 12 个月的收入和 3 天的支出塞进一张饼没有任何意义。
/// - **净资产曲线是回推的**：没有余额快照表，只能用"当前余额 − 之后每个月的净收支"
///   倒推历史点位。转账不影响净资产，所以它不进这条曲线；余额调整会，但后端还
///   没有那个类型，调过的钱在这儿看不出来。多币种直接相加也是同一类口径错误。
class LedgerStatsViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  /// 净资产曲线往回看多少个月
  static const int assetMonths = 12;

  final Rx<LedgerRangePreset> preset = LedgerRangePreset.thisMonth.obs;
  final Rx<LedgerPeriod> period = ledgerPeriodOf(LedgerRangePreset.thisMonth).obs;
  final RxString direction = kLedgerDirectionExpense.obs;

  /// 聚合轴。区间一变就按区间长度换一个不刺眼的起点，除非用户自己点过
  final Rx<LedgerAxis> axis = LedgerAxis.day.obs;
  bool _axisPinned = false;

  final Rx<LedgerSummary> summary = const LedgerSummary().obs;
  final RxList<LedgerCategoryRow> categoryRows = <LedgerCategoryRow>[].obs;
  final RxList<LedgerMerchantRow> merchantRows = <LedgerMerchantRow>[].obs;
  final RxList<LedgerDayRow> dayRows = <LedgerDayRow>[].obs;
  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerAxisRow> axisRows = <LedgerAxisRow>[].obs;
  final RxList<LedgerAssetPoint> assetPoints = <LedgerAssetPoint>[].obs;
  final RxInt selectedCategory = 0.obs;

  bool get isExpense => direction.value == kLedgerDirectionExpense;
  String get directionLabel => isExpense ? '支出' : '收入';

  /// 区间那句话说全：'本月 · 3.1 - 3.31'。只报"本月"的话，跨月自定义区间就没法核对
  String get rangeLabel {
    final p = period.value;
    if (p.isAll) return '全部时间';
    return p.preset == LedgerRangePreset.custom ? p.shortLabel : '${p.title} · ${p.shortLabel}';
  }

  String get monthLabel => period.value.title;

  /// 占比图的分母：当前方向本区间的合计
  double get categoryTotal =>
      categoryRows.isEmpty ? 0.0 : categoryRows.map((r) => r.total).reduce((a, b) => a + b);

  /// 选中某一类时，页面用它把其余扇区压暗
  double shareOf(LedgerCategoryRow row) {
    final total = categoryTotal;
    return total <= 0 ? 0 : row.total / total;
  }

  // ── 趋势 ──────────────────────────────────────────────────────────────────

  /// 轴上的格子。区间是"全部"时后端回来的日行才是边界，格子得跟着数据铺。
  List<LedgerBucket> get axisBuckets {
    final p = period.value;
    var start = p.startDate;
    var end = p.endDate;
    if (start.isEmpty || end.isEmpty) {
      final dates = dayRows.map((r) => r.billDate).where((d) => d.isNotEmpty).toList()..sort();
      if (dates.isEmpty) return const <LedgerBucket>[];
      start = dates.first;
      end = dates.last;
    }
    return ledgerBuckets(
      LedgerPeriod(startDate: start, endDate: end, title: p.title),
      axis.value,
    );
  }

  List<String> get axisLabels => axisBuckets.map((b) => b.label).toList(growable: false);

  List<double> get axisIncome => axisRows.map((r) => r.income).toList(growable: false);
  List<double> get axisExpense => axisRows.map((r) => r.expense).toList(growable: false);
  List<double> get axisNet => axisRows.map((r) => r.net).toList(growable: false);

  /// 轴上最忙的那一格，卡片副标题用它说"最忙的一周花了多少"这类话。
  ///
  /// 标签在格子那一侧（[axisBuckets]），行数据这边只有键，所以在这儿配对好再交给
  /// 页面——让页面自己格式化键，就等于又开一套标签口径。键也一起给：横轴刻度要短，
  /// 但"最忙的是3月28日"这种整句话该用明细页那套日期说法。
  ({String label, String date, double income, double expense, int count})? get busiestBucket {
    if (axisRows.isEmpty) return null;
    final buckets = axisBuckets;
    var index = 0;
    for (var i = 1; i < axisRows.length; i++) {
      final better = isExpense
          ? axisRows[i].expense > axisRows[index].expense
          : axisRows[i].income > axisRows[index].income;
      if (better) index = i;
    }
    final row = axisRows[index];
    return (
      label: index < buckets.length ? buckets[index].label : row.bucket,
      date: row.bucket,
      income: row.income,
      expense: row.expense,
      count: row.count,
    );
  }

  // ── 资产 ──────────────────────────────────────────────────────────────────

  /// 余额为正的那些账户；负债按"欠多少"的正数报出来
  double get assetNow =>
      accounts.where((a) => a.enabled && a.balance > 0).fold(0.0, (s, a) => s + a.balance);
  double get liabilityNow =>
      accounts.where((a) => a.enabled && a.balance < 0).fold(0.0, (s, a) => s - a.balance);
  double get netWorthNow =>
      accounts.where((a) => a.enabled).fold(0.0, (s, a) => s + a.balance);

  String get assetLabel =>
      accounts.any((a) => a.currency != 'CNY') ? '含外币，直接相加不准' : '';

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    accounts.assignAll(await _service.listAccounts());
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      await Future.wait([_loadRange(), _loadTrend(), _loadAsset()]);
      clearError();
    } catch (e) {
      setError('读取统计失败: $e');
    } finally {
      setLoading(false);
    }
  }

  LedgerFilter _rangeFilter({String withDirection = ''}) => LedgerFilter(
    startDate: period.value.startDate,
    endDate: period.value.endDate,
    direction: withDirection,
    status: kLedgerStatusPosted,
  );

  Future<void> _loadRange() async {
    // 汇总卡不看方向游标：收入和支出同时给，才看得出这个区间是结余还是透支
    summary.value = await _service.statsSummary(_rangeFilter());
    categoryRows.assignAll(await _service.statsByCategory(_rangeFilter(withDirection: direction.value)));
    merchantRows.assignAll(
      await _service.statsByMerchant(_rangeFilter(withDirection: direction.value), top: 10),
    );
  }

  Future<void> _loadTrend() async {
    // 按日行是唯一一份既能带方向又能自己折的原料，趋势不再单独查按月接口
    dayRows.assignAll(await _service.statsByDay(_rangeFilter(withDirection: direction.value)));
    _rebuildAxis();
  }

  /// 纯本地重排：换轴不查库
  void _rebuildAxis() {
    final buckets = axisBuckets;
    axisRows.assignAll(
      ledgerFoldAxis(
        buckets,
        <LedgerFlowSlot>[
          for (final row in dayRows)
            (
              date: row.billDate,
              income: row.income,
              expense: row.expense,
              count: row.count,
            ),
        ],
        axis.value,
      ),
    );
  }

  /// 净资产曲线：从当前余额往回倒推每个月末的点位
  Future<void> _loadAsset() async {
    final rows = await _service.statsByMonth(months: assetMonths);
    if (rows.isEmpty) {
      assetPoints.clear();
      return;
    }
    final sorted = [...rows]..sort((a, b) => a.month.compareTo(b.month));
    final keys = ledgerMonthSpan(sorted.first.month, sorted.last.month);
    final netOf = <String, double>{for (final r in sorted) r.month: r.net};
    // 从最后一个月往回累加：越靠后的月份离"现在"越近，要扣掉的钱越少
    var after = 0.0;
    final points = <LedgerAssetPoint>[];
    for (var i = keys.length - 1; i >= 0; i--) {
      points.insert(
        0,
        LedgerAssetPoint(
          date: keys[i],
          netWorth: netWorthNow - after,
          asset: i == keys.length - 1 ? assetNow : 0,
          liability: i == keys.length - 1 ? liabilityNow : 0,
        ),
      );
      after += netOf[keys[i]] ?? 0;
    }
    assetPoints.assignAll(points);
  }

  // ── 游标 ──────────────────────────────────────────────────────────────────

  Future<void> setPreset(LedgerRangePreset next) async {
    if (next == LedgerRangePreset.custom) return;
    preset.value = next;
    period.value = ledgerPeriodOf(next);
    await _onRangeChanged();
  }

  Future<void> setCustomRange(DateTime start, DateTime end) async {
    final s = ledgerDateOf(start);
    final e = ledgerDateOf(end.isBefore(start) ? start : end);
    preset.value = LedgerRangePreset.custom;
    period.value = LedgerPeriod(startDate: s, endDate: e, title: '$s ~ $e');
    await _onRangeChanged();
  }

  /// 直接跳到某个月：首页的"看这个月的统计"和日期选择器都走这里
  Future<void> goToMonth(String value) async {
    preset.value = LedgerRangePreset.custom;
    period.value = LedgerPeriod(
      startDate: ledgerMonthStart(value),
      endDate: ledgerMonthEnd(value),
      title: ledgerMonthLabel(value),
    );
    await _onRangeChanged();
  }

  /// 区间换了，轴跟着换档；用户手动点过轴就不再自作主张
  Future<void> _onRangeChanged() async {
    selectedCategory.value = 0;
    if (!_axisPinned) {
      axis.value = _axisForDays(period.value.dayCount);
    }
    await reload();
  }

  /// 三十天按日看得清，两年按日就是一团除了"哪里高"什么都读不出来的锯齿
  static LedgerAxis _axisForDays(int days) {
    if (days <= 0) return LedgerAxis.month;
    if (days <= 62) return LedgerAxis.day;
    if (days <= 400) return LedgerAxis.month;
    return LedgerAxis.year;
  }

  Future<void> setAxis(LedgerAxis next) async {
    if (axis.value == next) return;
    _axisPinned = true;
    axis.value = next;
    _rebuildAxis();
  }

  /// 轴还是想跟着区间走，再点一次预设就行
  Future<void> setDirection(String value) async {
    if (direction.value == value) return;
    direction.value = value;
    selectedCategory.value = 0;
    await reload();
  }

  void toggleCategory(int categoryId) {
    selectedCategory.value = selectedCategory.value == categoryId ? 0 : categoryId;
  }
}
