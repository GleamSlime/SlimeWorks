import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 待确认队列：邮件解析出的流水先进这里，用户点头才进账本。
///
/// 一封邮件对应一组流水，展开时才二次查询流水明细——
/// 列表页常见几十封，一次性把所有明细捞回来没必要。
class LedgerPendingViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  final RxList<LedgerPendingEmail> emails = <LedgerPendingEmail>[].obs;

  /// 已入账的历史邮件：账本里每一笔都要能回查到是哪封邮件带来的
  final RxList<LedgerPendingEmail> appliedEmails = <LedgerPendingEmail>[].obs;
  final RxList<LedgerRule> rules = <LedgerRule>[].obs;
  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;
  final RxMap<int, List<LedgerTx>> _details = <int, List<LedgerTx>>{}.obs;
  final RxList<int> expanded = <int>[].obs;
  final RxInt defaultAccountId = 0.obs;
  final RxString lastResult = ''.obs;

  /// 展开态：已加载的明细直接读缓存
  List<LedgerTx> detailsOf(int emailId) => _details[emailId] ?? const <LedgerTx>[];

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await reload();
    super.onInitAsync();
  }

  @override
  Future<void> reload() async {
    setLoading(true);
    try {
      emails.assignAll(await _service.listPending(limit: 200));
      // 已入账的历史邮件：账本里每一笔都要能回查到是哪封邮件带来的
      appliedEmails.assignAll(await _service.listReceivedEmails(limit: 50));
      rules.assignAll(await _service.listRules());
      accounts.assignAll(await _service.listAccounts());
      categories.assignAll(await _service.listCategories());
      if (defaultAccountId.value == 0 && accounts.isNotEmpty) {
        defaultAccountId.value = accounts.first.id;
      }
      clearError();
    } catch (e) {
      setError('读取待确认账单失败: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> toggleExpand(int emailId) async {
    if (expanded.contains(emailId)) {
      expanded.remove(emailId);
      return;
    }
    expanded.add(emailId);
    if (_details.containsKey(emailId)) return;
    try {
      _details[emailId] = await _service.transactionsOfEmail(emailId);
    } catch (e) {
      setError('读取邮件明细失败: $e');
    }
  }

  Map<String, dynamic> _patch({int? accountId, int? categoryId}) => <String, dynamic>{
    if (accountId != null && accountId > 0) 'account_id': accountId,
    if (categoryId != null && categoryId > 0) 'category_id': categoryId,
  };

  /// 整封确认：类别留空时由 Rust 按方向落到默认类别
  Future<void> confirmEmail(
    int emailId, {
    int? accountId,
    int? categoryId,
  }) async {
    try {
      final count = await _service.confirmAll(
        emailId,
        patch: _patch(accountId: accountId ?? defaultAccountId.value, categoryId: categoryId),
      );
      lastResult.value = '已入账 $count 笔';
      _details.remove(emailId);
      await reload();
    } catch (e) {
      setError('确认入账失败: $e');
    }
  }

  Future<void> confirmOne(int txId, {int? accountId, int? categoryId, String? merchant}) async {
    try {
      await _service.confirmTx(
        txId,
        patch: <String, dynamic>{
          ..._patch(accountId: accountId ?? defaultAccountId.value, categoryId: categoryId),
          if (merchant != null && merchant.isNotEmpty) 'merchant': merchant,
        },
      );
      await reload();
    } catch (e) {
      setError('确认这笔失败: $e');
    }
  }

  Future<void> ignoreEmail(int emailId) async {
    try {
      await _service.ignoreEmail(emailId);
      lastResult.value = '已忽略这封账单';
      await reload();
    } catch (e) {
      setError('忽略失败: $e');
    }
  }

  /// 银行改版后清场：删掉这封邮件带进来的全部流水
  Future<void> purgeEmail(int emailId) async {
    try {
      final count = await _service.purgeEmail(emailId);
      lastResult.value = '已清除 $count 笔流水';
      _details.remove(emailId);
      await reload();
    } catch (e) {
      setError('清除失败: $e');
    }
  }

  Future<void> checkRuleNow(int ruleId) async {
    try {
      lastResult.value = await _service.checkRule(ruleId);
      await reload();
    } catch (e) {
      setError('收取失败: $e');
    }
  }

  /// 类别下拉：只显示与这笔方向一致的类别
  List<LedgerCategory> categoriesFor(String direction) =>
      categories.where((c) => c.direction == direction).toList(growable: false);
}
