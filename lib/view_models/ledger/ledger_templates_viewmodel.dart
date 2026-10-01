import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 模板与定时记账页。
///
/// 两样都在 [LedgerStubStore]：后端还没有 `tx_templates` / `schedules` 两张表，
/// 界面上必须挂"演示数据"水印。但它们要记的那笔账是真的——点模板记下来的流水
/// 直接进 Rust 的账本，所以这一页不能整页标成演示，只有模板和规则那两块要标。
class LedgerTemplatesViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();
  final LedgerStubStore _store = LedgerStubStore.instance;

  final RxList<LedgerTxTemplate> templates = <LedgerTxTemplate>[].obs;
  final RxList<LedgerSchedule> schedules = <LedgerSchedule>[].obs;

  /// 模板点开编辑器时要选的账户与类别，页面自己不查库
  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;

  final RxString lastMessage = ''.obs;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await _store.init();
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      templates.assignAll(await _store.listTxTemplates());
      schedules.assignAll(await _store.listSchedules());
      accounts.assignAll(await _service.listAccounts());
      categories.assignAll(await _service.listCategories());
      clearError();
    } catch (e) {
      setError('读取模板与定时规则失败: $e');
    } finally {
      setLoading(false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 模板
  // ─────────────────────────────────────────────────────────────────────────

  /// 用得多的排前面：这张列表的意义就是"最常按的那几颗按钮"
  ///
  /// 同次数一定要再按名字钉死：`List.sort` 不是稳定排序，只比次数的话同样常用的两张
  /// 卡片每次刷新都可能换位置，出图基线也跟着一起红。
  List<LedgerTxTemplate> get sortedTemplates {
    final list = templates.toList();
    list.sort((a, b) {
      final byUse = b.useCount.compareTo(a.useCount);
      return byUse != 0 ? byUse : a.title.compareTo(b.title);
    });
    return list;
  }

  int get totalUses => templates.fold<int>(0, (sum, t) => sum + t.useCount);

  /// 挂在这张模板上的定时规则：删模板前要先说清会带走几条
  List<LedgerSchedule> schedulesOf(int templateId) =>
      schedules.where((s) => s.templateId == templateId).toList(growable: false);

  LedgerAccount? accountOf(int id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 模板里存的账户可能已经被删了（桩阶段没有外键拦着），这时候按名字也认一次
  LedgerAccount? accountOfTemplate(LedgerTxTemplate t) {
    final byId = accountOf(t.accountId);
    if (byId != null) return byId;
    for (final a in accounts) {
      if (a.name == t.accountName) return a;
    }
    return null;
  }

  /// 模板能不能直接记：账户没了就记不了，界面上要挡住而不是弹个错
  bool canUse(LedgerTxTemplate t) => t.accountId == 0 || accountOfTemplate(t) != null;

  Future<bool> deleteTemplate(LedgerTxTemplate template) async {
    try {
      final tied = schedulesOf(template.id).length;
      await _store.deleteTxTemplate(template.id);
      lastMessage.value = tied > 0
          ? '模板「${template.title}」已删除，挂在它上面的 $tied 条定时规则一起删了'
          : '模板「${template.title}」已删除';
      await reload();
      return true;
    } catch (e) {
      setError('删除模板失败: $e');
      return false;
    }
  }

  /// 按模板记下来的一笔：日期取当天，其余字段照抄
  LedgerTx draftOf(LedgerTxTemplate template) {
    final now = DateTime.now();
    final date = ledgerDateOf(now);
    return template.toDraft(
      billDate: date,
      occurredAt: '$date ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00',
    );
  }

  Future<void> markUsed(LedgerTxTemplate template) async {
    await _store.markTemplateUsed(template.id);
    await reload();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 定时规则
  // ─────────────────────────────────────────────────────────────────────────

  List<LedgerSchedule> get sortedSchedules {
    final list = schedules.toList();
    // 开着的排前面：这一页要看的第一件事是"接下来会跑什么"
    list.sort((a, b) {
      if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
      final byNext = a.nextRunAt.compareTo(b.nextRunAt);
      // 同一个点上的两条规则再按名字钉死，理由和上面一样
      return byNext != 0 ? byNext : a.name.compareTo(b.name);
    });
    return list;
  }

  int get runningSchedules => schedules.where((s) => s.enabled).length;

  Future<bool> saveSchedule(LedgerSchedule schedule) async {
    try {
      await _store.upsertSchedule(schedule);
      lastMessage.value = schedule.id > 0
          ? '规则「${schedule.name}」已更新'
          : '规则「${schedule.name}」已添加';
      await reload();
      return true;
    } catch (e) {
      setError('保存规则失败: $e');
      return false;
    }
  }

  Future<bool> toggleSchedule(LedgerSchedule schedule) async {
    try {
      await _store.setScheduleEnabled(schedule.id, !schedule.enabled);
      lastMessage.value = schedule.enabled
          ? '规则「${schedule.name}」已停用，到点不会记账'
          : '规则「${schedule.name}」已启用';
      await reload();
      return true;
    } catch (e) {
      setError('切换规则状态失败: $e');
      return false;
    }
  }

  Future<bool> deleteSchedule(LedgerSchedule schedule) async {
    try {
      await _store.deleteSchedule(schedule.id);
      lastMessage.value = '规则「${schedule.name}」已删除';
      await reload();
      return true;
    } catch (e) {
      setError('删除规则失败: $e');
      return false;
    }
  }
}
