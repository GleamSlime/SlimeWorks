import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_manage_editor.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_organize_viewmodel.dart';

/// 分类与标签：把"这笔钱按什么口径归堆"的两条轴放在同一页管理。
///
/// 类别是收支口径的唯一来源（统计、预算、对账都按它聚合），所以它必须留在 Rust 的
/// 库里；标签是跨类别的第二条检索轴，后端还没有这张表，这一页右边那半就地读写
/// 桩仓库，并挂上 [LedgerStubMark] 说明它是演示数据。
class LedgerOrganizeScreen extends BasePage<LedgerOrganizeViewModel> {
  const LedgerOrganizeScreen({super.key});

  @override
  State<LedgerOrganizeScreen> createState() => _LedgerOrganizeScreenState();
}

class _LedgerOrganizeScreenState
    extends BasePageState<LedgerOrganizeViewModel, LedgerOrganizeScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerOrganizeViewModel createViewModel() => LedgerOrganizeViewModel();

  Future<void> _editCategory([
    LedgerCategory? category,
    String direction = kLedgerDirectionExpense,
    int parentId = 0,
  ]) async {
    final result = await showLedgerCategoryEditor(
      context,
      initial: category,
      direction: category?.direction ?? direction,
      // 库里还没有 parent_id 时给空表，编辑器就不画"上级类别"那一栏
      parents: viewModel.hasSubLevels
          ? viewModel.parentCandidates(excludeId: category?.id ?? 0)
          : const <LedgerCategory>[],
      defaultParentId: category == null ? parentId : 0,
    );
    if (result == null) return;
    await viewModel.saveCategory(
      result.id > 0 || result.sortOrder > 0
          ? result
          : result.copyWith(sortOrder: viewModel.nextSortOrder(result.direction)),
    );
  }

  Future<void> _deleteCategory(LedgerCategory category) async {
    final kidCount = viewModel.childrenOf(category.id).length;
    final ok = await showConfirmDialog(
      context,
      title: '删除「${category.name}」？',
      message: category.isBuiltin
          ? '内置类别删不掉，只会告诉你为什么删不掉。'
          : kidCount > 0
              ? '它下面还有 $kidCount 个子类，删掉后这些子类的流水会一起归到"其他支出"。'
              : '它的流水会归到"其他支出"，商户归类记忆一起清掉。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteCategory(category);
  }

  Future<void> _editTagGroup([LedgerTagGroup? group]) async {
    final result = await showLedgerTagGroupEditor(context, initial: group);
    if (result != null) await viewModel.saveTagGroup(result);
  }

  Future<void> _deleteTagGroup(LedgerTagGroup group) async {
    final count = viewModel.tagsOf(group.id).length;
    final ok = await showConfirmDialog(
      context,
      title: '删除分组「${group.name}」？',
      message: count > 0
          ? '组里的 $count 个标签会一起删掉。已经挂在流水上的标签不受影响，'
              '但流水上的那几条引用会指向一个已经不存在的标签。'
          : '这个分组是空的，删掉不影响任何流水。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteTagGroup(group);
  }

  Future<void> _editTag(LedgerTag? tag, {int groupId = 0}) async {
    final result = await showLedgerTagEditor(
      context,
      initial: tag,
      groups: viewModel.tagGroups,
      defaultGroupId: groupId != 0
          ? groupId
          : (viewModel.tagGroups.isEmpty ? 0 : viewModel.tagGroups.first.id),
    );
    if (result != null) await viewModel.saveTag(result);
  }

  Future<void> _deleteTag(LedgerTag tag) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除标签「${tag.name}」？',
      message: tag.useCount > 0
          ? '有 ${tag.useCount} 笔流水挂着它，删除后这些流水就不再带这个标签了。'
          : '它还没挂在任何流水上，删掉不影响已记的账。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteTag(tag);
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '分类与标签',
        leading: appBarBackButton(context, prevRoutePath: '/ledger/settings'),
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: viewModel.reload,
          ),
          SizedBox(width: m.kSpace12),
        ],
      ),
      child: Obx(() => _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    final vm = viewModel;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        _Feedback(vm: vm),
        SectionHeader(
          title: '支出类别',
          subtitle: vm.hasSubLevels ? '点一下改名或换图标，子类挂在父类下面' : null,
          trailing: TextButton.icon(
            onPressed: () => _editCategory(),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
            label: const Text('添加'),
          ),
        ),
        SizedBox(height: m.kSpace4),
        _CategoryTree(
          direction: kLedgerDirectionExpense,
          vm: vm,
          onEdit: _editCategory,
          onDelete: _deleteCategory,
          onAddChild: (parent) => _editCategory(null, kLedgerDirectionExpense, parent.id),
          emptyHint: '内置的餐饮、交通、购物已经在库里，想加"宠物""美发"这种自己建一个。',
        ),
        SizedBox(height: m.kSpace20),
        SectionHeader(
          title: '收入类别',
          subtitle: vm.hasSubLevels ? '工资、报销、利息各归各的' : null,
          trailing: TextButton.icon(
            onPressed: () => _editCategory(null, kLedgerDirectionIncome),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
            label: const Text('添加'),
          ),
        ),
        SizedBox(height: m.kSpace4),
        _CategoryTree(
          direction: kLedgerDirectionIncome,
          vm: vm,
          onEdit: _editCategory,
          onDelete: _deleteCategory,
          onAddChild: (parent) => _editCategory(null, kLedgerDirectionIncome, parent.id),
          emptyHint: '收进来的钱单独一类，统计才不会和支出混在一起。',
        ),
        SizedBox(height: m.kSpace24),
        SectionHeader(
          title: '标签分组',
          subtitle: '标签是跨类别的第二条轴：一笔可以同时挂"出差"和"待报销"',
          trailing: TextButton.icon(
            onPressed: () => _editTagGroup(),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
            label: const Text('添加分组'),
          ),
        ),
        SizedBox(height: m.kSpace8),
        const LedgerStubMark(text: '标签是演示数据 · 后端未接入，删它不会改动已入账的流水'),
        SizedBox(height: m.kSpace12),
        if (vm.tagGroups.isEmpty && vm.ungroupedTags.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('还没有标签', style: AppTextStyles.rowTitle(context)),
                SizedBox(height: m.kSpace6),
                Text(
                  '类别只能单选，标签想挂几个挂几个。出差报销、分摊、给谁买的——'
                  '这类"不属于分类但一定要筛出来"的口子都靠它。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                FilledButton.tonal(
                  onPressed: () => _editTagGroup(),
                  child: const Text('添加第一个分组'),
                ),
              ],
            ),
          )
        else ...<Widget>[
          for (final group in vm.tagGroups) ...<Widget>[
            _TagGroupCard(
              group: group,
              tags: vm.tagsOf(group.id),
              onEditGroup: () => _editTagGroup(group),
              onDeleteGroup: () => _deleteTagGroup(group),
              onAddTag: () => _editTag(null, groupId: group.id),
              onEditTag: (tag) => _editTag(tag),
              onDeleteTag: _deleteTag,
            ),
            SizedBox(height: m.kSpace12),
          ],
          if (vm.ungroupedTags.isNotEmpty) ...<Widget>[
            _UngroupedCard(
              tags: vm.ungroupedTags,
              onEditTag: (tag) => _editTag(tag),
              onDeleteTag: _deleteTag,
            ),
            SizedBox(height: m.kSpace12),
          ],
        ],
        if (vm.tags.isNotEmpty) ...<Widget>[
          SizedBox(height: m.kSpace4),
          Text(
            vm.tagsInUse > 0
                ? '${vm.tags.length} 个标签，一共挂在 ${vm.tagsInUse} 笔流水上'
                : '${vm.tags.length} 个标签，还没有挂到任何流水上',
            style: AppTextStyles.caption(context),
          ),
        ],
      ],
    );
  }
}

/// 一次写操作的回执 / 读失败
class _Feedback extends StatelessWidget {
  const _Feedback({required this.vm});

  final LedgerOrganizeViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final error = vm.errorMessage;
    if (error != null && vm.categories.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: m.kSpace12),
        child: Row(
          children: <Widget>[
            DrawIcon(StrokeIcons.error, size: m.iconSize16, color: s.danger.color),
            SizedBox(width: m.kSpace8),
            Expanded(child: Text(error, style: AppTextStyles.caption(context))),
          ],
        ),
      );
    }
    if (vm.lastMessage.value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace12),
      child: Row(
        children: <Widget>[
          DrawIcon(StrokeIcons.checkCircle, size: m.iconSize16, color: s.success.color),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Text(
              vm.lastMessage.value,
              style: AppTextStyles.caption(context).copyWith(color: s.success.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一方向的类别：有第二级就铺成树，没有就平铺
class _CategoryTree extends StatelessWidget {
  const _CategoryTree({
    required this.direction,
    required this.vm,
    required this.onEdit,
    required this.onDelete,
    required this.onAddChild,
    required this.emptyHint,
  });

  final String direction;
  final LedgerOrganizeViewModel vm;
  final ValueChanged<LedgerCategory> onEdit;
  final ValueChanged<LedgerCategory> onDelete;
  final ValueChanged<LedgerCategory> onAddChild;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final flat = vm.flatOf(direction);
    if (flat.isEmpty) {
      return Text(emptyHint, style: AppTextStyles.caption(context));
    }
    // 后端还没有 parent_id：全是根类别时直接平铺，不留一层空缩进
    if (!vm.hasSubLevels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final category in flat)
            _CategoryRow(
              category: category,
              vm: vm,
              onEdit: () => onEdit(category),
              onDelete: () => onDelete(category),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final parent in vm.roots(direction)) ...<Widget>[
          _CategoryRow(
            category: parent,
            vm: vm,
            onEdit: () => onEdit(parent),
            onDelete: () => onDelete(parent),
            onAddChild: () => onAddChild(parent),
          ),
          for (final child in vm.childrenOf(parent.id))
            Padding(
              padding: EdgeInsets.only(left: m.kSpace20),
              child: _CategoryRow(
                category: child,
                vm: vm,
                child: true,
                onEdit: () => onEdit(child),
                onDelete: () => onDelete(child),
              ),
            ),
        ],
        // 挂在已经不存在的父类上的孤儿：宁可显式列出来，也不让它静默消失
        for (final orphan in flat.where((c) => !c.isRoot && vm.categoryById(c.parentId) == null))
          _CategoryRow(
            category: orphan,
            vm: vm,
            child: true,
            onEdit: () => onEdit(orphan),
            onDelete: () => onDelete(orphan),
          ),
      ],
    );
  }
}

/// 一行类别：图标 + 名字 +（内置）+ 动作
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.vm,
    required this.onEdit,
    required this.onDelete,
    this.onAddChild,
    this.child = false,
  });

  final LedgerCategory category;
  final LedgerOrganizeViewModel vm;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 只有父类行有：子类不能再生子类，口径只做两级
  final VoidCallback? onAddChild;
  final bool child;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      // 图标按钮没有文字，测试只能按 key 定位到某一行的动作
      key: ValueKey<String>('category-row:${category.id}'),
      onTap: onEdit,
      borderRadius: m.radius6,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace6, horizontal: m.kSpace2),
        child: Row(
          children: <Widget>[
            if (child)
              Padding(
                padding: EdgeInsets.only(right: m.kSpace8),
                child: DrawIcon(
                  StrokeIcons.chevronRight,
                  size: m.iconSize12,
                  color: s.textTertiary,
                ),
              )
            else
              LedgerIconBadge(
                iconKey: category.icon,
                income: category.isIncome,
                size: m.kSpace24,
              ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    category.name,
                    style: AppTextStyles.rowTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (child && category.parentId != 0) ...<Widget>[
                    SizedBox(height: m.kSpace2),
                    Text(
                      '父类：${vm.categoryById(category.parentId)?.name ?? '已删除的类别'}',
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ],
              ),
            ),
            if (category.isBuiltin) ...<Widget>[
              SizedBox(width: m.kSpace8),
              const StatusChip(label: '内置', tone: Tone.neutral),
            ],
            if (onAddChild != null)
              ToolIconButton(
                icon: StrokeIcons.add,
                tooltip: '添加子类',
                size: m.iconSize16,
                onPressed: onAddChild,
              ),
            ToolIconButton(
              icon: StrokeIcons.delete,
              tooltip: '删除',
              size: m.iconSize16,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个标签分组：组头 + 组内标签
class _TagGroupCard extends StatelessWidget {
  const _TagGroupCard({
    required this.group,
    required this.tags,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onAddTag,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final LedgerTagGroup group;
  final List<LedgerTag> tags;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final VoidCallback onAddTag;
  final ValueChanged<LedgerTag> onEditTag;
  final ValueChanged<LedgerTag> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final tint = ledgerColorOf(group.color, fallback: s.textSecondary);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: m.kSpace12,
                height: m.kSpace12,
                decoration: BoxDecoration(color: tint, borderRadius: m.radius6),
              ),
              SizedBox(width: m.kSpace10),
              Expanded(
                child: Text(
                  group.name,
                  style: AppTextStyles.rowTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                tags.isEmpty ? '空分组' : '${tags.length} 个标签',
                style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
              ),
              SizedBox(width: m.kSpace4),
              ToolIconButton(
                icon: StrokeIcons.add,
                tooltip: '在这个分组里加标签',
                size: m.iconSize16,
                onPressed: onAddTag,
              ),
              ToolIconButton(
                icon: StrokeIcons.edit,
                tooltip: '改名字或颜色',
                size: m.iconSize16,
                onPressed: onEditGroup,
              ),
              ToolIconButton(
                icon: StrokeIcons.delete,
                tooltip: '删除分组',
                size: m.iconSize16,
                onPressed: onDeleteGroup,
              ),
            ],
          ),
          if (tags.isNotEmpty) ...<Widget>[
            SizedBox(height: m.kSpace10),
            Wrap(
              spacing: m.kSpace8,
              runSpacing: m.kSpace8,
              children: <Widget>[
                for (final tag in tags)
                  LedgerTagChip(
                    label: tag.useCount > 0 ? '${tag.name} · ${tag.useCount}笔' : tag.name,
                    tint: ledgerColorOf(
                      tag.color.isNotEmpty ? tag.color : group.color,
                      fallback: s.textSecondary,
                    ),
                    onTap: () => onEditTag(tag),
                    onRemove: () => onDeleteTag(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 没归组的标签：就地新建标签时还没有任何分组，就会落在这里
class _UngroupedCard extends StatelessWidget {
  const _UngroupedCard({
    required this.tags,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final List<LedgerTag> tags;
  final ValueChanged<LedgerTag> onEditTag;
  final ValueChanged<LedgerTag> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('未分组', style: AppTextStyles.rowTitle(context)),
          SizedBox(height: m.kSpace4),
          Text(
            '点开编辑可以给它选一个分组。',
            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: m.kSpace10),
          Wrap(
            spacing: m.kSpace8,
            runSpacing: m.kSpace8,
            children: <Widget>[
              for (final tag in tags)
                LedgerTagChip(
                  label: tag.useCount > 0 ? '${tag.name} · ${tag.useCount}笔' : tag.name,
                  tint: tag.color.isEmpty
                      ? null
                      : ledgerColorOf(tag.color, fallback: s.textSecondary),
                  onTap: () => onEditTag(tag),
                  onRemove: () => onDeleteTag(tag),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
