import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

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

/// 模块自己的 UI 图标（标签、模板、定时、导入导出这类入口）。
///
/// 与 [kLedgerIcons] 分成两张表是刻意的：那张表的键要和 Rust 播种的内置类别
/// 逐字对齐，并且有一条"重复项只有那几组别名"的快照测试守着；把界面图标混进去，
/// 那条测试就会把"转账图标复用了交换符号"误报成类别图标漂移。
const Map<String, StrokeIcon> kLedgerUiIcons = <String, StrokeIcon>{
  'tag': StrokeIcons.label,
  'group': StrokeIcons.folder,
  'transfer': StrokeIcons.exchange,
  'balance': StrokeIcons.tune,
  'template': StrokeIcons.playlistAdd,
  'schedule': StrokeIcons.eventRepeat,
  'data': StrokeIcons.storage,
  'export': StrokeIcons.fileDownload,
  'import': StrokeIcons.upload,
  'filter': StrokeIcons.filterList,
  'calendar': StrokeIcons.calendarMonth,
  'organize': StrokeIcons.category,
  'pending': StrokeIcons.inbox,
  'account': StrokeIcons.assetMenuBill,
};

StrokeIcon ledgerUiIconOf(String key) => kLedgerUiIcons[key] ?? StrokeIcons.dots;

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
///
/// 负债类只有信用卡和借贷两种——判断"这一类是不是欠钱"就看这张表，
/// 别在页面上按名字猜（用户可以把储蓄卡起名叫"信用卡"）。
const Map<String, String> kLedgerAccountTypes = <String, String>{
  'cash': '现金',
  'debit_card': '储蓄卡',
  'credit_card': '信用卡',
  'e_wallet': '电子钱包',
  'deposit': '存款',
  'invest': '投资',
  'loan': '借贷',
  'receivable': '应收款',
  'other': '其他',
};

/// 负债类账户：余额在这里表示"还欠多少"
const Set<String> kLedgerLiabilityTypes = <String>{'credit_card', 'loan'};

bool ledgerAccountIsLiability(String type) => kLedgerLiabilityTypes.contains(type);

/// 标签与标签分组能挑的颜色，顺序就是挑选器的展示顺序。
///
/// 存的是 `#RRGGBB` 文本而不是 [Color]：库里那一列就是文本，图表按它取色。
/// 不能用 `ledgerVizPalette` 那种随深浅色切换的语义色——用户挑定的颜色跟着主题
/// 换色，昨天认得出的"紫色那组"今天就成了别的颜色。
const List<String> kLedgerTagPalette = <String>[
  '#5B8FF9',
  '#61DDAA',
  '#F6BD16',
  '#E8684A',
  '#9270CA',
  '#5D7092',
];

StrokeIcon ledgerAccountIconOf(String type) => switch (type) {
  'cash' => StrokeIcons.money,
  'debit_card' => StrokeIcons.accountBalanceWallet,
  'credit_card' => StrokeIcons.creditCard,
  'e_wallet' => StrokeIcons.phoneAndroid,
  'deposit' => StrokeIcons.building,
  'invest' => StrokeIcons.trendingUp,
  'loan' => StrokeIcons.receipt,
  'receivable' => StrokeIcons.arrowOutward,
  _ => StrokeIcons.dots,
};

String ledgerAccountTypeLabel(String type) => kLedgerAccountTypes[type] ?? type;

/// 四种记账类型的图标与名字
StrokeIcon ledgerTxTypeIconOf(String txType) => switch (txType) {
  kLedgerTxTypeIncome => StrokeIcons.trendingUp,
  kLedgerTxTypeTransfer => StrokeIcons.exchange,
  kLedgerTxTypeBalance => StrokeIcons.tune,
  _ => StrokeIcons.trendingDown,
};

String ledgerTxTypeLabel(String txType) => switch (txType) {
  kLedgerTxTypeIncome => '收入',
  kLedgerTxTypeTransfer => '转账',
  kLedgerTxTypeBalance => '余额调整',
  _ => '支出',
};

/// 记一笔表单顶部的类型切换条，顺序就是按钮顺序
const List<String> kLedgerTxTypes = <String>[
  kLedgerTxTypeExpense,
  kLedgerTxTypeIncome,
  kLedgerTxTypeTransfer,
  kLedgerTxTypeBalance,
];
