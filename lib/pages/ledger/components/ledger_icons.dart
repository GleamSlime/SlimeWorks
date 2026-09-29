import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 流水账的图标表。
///
/// 键必须与 Rust `ledger_module` 播种内置类别时写的 `icon` 字段逐字一致——
/// 库里存的是这个字符串，不是图标常量，所以两边改名要一起改。
/// 找不到时一律回落到 [StrokeIcons.category]，不让一条手写数据画出个空洞。
const Map<String, StrokeIcon> kLedgerIcons = <String, StrokeIcon>{
  'restaurant': StrokeIcons.restaurant,
  'bus': StrokeIcons.bus,
  'shoppingCart': StrokeIcons.shoppingCart,
  'game': StrokeIcons.game,
  'home': StrokeIcons.home,
  'firstAid': StrokeIcons.firstAid,
  'book': StrokeIcons.book,
  'building': StrokeIcons.building,
  'gift': StrokeIcons.gift,
  'paw': StrokeIcons.paw,
  'scissors': StrokeIcons.scissors,
  'plane': StrokeIcons.plane,
  'deviceSimChat': StrokeIcons.deviceSim,
  'deviceDesktop': StrokeIcons.deviceDesktop,
  'dots': StrokeIcons.dots,
  'money': StrokeIcons.money,
  'giftCard': StrokeIcons.giftCard,
  'chartLine': StrokeIcons.chartLine,
  'receipt': StrokeIcons.receipt,
  'refund': StrokeIcons.refund,
  'exchange': StrokeIcons.exchange,
  'store': StrokeIcons.store,
  'car': StrokeIcons.bus,
  'coffee': StrokeIcons.restaurant,
  'heart': StrokeIcons.firstAid,
  'wallet': StrokeIcons.accountBalanceWallet,
  'creditCard': StrokeIcons.creditCard,
  'mail': StrokeIcons.mail,
  'trendUp': StrokeIcons.trendingUp,
  'trendDown': StrokeIcons.trendingDown,
};

/// 图标挑选器用的中文名（键顺序就是展示顺序）
const Map<String, String> kLedgerIconLabels = <String, String>{
  'restaurant': '餐饮',
  'bus': '交通',
  'shoppingCart': '购物',
  'game': '娱乐',
  'home': '居家',
  'firstAid': '医疗',
  'book': '学习',
  'building': '住房',
  'gift': '礼物',
  'paw': '宠物',
  'scissors': '美发',
  'plane': '旅行',
  'deviceSimChat': '通讯',
  'deviceDesktop': '数码',
  'store': '门店',
  'money': '现金',
  'giftCard': '补贴',
  'chartLine': '理财',
  'receipt': '票据',
  'refund': '退款',
  'exchange': '转账',
  'dots': '其他',
};

List<String> get kLedgerIconKeys => kLedgerIconLabels.keys.toList(growable: false);

StrokeIcon ledgerIconOf(String key) => kLedgerIcons[key] ?? StrokeIcons.category;

/// 账户类型：值域与 Rust `Account.type` 一致
const Map<String, String> kLedgerAccountTypes = <String, String>{
  'credit_card': '信用卡',
  'debit_card': '储蓄卡',
  'cash': '现金',
  'deposit': '存款',
  'other': '其他',
};

StrokeIcon ledgerAccountIconOf(String type) => switch (type) {
  'credit_card' => StrokeIcons.creditCard,
  'debit_card' => StrokeIcons.accountBalanceWallet,
  'cash' => StrokeIcons.money,
  'deposit' => StrokeIcons.building,
  _ => StrokeIcons.dots,
};

String ledgerAccountTypeLabel(String type) => kLedgerAccountTypes[type] ?? type;
