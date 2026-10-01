import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 分类与标签管理页。
///
/// 这一页的左右两半来自两个地方：类别在 Rust（流水的外键指着它，必须和账本同库），
/// 标签还在 Dart 桩仓库（后端没有这张表）。所以写操作一半走 [LedgerService]、
/// 一半走 [LedgerStubStore]，而右边那半在界面上必须挂水印——不然用户会以为
/// 在这里删掉标签，就已经入过账的那几笔也跟着变了。
class LedgerOrganizeViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();
  final LedgerStubStore _tags = LedgerStubStore.instance;

  final RxList<LedgerCategory> categories = <LedgerCategory>[].obs;
  final RxList<LedgerTagGroup> tagGroups = <LedgerTagGroup>[].obs;
  final RxList<LedgerTag> tags = <LedgerTag>[].obs;

  /// 最近一次写操作的中文回执，页面就地显示在对应分区顶上
  final RxString lastMessage = ''.obs;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await _tags.init();
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      categories.assignAll(await _service.listCategories());
      tagGroups.assignAll(await _tags.listTagGroups());
      tags.assignAll(await _tags.listTags());
      clearError();
    } catch (e) {
      setError('读取分类与标签失败: $e');
    } finally {
      setLoading(false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 类别：两级树
  // ─────────────────────────────────────────────────────────────────────────

  List<LedgerCategory> roots(String direction) => categories
      .where((c) => c.direction == direction && c.isRoot)
      .toList(growable: false);

  List<LedgerCategory> childrenOf(int parentId) =>
      categories.where((c) => c.parentId == parentId).toList(growable: false);

  /// 平铺的类别（后端还没有 parent_id 列时就是这个形态）
  List<LedgerCategory> flatOf(String direction) =>
      categories.where((c) => c.direction == direction).toList(growable: false);

  /// 库里有没有第二级。为 false 时"上级类别"那一栏和「添加子类」都不出现——
  /// 摆一个点了也不生效的控件，比不给这个功能更容易骗人。
  bool get hasSubLevels => categories.any((c) => !c.isRoot);

  /// 上级候选：只能是根类别，且不能是自己（自己当自己的父类会让树打结）
  List<LedgerCategory> parentCandidates({int excludeId = 0}) => categories
      .where((c) => c.isRoot && c.id != excludeId)
      .toList(growable: false);

  /// 新类别排到同方向末尾：Rust 按 sort_order 出序，给 0 就全挤在最前面
  int nextSortOrder(String direction) {
    var max = 0;
    for (final c in categories) {
      if (c.direction == direction && c.sortOrder > max) max = c.sortOrder;
    }
    return max + 1;
  }

  LedgerCategory? categoryById(int id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
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
      // 影响面（几笔流水归去哪）由 Rust 算，这里原样透出，界面不自己猜
      lastMessage.value = await _service.deleteCategory(category.id);
      await reload();
      return true;
    } catch (e) {
      setError('删除类别失败: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 标签与分组：桩仓库
  // ─────────────────────────────────────────────────────────────────────────

  List<LedgerTag> tagsOf(int groupId) =>
      tags.where((t) => t.groupId == groupId).toList(growable: false);

  /// groupId=0 的漏网标签：在挑标签对话框里就地新建、当时还没有任何分组时会落到这里
  List<LedgerTag> get ungroupedTags => tagsOf(0);

  String groupNameOf(int groupId) {
    for (final g in tagGroups) {
      if (g.id == groupId) return g.name;
    }
    return '未分组';
  }

  int get tagsInUse => tags.fold<int>(0, (sum, t) => sum + t.useCount);

  Future<bool> saveTagGroup(LedgerTagGroup group) async {
    try {
      await _tags.upsertTagGroup(group);
      lastMessage.value = group.id > 0 ? '分组「${group.name}」已更新' : '分组「${group.name}」已添加';
      await reload();
      return true;
    } catch (e) {
      setError('保存分组失败: $e');
      return false;
    }
  }

  Future<bool> deleteTagGroup(LedgerTagGroup group) async {
    try {
      await _tags.deleteTagGroup(group.id);
      lastMessage.value = '分组「${group.name}」和组里的 ${tagsOf(group.id).length} 个标签已删除';
      await reload();
      return true;
    } catch (e) {
      setError('删除分组失败: $e');
      return false;
    }
  }

  Future<bool> saveTag(LedgerTag tag) async {
    try {
      await _tags.upsertTag(tag);
      lastMessage.value = tag.id > 0 ? '标签「${tag.name}」已更新' : '标签「${tag.name}」已添加';
      await reload();
      return true;
    } catch (e) {
      setError('保存标签失败: $e');
      return false;
    }
  }

  Future<bool> deleteTag(LedgerTag tag) async {
    try {
      await _tags.deleteTag(tag.id);
      lastMessage.value = '标签「${tag.name}」已删除';
      await reload();
      return true;
    } catch (e) {
      setError('删除标签失败: $e');
      return false;
    }
  }
}
