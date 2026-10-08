import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 窄屏（移动端 + 桌面端窄窗）判定：账本这类列表页在 720 以下要收列
bool ledgerNarrow(BuildContext context) =>
    PlatformUtil.isMobile || MediaQuery.of(context).size.width < 720;

/// 这一档窗口要不要走底部导航。
///
/// 阈值必须是 600 而不是 [ledgerNarrow] 的 720：`ScreenChrome` 只在
/// "本地 Scaffold + AppBar"形态下才画 bottomBar，而它切到那个形态的条件就是
/// 宽度 ≤600。用 720 会让 600~720 这段桌面窗口两头都不挂导航——页面变成孤岛。
bool ledgerBottomNavMode(BuildContext context) =>
    PlatformUtil.isMobile || MediaQuery.of(context).size.width <= 600;

/// 把库里存的 `#RRGGBB` 解析成颜色。
///
/// 类别和标签的颜色是用户手填的，空串或写错位数都可能发生，
/// 解析不了就回落到调用方给的角色色，不能让整页因为一个坏值画崩。
Color ledgerColorOf(String hex, {required Color fallback}) {
  var raw = hex.trim();
  if (raw.startsWith('#')) raw = raw.substring(1);
  if (raw.length != 6) return fallback;
  final value = int.tryParse(raw, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

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
    // 转账读的是"从哪到哪"，不是"花了多少"，所以副标题不走类别那一套
    final subtitle = tx.isTransfer
        ? '${tx.accountName.isEmpty ? '转出' : tx.accountName}'
              ' → ${tx.destAccountName.isEmpty ? '转入' : tx.destAccountName}'
        : <String>[
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
                      if (tx.isTransfer) ...<Widget>[
                        SizedBox(width: m.kSpace4),
                        DrawIcon(
                          StrokeIcons.exchange,
                          size: m.iconSize12,
                          color: s.info.color,
                          semanticLabel: '转账',
                        ),
                      ],
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
                  if (tx.tagNames.isEmpty && subtitle.isEmpty)
                    // 商户为空的邮件行不留一行空白
                    const SizedBox.shrink()
                  else
                    Row(
                      children: <Widget>[
                        if (subtitle.isNotEmpty) ...<Widget>[
                          Flexible(
                            child: Text(
                              subtitle,
                              style: AppTextStyles.caption(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        for (final tag in tx.tagNames.take(2)) ...<Widget>[
                          SizedBox(width: m.kSpace6),
                          LedgerTagChip(label: tag),
                        ],
                        if (tx.tagNames.length > 2)
                          Padding(
                            padding: EdgeInsets.only(left: m.kSpace4),
                            child: Text('+${tx.tagNames.length - 2}', style: AppTextStyles.caption(context)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace12),
            if (trailing != null)
              trailing!
            else if (tx.isTransfer || tx.isBalanceAdjust)
              // 搬运的钱没有方向：给个 +/- 就变成"这笔花了 5000"，读的人只会算错账
              LedgerAmountText(amount: tx.amount, income: false, signed: false)
            else
              LedgerAmountText(amount: tx.amount, income: tx.isIncome),
          ],
        ),
      ),
    );
  }
}

/// 标签的小胶囊
class LedgerTagChip extends StatelessWidget {
  const LedgerTagChip({super.key, required this.label, this.onTap, this.onRemove, this.tint});

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final color = tint ?? s.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radiusPill,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
        decoration: BoxDecoration(
          borderRadius: m.radiusPill,
          border: Border.all(color: s.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(ledgerUiIconOf('tag'), size: m.iconSize12, color: color),
            SizedBox(width: m.kSpace2),
            Text(
              label,
              style: AppTextStyles.caption(context).copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRemove != null) ...<Widget>[
              SizedBox(width: m.kSpace2),
              InkWell(
                // 摘掉标签的那颗 ×：图标是手画的 DrawIcon，测试只能按 key 找
                key: ValueKey<String>('tag-remove:$label'),
                onTap: onRemove,
                child: DrawIcon(StrokeIcons.close, size: m.iconSize12, color: s.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "这一页现在是桩数据"的水印。
///
/// 后端还没接的那几样（标签、模板、定时、附件）必须自带这句话，
/// 否则用户会把演示数据当成自己的账，等到真记账时才发现对不上。
class LedgerStubMark extends StatelessWidget {
  const LedgerStubMark({super.key, this.text = '演示数据 · 后端未接入'});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
      decoration: BoxDecoration(
        color: s.warning.container,
        borderRadius: m.radius8,
        border: Border.all(color: s.warning.containerBorder),
      ),
      child: Row(
        children: <Widget>[
          DrawIcon(StrokeIcons.infoOutline, size: m.iconSize14, color: s.warning.color),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption(context).copyWith(color: s.warning.onContainer),
            ),
          ),
        ],
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

/// 按月分组的组头：这个月的收/支/结余。跨月区间先看总账再看每天
class LedgerMonthHeader extends StatelessWidget {
  const LedgerMonthHeader({
    super.key,
    required this.title,
    required this.income,
    required this.expense,
    required this.count,
  });

  final String title;
  final double income;
  final double expense;
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace16, bottom: m.kSpace4),
      child: Row(
        children: <Widget>[
          Text(title, style: AppTextStyles.sectionTitle(context)),
          SizedBox(width: m.kSpace8),
          Text('$count 笔', style: AppTextStyles.caption(context).copyWith(color: s.textTertiary)),
          const Spacer(),
          LedgerAmountText(amount: income, income: true, size: LedgerAmountSize.dense),
          SizedBox(width: m.kSpace10),
          LedgerAmountText(amount: expense, income: false, size: LedgerAmountSize.dense),
        ],
      ),
    );
  }
}

/// 月历页型：一天一格，格子里是当天的结余。
///
/// 只画"哪天有钱动"，不画具体几笔——明细仍然归列表管，点格子才切回列表。
class LedgerCalendarMonth extends StatelessWidget {
  const LedgerCalendarMonth({
    super.key,
    required this.month,
    required this.rows,
    required this.focused,
    required this.onPickDay,
    required this.onShiftMonth,
  });

  /// '2026-03'
  final String month;
  final List<LedgerDayRow> rows;

  /// 已选中只看的那一天，'' 表示没选
  final String focused;
  final ValueChanged<String> onPickDay;

  /// delta = ±1 个月
  final ValueChanged<int> onShiftMonth;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final first = DateTime.tryParse('$month-01');
    if (first == null) {
      return Text('月份读不出来：$month', style: AppTextStyles.body(context));
    }
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    // 周一开头：周日那一列排到最后，符合国内日历的读法。
    // weekday 是 Mon=1..Sun=7，减 1 才是"周一开头的第几列"，取余会把周日顶到第一列
    final leading = first.weekday - 1;
    final byDate = <String, LedgerDayRow>{for (final r in rows) r.billDate: r};

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const _CalendarCell.blank(),
      for (var day = 1; day <= lastDay; day++)
        () {
          final date = '$month-${day.toString().padLeft(2, '0')}';
          final row = byDate[date];
          return _CalendarCell(
            date: date,
            day: day,
            net: row?.net ?? 0,
            count: row?.count ?? 0,
            selected: focused == date,
            onTap: () => onPickDay(date),
          );
        }(),
    ];

    final weeks = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final slice = cells.skip(i).take(7).toList();
      while (slice.length < 7) {
        slice.add(const _CalendarCell.blank());
      }
      weeks.add(
        Row(children: <Widget>[for (final cell in slice) Expanded(child: cell)]),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace4, vertical: m.kSpace6),
          child: Row(
            children: <Widget>[
              ToolIconButton(
                icon: StrokeIcons.chevronLeft,
                tooltip: '上一月',
                onPressed: () => onShiftMonth(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${first.year} 年 ${first.month} 月',
                    style: AppTextStyles.cardTitle(context),
                  ),
                ),
              ),
              ToolIconButton(
                icon: StrokeIcons.chevronRight,
                tooltip: '下一月',
                onPressed: () => onShiftMonth(1),
              ),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            for (final label in kCalendarWeekdayOrder)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: m.kSpace6),
        for (final week in weeks) Padding(
          padding: EdgeInsets.only(bottom: m.kSpace4),
          child: week,
        ),
      ],
    );
  }

  /// 周一开头的星期表头，和 [_CalendarCell] 的排布必须同一套口径
  static const List<String> kCalendarWeekdayOrder = <String>['一', '二', '三', '四', '五', '六', '日'];
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.day,
    required this.net,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  const _CalendarCell.blank()
    : date = '',
      day = 0,
      net = 0,
      count = 0,
      selected = false,
      onTap = null;

  final String date;
  final int day;
  final double net;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    if (date.isEmpty) return SizedBox(height: AppTheme.metrics.kSpace56);
    final hasMoney = count > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radius8,
      child: Container(
        height: m.kSpace56,
        margin: EdgeInsets.symmetric(horizontal: m.kSpace2, vertical: m.kSpace2),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace4, vertical: m.kSpace4),
        decoration: BoxDecoration(
          color: selected ? s.accentContainer : (hasMoney ? s.surfaceSunken : Colors.transparent),
          borderRadius: m.radius8,
          border: Border.all(color: selected ? s.accentContainerBorder : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$day',
              style: AppTextStyles.caption(context).copyWith(
                color: hasMoney ? s.textPrimary : s.textTertiary,
              ),
            ),
            if (hasMoney)
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    ledgerCompactAmountLabel(net.abs()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(context).copyWith(
                      color: net >= 0 ? s.success.color : s.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 窄格子里的金额：一位一格只有 50 来逻辑像素，带上小数就只剩"888…"这种废话。
/// 日历只回答"哪天有钱动、大概多少"，精确到分归列表管，所以这里舍到元、
/// 过万折成"1.2万"。
String ledgerCompactAmountLabel(double value) {
  final abs = value.abs();
  if (abs >= 10000) {
    final wan = (abs / 10000).toStringAsFixed(abs >= 100000 ? 0 : 1);
    return '${wan.endsWith('.0') ? wan.substring(0, wan.length - 2) : wan}万';
  }
  return formatLedgerAmount(abs.roundToDouble()).split('.').first;
}

/// 模块内导航的一条目。侧栏、底部导航、设置页的入口列表都从这一份读，
/// 免得三处各写一遍名字和路径，改一个漏两个。
typedef LedgerNavEntry = ({String label, StrokeIcon icon, String location});

/// 移动端底部导航的四个落点（中间那颗"记一笔"另算，见 [LedgerBottomNav]）
const List<LedgerNavEntry> kLedgerPrimaryNav = <LedgerNavEntry>[
  (label: '概览', icon: StrokeIcons.chartLine, location: '/ledger'),
  (label: '明细', icon: StrokeIcons.list, location: '/ledger/records'),
  (label: '统计', icon: StrokeIcons.chartPie, location: '/ledger/stats'),
  (label: '设置', icon: StrokeIcons.settings, location: '/ledger/settings'),
];

/// 模块内导航：一条胶囊 tab，桌面端挂顶栏 toolbar。
///
/// 不用 TabBar/DefaultTabController：这几页各自是路由、各自有 ViewModel，
/// 做成同一页内的 Tab 会把状态搅在一起，也没有返回栈。
///
/// 只给**桌面宽屏**用。移动端与窄窗改走 [LedgerBottomNav]——五个胶囊在 390
/// 宽上正好溢出一截，而底部导航是拇指能直接够到的位置。
class LedgerTabs extends StatelessWidget {
  const LedgerTabs({super.key, required this.current});

  /// 当前路径，和 [_entries] 里的 location 比对高亮
  final String current;

  static const List<LedgerNavEntry> _entries = <LedgerNavEntry>[
    // 首项与 [kLedgerPrimaryNav] 用同一个名字：两条导航指的是同一个页面，
    // 一边叫"流水"一边叫"概览"会让人以为是两个地方。
    (label: '概览', icon: StrokeIcons.chartLine, location: '/ledger'),
    (label: '明细', icon: StrokeIcons.list, location: '/ledger/records'),
    (label: '统计', icon: StrokeIcons.chartPie, location: '/ledger/stats'),
    (label: '待确认', icon: StrokeIcons.inbox, location: '/ledger/pending'),
    (label: '设置', icon: StrokeIcons.settings, location: '/ledger/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
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
                selected: current == entry.location,
                onTap: () => context.go(entry.location),
              ),
            ),
        ],
      ),
    );
  }
}

/// 移动端/窄窗的底部导航：四个页面 + 中间一颗"记一笔"。
///
/// 中间那颗是整块区域唯一的强调控件——记账 App 的第一动作永远是记一笔，
/// 把它和导航放同一条上、给它最大的形状，比另开一个悬浮按钮更省地方，
/// 也不会盖住列表最后一行的金额。
class LedgerBottomNav extends StatelessWidget {
  const LedgerBottomNav({super.key, required this.current, this.onAdd});

  final String current;

  /// 各页自带自己的编辑器打开逻辑（默认账户、默认类别都不一样），所以不在这颗按钮里记账
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final left = kLedgerPrimaryNav.take(2).toList(growable: false);
    final right = kLedgerPrimaryNav.skip(2).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        border: Border(top: BorderSide(color: s.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: m.kSpace56,
          child: Row(
            children: <Widget>[
              for (final entry in left)
                Expanded(
                  child: _BottomNavItem(
                    entry: entry,
                    selected: current == entry.location,
                  ),
                ),
              SizedBox(
                width: m.kSpace56,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace6),
                  child: _QuickAddButton(onTap: onAdd),
                ),
              ),
              for (final entry in right)
                Expanded(
                  child: _BottomNavItem(
                    entry: entry,
                    selected: current == entry.location,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({required this.entry, required this.selected});

  final LedgerNavEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final color = selected ? s.accent : s.textTertiary;
    return InkWell(
      onTap: () => context.go(entry.location),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          DrawIcon(entry.icon, size: m.iconSize20, color: color),
          SizedBox(height: m.kSpace2),
          Text(
            entry.label,
            style: AppTextStyles.caption(context).copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Material(
      color: onTap == null ? s.surfaceHover : s.accent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: DrawIcon(
            StrokeIcons.add,
            size: m.iconSize24,
            color: onTap == null ? s.textDisabled : s.accentOn,
          ),
        ),
      ),
    );
  }
}

class _LedgerTabPill extends StatelessWidget {
  const _LedgerTabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final StrokeIcon icon;
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
            DrawIcon(
              icon,
              size: m.iconSize14,
              color: selected ? s.accentText : s.textSecondary,
            ),
            SizedBox(width: m.kSpace6),
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
    return AppTextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatter == null ? null : <TextInputFormatter>[formatter!],
      decoration: InputDecoration(isDense: true, hintText: hint),
    );
  }
}

/// 弹出标签挑选器：返回选中的标签 id，取消返回 null。
///
/// 记一笔要它，明细页的标签筛选也要它，所以入口放在 shared 里，
/// 免得筛选条去 import 编辑器。
Future<List<int>?> showLedgerTagPicker(
  BuildContext context, {
  required Set<int> selected,
  String title = '选标签',
}) => showDialog<List<int>>(
  context: context,
  builder: (ctx) => LedgerTagPicker(selected: selected, title: title),
);

/// 标签挑选器：按分组列，多选，就地新建
class LedgerTagPicker extends StatefulWidget {
  const LedgerTagPicker({super.key, required this.selected, this.title = '选标签'});

  final Set<int> selected;
  final String title;

  @override
  State<LedgerTagPicker> createState() => LedgerTagPickerState();
}

class LedgerTagPickerState extends State<LedgerTagPicker> {
  late Set<int> _picked = <int>{...widget.selected};
  List<LedgerTagGroup> _groups = const <LedgerTagGroup>[];
  int _targetGroupId = 0;
  final TextEditingController _newTag = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await LedgerStubStore.instance.init();
    final groups = await LedgerStubStore.instance.listTagGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      // 第一次加载时才拿得到分组，新建默认落在第一组
      _targetGroupId = groups.isEmpty ? 0 : groups.first.id;
    });
  }

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newTag.text.trim();
    if (name.isEmpty) return;
    final created = await LedgerStubStore.instance.upsertTagByName(name, groupId: _targetGroupId);
    _newTag.clear();
    final groups = await LedgerStubStore.instance.listTagGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      // 新建完立刻选上：绝大多数时候用户就是为了这一笔才建的
      _picked = <int>{..._picked, created.id};
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Dialog(
      backgroundColor: s.surface,
      shape: RoundedRectangleBorder(borderRadius: m.radiusOverlay, side: BorderSide(color: s.hairline)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scaleW(420)),
        child: Padding(
          padding: EdgeInsets.all(m.kSpace20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(widget.title, style: AppTextStyles.sectionTitle(context)),
                  const Spacer(),
                  ToolIconButton(
                    icon: StrokeIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
                ],
              ),
              SizedBox(height: m.kSpace8),
              const LedgerStubMark(text: '标签是演示数据，后端接入后才会跟着流水入库'),
              SizedBox(height: m.kSpace12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final group in _groups) ...<Widget>[
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace10, bottom: m.kSpace6),
                        child: Row(
                          children: <Widget>[
                            DrawIcon(ledgerUiIconOf('group'), size: m.iconSize14, color: s.textTertiary),
                            SizedBox(width: m.kSpace6),
                            Text(group.name, style: AppTextStyles.overline(context)),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: m.kSpace6,
                        runSpacing: m.kSpace6,
                        children: <Widget>[
                          for (final tag in group.tags)
                            LedgerTagOption(
                              tag: tag,
                              picked: _picked.contains(tag.id),
                              onTap: () => setState(
                                () => _picked = _picked.contains(tag.id)
                                    ? _picked.difference(<int>{tag.id})
                                    : <int>{..._picked, tag.id},
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: m.kSpace12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppTextField(
                      controller: _newTag,
                      onSubmitted: (_) => _create(),
                      decoration: const InputDecoration(isDense: true, hintText: '新建标签名'),
                    ),
                  ),
                  SizedBox(width: m.kSpace8),
                  FilledButton.tonal(onPressed: _create, child: const Text('新建')),
                ],
              ),
              if (_groups.isNotEmpty) ...<Widget>[
                SizedBox(height: m.kSpace8),
                Row(
                  children: <Widget>[
                    // 不选就全塞进第一个组，标签组也就失去意义了
                    Text('归入', style: AppTextStyles.caption(context)),
                    SizedBox(width: m.kSpace8),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _groups.any((g) => g.id == _targetGroupId)
                            ? _targetGroupId
                            : _groups.first.id,
                        items: <DropdownMenuItem<int>>[
                          for (final g in _groups)
                            DropdownMenuItem<int>(value: g.id, child: Text(g.name)),
                        ],
                        onChanged: (id) => setState(() => _targetGroupId = id ?? _targetGroupId),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: m.kSpace16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  SizedBox(width: m.kSpace12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_picked.toList()),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LedgerTagOption extends StatelessWidget {
  const LedgerTagOption({super.key, required this.tag, required this.picked, required this.onTap});

  final LedgerTag tag;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radiusPill,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
        decoration: BoxDecoration(
          color: picked ? s.accentContainer : Colors.transparent,
          borderRadius: m.radiusPill,
          border: Border.all(color: picked ? s.accentContainerBorder : s.hairline),
        ),
        child: Text(
          tag.name,
          style: AppTextStyles.body(context).copyWith(
            color: picked ? s.accentText : s.textSecondary,
          ),
        ),
      ),
    );
  }
}
