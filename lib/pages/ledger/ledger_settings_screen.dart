import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_rule_editor.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_settings_viewmodel.dart';

/// 账单邮箱设置：规则 CRUD、连接自检、调度开关、收取日志。
///
/// 口令不在这一页出现明文，也不写进规则 JSON——它只进安全存储，
/// 界面上最多显示"已保存口令"这个事实。
class LedgerSettingsScreen extends BasePage<LedgerSettingsViewModel> {
  const LedgerSettingsScreen({super.key});

  @override
  State<LedgerSettingsScreen> createState() => _LedgerSettingsScreenState();
}

class _LedgerSettingsScreenState
    extends BasePageState<LedgerSettingsViewModel, LedgerSettingsScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerSettingsViewModel createViewModel() => LedgerSettingsViewModel();

  void _openEditor([LedgerRule? rule]) {
    showLedgerRuleEditor(context, vm: viewModel, initial: rule);
  }

  Future<void> _delete(LedgerRule rule) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除规则「${rule.name}」？',
      message: '已经入账的流水会保留，只是不再收这个邮箱的信。已存口令会一并清除。',
      confirmLabel: '删除',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await viewModel.deleteRule(rule.id);
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '账单邮箱',
        toolbar: ledgerBottomNavMode(context)
            ? null
            : const LedgerTabs(current: '/ledger/settings'),
        toolbarHeight: m.kSpace44,
        bottomBar: LedgerBottomNav(current: '/ledger/settings', onAdd: () => ledgerQuickAdd(context)),
        bottomBarHeight: m.kSpace56,
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => viewModel.reload(),
          ),
          SizedBox(width: m.kSpace12),
        ],
      ),
      child: Obx(() => _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        _SchedulerCard(vm: viewModel),
        SizedBox(height: m.kSpace20),
        SectionHeader(
          title: '邮箱规则',
          trailing: FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
            label: const Text('添加规则'),
          ),
        ),
        if (viewModel.lastMessage.value.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: m.kSpace8),
            child: Text(viewModel.lastMessage.value, style: AppTextStyles.caption(context)),
          ),
        if (viewModel.rules.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('还没有邮箱规则', style: AppTextStyles.rowTitle(context)),
                SizedBox(height: m.kSpace6),
                Text(
                  '配一条"发件人 + 标题"的匹配规则，每天到的信用卡账单就会被自动解析成流水。'
                  '解析结果先进待确认队列，你点头才入账。',
                  style: AppTextStyles.caption(context),
                ),
                SizedBox(height: m.kSpace12),
                FilledButton.tonal(onPressed: _openEditor, child: const Text('添加第一条规则')),
              ],
            ),
          )
        else
          for (final rule in viewModel.rules) ...[
            _RuleCard(vm: viewModel, rule: rule, onDelete: () => _delete(rule)),
            SizedBox(height: m.kSpace12),
          ],
        SizedBox(height: m.kSpace8),
        LedgerNavTile(
          icon: StrokeIcons.accountBalanceWallet,
          title: '账户',
          subtitle: '管理记账用的账户和商户自动归类习惯',
          onTap: () => const LedgerAccountsRoute().go(context),
        ),
        SizedBox(height: m.kSpace4),
        LedgerNavTile(
          icon: StrokeIcons.category,
          title: '分类与标签',
          subtitle: '收支类别的两级树、标签与标签分组',
          onTap: () => const LedgerOrganizeRoute().go(context),
        ),
        SizedBox(height: m.kSpace4),
        LedgerNavTile(
          icon: StrokeIcons.eventRepeat,
          title: '模板与定时',
          subtitle: '常记的那几笔存成模板，再配一条到点自动记的规则',
          onTap: () => const LedgerTemplatesRoute().go(context),
        ),
        SizedBox(height: m.kSpace4),
        LedgerNavTile(
          icon: StrokeIcons.assetLibraryImport,
          title: '导入与导出',
          subtitle: '把流水写成 CSV/JSON 带走，或从一份表格导进账本',
          onTap: () => const LedgerDataRoute().go(context),
        ),
        SizedBox(height: m.kSpace20),
        _LogSection(vm: viewModel),
      ],
    );
  }
}

/// 调度：跑在 Rust 里的定时器，开关与状态都在这里
class _SchedulerCard extends StatelessWidget {
  const _SchedulerCard({required this.vm});

  final LedgerSettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final status = vm.scheduler.value;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('自动收取', style: AppTextStyles.sectionTitle(context)),
          SizedBox(height: m.kSpace6),
          Text(
            status.running
                ? '定时器在跑 · 生效规则 ${status.activeRules} 条 · 每 ${status.checkIntervalSecs} 秒看一次'
                : '定时器没跑，只能手动"立即收取"',
            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
          ),
          if (status.nextCheckAt.isNotEmpty) ...[
            SizedBox(height: m.kSpace4),
            Text('下次检查 ${status.nextCheckAt}', style: AppTextStyles.caption(context)),
          ],
          if (status.lastSummary.isNotEmpty) ...[
            SizedBox(height: m.kSpace6),
            Text('最近一轮：${status.lastSummary}', style: AppTextStyles.caption(context)),
          ],
          SizedBox(height: m.kSpace8),
          _SwitchRow(
            value: status.enabled,
            onChanged: vm.setSchedulerEnabled,
            title: '在本机定时收信',
            subtitle: '关掉后规则仍然生效，只是不会自己跑',
          ),
          _SwitchRow(
            value: vm.autoOpenScheduler.value,
            onChanged: vm.setAutoOpenScheduler,
            title: '启动应用时自动打开',
            subtitle: '打开后每次启动都会按规则去收一次信',
          ),
        ],
      ),
    );
  }
}

/// 卡片里的开关行
///
/// 不用 SwitchListTile：它把墨水画在最近的 Material 祖先上，而 AppCard 是用
/// DecoratedBox 上色的，Flutter 3.47 起这条会被断言拦下。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.rowTitle(context)),
                Text(
                  subtitle,
                  style: AppTextStyles.caption(context).copyWith(
                    color: AppSemantic.of(context).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: m.kSpace8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 一条规则：状态、上次结果、四个动作
class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.vm, required this.rule, required this.onDelete});

  final LedgerSettingsViewModel vm;
  final LedgerRule rule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final busy = vm.probing.value;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(rule.name, style: AppTextStyles.rowTitle(context)),
              ),
              StatusChip(
                label: switch (rule.protocol) {
                  'imap' => 'IMAP',
                  'pop3' => 'POP3',
                  'smtp' => 'SMTP',
                  _ => rule.protocol,
                },
                tone: rule.protocolSupported ? Tone.info : Tone.warning,
              ),
              SizedBox(width: m.kSpace6),
              StatusChip(
                label: rule.enabled ? '启用' : '停用',
                tone: rule.enabled ? Tone.success : Tone.neutral,
              ),
              if (rule.autoApply) ...[
                SizedBox(width: m.kSpace6),
                const StatusChip(label: '自动入账', tone: Tone.accent),
              ],
            ],
          ),
          SizedBox(height: m.kSpace6),
          Text(
            <String>[
              '${rule.username} @ ${rule.host}:${rule.port}${rule.useSsl ? ' (SSL)' : ''}',
              if (rule.senderMatch.isNotEmpty) '发件人含 ${rule.senderMatch}',
              if (rule.subjectMatch.isNotEmpty) '标题含 ${rule.subjectMatch}',
            ].join('  ·  '),
            style: AppTextStyles.caption(context),
          ),
          if (!rule.protocolSupported)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace8),
              child: Text(
                '这个协议还没实现，保存配置可以，收取会返回"尚未支持"。',
                style: AppTextStyles.caption(context).copyWith(color: s.warning.color),
              ),
            ),
          if (rule.lastRunAt.isNotEmpty || rule.lastResult.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace8),
              child: Text(
                [
                  if (rule.lastRunAt.isNotEmpty) '上次 ${rule.lastRunAt}',
                  if (rule.lastResult.isNotEmpty) rule.lastResult,
                ].join('  ·  '),
                style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
              ),
            ),
          SizedBox(height: m.kSpace12),
          Wrap(
            spacing: m.kSpace8,
            runSpacing: m.kSpace6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Switch(
                value: rule.enabled,
                onChanged: (value) => vm.setEnabled(rule.id, value),
              ),
              TextButton(
                onPressed: busy ? null : () => vm.runRuleNow(rule.id),
                child: const Text('立即收取'),
              ),
              TextButton.icon(
                // 回补是几十秒起步的批量抓取，先确认再跑；probing 期间整排按钮一起收掉
                onPressed: busy
                    ? null
                    : () async {
                        if (!await confirmLedgerBackfill(context, rule.name)) {
                          return;
                        }
                        await vm.backfillRule(rule.id);
                      },
                icon: DrawIcon(StrokeIcons.history, size: m.iconSize14),
                label: const Text('回补历史'),
              ),
              TextButton.icon(
                onPressed: () => showLedgerRuleEditor(context, vm: vm, initial: rule),
                icon: DrawIcon(StrokeIcons.edit, size: m.iconSize14),
                label: const Text('编辑'),
              ),
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

/// 收取日志：成功也要看得见，不然"为什么没进来"只能靠猜
class _LogSection extends StatelessWidget {
  const _LogSection({required this.vm});

  final LedgerSettingsViewModel vm;

  Future<void> _clear(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空收取日志？',
      message: '只删日志，规则和流水都不动。',
      confirmLabel: '清空',
    );
    if (ok) await vm.clearLogs();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeader(
          title: '收取日志',
          trailing: vm.logs.isEmpty
              ? null
              : TextButton(
                  onPressed: () => _clear(context),
                  child: const Text('清空'),
                ),
        ),
        if (vm.logs.isEmpty)
          Text('还没有收过信', style: AppTextStyles.caption(context))
        else
          AppCard(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
            child: Column(
              children: <Widget>[
                for (final log in vm.logs)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: m.kSpace6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DrawIcon(
                          log.ok ? StrokeIcons.checkCircle : StrokeIcons.error,
                          size: m.iconSize16,
                          color: log.ok ? s.success.color : s.danger.color,
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(log.startedAt, style: AppTextStyles.rowTitle(context)),
                              if (log.detail.isNotEmpty)
                                Text(log.detail, style: AppTextStyles.caption(context)),
                            ],
                          ),
                        ),
                        Text(
                          '+${log.newEmails} 封 / +${log.newTx} 笔'
                          '${log.skippedTx > 0 ? ' · 跳过 ${log.skippedTx}' : ''}',
                          style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
