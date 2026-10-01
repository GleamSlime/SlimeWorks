import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 数据导入导出页。
///
/// 这一页两头都是**真账**：导出读的是 Rust 的流水表，导入写的也是。CSV 的编解码
/// 暂时住在 [LedgerStubStore]（纯文本处理，放在哪儿都不影响界面），所以整页不挂
/// "演示数据"水印——只有"标签那一列导进来会丢"这一条得单独说清楚，因为后端还
/// 没有标签表，那是真的存不住。
class LedgerDataViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  // ── 导出 ──

  final Rx<LedgerRangePreset> range = LedgerRangePreset.all.obs;
  final RxString customStart = ''.obs;
  final RxString customEnd = ''.obs;

  /// false=CSV（给人看、也能再导回来），true=JSON（给程序看，字段与库里一一对应）
  final RxBool asJson = false.obs;
  final RxInt exportCount = 0.obs;

  /// 同区间里的待确认笔数：不说清"为什么文件里少了这几笔"，用户会以为导出漏了
  final RxInt exportPending = 0.obs;

  // ── 导入 ──

  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;
  final Rx<LedgerCsvPreview?> preview = Rx<LedgerCsvPreview?>(null);
  final RxString fileName = ''.obs;

  /// 文件里的账户名对不上时统一落到哪个账户；0 = 不落账户
  final RxInt fallbackAccountId = 0.obs;

  /// 与已入账流水"像同一笔"的行数：导入前只问一次，不逐行弹窗
  final RxInt duplicateCount = 0.obs;

  /// 选文件这一步本身的失败（编码不对、读不到）：跟"解析出 0 行"不是一回事，
  /// 所以它挂在页上而不是塞进 preview 里
  final RxString importNote = ''.obs;
  final RxString lastMessage = ''.obs;
  final RxBool busy = false.obs;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await _store.init();
    await reload();
    super.onInitAsync();
  }

  LedgerStubStore get _store => LedgerStubStore.instance;

  Future<void> reload() async {
    setLoading(true);
    try {
      accounts.assignAll(await _service.listAccounts());
      categories.assignAll(await _service.listCategories());
      await refreshExportCount();
      clearError();
    } catch (e) {
      setError('读取账户与类别失败: $e');
    } finally {
      setLoading(false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 导出
  // ─────────────────────────────────────────────────────────────────────────

  /// 导出可选的几档。没有"上一账单周期"：那一档要拿某个账户的账单日当锚点，
  /// 而"整个账本导出到哪一天"跟账单日无关，摆在这里只会让人以为导的是信用卡。
  static const List<LedgerRangePreset> kRangeChoices = <LedgerRangePreset>[
    LedgerRangePreset.all,
    LedgerRangePreset.thisYear,
    LedgerRangePreset.thisMonth,
    LedgerRangePreset.lastMonth,
    LedgerRangePreset.last30,
    LedgerRangePreset.custom,
  ];

  LedgerPeriod get period {
    if (range.value != LedgerRangePreset.custom) {
      return ledgerPeriodOf(range.value, now: DateTime.now());
    }
    final start = customStart.value;
    final end = customEnd.value;
    return LedgerPeriod(
      startDate: start,
      endDate: end,
      title: start.isEmpty && end.isEmpty
          ? '自定义（还没选日期）'
          : '${start.isEmpty ? '最早' : start} ~ ${end.isEmpty ? '今天' : end}',
    );
  }

  Future<void> setRange(LedgerRangePreset preset) async {
    if (range.value == preset) return;
    range.value = preset;
    await refreshExportCount();
  }

  Future<void> setCustom({String? start, String? end}) async {
    range.value = LedgerRangePreset.custom;
    if (start != null) customStart.value = start;
    if (end != null) customEnd.value = end;
    await refreshExportCount();
  }

  Future<void> setFormat({required bool json}) async {
    if (asJson.value == json) return;
    asJson.value = json;
  }

  /// 区间内已入账的笔数。待确认队列不算：那笔钱用户还没认，导出去就是一张
  /// 对不上的表，而且再导回来会变成两笔。
  Future<void> refreshExportCount() async {
    try {
      exportCount.value = await _service.countTransactions(period.toFilter());
      exportPending.value = await _service.countTransactions(
        period.toFilter(status: kLedgerStatusPending),
      );
    } catch (e) {
      setError('数不出要导出多少笔: $e');
    }
  }

  Future<String> buildExport() async {
    final rows = await _service.listTransactions(period.toFilter());
    if (asJson.value) {
      return const JsonEncoder.withIndent('  ').convert(
        rows.map((LedgerTx r) => r.toJson()).toList(),
      );
    }
    return LedgerStubStore.encodeCsv(rows);
  }

  String get exportFileName {
    final scope = period.isAll
        ? '全部'
        : <String>[period.startDate, period.endDate].where((s) => s.isNotEmpty).join('_');
    return '流水账-$scope-${ledgerDateOf(DateTime.now())}.${asJson.value ? 'json' : 'csv'}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 导入
  // ─────────────────────────────────────────────────────────────────────────

  /// 解析结果：只读预览，一行都不写库。落库要用户按"导入"那一下。
  Future<void> loadCsv(String text, String name) async {
    fileName.value = name;
    importNote.value = '';
    final parsed = LedgerStubStore.decodeCsv(text);
    // 解析器说"这份表根本对不上"时不建预览：一块写着"能读 0 笔"的空表
    // 远不如一句"至少要能对上日期和金额两列"有用
    if (parsed.error != null) {
      preview.value = null;
      importNote.value = parsed.error!;
      return;
    }
    preview.value = parsed;
    lastMessage.value = '';
    duplicateCount.value = 0;
    if (parsed.rows.isEmpty) return;
    busy.value = true;
    try {
      var dup = 0;
      for (final row in parsed.rows) {
        final check = await _service.checkDuplicate(
          merchant: row.merchant,
          amount: row.amount,
          billDate: row.billDate,
          accountId: _resolveAccount(row).id,
        );
        if (check.duplicated) dup++;
      }
      duplicateCount.value = dup;
    } catch (e) {
      setError('查重失败: $e');
    } finally {
      busy.value = false;
    }
  }

  void clearPreview() {
    preview.value = null;
    fileName.value = '';
    importNote.value = '';
    duplicateCount.value = 0;
  }

  List<LedgerTx> get _rows => preview.value?.rows ?? const <LedgerTx>[];

  /// 真正要写库的那些行：名字已经换成 id，落不上的按界面上的兜底选择处理
  List<LedgerTx> get resolvedRows => <LedgerTx>[for (final row in _rows) bind(row)];

  /// 一行的账户/类别只认一次：认第二遍不会更准，只会让预览统计在几百行上明显发顿。
  /// 界面预览也走它，预览里看到的账户/类别就是真要写进去的那两个。
  LedgerTx bind(LedgerTx row) {
    final account = _resolveAccount(row);
    final category = _resolveCategory(row);
    return row.copyWith(
      accountId: account.id,
      accountName: account.name,
      categoryId: category.id,
      categoryName: category.name,
      categoryIcon: category.icon,
      // 标签表还没接后端：带着 tagIds 写进去是一串指向空气的外键
      tagIds: const <int>[],
    );
  }

  ({int id, String name}) _resolveAccount(LedgerTx row) {
    for (final a in accounts) {
      if (a.enabled && a.name == row.accountName) return (id: a.id, name: a.name);
    }
    final fallback = accounts.where((a) => a.id == fallbackAccountId.value).firstOrNull;
    return (id: fallback?.id ?? 0, name: fallback?.name ?? '');
  }

  /// 类别列允许写成"父/子"：两级分类在表格里就是一行一格，不写清父类就没法
  /// 表达"餐饮/早餐"和"交通/早餐"是两个不同的格子。
  ({int id, String name, String icon}) _resolveCategory(LedgerTx row) {
    final raw = row.categoryName.trim();
    if (raw.isEmpty) return (id: 0, name: '', icon: '');
    final parts = raw.split(RegExp(r'[/／>」]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final leaf = parts.last;
    final parentName = parts.length > 1 ? parts[parts.length - 2] : '';
    LedgerCategory? hit;
    if (parentName.isNotEmpty) {
      final parent = categories
          .where((c) => c.isRoot && c.name == parentName && c.direction == row.direction)
          .firstOrNull;
      hit = categories
          .where(
            (c) =>
                c.name == leaf &&
                c.direction == row.direction &&
                (parent == null || c.parentId == parent.id),
          )
          .firstOrNull;
    } else {
      // 只给了一层名字：先当它是父类，再退而求其次当它是子类
      hit =
          categories
              .where((c) => c.isRoot && c.name == leaf && c.direction == row.direction)
              .firstOrNull ??
          categories.where((c) => c.name == leaf && c.direction == row.direction).firstOrNull;
    }
    return (id: hit?.id ?? 0, name: hit?.name ?? '', icon: hit?.icon ?? '');
  }

  /// 文件里写了账户、但这个账户在当前账本里找不到（或已停用）的行数
  int get unmatchedAccountCount => _rows
      .where((r) => r.accountName.trim().isNotEmpty && bind(r).accountName != r.accountName.trim())
      .length;

  /// 文件里根本没写账户列的行数——这不算"对不上"，用户可能就是从只记金额的表导出来的
  int get noAccountCount => _rows.where((r) => r.accountName.trim().isEmpty).length;

  int get uncategorizedCount => _rows.where((r) => bind(r).categoryId == 0).length;

  int get taggedCount => _rows.where((r) => r.tagNames.isNotEmpty).length;

  /// 导入：逐笔写进 Rust 的账本。返回给界面显示的回执，null 表示没写成。
  Future<String?> importAll() async {
    final rows = resolvedRows;
    if (rows.isEmpty) return null;
    busy.value = true;
    try {
      var done = 0;
      for (final row in rows) {
        await _service.addTransaction(row);
        done++;
      }
      final tail = <String>[
        if (preview.value!.skipped > 0) '跳过 ${preview.value!.skipped} 行读不出日期的',
        if (uncategorizedCount > 0) '$uncategorizedCount 笔没落类别',
        if (taggedCount > 0) '标签暂时存不住，已丢掉',
      ];
      lastMessage.value = '已导入 $done 笔${tail.isEmpty ? '' : ' · ${tail.join(' · ')}'}';
      clearPreview();
      await refreshExportCount();
      return lastMessage.value;
    } catch (e) {
      setError('导入失败: $e');
      return null;
    } finally {
      busy.value = false;
    }
  }
}
