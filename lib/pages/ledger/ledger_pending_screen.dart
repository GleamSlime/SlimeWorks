import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/components/ledger_tx_editor.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_pending_viewmodel.dart';

/// 待确认队列：邮件抓到的账单先落在这里，用户点头才进账本。
///
/// 一封邮件是一张卡，明细折叠在里面——银行每天发来一封、十几笔，
/// 平铺成几十行会让"哪一天没处理"这件事看不见。
class LedgerPendingScreen extends BasePage<LedgerPendingViewModel> {
  const LedgerPendingScreen({super.key});

  @override
  State<LedgerPendingScreen> createState() => _LedgerPendingScreenState();
}

class _LedgerPendingScreenState
    extends BasePageState<LedgerPendingViewModel, LedgerPendingScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerPendingViewModel createViewModel() => LedgerPendingViewModel();

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '待确认账单',
        toolbar: ledgerBottomNavMode(context)
            ? null
            : const LedgerTabs(current: '/ledger/pending'),
        toolbarHeight: m.kSpace44,
        bottomBar: LedgerBottomNav(current: '/ledger/pending', onAdd: () => ledgerQuickAdd(context)),
        bottomBarHeight: m.kSpace56,
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => viewModel.reload(),
          ),
          SizedBox(width: m.kSpace8),
          Padding(
            padding: EdgeInsets.only(right: m.kSpace12),
            // Obx 里同时读 rules/fetching：两枚胶囊共用一套「选哪条规则」的菜单，
            // 抓取跑起来时一起收掉，免得并发点开两条抓取链路。
            child: Obx(() {
              final rules = viewModel.rules
                  .where((r) => r.enabled && r.protocolSupported)
                  .toList(growable: false);
              final busy = viewModel.fetching.value;
              return Row(
                children: <Widget>[
                  _RulePickPill(
                    icon: StrokeIcons.mail,
                    label: '立即收取',
                    tooltip: '选择要立即收取的邮箱',
                    menuPrefix: '收取',
                    rules: rules,
                    busy: busy,
                    onRun: viewModel.checkRuleNow,
                  ),
                  SizedBox(width: m.kSpace6),
                  _RulePickPill(
                    icon: StrokeIcons.history,
                    label: '回补历史',
                    tooltip: '选择要回补历史邮件的邮箱',
                    menuPrefix: '回补',
                    rules: rules,
                    busy: busy,
                    onRun: (ruleId) async {
                      final name = viewModel.rules
                          .firstWhereOrNull((r) => r.id == ruleId)
                          ?.name;
                      if (!await confirmLedgerBackfill(context, name ?? '该邮箱')) {
                        return;
                      }
                      await viewModel.backfillRuleNow(ruleId);
                    },
                  ),
                ],
              );
            }),
          ),
        ],
      ),
      child: Obx(() => _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final emails = viewModel.emails;
    return LedgerStateView(
      error: viewModel.errorMessage,
      empty: emails.isEmpty,
      emptyTitle: '没有等你确认的账单',
      emptyIcon: StrokeIcons.inbox,
      emptyAction: TextButton.icon(
        onPressed: () => const LedgerSettingsRoute().go(context),
        icon: DrawIcon(StrokeIcons.settings, size: m.iconSize16),
        label: const Text('去设置邮箱账单'),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
        children: <Widget>[
          Row(
            children: <Widget>[
              _ConfirmTarget(
                accounts: viewModel.accounts,
                accountId: viewModel.defaultAccountId.value,
                onPicked: (id) => viewModel.defaultAccountId.value = id,
              ),
              const Spacer(),
              if (viewModel.lastResult.value.isNotEmpty)
                Text(
                  viewModel.lastResult.value,
                  style: AppTextStyles.caption(context).copyWith(color: s.success.color),
                ),
            ],
          ),
          SizedBox(height: m.kSpace12),
          for (final email in emails) ...[
            _EmailCard(vm: viewModel, email: email),
            SizedBox(height: m.kSpace12),
          ],
          if (viewModel.appliedEmails.isNotEmpty) ...[
            SizedBox(height: m.kSpace8),
            _AppliedSection(vm: viewModel),
          ],
        ],
      ),
    );
  }
}

/// 顶栏「挑一条规则触发一次收取」的胶囊：一条规则直接跑，多条给菜单。
///
/// 立即收取和回补历史只差扫描深度、选规则的交互一模一样，所以共用这个壳；
/// [busy] 期间整枚胶囊禁用（[StrokeIcons.history] 那枚还会在确认框里再问一次）。
class _RulePickPill extends StatelessWidget {
  const _RulePickPill({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.menuPrefix,
    required this.rules,
    required this.onRun,
    required this.busy,
  });

  final StrokeIcon icon;
  final String label;
  final String tooltip;

  /// 多条规则时菜单项的前缀，例如「收取「招行」」/「回补「招行」」
  final String menuPrefix;
  final List<LedgerRule> rules;
  final void Function(int ruleId) onRun;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    if (rules.length > 1) {
      return PopupMenuButton<int>(
        color: s.surfaceRaised,
        tooltip: busy ? null : tooltip,
        enabled: !busy,
        onSelected: onRun,
        itemBuilder: (context) => <PopupMenuEntry<int>>[
          for (final rule in rules)
            PopupMenuItem(value: rule.id, child: Text('$menuPrefix「${rule.name}」')),
        ],
        // 这里不能给胶囊自己的 InkWell 装 onTap：它会和 PopupMenuButton
        // 的外层手势抢同一次点击，结果是菜单永远弹不出来。
        child: _Pill(icon: icon, label: label, enabled: !busy),
      );
    }
    return _Pill(
      icon: icon,
      label: label,
      enabled: !busy && rules.length == 1,
      onTap: rules.isEmpty ? null : () => onRun(rules.first.id),
    );
  }
}

/// 顶栏里的胶囊按钮（与 [LedgerTabs] 同一种体量）
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.enabled = true, this.onTap});

  final StrokeIcon icon;
  final String label;
  final bool enabled;

  /// null 表示这枚胶囊只是 [PopupMenuButton] 的外皮，点击由外层处理
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final color = enabled ? s.accentText : s.textTertiary;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: m.radiusPill,
      child: Container(
        height: m.kSpace32,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
        decoration: BoxDecoration(
          color: enabled ? s.accentContainer : s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(color: enabled ? s.accentContainerBorder : s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(icon, size: m.iconSize14, color: color),
            SizedBox(width: m.kSpace6),
            Text(label, style: AppTextStyles.body(context).copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 入账目标账户：整封确认时这些流水挂到谁身上
class _ConfirmTarget extends StatelessWidget {
  const _ConfirmTarget({
    required this.accounts,
    required this.accountId,
    required this.onPicked,
  });

  final List<LedgerAccount> accounts;
  final int accountId;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final picked = accounts.where((a) => a.id == accountId).firstOrNull;
    return PopupMenuButton<int>(
      color: s.surfaceRaised,
      enabled: accounts.isNotEmpty,
      tooltip: '新确认的流水记到哪个账户',
      onSelected: onPicked,
      itemBuilder: (context) => <PopupMenuEntry<int>>[
        for (final a in accounts) PopupMenuItem(value: a.id, child: Text(a.name)),
      ],
      child: Container(
        height: m.kSpace32,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
        decoration: BoxDecoration(
          color: s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(color: s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(
              StrokeIcons.accountBalanceWallet,
              size: m.iconSize14,
              color: s.textSecondary,
            ),
            SizedBox(width: m.kSpace6),
            Text(
              picked == null ? '还没账户' : '入账到 ${picked.name}',
              style: AppTextStyles.caption(context),
            ),
            SizedBox(width: m.kSpace4),
            DrawIcon(
              StrokeIcons.keyboardArrowDown,
              size: m.iconSize12,
              color: s.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 已入账的邮件收成一段：默认折叠，账本平时不需要翻它，
/// 但银行改版清场、或追查某笔的来源时要找得到入口。
class _AppliedSection extends StatefulWidget {
  const _AppliedSection({required this.vm});

  final LedgerPendingViewModel vm;

  @override
  State<_AppliedSection> createState() => _AppliedSectionState();
}

class _AppliedSectionState extends State<_AppliedSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final count = widget.vm.appliedEmails.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: m.radius8,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: m.kSpace8),
            child: Row(
              children: <Widget>[
                DrawIcon(
                  _open ? StrokeIcons.chevronLeft : StrokeIcons.chevronRight,
                  size: m.iconSize14,
                  color: s.textTertiary,
                ),
                SizedBox(width: m.kSpace6),
                Text('已入账的邮件（$count）', style: AppTextStyles.cardTitle(context)),
              ],
            ),
          ),
        ),
        if (_open)
          for (final email in widget.vm.appliedEmails) ...[
            SizedBox(height: m.kSpace8),
            _EmailCard(vm: widget.vm, email: email),
          ],
      ],
    );
  }
}

/// 一封账单邮件：抬头 + 解析警告 + 折叠明细
class _EmailCard extends StatelessWidget {
  const _EmailCard({required this.vm, required this.email});

  final LedgerPendingViewModel vm;
  final LedgerPendingEmail email;

  Future<void> _ignore(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '忽略这封账单？',
      message: '${email.txCount} 笔流水会被标为忽略，之后不会再出现在待确认里。',
      confirmLabel: '忽略',
    );
    if (ok) await vm.ignoreEmail(email.id);
  }

  Future<void> _purge(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: '清除这封带来的流水？',
      message: '已经入账的 ${email.txCount} 笔会被删掉。银行改了账单格式、需要重新抓一次时用这个清场。',
      confirmLabel: '清除流水',
      confirmColor: AppSemantic.of(context).danger.color,
    );
    if (ok) await vm.purgeEmail(email.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final expanded = vm.expanded.contains(email.id);

    return AppCard(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace12, m.kSpace12, m.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => vm.toggleExpand(email.id),
            borderRadius: m.radius8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DrawIcon(StrokeIcons.mail, size: m.iconSize20, color: s.info.color),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        email.subject.isEmpty ? '(无主题)' : email.subject,
                        style: AppTextStyles.rowTitle(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: m.kSpace2),
                      Text(
                        <String>[
                          if (email.ruleName.isNotEmpty) email.ruleName,
                          ledgerDateLabel(email.billDate),
                          '${email.txCount} 笔',
                        ].join(' · '),
                        style: AppTextStyles.caption(context),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: m.kSpace8),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  child: DrawIcon(
                    StrokeIcons.chevronRight,
                    size: m.iconSize16,
                    color: s.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          for (final warning in email.warnings)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DrawIcon(
                    StrokeIcons.warning,
                    size: m.iconSize14,
                    color: s.warning.color,
                    semanticLabel: '解析警告',
                  ),
                  SizedBox(width: m.kSpace6),
                  Expanded(
                    child: Text(
                      warning,
                      style: AppTextStyles.caption(context).copyWith(color: s.warning.color),
                    ),
                  ),
                ],
              ),
            ),
          if (email.availableCredit != null || email.pointsBalance != null)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace8),
              child: Text(
                <String>[
                  if (email.availableCredit != null)
                    '可用额度 ¥${formatLedgerAmount(email.availableCredit!)}',
                  if (email.pointsBalance != null) '积分 ${email.pointsBalance}',
                ].join('  ·  '),
                style: AppTextStyles.caption(context),
              ),
            ),
          SizedBox(height: m.kSpace12),
          Wrap(
            spacing: m.kSpace8,
            runSpacing: m.kSpace6,
            children: <Widget>[
              if (!email.applied)
                FilledButton.tonal(
                  onPressed: () => vm.confirmEmail(email.id),
                  child: Text('全部入账（${email.txCount}）'),
                ),
              if (!email.applied)
                TextButton(onPressed: () => _ignore(context), child: const Text('忽略这封')),
              if (email.applied)
                TextButton(
                  onPressed: () => _purge(context),
                  child: const Text('清除这封的流水'),
                ),
            ],
          ),
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: expanded
                ? _EmailDetails(vm: vm, email: email)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _EmailDetails extends StatelessWidget {
  const _EmailDetails({required this.vm, required this.email});

  final LedgerPendingViewModel vm;
  final LedgerPendingEmail email;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final details = vm.detailsOf(email.id);
    if (details.isEmpty) {
      // 明细是点开才取的；取回来之前先占住这一段高度
      return Padding(
        padding: EdgeInsets.only(top: m.kSpace8),
        child: AppLoading(message: '读取明细…', size: m.iconSize18),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AppDivider(),
          SizedBox(height: m.kSpace6),
          for (final tx in details)
            LedgerTxTile(
              tx: tx,
              // 点一笔 = 只入这一笔；已入账的没有后续动作，只展示
              onTap: tx.isPending ? () => vm.confirmOne(tx.id) : null,
              trailing: tx.isPending
                  ? TextButton(
                      onPressed: () => vm.confirmOne(tx.id),
                      child: const Text('入账'),
                    )
                  : LedgerAmountText(
                      amount: tx.amount,
                      income: tx.isIncome,
                      size: LedgerAmountSize.dense,
                    ),
            ),
          Text(
            '来自 ${email.fromAddr} · ${email.receivedAt}',
            style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }
}
