import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 账户与类别管理页。
///
/// 删除账户/类别时 Rust 返回的是"这个账户还有 N 笔流水，已改为停用"这类影响面
/// 说明，而不是布尔结果——它决定用户点下删除后看到什么，必须原样透出。
class LedgerAccountsViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;

  /// 商户 → 类别 的自动归类记忆表
  final RxList<Map<String, dynamic>> merchantMemory = <Map<String, dynamic>>[].obs;

  /// 最近一次写操作的中文回执（来自 Rust）
  final RxString lastMessage = ''.obs;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      accounts.assignAll(await _service.listAccounts());
      categories.assignAll(await _service.listCategories());
      merchantMemory.assignAll(await _service.listMerchantMemory());
      clearError();
    } catch (e) {
      setError('读取账户与类别失败: $e');
    } finally {
      setLoading(false);
    }
  }

  List<LedgerCategory> expenseCategories() =>
      categories.where((c) => c.direction == kLedgerDirectionExpense).toList(growable: false);

  List<LedgerCategory> incomeCategories() =>
      categories.where((c) => c.direction == kLedgerDirectionIncome).toList(growable: false);

  LedgerCategory? categoryById(int id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 商户记忆表里的 category_id 换成可读名字；类别被删过时显示"已删除"
  String categoryNameOf(int categoryId) {
    final found = categoryById(categoryId);
    if (found != null) return found.name;
    return '已删除的类别';
  }

  Future<bool> saveAccount(LedgerAccount account) async {
    try {
      await _service.upsertAccount(account);
      lastMessage.value = account.id > 0 ? '账户「${account.name}」已更新' : '账户「${account.name}」已添加';
      await reload();
      return true;
    } catch (e) {
      setError('保存账户失败: $e');
      return false;
    }
  }

  /// 停用/启用：走同一条 upsert，Rust 没有单独的开关接口
  Future<void> toggleAccount(LedgerAccount account) async {
    try {
      await _service.upsertAccount(account.copyWith(enabled: !account.enabled));
      await reload();
    } catch (e) {
      setError('切换账户状态失败: $e');
    }
  }

  Future<bool> deleteAccount(LedgerAccount account) async {
    try {
      lastMessage.value = await _service.deleteAccount(account.id);
      await reload();
      return true;
    } catch (e) {
      setError('删除账户失败: $e');
      return false;
    }
  }

  Future<bool> saveCategory(LedgerCategory category) async {
    try {
      await _service.upsertCategory(category);
      lastMessage.value =
          category.id > 0 ? '类别「${category.name}」已更新' : '类别「${category.name}」已添加';
      await reload();
      return true;
    } catch (e) {
      setError('保存类别失败: $e');
      return false;
    }
  }

  Future<bool> deleteCategory(LedgerCategory category) async {
    try {
      lastMessage.value = await _service.deleteCategory(category.id);
      await reload();
      return true;
    } catch (e) {
      // 内置类别不可删除——这条判定在 Rust，这里只负责把它原样说给用户
      setError('删除类别失败: $e');
      return false;
    }
  }

  Future<void> forgetMerchant(String merchantKey) async {
    try {
      await _service.forgetMerchant(merchantKey);
      merchantMemory.removeWhere((row) => (row['merchant_key'] ?? '').toString() == merchantKey);
      lastMessage.value = '已忘记「$merchantKey」的归类习惯';
    } catch (e) {
      setError('清除归类记忆失败: $e');
    }
  }
}
