import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/components/ledger_manage_editor.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_accounts_viewmodel.dart';

/// 账户与类别：卡/钱包、收支类别、商户自动归类的记忆表。
///
/// 删除操作的影响面由 Rust 决定并返回中文说明（"这个账户还有 N 笔流水，已改为停用"），
/// 这一页只负责把那段说明原样显示出来——界面自己猜后果，就会和库里的实际状态对不上。
class LedgerAccountsScreen extends BasePage<LedgerAccountsViewModel> {
  const LedgerAccountsScreen({super.key});

  @override
  State<LedgerAccountsScreen> createState() => _LedgerAccountsScreenState();
}

class _LedgerAccountsScreenState
    extends BasePageState<LedgerAccountsViewModel, LedgerAccountsScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerAccountsViewModel createViewModel() => LedgerAccountsViewModel();

  Future<void> _editAccount([LedgerAccount? account]) async {
    final result = await showLedgerAccountEditor(context, initial: account);
    if (result != null) await viewModel.saveAccount(result);
  }

  Future<void> _editCategory([
    LedgerCategory? category,
    String direction = kLedgerDirectionExpense,
  ]) async {
    final result = await showLedgerCategoryEditor(
      context,
      initial: category,
      direction: category?.direction ?? direction,
    );
    if (result != null) await viewModel.saveCategory(result);
  }

  Future<void> _deleteAccount(LedgerAccount account) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除「${account.name}」？',
      message: '已经记在这上面的流水不会被删。如果它还有流水，这里会变成"改为停用"。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteAccount(account);
  }

  Future<void> _deleteCategory(LedgerCategory category) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除「${category.name}」？',
      message: category.isBuiltin
          ? '内置类别删不掉，只会告诉你为什么删不掉。'
          : '它的流水会归到"其他支出"，商户归类记忆一起清掉。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteCategory(category);
  }

  Future<void> _forgetMerchant(String key) async {
    final ok = await showConfirmDialog(
      context,
      title: '忘记这条归类习惯？',
      message: '下次再遇到「$key」就要手动选类别了。已经入账的流水不受影响。',
      confirmLabel: '忘记',
    );
    if (ok) await viewModel.forgetMerchant(key);
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '账户与类别',
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final vm = viewModel;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        if (vm.errorMessage != null && vm.accounts.isEmpty)
          _Notice(text: vm.errorMessage!, danger: true)
        else if (vm.lastMessage.value.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: m.kSpace8),
            child: Text(
              vm.lastMessage.value,
              style: AppTextStyles.caption(context).copyWith(color: s.success.color),
            ),
          ),
        SectionHeader(
          title: '账户',
          subtitle: '信用卡、储蓄卡、现金钱包——记一笔时选的就是这些',
          trailing: FilledButton.icon(
            onPressed: () => _editAccount(),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
            label: const Text('添加账户'),
          ),
        ),
        if (vm.accounts.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('还没有账户', style: AppTextStyles.rowTitle(context)),
                SizedBox(height: m.kSpace6),
                Text(
                  '至少建一个，流水才知道记在哪张卡上。邮件账单转进来的那几笔，'
                  '也会落到邮箱规则里指定的默认账户。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                FilledButton.tonal(onPressed: () => _editAccount(), child: const Text('添加第一个账户')),
              ],
            ),
          )
        else
          for (final account in vm.accounts) ...<Widget>[
            _AccountCard(
              account: account,
              onEdit: () => _editAccount(account),
              onToggle: () => vm.toggleAccount(account),
              onDelete: () => _deleteAccount(account),
            ),
            SizedBox(height: m.kSpace10),
          ],
        SizedBox(height: m.kSpace12),
        _CategorySection(
          title: '支出类别',
          categories: vm.expenseCategories(),
          onAdd: () => _editCategory(),
          onEdit: _editCategory,
          onDelete: _deleteCategory,
          emptyHint: '内置类别删不掉，自己加的几个想改图标、改名都在这里。',
        ),
        SizedBox(height: m.kSpace20),
        _CategorySection(
          title: '收入类别',
          categories: vm.incomeCategories(),
          onAdd: () => _editCategory(null, kLedgerDirectionIncome),
          onEdit: _editCategory,
          onDelete: _deleteCategory,
          emptyHint: '工资、报销、利息——收进来的钱单独一类，统计才不会和支出混在一起。',
        ),
        SizedBox(height: m.kSpace20),
        _MerchantMemorySection(
          rows: vm.merchantMemory,
          nameOf: vm.categoryNameOf,
          onForget: _forgetMerchant,
        ),
      ],
    );
  }
}

/// 一个账户：余额 + 启停 + 编辑/删除
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final LedgerAccount account;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final detail = <String>[
      ledgerAccountTypeLabel(account.type),
      if (account.displaySuffix.isNotEmpty) account.displaySuffix,
      if (account.creditLimit > 0) '额度 ${formatLedgerAmount(account.creditLimit)}',
      if (!account.enabled) '已停用',
    ].join('  ·  ');
    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: m.kSpace32,
                height: m.kSpace32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.surfaceHover,
                  borderRadius: m.radius8,
                ),
                child: DrawIcon(
                  ledgerAccountIconOf(account.type),
                  size: m.iconSize18,
                  color: account.enabled ? s.textSecondary : s.textTertiary,
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      account.name,
                      style: AppTextStyles.rowTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: m.kSpace2),
                    Text(
                      detail,
                      style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.kSpace12),
              LedgerAmountText(amount: account.balance, income: false, signed: false),
            ],
          ),
          SizedBox(height: m.kSpace10),
          Row(
            children: <Widget>[
              // 停用而不是删除：让老数据留在原处，只是不再出现在记一笔的选项里
              Switch(value: account.enabled, onChanged: (_) => onToggle()),
              SizedBox(width: m.kSpace6),
              Text('启用', style: AppTextStyles.caption(context)),
              const Spacer(),
              TextButton.icon(
                onPressed: onEdit,
                icon: DrawIcon(StrokeIcons.edit, size: m.iconSize14),
                label: const Text('编辑'),
              ),
              SizedBox(width: m.kSpace4),
              TextButton.icon(
                onPressed: onDelete,
                icon: DrawIcon(StrokeIcons.delete, size: m.iconSize14, color: s.danger.color),
                label: Text(
                  '删除',
                  style: AppTextStyles.caption(context).copyWith(color: s.danger.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一组类别：胶囊平铺，点=改，长按=删
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.categories,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.emptyHint,
  });

  final String title;
  final List<LedgerCategory> categories;
  final VoidCallback onAdd;
  final ValueChanged<LedgerCategory> onEdit;
  final ValueChanged<LedgerCategory> onDelete;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: title,
          // 空类别时解释只留下面那一行：这里再写一遍就是同一句话上下刷两次
          subtitle: categories.isEmpty ? null : '点一下改名或换图标，长按删除',
          trailing: TextButton.icon(
            onPressed: onAdd,
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
            label: const Text('添加'),
          ),
        ),
        if (categories.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: m.kSpace4),
            child: Text(emptyHint, style: AppTextStyles.caption(context)),
          )
        else
          Padding(
            padding: EdgeInsets.only(top: m.kSpace4),
            child: Wrap(
              spacing: m.kSpace8,
              runSpacing: m.kSpace8,
              children: <Widget>[
                for (final category in categories)
                  _CategoryChip(
                    category: category,
                    onTap: () => onEdit(category),
                    onLongPress: () => onDelete(category),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerCategory category;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Tooltip(
      message: category.isBuiltin ? '${category.name}（内置，不可删除）' : category.name,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: m.radiusPill,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace6),
          decoration: BoxDecoration(
            color: s.surfaceSunken,
            borderRadius: m.radiusPill,
            border: Border.all(color: s.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LedgerIconBadge(
                iconKey: category.icon,
                income: category.isIncome,
                size: m.kSpace24,
              ),
              SizedBox(width: m.kSpace8),
              Text(category.name, style: AppTextStyles.body(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 商户 → 类别 的记忆表：记账时自动猜类别的那张表，看得见也擦得掉
class _MerchantMemorySection extends StatelessWidget {
  const _MerchantMemorySection({
    required this.rows,
    required this.nameOf,
    required this.onForget,
  });

  final List<Map<String, dynamic>> rows;
  final String Function(int) nameOf;
  final ValueChanged<String> onForget;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: '自动归类习惯',
          subtitle: rows.isEmpty
              ? '确认过几笔之后，这里会记下"某个商户通常算哪一类"，之后同类商户自动归好。'
              : '猜错了就在这里改掉或删掉，下一笔重新学',
          dense: true,
        ),
        if (rows.isNotEmpty)
          AppCard(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace6),
            child: Column(
              children: <Widget>[
                for (final row in rows)
                  Builder(builder: (context) {
                    final key = (row['merchant_key'] ?? '').toString();
                    final categoryId = (row['category_id'] as num?)?.toInt() ?? 0;
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: m.kSpace6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              key,
                              style: AppTextStyles.rowTitle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: m.kSpace12),
                          Text(
                            nameOf(categoryId),
                            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
                          ),
                          SizedBox(width: m.kSpace6),
                          ToolIconButton(
                            icon: StrokeIcons.close,
                            tooltip: '忘记这条习惯',
                            size: m.iconSize16,
                            onPressed: () => onForget(key),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一行提示：成功回执用中性色，失败才用报警色
class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace8),
      child: Row(
        children: <Widget>[
          DrawIcon(
            danger ? StrokeIcons.error : StrokeIcons.checkCircle,
            size: m.iconSize16,
            color: danger ? s.danger.color : s.success.color,
          ),
          SizedBox(width: m.kSpace8),
          Expanded(child: Text(text, style: AppTextStyles.caption(context))),
        ],
      ),
    );
  }
}
