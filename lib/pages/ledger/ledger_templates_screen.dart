import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/pages/ledger/components/ledger_manage_editor.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_templates_viewmodel.dart';

/// 模板与定时记账：把"每个月都要重填一遍的那几笔"从手工里拿出来。
///
/// 两样数据都还在 [LedgerStubStore]，所以块头挂水印；但点模板记下来的那一笔走的是
/// 真账（Rust 的账本），水印只说"模板这张草稿是演示的"，不说"记的账是假的"。
class LedgerTemplatesScreen extends BasePage<LedgerTemplatesViewModel> {
  const LedgerTemplatesScreen({super.key});

  @override
  State<LedgerTemplatesScreen> createState() => _LedgerTemplatesScreenState();
}

class _LedgerTemplatesScreenState
    extends BasePageState<LedgerTemplatesViewModel, LedgerTemplatesScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerTemplatesViewModel createViewModel() => LedgerTemplatesViewModel();

  /// 用一次：拿模板开一单，日期已经是今天，改个金额就能记
  Future<void> _useTemplate(LedgerTxTemplate template) async {
    final tx = await showLedgerTxEditor(
      context,
      initial: viewModel.draftOf(template),
      accounts: viewModel.accounts,
      categories: viewModel.categories,
    );
    if (tx == null) return;
    if (!mounted) return;
    final saved = await ledgerCommitTx(context, tx);
    if (saved) await viewModel.markUsed(template);
  }

  /// 改模板：同一个表单，只是保存的去处从账本换成模板仓库
  Future<void> _editTemplate(LedgerTxTemplate template) async {
    final result = await showLedgerTxEditor(
      context,
      initial: viewModel.draftOf(template),
      asTemplate: template,
      accounts: viewModel.accounts,
      categories: viewModel.categories,
    );
    if (result != null) await viewModel.reload();
  }

  Future<void> _deleteTemplate(LedgerTxTemplate template) async {
    final tied = viewModel.schedulesOf(template.id).length;
    final ok = await showConfirmDialog(
      context,
      title: '删除模板「${template.title}」？',
      message: tied > 0
          ? '有 $tied 条定时规则挂着它，删掉之后这些规则也一起没了。已经记过的账不受影响。'
          : '已经记过的账不受影响，只是下次还得重填。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteTemplate(template);
  }

  Future<void> _editSchedule([LedgerSchedule? schedule]) async {
    if (viewModel.templates.isEmpty) {
      // 只有确认框可用，那就让主按钮真的去做缺的那件事，而不是摆一颗只会关窗的「知道了」
      final go = await showConfirmDialog(
        context,
        title: '还没有模板',
        message: '定时规则到点照哪张模板记账？先记一笔并勾上"存为模板"，回来就能建规则了。',
        confirmLabel: '去记一笔',
        cancelLabel: '知道了',
      );
      if (go && mounted) await ledgerQuickAdd(context);
      return;
    }
    final result = await showLedgerScheduleEditor(
      context,
      initial: schedule,
      templates: viewModel.templates,
    );
    if (result != null) await viewModel.saveSchedule(result);
  }

  Future<void> _deleteSchedule(LedgerSchedule schedule) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除规则「${schedule.name}」？',
      message: '只是不再到点自动记，模板和已经记下的账都还在。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteSchedule(schedule);
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '模板与定时',
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
          title: '模板',
          subtitle: '点一下就带着这些值开一单，改完确认才入账',
        ),
        SizedBox(height: m.kSpace4),
        if (vm.templates.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('还没有模板', style: AppTextStyles.rowTitle(context)),
                SizedBox(height: m.kSpace6),
                Text(
                  '模板就是"下次还要填一遍的那一笔"。记一笔的时候勾一下"存为模板"，'
                  '它就出现在这里，以后点一下就是一单。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                FilledButton.tonal(
                  onPressed: () => ledgerQuickAdd(context),
                  child: const Text('去记一笔'),
                ),
              ],
            ),
          )
        else
          for (final template in vm.sortedTemplates) ...<Widget>[
            _TemplateCard(
              template: template,
              usable: vm.canUse(template),
              onUse: () => _useTemplate(template),
              onEdit: () => _editTemplate(template),
              onDelete: () => _deleteTemplate(template),
            ),
            SizedBox(height: m.kSpace10),
          ],
        if (vm.templates.isNotEmpty) ...<Widget>[
          Padding(
            padding: EdgeInsets.only(top: m.kSpace4),
            child: Text(
              vm.totalUses > 0
                  ? '${vm.templates.length} 张模板，一共按过 ${vm.totalUses} 次'
                  : '${vm.templates.length} 张模板，还没有用过',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
        SizedBox(height: m.kSpace24),
        SectionHeader(
          title: '定时记账',
          subtitle: '到点照模板记一笔，进的是待确认还是已入账由下面的开关决定',
          trailing: FilledButton.icon(
            onPressed: () => _editSchedule(),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
            label: const Text('新建规则'),
          ),
        ),
        SizedBox(height: m.kSpace8),
        const LedgerStubMark(
          text: '模板与规则是演示数据 · 后端未接入；按模板记下来的那一笔是真账',
        ),
        SizedBox(height: m.kSpace12),
        if (vm.schedules.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('还没有定时规则', style: AppTextStyles.rowTitle(context)),
                SizedBox(height: m.kSpace6),
                Text(
                  '房租、会员续费、每月 15 号的话费——这类日期比金额更确定的账，'
                  '配一条规则就不用惦记了。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                FilledButton.tonal(
                  onPressed: () => _editSchedule(),
                  child: const Text('新建第一条规则'),
                ),
              ],
            ),
          )
        else
          for (final schedule in vm.sortedSchedules) ...<Widget>[
            _ScheduleCard(
              schedule: schedule,
              onToggle: () => vm.toggleSchedule(schedule),
              onEdit: () => _editSchedule(schedule),
              onDelete: () => _deleteSchedule(schedule),
            ),
            SizedBox(height: m.kSpace12),
          ],
        if (vm.schedules.isNotEmpty) ...<Widget>[
          Padding(
            padding: EdgeInsets.only(top: m.kSpace4),
            child: Text(
              vm.runningSchedules > 0
                  ? '${vm.schedules.length} 条规则，${vm.runningSchedules} 条在跑'
                  : '${vm.schedules.length} 条规则，全部停着，到点不会记账',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// 一次写操作的回执 / 读失败
class _Feedback extends StatelessWidget {
  const _Feedback({required this.vm});

  final LedgerTemplatesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final error = vm.errorMessage;
    if (error != null && vm.templates.isEmpty && vm.schedules.isEmpty) {
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

/// 一张模板：左边按下去就是"用一次"，右边的笔是"改这张模板本身"
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.usable,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final LedgerTxTemplate template;
  final bool usable;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 转账的"金额"没有收支方向，所以它不带正负号，钱去哪写在标题行里
  bool get _isTransfer => template.isTransfer;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final parts = <String>[
      if (template.accountName.isNotEmpty) template.accountName,
      if (_isTransfer)
        '转到${template.destAccountName.isEmpty ? '另一个账户' : template.destAccountName}'
      else if (template.categoryName.isNotEmpty)
        template.categoryName,
      if (template.merchant.isNotEmpty) template.merchant,
    ];
    return AppCard(
      child: InkWell(
        // 测试要按 id 找到某一张卡片的动作按钮，图标按钮没有文字可匹配
        key: ValueKey<String>('template-card:${template.id}'),
        onTap: onUse,
        borderRadius: m.radius8,
        child: Row(
          children: <Widget>[
            LedgerIconBadge(
              iconKey: template.categoryIcon,
              income: template.isIncome,
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          template.title.isEmpty ? '（没有名字）' : template.title,
                          style: AppTextStyles.rowTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!usable) ...<Widget>[
                        SizedBox(width: m.kSpace6),
                        const StatusChip(label: '账户没了', tone: Tone.warning),
                      ],
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    parts.isEmpty ? ledgerTxTypeName(template.txType) : parts.join(' · '),
                    style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    template.useCount > 0 ? '用过 ${template.useCount} 次' : '还没用过',
                    style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
                  ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace8),
            LedgerAmountText(
              amount: template.amount,
              income: template.isIncome,
              signed: !_isTransfer,
              size: LedgerAmountSize.dense,
              toneColor: _isTransfer ? s.textSecondary : null,
            ),
            SizedBox(width: m.kSpace4),
            ToolIconButton(
              icon: StrokeIcons.edit,
              tooltip: '改这张模板',
              size: m.iconSize16,
              onPressed: onEdit,
            ),
            ToolIconButton(
              icon: StrokeIcons.delete,
              tooltip: '删除模板',
              size: m.iconSize16,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条定时规则：开关就在卡片上，"下次"是推算出来的预览
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final LedgerSchedule schedule;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  schedule.name,
                  style: AppTextStyles.rowTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!schedule.enabled) const StatusChip(label: '已停用', tone: Tone.neutral),
              Switch(value: schedule.enabled, onChanged: (_) => onToggle()),
              ToolIconButton(
                icon: StrokeIcons.edit,
                tooltip: '编辑规则',
                size: m.iconSize16,
                onPressed: onEdit,
              ),
              ToolIconButton(
                icon: StrokeIcons.delete,
                tooltip: '删除规则',
                size: m.iconSize16,
                onPressed: onDelete,
              ),
            ],
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '${schedule.whenLabel} · 模板「${schedule.templateTitle}」',
            style: AppTextStyles.body(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: m.kSpace6),
          Text(
            _nextLabel,
            style: AppTextStyles.caption(context).copyWith(
              color: schedule.enabled ? s.textSecondary : s.textTertiary,
            ),
          ),
          SizedBox(height: m.kSpace2),
          Text(
            '到点由本机的调度器执行 · 远程节点上不跑',
            style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 停用状态不说"下次"：那条规则根本不会跑，写个日期反而误导
  String get _nextLabel {
    if (!schedule.enabled) {
      return schedule.lastRunAt.isEmpty
          ? '还没跑过 · 现在是停用状态'
          : '上次 ${schedule.lastRunAt} · 现在是停用状态';
    }
    final range = schedule.hasEnd ? ' · 到 ${schedule.endDate} 止' : '';
    return '下次 ${schedule.nextRunAt}$range';
  }
}
