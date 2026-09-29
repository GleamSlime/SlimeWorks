// 流水账六个页面的离屏出图 + 逐帧排版冒烟。
//
// FFI 全部走 RustLib.initMock 桩：桩里给的是 Rust 侧那一路 JSON 文本，页面拿到的
// 形状与真实库一致；桩只按方法名给值，不做过滤，所以月份游标要自己钉住，
// 否则出图内容跟着系统日期走，基线每个月红一次。
//
// 数据全是编的（仓库公开，真实账单不许进仓库），金额商户名都只对"排版长得对不对"负责。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/pages/ledger/ledger_accounts_screen.dart';
import 'package:slime_works/pages/ledger/ledger_pending_screen.dart';
import 'package:slime_works/pages/ledger/ledger_records_screen.dart';
import 'package:slime_works/pages/ledger/ledger_screen.dart';
import 'package:slime_works/pages/ledger/ledger_settings_screen.dart';
import 'package:slime_works/pages/ledger/ledger_stats_screen.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

import 'helpers/page_golden.dart';

// ── 窗口档位 ────────────────────────────────────────────────────────────────
//
// 真机的设计稿是固定的（桌面 1920x1080、手机 375x815），窗口比设计稿窄系数就 <1。
// 出图要复现的就是这套系数，所以窗口尺寸和设计尺寸分开给。
const Size _desktopWindow = Size(1440, 900);
const Size _desktopDesign = Size(1920, 1080);
const Size _phoneWindow = Size(390, 844);
const Size _phoneDesign = Size(375, 815);

/// 出图钉住的业务月份
const String _month = '2026-03';

// ── FRB mock ────────────────────────────────────────────────────────────────

String fn(String apiName) =>
    'crateApiLedger${apiName[0].toUpperCase()}${apiName.substring(1)}';

String _symbolName(Symbol symbol) {
  final text = symbol.toString();
  final match = RegExp(r'Symbol\("(.+?)"\)').firstMatch(text);
  return match?.group(1) ?? text;
}

class _MockLedgerApi implements RustLibApi {
  final Map<String, Object?> responses = <String, Object?>{};
  final Map<String, Object? Function(Map<Symbol, Object?>)> responders =
      <String, Object? Function(Map<Symbol, Object?>)>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = _symbolName(invocation.memberName);
    final responder = responders[method];
    if (responder != null) return responder(invocation.namedArguments);
    if (responses.containsKey(method)) return responses[method];
    throw StateError('流水账 mock 缺桩: $method');
  }
}

final _MockLedgerApi _api = _MockLedgerApi();

String _json(List<Map<String, dynamic>> rows) => jsonEncode(rows);

// ── 样例数据 ────────────────────────────────────────────────────────────────

const List<Map<String, dynamic>> _accounts = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'name': '现金钱包',
    'type': 'cash',
    'last4': '',
    'currency': 'CNY',
    'credit_limit': 0,
    'balance': 860.0,
    'sort_order': 1,
    'enabled': true,
    'created_at': '2026-03-01 09:12:00',
  },
  <String, dynamic>{
    'id': 2,
    'name': '信用卡',
    'type': 'credit_card',
    'last4': '0123',
    'currency': 'CNY',
    'credit_limit': 20000,
    'balance': -1580.35,
    'sort_order': 2,
    'enabled': true,
    'created_at': '2026-03-01 09:12:00',
  },
  <String, dynamic>{
    'id': 3,
    'name': '储蓄卡',
    'type': 'debit_card',
    'last4': '4567',
    'currency': 'CNY',
    'credit_limit': 0,
    'balance': 15230.55,
    'sort_order': 3,
    'enabled': true,
    'created_at': '2026-03-01 09:12:00',
  },
  <String, dynamic>{
    'id': 4,
    'name': '已经停用的副卡',
    'type': 'credit_card',
    'last4': '8901',
    'currency': 'CNY',
    'credit_limit': 5000,
    'balance': -20.0,
    'sort_order': 4,
    'enabled': false,
    'created_at': '2026-03-01 09:12:00',
  },
];

const List<Map<String, dynamic>> _expenseCategories = <Map<String, dynamic>>[
  <String, dynamic>{'id': 1, 'name': '餐饮', 'icon': 'restaurant', 'direction': 'expense', 'sort_order': 1, 'is_builtin': true},
  <String, dynamic>{'id': 2, 'name': '交通', 'icon': 'bus', 'direction': 'expense', 'sort_order': 2, 'is_builtin': true},
  <String, dynamic>{'id': 3, 'name': '购物', 'icon': 'shoppingCart', 'direction': 'expense', 'sort_order': 3, 'is_builtin': true},
  <String, dynamic>{'id': 4, 'name': '居家', 'icon': 'home', 'direction': 'expense', 'sort_order': 4, 'is_builtin': true},
  <String, dynamic>{'id': 5, 'name': '医疗', 'icon': 'firstAid', 'direction': 'expense', 'sort_order': 5, 'is_builtin': true},
  <String, dynamic>{'id': 6, 'name': '其他', 'icon': 'dots', 'direction': 'expense', 'sort_order': 6, 'is_builtin': true},
];

const List<Map<String, dynamic>> _incomeCategories = <Map<String, dynamic>>[
  <String, dynamic>{'id': 7, 'name': '工资', 'icon': 'building', 'direction': 'income', 'sort_order': 1, 'is_builtin': true},
  <String, dynamic>{'id': 8, 'name': '补贴', 'icon': 'giftCard', 'direction': 'income', 'sort_order': 2, 'is_builtin': false},
];

/// 拼一笔流水；`_tx` 把联表带出来的账户/类别名一并填上，Rust 侧就是这么返回的。
Map<String, dynamic> _tx({
  required int id,
  required String date,
  required String merchant,
  required double amount,
  String direction = 'expense',
  int accountId = 1,
  int categoryId = 6,
  String source = 'manual',
  String note = '',
  String emailUid = '',
}) {
  final category = [..._expenseCategories, ..._incomeCategories]
      .firstWhere((c) => c['id'] == categoryId);
  final account = _accounts.firstWhere((a) => a['id'] == accountId);
  return <String, dynamic>{
    'id': id,
    'occurred_at': '$date 12:00:00',
    'bill_date': date,
    'direction': direction,
    'amount': amount,
    'currency': 'CNY',
    'account_id': accountId,
    'category_id': categoryId,
    'merchant': merchant,
    'note': note,
    'source': source,
    'rule_id': source == 'email' ? 1 : 0,
    'email_uid': emailUid,
    'status': 'posted',
    'created_at': '$date 12:00:00',
    'updated_at': '$date 12:00:00',
    'account_name': account['name'],
    'category_name': category['name'],
    'category_icon': category['icon'],
    'category_direction': category['direction'],
  };
}

final List<Map<String, dynamic>> _txs = <Map<String, dynamic>>[
  _tx(id: 1, date: '2026-03-28', merchant: '山姆会员商店（内环高架店）', amount: 888.88, accountId: 2, categoryId: 3),
  _tx(id: 2, date: '2026-03-27', merchant: '全家便利店', amount: 28.50, categoryId: 1),
  _tx(id: 3, date: '2026-03-25', merchant: '京东商城', amount: 359.00, accountId: 2, categoryId: 3, source: 'email', emailUid: 'UID 10234'),
  _tx(id: 4, date: '2026-03-21', merchant: '房租', amount: 2600.00, accountId: 3, categoryId: 4, note: '三月与四月合付'),
  _tx(id: 5, date: '2026-03-18', merchant: '地铁出行', amount: 6.00, categoryId: 2),
  _tx(id: 6, date: '2026-03-15', merchant: '连锁药房', amount: 42.80, categoryId: 5),
  _tx(id: 7, date: '2026-03-12', merchant: '星巴克', amount: 36.00, categoryId: 1),
  _tx(id: 8, date: '2026-03-10', merchant: '交通卡充值', amount: 100.00, categoryId: 2),
  _tx(id: 9, date: '2026-03-05', merchant: '本月工资', amount: 12000.00, direction: 'income', accountId: 3, categoryId: 7),
  _tx(id: 10, date: '2026-03-02', merchant: '高温补贴', amount: 320.00, direction: 'income', categoryId: 8),
];

const Map<String, dynamic> _summary = <String, dynamic>{
  'income': 12320.0,
  'expense': 4061.18,
  'net': 8258.82,
  'count': 10,
  'min_date': '2026-03-02',
  'max_date': '2026-03-28',
  'month': _month,
  'month_income': 12320.0,
  'month_expense': 4061.18,
  'month_net': 8258.82,
};

const List<Map<String, dynamic>> _dayRows = <Map<String, dynamic>>[
  <String, dynamic>{'bill_date': '2026-03-02', 'income': 320.0, 'expense': 0.0, 'count': 1},
  <String, dynamic>{'bill_date': '2026-03-12', 'income': 0.0, 'expense': 36.0, 'count': 1},
  <String, dynamic>{'bill_date': '2026-03-18', 'income': 0.0, 'expense': 48.8, 'count': 2},
  <String, dynamic>{'bill_date': '2026-03-25', 'income': 0.0, 'expense': 359.0, 'count': 1},
  <String, dynamic>{'bill_date': '2026-03-28', 'income': 0.0, 'expense': 888.88, 'count': 1},
];

const List<Map<String, dynamic>> _categoryRows = <Map<String, dynamic>>[
  <String, dynamic>{'category_id': 4, 'category_name': '居家', 'category_icon': 'home', 'direction': 'expense', 'total': 2600.0, 'count': 1},
  <String, dynamic>{'category_id': 3, 'category_name': '购物', 'category_icon': 'shoppingCart', 'direction': 'expense', 'total': 1247.88, 'count': 2},
  // Rust 按金额倒序返回，桩也得照这个顺序给，不然出图看着像界面排错了序
  <String, dynamic>{'category_id': 2, 'category_name': '交通', 'category_icon': 'bus', 'direction': 'expense', 'total': 106.0, 'count': 2},
  <String, dynamic>{'category_id': 1, 'category_name': '餐饮', 'category_icon': 'restaurant', 'direction': 'expense', 'total': 64.5, 'count': 2},
];

const List<Map<String, dynamic>> _merchantRows = <Map<String, dynamic>>[
  <String, dynamic>{'merchant': '山姆会员商店（内环高架店）', 'total': 888.88, 'count': 1, 'last_date': '2026-03-28'},
  <String, dynamic>{'merchant': '京东商城', 'total': 359.0, 'count': 1, 'last_date': '2026-03-25'},
  <String, dynamic>{'merchant': '星巴克', 'total': 36.0, 'count': 1, 'last_date': '2026-03-12'},
  <String, dynamic>{'merchant': '全家便利店', 'total': 28.5, 'count': 1, 'last_date': '2026-03-27'},
];

/// 2026-01 故意缺：那个月一笔账都没有，趋势图要留出一个空格子而不是把后面往前挪
const List<Map<String, dynamic>> _monthRows = <Map<String, dynamic>>[
  <String, dynamic>{'month': '2025-10', 'income': 11800.0, 'expense': 9210.4, 'net': 2589.6, 'count': 42},
  <String, dynamic>{'month': '2025-11', 'income': 11800.0, 'expense': 8012.0, 'net': 3788.0, 'count': 38},
  <String, dynamic>{'month': '2025-12', 'income': 15200.0, 'expense': 11040.75, 'net': 4159.25, 'count': 51},
  <String, dynamic>{'month': '2026-02', 'income': 12000.0, 'expense': 6980.0, 'net': 5020.0, 'count': 29},
  <String, dynamic>{'month': '2026-03', 'income': 12320.0, 'expense': 4061.18, 'net': 8258.82, 'count': 10},
];

const List<Map<String, dynamic>> _pendingEmails = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'rule_id': 1,
    'rule_name': '信用卡账单收信',
    'message_uid': 'UID 10241',
    'from_addr': 'no-reply@example-bank.com',
    'subject': '您的信用卡账单已生成（2026年3月）',
    'received_at': '2026-03-29 08:31:02',
    'bill_date': '2026-03-28',
    'tx_count': 6,
    'applied': false,
    'available_credit': 18419.65,
    'points_balance': 12034,
    'warnings': <String>['1 行商户名未能识别，已归到"其他"'],
    'html_len': 71234,
  },
  <String, dynamic>{
    'id': 2,
    'rule_id': 1,
    'rule_name': '信用卡账单收信',
    'message_uid': 'UID 10242',
    'from_addr': 'no-reply@example-bank.com',
    'subject': '您的信用卡账单已生成（2026年3月补充）',
    'received_at': '2026-03-29 09:02:11',
    'bill_date': '2026-03-29',
    'tx_count': 2,
    'applied': false,
    'available_credit': null,
    'points_balance': null,
    'warnings': <String>[],
    'html_len': 1823,
  },
];

const List<Map<String, dynamic>> _receivedEmails = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 3,
    'rule_id': 1,
    'rule_name': '信用卡账单收信',
    'message_uid': 'UID 10234',
    'from_addr': 'no-reply@example-bank.com',
    'subject': '您的信用卡账单已生成（2026年2月）',
    'received_at': '2026-02-28 08:30:40',
    'bill_date': '2026-02-27',
    'tx_count': 4,
    'applied': true,
    'available_credit': 19000.0,
    'points_balance': 11800,
    'warnings': <String>[],
    'html_len': 68211,
  },
];

const List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'name': '信用卡账单收信',
    'enabled': true,
    'protocol': 'imap',
    'host': 'imap.example-bank.com',
    'port': 993,
    'use_ssl': true,
    'username': 'ledger@example.com',
    'mailbox': 'INBOX',
    'sender_match': 'no-reply@example-bank.com',
    'subject_match': '信用卡账单已生成',
    'match_is_regex': false,
    'template_id': 'cmb_daily_bill',
    'template_config': '{}',
    'interval_minutes': 0,
    'daily_time': '08:30',
    'default_account_id': 2,
    'auto_apply': false,
    'accept_invalid_certs': false,
    'last_run_at': '2026-03-29 08:31:02',
    'last_result': '新增 1 封 / 待确认 6 笔',
  },
  <String, dynamic>{
    'id': 2,
    'name': '备用 POP3 通道',
    'enabled': false,
    'protocol': 'pop3',
    'host': 'pop.example-bank.com',
    'port': 995,
    'use_ssl': true,
    'username': 'ledger@example.com',
    'mailbox': 'INBOX',
    'sender_match': '',
    'subject_match': '',
    'match_is_regex': false,
    'template_id': 'auto',
    'template_config': '{}',
    'interval_minutes': 30,
    'daily_time': '',
    'default_account_id': 2,
    'auto_apply': true,
    'accept_invalid_certs': false,
    'last_run_at': '',
    'last_result': '',
  },
];

const List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 3,
    'rule_id': 1,
    'started_at': '2026-03-29 08:30:00',
    'finished_at': '2026-03-29 08:31:02',
    'ok': true,
    'new_emails': 1,
    'new_tx': 0,
    'skipped_tx': 6,
    'detail': '命中 1 封，进入待确认',
  },
  <String, dynamic>{
    'id': 2,
    'rule_id': 1,
    'started_at': '2026-03-28 08:30:00',
    'finished_at': '2026-03-28 08:30:21',
    'ok': false,
    'new_emails': 0,
    'new_tx': 0,
    'skipped_tx': 0,
    'detail': '连接超时（已重试 2 次）',
  },
];

const Map<String, dynamic> _scheduler = <String, dynamic>{
  'running': true,
  'enabled': true,
  'check_interval_secs': 60,
  'last_check_at': '2026-03-29 08:30:00',
  'next_check_at': '2026-03-29 08:31:00',
  'active_rules': 1,
  'last_summary': '上次收取：新增 1 封 / 待确认 6 笔',
};

const List<Map<String, dynamic>> _templates = <Map<String, dynamic>>[
  <String, dynamic>{'id': 'auto', 'name': '自动判断', 'description': '按正文结构在内置模板里挑一个'},
  <String, dynamic>{'id': 'cmb_daily_bill', 'name': '信用卡每日账单', 'description': '逐行读取账单明细表，生成支出流水与额度信息'},
];

const List<Map<String, dynamic>> _merchantMemory = <Map<String, dynamic>>[
  <String, dynamic>{'merchant_key': '全家便利店', 'category_id': 1},
  <String, dynamic>{'merchant_key': '京东商城', 'category_id': 3},
];

void _seedFull() {
  _api.responses
    ..clear()
    ..addAll(<String, Object?>{
      fn('ledgerIsReady'): true,
      fn('ledgerVersion'): '1.0.0-test',
      fn('ledgerListAccounts'): _json(_accounts),
      fn('ledgerListTransactions'): _json(_txs),
      fn('ledgerCountTransactions'): _txs.length,
      fn('ledgerStatsSummary'): jsonEncode(_summary),
      fn('ledgerStatsByDay'): _json(_dayRows),
      fn('ledgerStatsByCategory'): _json(_categoryRows),
      fn('ledgerStatsByMerchant'): _json(_merchantRows),
      fn('ledgerStatsByMonth'): _json(_monthRows),
      fn('ledgerPendingCount'): _pendingEmails.length,
      fn('ledgerListPending'): _json(_pendingEmails),
      fn('ledgerListReceivedEmails'): _json(_receivedEmails),
      fn('ledgerEmailTransactions'): _json(_txs.take(2).toList()),
      fn('ledgerListRules'): _json(_rules),
      fn('ledgerGetLogs'): _json(_logs),
      fn('ledgerListMerchantMemory'): _json(_merchantMemory),
      fn('ledgerSchedulerStatus'): jsonEncode(_scheduler),
      fn('ledgerTemplates'): _json(_templates),
      fn('ledgerHasRulePassword'): true,
    });
  _api.responders
    ..clear()
    ..[fn('ledgerListCategories')] = (args) => switch (args[#direction]) {
      'income' => _json(_incomeCategories),
      _ => _json(_expenseCategories),
    };
}

void _seedEmpty() {
  _seedFull();
  _api.responses
    ..[fn('ledgerListAccounts')] = '[]'
    ..[fn('ledgerListTransactions')] = '[]'
    ..[fn('ledgerCountTransactions')] = 0
    ..[fn('ledgerStatsSummary')] = jsonEncode(<String, dynamic>{'month': _month})
    ..[fn('ledgerStatsByDay')] = '[]'
    ..[fn('ledgerStatsByCategory')] = '[]'
    ..[fn('ledgerStatsByMerchant')] = '[]'
    ..[fn('ledgerStatsByMonth')] = '[]'
    ..[fn('ledgerPendingCount')] = 0
    ..[fn('ledgerListPending')] = '[]'
    ..[fn('ledgerListReceivedEmails')] = '[]'
    ..[fn('ledgerListRules')] = '[]'
    ..[fn('ledgerGetLogs')] = '[]'
    ..[fn('ledgerListMerchantMemory')] = '[]'
    ..[fn('ledgerSchedulerStatus')] = jsonEncode(<String, dynamic>{'check_interval_secs': 60});
  _api.responders[fn('ledgerListCategories')] = (_) => '[]';
}

// ── 出图工具 ────────────────────────────────────────────────────────────────

/// 服务是 GetIt 单例，`ensureInitialized` 只在第一次真正跑；
/// 桩必须在第一次 pump 页面之前装好。
Future<void> _pumpLedger(
  WidgetTester tester,
  Widget page, {
  required Size window,
  required Size design,
  bool dark = false,
}) async {
  if (!getIt.isRegistered<LedgerService>()) {
    getIt.registerSingleton<LedgerService>(LedgerService());
  }
  // 桌面档挂了真顶栏，顶栏读 SidebarController 的展开态和当前路由
  if (!Get.isRegistered<SidebarController>()) {
    Get.put<SidebarController>(
      SidebarController()
        ..isExpanded.value = true
        ..selectedRoute.value = '/ledger',
      permanent: true,
    );
  }
  // ScreenChrome 靠这个开关决定标题/标签页画在全局顶栏还是页面内的 AppBar，
  // 而它是按 dotenv 的窗口宽一次性算死的。不跟着档位改，手机档就只剩正文，
  // 页面标题和那排标签页根本没排过版。
  registerPageServices();
  final phone = window == _phoneWindow;
  getIt<DesktopScreenProvider>()
    ..isMobile.value = phone
    ..isDesktop.value = !phone;
  await pumpAppPage(
    tester,
    page,
    dark: dark,
    size: window,
    withTopBar: !phone,
    designSize: design,
  );
  await advance(tester);
}

/// 把页面的月份游标钉死，出图内容才不跟着系统日期漂
///
/// VM 由 BasePageState 自己 new，测试里没有注册进 Get，只能从 State 上取。
/// 只有三页有月份口径，其余页面 pin 为 null 直接跳过。
final Map<String, void Function(dynamic vm)?> _pinBySlug = <String, void Function(dynamic vm)?>{
  'home': (vm) => vm.goToMonth(_month),
  'stats': (vm) => vm.goToMonth(_month),
  'records': (vm) => vm.setMonth(_month),
};

Future<void> _pinMonth(
  WidgetTester tester,
  Finder finder,
  String slug,
) async {
  final pin = _pinBySlug[slug];
  if (pin == null) return;
  pin((tester.state(finder) as dynamic).viewModel);
  await tester.pump();
  await advance(tester);
}

Future<void> _expectNoException(WidgetTester tester) async {
  final failures = <Object?>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    failures.add(error);
  }
  expect(failures, isEmpty);
}

final List<(String, Widget)> _pages = <(String, Widget)>[
  ('home', const LedgerScreen()),
  ('records', const LedgerRecordsScreen()),
  ('stats', const LedgerStatsScreen()),
  ('pending', const LedgerPendingScreen()),
  ('settings', const LedgerSettingsScreen()),
  ('accounts', const LedgerAccountsScreen()),
];

void main() {
  setUpAll(() async {
    // 一个 isolate 只能 initMock 一次，桩表按用例重建就够了
    RustLib.initMock(api: _api);
    // 不挂字体：中文全是豆腐块、描边图标全是方框，出图没法当验收依据
    await loadAppFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 安全存储没有测试替身就会挂在平台信道上：fake async 等不到原生回包，
    // 整条 load 链永远不返回（表现为测试进程满核转圈，不是超时报错）。
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      LedgerService.secretKey(1): 'stub-password',
    });
    _seedFull();
  });

  group('流水账页面出图', () {
    for (final (slug, page) in _pages) {
      final type = page.runtimeType;
      testWidgets('$slug 桌面 1440x900', (tester) async {
        await _pumpLedger(
          tester,
          page,
          window: _desktopWindow,
          design: _desktopDesign,
        );
        await _pinMonth(tester, find.byType(type), slug);
        await expectLater(
          find.byType(type),
          matchesGoldenFile('goldens/ledger_${slug}_desktop.png'),
        );
        await unmountPage(tester);
      }, tags: <String>['golden']);

      testWidgets('$slug 手机 390x844', (tester) async {
        await _pumpLedger(
          tester,
          page,
          window: _phoneWindow,
          design: _phoneDesign,
        );
        await _pinMonth(tester, find.byType(type), slug);
        await expectLater(
          find.byType(type),
          matchesGoldenFile('goldens/ledger_${slug}_mobile.png'),
        );
        await unmountPage(tester);
      }, tags: <String>['golden']);
    }

    testWidgets('首页暗色', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
        dark: true,
      );
      await _pinMonth(tester, find.byType(LedgerScreen), 'home');
      await expectLater(
        find.byType(LedgerScreen),
        matchesGoldenFile('goldens/ledger_home_dark.png'),
      );
      await unmountPage(tester);
    }, tags: <String>['golden']);

    testWidgets('空账本首屏', (tester) async {
      _seedEmpty();
      await _pumpLedger(
        tester,
        const LedgerScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await _pinMonth(tester, find.byType(LedgerScreen), 'home');
      expect(find.text('这个月还没有账'), findsOneWidget);
      // 空的是这个月，不是整本账：月份条必须还在，不然用户没法翻到有账的那个月
      expect(find.text('2026年3月'), findsOneWidget);
      await expectLater(
        find.byType(LedgerScreen),
        matchesGoldenFile('goldens/ledger_home_empty.png'),
      );
      await unmountPage(tester);
    }, tags: <String>['golden']);

    testWidgets('空待确认首屏', (tester) async {
      _seedEmpty();
      await _pumpLedger(
        tester,
        const LedgerPendingScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('没有等你确认的账单'), findsOneWidget);
      await expectLater(
        find.byType(LedgerPendingScreen),
        matchesGoldenFile('goldens/ledger_pending_empty.png'),
      );
      await unmountPage(tester);
    }, tags: <String>['golden']);
  });

  // 出图只拍终态，这一组把途中的每一帧都过一遍：过冲、级联、窄宽度都是在途中炸的
  group('逐帧排版冒烟', () {
    for (final (slug, page) in _pages) {
      final type = page.runtimeType;
      testWidgets('$slug 桌面逐帧无异常', (tester) async {
        await _pumpLedger(
          tester,
          page,
          window: _desktopWindow,
          design: _desktopDesign,
        );
        await _pinMonth(tester, find.byType(type), slug);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await _expectNoException(tester);
        await unmountPage(tester);
      });

      testWidgets('$slug 手机逐帧无异常', (tester) async {
        await _pumpLedger(
          tester,
          page,
          window: _phoneWindow,
          design: _phoneDesign,
        );
        await _pinMonth(tester, find.byType(type), slug);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await _expectNoException(tester);
        await unmountPage(tester);
      });
    }
  });

  group('首屏真的画出了数据', () {
    testWidgets('首页：概览 + 最近流水', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await _pinMonth(tester, find.byType(LedgerScreen), 'home');
      expect(find.text('2026年3月'), findsWidgets);
      expect(find.text('最近流水'), findsOneWidget);
      expect(find.text('全家便利店'), findsWidgets);
      expect(find.text('有 2 笔邮件账单等你确认'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('待确认：邮件标题与溯源', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerPendingScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('您的信用卡账单已生成（2026年3月）'), findsOneWidget);
      expect(find.text('已入账的邮件（1）'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('设置：规则与日志', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerSettingsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('信用卡账单收信'), findsOneWidget);
      expect(find.text('备用 POP3 通道'), findsOneWidget);
      expect(find.textContaining('命中 1 封'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('账户与类别：四类账户都在', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerAccountsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('现金钱包'), findsOneWidget);
      expect(find.text('已经停用的副卡'), findsOneWidget);
      expect(find.text('全家便利店'), findsOneWidget);
      await unmountPage(tester);
    });
  });
}
