import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 窄屏（移动端 + 桌面端窄窗）判定：账本这类列表页在 720 以下要收列
bool ledgerNarrow(BuildContext context) =>
    PlatformUtil.isMobile || MediaQuery.of(context).size.width < 720;

/// 「回补历史邮件」的二次确认。
///
/// 这一笔点下去是逐封下载几十到几百封全文的批量抓取，几十秒起步；没有确认框
/// 的话界面半天不动，很容易被当成卡死再点一次。已入账的邮件由 Rust 侧按 UID
/// 与流水唯一索引双重跳过，所以重复点不会重复记账。
Future<bool> confirmLedgerBackfill(BuildContext context, String ruleName) => showConfirmDialog(
      context,
      title: '回补「$ruleName」的历史邮件？',
      message: '日常收取只看收件箱最新 10 封，这里会把最近的历史邮件逐封下载并匹配账单，'
          '可能要几十秒到几分钟。已经入过账的会自动跳过，重复点不会记两遍。',
      confirmLabel: '开始回补',
    );

/// 金额字：正负号由方向决定，颜色只用语义角色
///
/// 收入绿、支出不着色是记账软件的通行读法——把支出涂红会让整页读起来像报警。
class LedgerAmountText extends StatelessWidget {
  const LedgerAmountText({
    super.key,
    required this.amount,
    required this.income,
    this.size = LedgerAmountSize.row,
    this.signed = true,
    this.toneColor,
  });

  final double amount;
  final bool income;
  final LedgerAmountSize size;

  /// false 时只显示绝对值（账户余额那类没有"方向"的数）
  final bool signed;
  final Color? toneColor;

  static const String _currencySign = '¥';

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final base = switch (size) {
      LedgerAmountSize.row => AppTextStyles.cardTitle(context),
      LedgerAmountSize.headline => AppTextStyles.metric(context),
      LedgerAmountSize.dense => AppTextStyles.body(context),
    };
    final style = signed
        ? base.copyWith(color: toneColor ?? (income ? s.success.color : s.textPrimary))
        : base.copyWith(color: toneColor ?? s.textPrimary);
    final text = '${signed ? (income ? '+' : '-') : ''}'
        '$_currencySign${formatLedgerAmount(amount)}';
    return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

enum LedgerAmountSize { row, headline, dense }

/// 类别图标底：一小块水洗底 + 描边图标
class LedgerIconBadge extends StatelessWidget {
  const LedgerIconBadge({
    super.key,
    required this.iconKey,
    required this.income,
    this.size,
  });

  final String iconKey;
  final bool income;

  /// 方块边长；不给用列表行的默认档
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final box = size ?? m.kSpace32;
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: income ? s.success.container : s.surfaceHover,
        borderRadius: m.radius8,
      ),
      child: DrawIcon(
        ledgerIconOf(iconKey),
        size: box * 0.55,
        color: income ? s.success.color : s.textSecondary,
      ),
    );
  }
}

/// 一笔流水的行。点进去改，长按删——和主流记账 App 的手势一致。
class LedgerTxTile extends StatelessWidget {
  const LedgerTxTile({
    super.key,
    required this.tx,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final LedgerTx tx;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 待确认队列在这里放"入账/忽略"两个按钮
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final subtitle = <String>[
      if (tx.categoryName.isNotEmpty) tx.categoryName,
      if (tx.timeLabel.isNotEmpty) tx.timeLabel,
      if (tx.accountName.isNotEmpty) tx.accountName,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: m.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace8),
        child: Row(
          children: <Widget>[
            LedgerIconBadge(iconKey: tx.categoryIcon, income: tx.isIncome),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          tx.merchant.isEmpty ? (tx.note.isEmpty ? '未命名' : tx.note) : tx.merchant,
                          style: AppTextStyles.rowTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (tx.fromEmail) ...<Widget>[
                        SizedBox(width: m.kSpace4),
                        DrawIcon(
                          StrokeIcons.mail,
                          size: m.iconSize12,
                          color: s.info.color,
                          semanticLabel: '来自邮件账单',
                        ),
                      ],
                      if (tx.isPending) ...<Widget>[
                        SizedBox(width: m.kSpace4),
                        DrawIcon(
                          StrokeIcons.pending,
                          size: m.iconSize12,
                          color: s.warning.color,
                          semanticLabel: '待确认',
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    subtitle.isEmpty ? (tx.merchant.isEmpty ? '' : tx.note) : subtitle,
                    style: AppTextStyles.caption(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace12),
            if (trailing != null)
              trailing!
            else
              LedgerAmountText(amount: tx.amount, income: tx.isIncome),
          ],
        ),
      ),
    );
  }
}

/// 按天分组的组头：日期 + 当日收支
class LedgerDayHeader extends StatelessWidget {
  const LedgerDayHeader({
    super.key,
    required this.date,
    required this.income,
    required this.expense,
    required this.count,
  });

  final String date;
  final double income;
  final double expense;
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace14, bottom: m.kSpace6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(ledgerDateLabel(date), style: AppTextStyles.cardTitle(context)),
          SizedBox(width: m.kSpace8),
          Text('$count 笔', style: AppTextStyles.caption(context)),
          const Spacer(),
          Text(
            '收 ${formatLedgerAmount(income)}  支 ${formatLedgerAmount(expense)}',
            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 模块内导航：一条胶囊 tab，桌面端挂顶栏 toolbar、移动端挂 AppBar 下沿。
///
/// 不用 TabBar/DefaultTabController：这几页各自是路由、各自有 ViewModel，
/// 做成同一页内的 Tab 会把状态搅在一起，也没有返回栈。
class LedgerTabs extends StatelessWidget {
  const LedgerTabs({super.key, required this.current});

  /// 当前路径，和 [_entries] 里的 location 比对高亮
  final String current;

  static const List<({String label, StrokeIcon icon, String location})> _entries =
      <({String label, StrokeIcon icon, String location})>[
    (label: '流水', icon: StrokeIcons.chartLine, location: '/ledger'),
    (label: '明细', icon: StrokeIcons.list, location: '/ledger/records'),
    (label: '统计', icon: StrokeIcons.chartPie, location: '/ledger/stats'),
    (label: '待确认', icon: StrokeIcons.inbox, location: '/ledger/pending'),
    (label: '设置', icon: StrokeIcons.settings, location: '/ledger/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    // 窄屏只留文字：五个带图标的胶囊在 390 宽上正好溢出一截，
    // 而这条 tab 是整页导航，宁可少几个图标也不能看不见最后一个。
    final showIcon = !ledgerNarrow(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
      child: Row(
        children: <Widget>[
          for (final entry in _entries)
            Padding(
              padding: EdgeInsets.only(right: m.kSpace6),
              child: _LedgerTabPill(
                label: entry.label,
                icon: entry.icon,
                showIcon: showIcon,
                selected: current == entry.location,
                onTap: () => context.go(entry.location),
              ),
            ),
        ],
      ),
    );
  }
}

class _LedgerTabPill extends StatelessWidget {
  const _LedgerTabPill({
    required this.label,
    required this.icon,
    required this.showIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final StrokeIcon icon;

  /// 窄屏收起图标，只留名字
  final bool showIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radiusPill,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
        decoration: BoxDecoration(
          color: selected ? s.accentContainer : Colors.transparent,
          borderRadius: m.radiusPill,
          border: Border.all(color: selected ? s.accentContainerBorder : s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showIcon) ...<Widget>[
              DrawIcon(
                icon,
                size: m.iconSize14,
                color: selected ? s.accentText : s.textSecondary,
              ),
              SizedBox(width: m.kSpace6),
            ],
            Text(
              label,
              style: AppTextStyles.body(context).copyWith(
                color: selected ? s.accentText : s.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月份游标：左右翻页 + 点标题直接选月。首页和统计页共用同一套翻页手势。
class LedgerMonthStrip extends StatelessWidget {
  const LedgerMonthStrip({
    super.key,
    required this.monthLabel,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPickMonth,
  });

  final String monthLabel;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickMonth;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: <Widget>[
        ToolIconButton(icon: StrokeIcons.chevronLeft, tooltip: '上一月', onPressed: onPrevious),
        InkWell(
          onTap: onPickMonth,
          borderRadius: m.radius8,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
            child: Row(
              children: <Widget>[
                Text(monthLabel, style: AppTextStyles.sectionTitle(context)),
                SizedBox(width: m.kSpace4),
                DrawIcon(StrokeIcons.calendarMonth, size: m.iconSize14, color: s.textTertiary),
              ],
            ),
          ),
        ),
        ToolIconButton(
          icon: StrokeIcons.chevronRight,
          tooltip: '下一月',
          onPressed: canGoNext ? onNext : null,
        ),
      ],
    );
  }
}

/// 空表/错误/加载三态收在这里，页面只描述"有数据时长什么样"
class LedgerStateView extends StatelessWidget {
  const LedgerStateView({
    super.key,
    required this.empty,
    required this.error,
    required this.child,
    this.emptyTitle = '还没有记录',
    this.emptyIcon = StrokeIcons.inbox,
    this.onRetry,
    this.emptyAction,
  });

  final bool empty;
  final String? error;
  final Widget child;
  final String emptyTitle;
  final StrokeIcon emptyIcon;
  final VoidCallback? onRetry;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    // 首帧加载由 BasePage 的遮罩负责，这里只管"没有数据"和"读挂了"两种落点
    if (error != null && empty) {
      return EmptyState(
        title: '读取失败',
        description: error,
        icon: StrokeIcons.warning,
        action: onRetry == null
            ? null
            : FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
      );
    }
    if (empty) {
      return EmptyState(
        title: emptyTitle,
        icon: emptyIcon,
        action: emptyAction,
      );
    }
    return child;
  }
}

/// 一行可点的设置入口（图标 + 标题 + 说明 + 箭头）
class LedgerNavTile extends StatelessWidget {  const LedgerNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final StrokeIcon icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace10),
        child: Row(
          children: <Widget>[
            DrawIcon(icon, size: m.iconSize18, color: s.textSecondary),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title, style: AppTextStyles.rowTitle(context)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                    SizedBox(height: m.kSpace2),
                    Text(subtitle!, style: AppTextStyles.caption(context)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing! else DrawIcon(
              StrokeIcons.chevronRight,
              size: m.iconSize16,
              color: s.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 表单里的一段：小标签 + 控件 + 可选说明
class LedgerField extends StatelessWidget {
  const LedgerField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppTextStyles.overline(context)),
          SizedBox(height: m.kSpace6),
          child,
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace4),
              child: Text(hint!, style: AppTextStyles.caption(context)),
            ),
        ],
      ),
    );
  }
}

/// 表单里的单行输入框
class LedgerInput extends StatelessWidget {
  const LedgerInput(
    this.controller, {
    super.key,
    required this.hint,
    this.keyboardType,
    this.formatter,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputFormatter? formatter;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatter == null ? null : <TextInputFormatter>[formatter!],
      style: AppTextStyles.body(context),
      decoration: InputDecoration(isDense: true, hintText: hint),
    );
  }
}
