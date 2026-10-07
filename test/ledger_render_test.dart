// 流水账九个页面的离屏出图 + 逐帧排版冒烟。
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
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/widgets/app_chips.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';
import 'package:slime_works/pages/ledger/ledger_accounts_screen.dart';
import 'package:slime_works/pages/ledger/ledger_data_screen.dart';
import 'package:slime_works/pages/ledger/ledger_organize_screen.dart';
import 'package:slime_works/pages/ledger/ledger_pending_screen.dart';
import 'package:slime_works/pages/ledger/ledger_records_screen.dart';
import 'package:slime_works/pages/ledger/ledger_screen.dart';
import 'package:slime_works/pages/ledger/ledger_settings_screen.dart';
import 'package:slime_works/pages/ledger/ledger_stats_screen.dart';
import 'package:slime_works/pages/ledger/ledger_templates_screen.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/src/rust/frb_generated.dart';
import 'package:slime_works/view_models/ledger/ledger_data_viewmodel.dart';

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

/// 带第二级的类别表：等 Rust 给 categories 补上 parent_id 列，返回的就是这个形状。
/// 现在真库全是 parent_id=0 的一级类别，所以这份 fixture 只在测试里喂，
/// 用来钉住"两级树怎么铺、父类行给什么按钮"这两件事。
const List<Map<String, dynamic>> _treeCategories = <Map<String, dynamic>>[
  <String, dynamic>{'id': 1, 'name': '餐饮', 'icon': 'restaurant', 'direction': 'expense', 'sort_order': 1, 'is_builtin': true, 'parent_id': 0},
  <String, dynamic>{'id': 2, 'name': '交通', 'icon': 'bus', 'direction': 'expense', 'sort_order': 2, 'is_builtin': true, 'parent_id': 0},
  <String, dynamic>{'id': 6, 'name': '其他', 'icon': 'dots', 'direction': 'expense', 'sort_order': 6, 'is_builtin': true, 'parent_id': 0},
  <String, dynamic>{'id': 9, 'name': '早餐', 'icon': 'restaurant', 'direction': 'expense', 'sort_order': 1, 'is_builtin': false, 'parent_id': 1},
  <String, dynamic>{'id': 10, 'name': '工作日午餐', 'icon': 'restaurant', 'direction': 'expense', 'sort_order': 2, 'is_builtin': false, 'parent_id': 1},
  <String, dynamic>{'id': 11, 'name': '打车', 'icon': 'bus', 'direction': 'expense', 'sort_order': 1, 'is_builtin': false, 'parent_id': 2},
  <String, dynamic>{'id': 7, 'name': '工资', 'icon': 'building', 'direction': 'income', 'sort_order': 1, 'is_builtin': true, 'parent_id': 0},
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
      // 这两个是异步接口（FRB 生成的是 Future<String>），桩必须给 Future，
      // 给裸字符串会在返回值上做类型检查时炸掉
      fn('ledgerCheckRule'): Future<String>.value('收取 1 封新邮件，新增 6 笔流水，跳过 0 笔（2 秒）'),
      fn('ledgerBackfillRule'):
          Future<String>.value('历史回补：扫描 200 封，新增 3 封账单 / 6 笔流水，跳过 0 笔（41 秒）'),
      fn('ledgerGetLogs'): _json(_logs),
      fn('ledgerListMerchantMemory'): _json(_merchantMemory),
      fn('ledgerSchedulerStatus'): jsonEncode(_scheduler),
      fn('ledgerTemplates'): _json(_templates),
      fn('ledgerHasRulePassword'): true,
      // 模板页"用一次"走的是真账链路：查重 →（像重了才问）→ 写入。
      // 不桩这两个，点模板卡片就会挂在 MissingStubError 上。
      fn('ledgerCheckDuplicate'): '{"duplicated": false, "existing_id": 0, "existing_desc": ""}',
      fn('ledgerAddTransaction'): 99,
    });
  _api.responders
    ..clear()
    ..[fn('ledgerListCategories')] = (args) => switch (args[#direction]) {
      'income' => _json(_incomeCategories),
      'expense' => _json(_expenseCategories),
      // 不带方向就是全要：Rust 的 list_categories("") 返回两个方向的并集
      _ => _json(<Map<String, dynamic>>[..._expenseCategories, ..._incomeCategories]),
    };
  // 数笔数的桩要真按 filter 筛：明细页翻月份、导出页换区间都靠它，
  // 一律返回总笔数就等于没测这两条链路。桩里 10 笔全在 2026-03 且都已入账。
  _api.responders[fn('ledgerCountTransactions')] = (args) {
    final filter = jsonDecode(args[#filterJson] as String) as Map<String, dynamic>;
    final status = (filter['status'] ?? '') as String;
    final start = (filter['start_date'] ?? '') as String;
    final end = (filter['end_date'] ?? '') as String;
    return _txs.where((t) {
      if (status.isNotEmpty && t['status'] != status) return false;
      final date = t['bill_date'] as String;
      if (start.isNotEmpty && date.compareTo(start) < 0) return false;
      if (end.isNotEmpty && date.compareTo(end) > 0) return false;
      return true;
    }).length;
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
  // responder 比 responses 先查：不一起覆盖，上面那句"笔数归零"就是空话
  _api.responders[fn('ledgerCountTransactions')] = (_) => 0;
}

/// 换成带第二级的类别表（真库还没有 parent_id 列，这个形状只在测试里出现）
void _seedTree() {
  _api.responders[fn('ledgerListCategories')] = (args) => switch (args[#direction]) {
    'income' => _json(_treeCategories.where((c) => c['direction'] == 'income').toList()),
    'expense' => _json(_treeCategories.where((c) => c['direction'] == 'expense').toList()),
    _ => _json(_treeCategories),
  };
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
  ('organize', const LedgerOrganizeScreen()),
  ('templates', const LedgerTemplatesScreen()),
  ('data', const LedgerDataScreen()),
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

    testWidgets('待确认：回补历史挨着立即收取，点了先确认再真跑', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerPendingScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      // 桩里只有一条启用规则，所以两枚胶囊都是"直接跑"，不套菜单
      final now = find.text('立即收取');
      final history = find.text('回补历史');
      expect(now, findsOneWidget);
      expect(history, findsOneWidget);
      // 位置也钉住：同一行、回补在立即收取右边——用户找的就是"旁边那个"
      expect(
        tester.getTopLeft(history).dy,
        closeTo(tester.getTopLeft(now).dy, 1.0),
        reason: '两枚胶囊必须在同一条顶栏带上',
      );
      expect(
        tester.getTopLeft(history).dx,
        greaterThan(tester.getTopLeft(now).dx),
        reason: '回补历史排在立即收取右边',
      );

      await tester.tap(history);
      await advance(tester);
      expect(find.textContaining('回补「信用卡账单收信」的历史邮件'), findsOneWidget);

      await tester.tap(find.text('开始回补'));
      // 收取是异步 FFI：桩里的 Future 要真事件循环才翻得过来，
      // fake async 的 pump 只会把它一直吊在「正在回补历史邮件…」。
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await advance(tester);
      // 这句概况来自 mock 的 ledger_backfill_rule 桩：能看见就说明
      // 按钮 → 确认框 → 服务 → FFI 整条链路真的走通了，而不只是画了个按钮
      expect(find.textContaining('历史回补：扫描 200 封'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('设置：每条规则都配一个回补历史入口', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerSettingsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('立即收取'), findsNWidgets(2));
      expect(find.text('回补历史'), findsNWidgets(2));
      await unmountPage(tester);
    });

    testWidgets('设置：回补历史要先确认，取消就什么都不发', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerSettingsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await tester.tap(find.text('回补历史').first);
      await advance(tester);
      expect(find.textContaining('已经入过账的会自动跳过'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await advance(tester);
      expect(find.textContaining('回补「'), findsNothing);
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

  // 明细页这轮改的全是交互：页型切换、本地筛、长按菜单。出图只拍终态拍不到，
  // 所以这一组每条分支各点一遍，顺带把"筛的是已读到的那一页"这句实话钉住。
  group('明细页交互', () {
    dynamic vmOf(WidgetTester tester) =>
        (tester.state(find.byType(LedgerRecordsScreen)) as dynamic).viewModel;

    Future<void> openRecords(WidgetTester tester) async {
      await _pumpLedger(
        tester,
        const LedgerRecordsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await _pinMonth(tester, find.byType(LedgerRecordsScreen), 'records');
    }

    testWidgets('切日历停在列表筛中的那个月，格子按周一开头排', (tester) async {
      await openRecords(tester);
      // 单月区间不画月头：日组头已经写着 3月28日，再来一行"2026 年 3 月"是重复
      expect(find.text('2026 年 3 月'), findsNothing);
      await vmOf(tester).setCalendarMode(true);
      await advance(tester);
      expect(find.text('2026 年 3 月'), findsOneWidget);
      // 桩里 3-28 支 888.88、3-02 收 320；格子里是当天结余的绝对值，舍到元才放得下
      expect(find.text('889'), findsOneWidget);
      expect(find.text('320'), findsOneWidget);
      // 2026-03-01 是周日，周日必须在那一行的最后一列，次日（周一）另起一行第一列
      expect(
        tester.getCenter(find.text('1')).dx,
        greaterThan(tester.getCenter(find.text('2')).dx),
        reason: '周日排在最后一列，不是顶到第一列',
      );
      expect(
        tester.getCenter(find.text('1')).dy,
        lessThan(tester.getCenter(find.text('2')).dy),
      );
      await unmountPage(tester);
    });

    testWidgets('日历点一天：回列表并只看那天，再点取消', (tester) async {
      await openRecords(tester);
      await vmOf(tester).setCalendarMode(true);
      await advance(tester);
      await tester.tap(find.text('28'));
      await advance(tester);
      expect(find.text('山姆会员商店（内环高架店）'), findsOneWidget);
      expect(find.text('全家便利店'), findsNothing);
      // 筛选条上挂着"只看 X"那颗胶囊，摘掉就回到整月
      expect(find.textContaining('只看'), findsOneWidget);
      await tester.tap(find.textContaining('只看'));
      await advance(tester);
      expect(find.text('全家便利店'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('金额区间：只在已读到的一页里筛，界面上要写明', (tester) async {
      await openRecords(tester);
      await vmOf(tester).setAmountRange(400.0, 0.0);
      await advance(tester);
      expect(find.text('山姆会员商店（内环高架店）'), findsOneWidget);
      expect(find.text('房租'), findsOneWidget);
      expect(find.text('本月工资'), findsOneWidget);
      expect(find.text('京东商城'), findsNothing);
      expect(find.text('全家便利店'), findsNothing);
      expect(find.textContaining('是在已读到的 10 笔里筛的'), findsOneWidget);

      // "清空"得连区间一起清掉，否则用户以为清干净了其实还筛着一个月
      await tester.ensureVisible(find.text('清空'));
      await tester.tap(find.text('清空'));
      await advance(tester);
      expect(find.text('全家便利店'), findsOneWidget);
      expect(find.textContaining('是在已读到的'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('类型=转账：本地筛到空，空态要说是"没符合条件"', (tester) async {
      await openRecords(tester);
      await vmOf(tester).setTxType('transfer');
      await advance(tester);
      // 桩里的流水都没有 tx_type 列，effectiveType 回落到收支方向，所以转账必空
      expect(find.text('没有符合条件的流水'), findsOneWidget);
      expect(find.text('还没有流水'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('长按一行出三个动作', (tester) async {
      await openRecords(tester);
      await tester.longPress(find.text('山姆会员商店（内环高架店）'));
      await advance(tester);
      expect(find.text('再记一笔同样的'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      await unmountPage(tester);
    });

    // 跨月才画月头。桩按方法名给值、不认日期条件，所以这里直接换掉这一页的数据。
    testWidgets('跨月区间：每月一行月头，写的是本月的和', (tester) async {
      _api.responders[fn('ledgerListTransactions')] = (_) => _json(
        <Map<String, dynamic>>[
          _tx(id: 21, date: '2026-03-28', merchant: '山姆会员商店（内环高架店）', amount: 888.88, accountId: 2, categoryId: 3),
          _tx(id: 22, date: '2026-03-10', merchant: '交通卡充值', amount: 100.00, categoryId: 2),
          _tx(id: 23, date: '2026-02-20', merchant: '二月房租', amount: 2600.00, accountId: 3, categoryId: 4),
        ],
      );
      await _pumpLedger(
        tester,
        const LedgerRecordsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      expect(find.text('2026 年 3 月'), findsOneWidget);
      expect(find.text('2026 年 2 月'), findsOneWidget);
      // 988.88 = 888.88 + 100.00，只有月头会算这个和；任何一行单独都对不上
      expect(find.text('-¥988.88'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('2026 年 3 月')).dy,
        lessThan(tester.getTopLeft(find.text('2026 年 2 月')).dy),
        reason: '日期倒序：新的月份在上面',
      );
      await unmountPage(tester);
    });

    // 日历页型在 390 宽上一格只有 52 逻辑像素，金额会不会被省略号吃掉只能看出图
    testWidgets('records 日历页型 手机 390x844', (tester) async {
      await _pumpLedger(
        tester,
        const LedgerRecordsScreen(),
        window: _phoneWindow,
        design: _phoneDesign,
      );
      await _pinMonth(tester, find.byType(LedgerRecordsScreen), 'records');
      await vmOf(tester).setCalendarMode(true);
      await advance(tester);
      await expectLater(
        find.byType(LedgerRecordsScreen),
        matchesGoldenFile('goldens/ledger_records_calendar_mobile.png'),
      );
      await unmountPage(tester);
    }, tags: <String>['golden']);
  });

  // 统计页这一轮加的是两个自由度（区间、聚合轴）和一条回推出来的净资产曲线。
  // 出图只能拍到终态，拍不到"换轴其实没查库""空掉的月份还留着格子"这两件事，
  // 所以这一组按分支各点一遍。
  group('统计页交互', () {
    dynamic vmOf(WidgetTester tester) =>
        (tester.state(find.byType(LedgerStatsScreen)) as dynamic).viewModel;

    Future<void> openStats(WidgetTester tester) async {
      await _pumpLedger(
        tester,
        const LedgerStatsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await _pinMonth(tester, find.byType(LedgerStatsScreen), 'stats');
    }

    testWidgets('区间变长就自动降到更粗的轴，"全部"跟着数据铺格子', (tester) async {
      await openStats(tester);
      // 钉住的那个月只有 31 天，按日 31 格还读得清
      expect(vmOf(tester).axis.value, LedgerAxis.day);
      expect(find.text('按日'), findsOneWidget);

      await vmOf(tester).setPreset(LedgerRangePreset.thisYear);
      await advance(tester);
      expect(vmOf(tester).axis.value, LedgerAxis.month, reason: '一年按日就是一团锯齿');
      expect(vmOf(tester).rangeLabel, startsWith('今年 · '));

      await vmOf(tester).setPreset(LedgerRangePreset.all);
      await advance(tester);
      expect(vmOf(tester).rangeLabel, '全部时间');
      // 区间是"全部"时没有起止日期，格子跟着后端回来的日行铺：桩里全在 2026-03，
      // 按月就只有一格，而不是凭空排出一排年份
      expect((vmOf(tester).axisBuckets as List).length, 1);
      await unmountPage(tester);
    });

    testWidgets('点过轴就不再自作主张', (tester) async {
      await openStats(tester);
      await tester.tap(find.text('按日'));
      await advance(tester);
      await tester.tap(find.text('按年'));
      await advance(tester);
      expect(vmOf(tester).axis.value, LedgerAxis.year);

      await vmOf(tester).setPreset(LedgerRangePreset.thisYear);
      await advance(tester);
      expect(vmOf(tester).axis.value, LedgerAxis.year, reason: '用户点过的轴优先于区间长度');
      await unmountPage(tester);
    });

    testWidgets('换轴只在本地归并，不重新查库', (tester) async {
      var dayCalls = 0;
      _api.responders[fn('ledgerStatsByDay')] = (args) {
        dayCalls++;
        return _json(_dayRows);
      };
      await openStats(tester);
      final before = dayCalls;
      expect(before, greaterThan(0));
      // 按日：桩里 5 个有账的日子落在 31 天区间里，空格子也得占着
      expect(vmOf(tester).axisRows.length, 31);

      await vmOf(tester).setAxis(LedgerAxis.quarter);
      await advance(tester);
      expect(dayCalls, before, reason: '换轴是把日行按键归并，不该再查一遍');
      expect(vmOf(tester).axisRows.length, 1);
      // 3 月全在一季度里：36 + 48.8 + 359 + 888.88
      expect((vmOf(tester).axisExpense as List).single, closeTo(1332.68, 0.001));
      expect((vmOf(tester).axisIncome as List).single, closeTo(320.0, 0.001));
      await unmountPage(tester);
    });

    testWidgets('方向游标带着查询条件和"最忙那格"一起走', (tester) async {
      final seen = <String>[];
      _api.responders[fn('ledgerStatsByDay')] = (args) {
        seen.add(jsonDecode(args[#filterJson] as String)['direction'] as String);
        return _json(_dayRows);
      };
      await openStats(tester);
      await tester.ensureVisible(find.textContaining('最忙的是'));
      expect(find.textContaining('最忙的是3月28日：支出'), findsOneWidget);

      await vmOf(tester).setDirection(kLedgerDirectionIncome);
      await advance(tester);
      // 按日行是唯一一份既能带方向又能自己折的原料，切方向必须真的换查询条件
      expect(seen.first, 'expense');
      expect(seen.last, 'income');
      await tester.ensureVisible(find.textContaining('最忙的是'));
      expect(find.textContaining('最忙的是3月2日：收入'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('净资产是回推的，空掉的月份照样留一格', (tester) async {
      await openStats(tester);
      final vm = vmOf(tester);
      // 只算启用中的账户：860 − 1580.35 + 15230.55，停用的副卡不进合计
      expect(vm.netWorthNow, closeTo(14510.2, 0.001));
      final points = vm.assetPoints as List;
      // 桩里 2025-10..2026-03 只有 5 个月有账，2026-01 一笔都没有
      expect(points.length, 6);
      expect(points.first.date, '2025-10');
      expect(points.last.date, '2026-03');
      expect(points.last.netWorth, closeTo(14510.2, 0.001));
      // 往前一格就扣掉后一格的净收支：3 月净 8258.82
      expect(points[points.length - 2].netWorth, closeTo(6251.38, 0.001));
      // 1 月没有流水，点位与 12 月持平——格子在、钱没动，这两件事得分开说
      expect(points[3].date, '2026-01');
      expect(points[3].netWorth, points[2].netWorth);
      await unmountPage(tester);
    });

    testWidgets('点图例只看一类，再点回全部', (tester) async {
      await openStats(tester);
      await tester.ensureVisible(find.text('居家'));
      await tester.tap(find.text('居家'));
      await advance(tester);
      expect(find.text('看全部类别'), findsOneWidget);
      await tester.ensureVisible(find.text('看全部类别'));
      await tester.tap(find.text('看全部类别'));
      await advance(tester);
      expect(find.text('看全部类别'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('空账本：说"这段时间没有流水"而不是没数据', (tester) async {
      _seedEmpty();
      await _pumpLedger(
        tester,
        const LedgerStatsScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      await _pinMonth(tester, find.byType(LedgerStatsScreen), 'stats');
      expect(find.text('这段时间还没有流水'), findsOneWidget);
      await unmountPage(tester);
    });
  });

  // 这一页左半（类别）在 Rust，右半（标签）在桩仓库。
  // 两半的"能不能删、删了会怎样"口径完全不同，所以分别钉一遍。
  group('分类与标签页', () {
    setUp(() async {
      // 桩仓库是进程级单例，用例之间必须清零，否则上一条建的分组会串进来
      await LedgerStubStore.instance.resetForTest();
    });

    Future<void> openOrganize(WidgetTester tester) async {
      await _pumpLedger(
        tester,
        const LedgerOrganizeScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
    }

    /// 这一页正文的那个可滚区域
    ///
    /// ListView 懒建：屏幕外的分组、页顶的回执都根本没建出来，所以查它们之前
    /// 必须先把滚到的位置对上，不能指望 finder 穿到没构建的子树里。
    Finder organizeList() => find.descendant(
      of: find.byType(LedgerOrganizeScreen),
      matching: find.byType(Scrollable),
    ).first;

    Future<void> scrollToTop(WidgetTester tester) async {
      await tester.drag(organizeList(), const Offset(0, 2400));
      await advance(tester);
    }

    Future<void> reveal(WidgetTester tester, Finder target) =>
        tester.scrollUntilVisible(target, 200, scrollable: organizeList());

    testWidgets('库里只有一级类别时，不摆一个点了也不生效的"上级"控件', (tester) async {
      await openOrganize(tester);
      expect(find.text('餐饮'), findsOneWidget);
      expect(find.text('工资'), findsOneWidget);
      expect(find.textContaining('父类：'), findsNothing);
      expect(find.byTooltip('添加子类'), findsNothing);

      await tester.tap(find.text('添加').first);
      await advance(tester);
      expect(find.text('上级类别'), findsNothing);
      expect(find.text('图标'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await advance(tester);
      await unmountPage(tester);
    });

    testWidgets('有第二级就铺成树：子类缩进、写清父类，父类行才有「添加子类」', (tester) async {
      _seedTree();
      await openOrganize(tester);
      expect(find.text('早餐'), findsOneWidget);
      expect(find.text('工作日午餐'), findsOneWidget);
      expect(find.textContaining('父类：餐饮'), findsNWidgets(2));
      // 只有根类别行配「添加子类」：口径只做两级
      expect(find.byTooltip('添加子类'), findsNWidgets(4));
      expect(
        tester.getTopLeft(find.text('早餐')).dx,
        greaterThan(tester.getTopLeft(find.text('餐饮')).dx),
        reason: '子类缩进在父类下面',
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('category-row:1')),
          matching: find.byTooltip('添加子类'),
        ),
      );
      await advance(tester);
      expect(find.text('在「餐饮」下添加子类'), findsOneWidget);
      expect(find.text('上级类别'), findsOneWidget);
      final chips = tester.widgetList<TagChip>(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TagChip)),
      );
      expect(
        chips.firstWhere((TagChip chip) => chip.label == '餐饮').selected,
        isTrue,
        reason: '从父类行点进来的，上级就该已经选中',
      );
      await unmountPage(tester);
    });

    testWidgets('标签那一半来自桩仓库，页面上要写明', (tester) async {
      await openOrganize(tester);
      expect(find.textContaining('标签是演示数据'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      // 种子里"出差"排在组内第 0 个，useCount=(0*7+3)%19=3
      expect(find.text('出差 · 3笔'), findsOneWidget);
      expect(find.text('未分组'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('新建分组就地可见，回执写在页顶', (tester) async {
      await openOrganize(tester);
      await reveal(tester, find.text('添加分组'));
      await tester.tap(find.text('添加分组'));
      await advance(tester);
      await tester.enterText(find.bySubtype<TextField>(), '实验');
      await tester.tap(find.text('保存'));
      await advance(tester);
      expect(find.text('实验'), findsOneWidget);
      await scrollToTop(tester);
      expect(find.textContaining('分组「实验」已添加'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('删标签先报"有几笔挂着它"，取消就不动', (tester) async {
      await openOrganize(tester);
      final remove = find.byKey(const ValueKey<String>('tag-remove:出差 · 3笔'));
      await reveal(tester, remove);
      await tester.tap(remove);
      await advance(tester);
      expect(find.text('删除标签「出差」？'), findsOneWidget);
      expect(find.textContaining('有 3 笔流水挂着它'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await advance(tester);
      expect(find.text('出差 · 3笔'), findsOneWidget);

      await reveal(tester, remove);
      await tester.tap(remove);
      await advance(tester);
      await tester.tap(find.text('删除'));
      await advance(tester);
      expect(find.text('出差 · 3笔'), findsNothing);
      await scrollToTop(tester);
      expect(find.textContaining('标签「出差」已删除'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('没归组的标签单独一块，不会静默藏起来', (tester) async {
      final store = LedgerStubStore.instance;
      await store.init();
      // 挑标签的对话框就地新建、当时还没有任何分组，就会落在 groupId=0
      await store.upsertTagByName('临时标签');
      await openOrganize(tester);
      // 这块排在所有分组卡片下面，不滚过去根本没建出来
      await reveal(tester, find.text('未分组'));
      expect(find.text('未分组'), findsOneWidget);
      expect(find.text('临时标签'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('删类别的影响面由 Rust 给，页面原样透出', (tester) async {
      _seedTree();
      // ledger_delete_category 在 FRB 那边是同步函数，桩要给裸字符串
      _api.responses[fn('ledgerDeleteCategory')] = '类别已删除（2 笔流水归入其他支出）';
      await openOrganize(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('category-row:9')),
          matching: find.byTooltip('删除'),
        ),
      );
      await advance(tester);
      expect(find.text('删除「早餐」？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await advance(tester);
      expect(find.textContaining('类别已删除（2 笔流水归入其他支出）'), findsOneWidget);
      await unmountPage(tester);
    });

    // 两级树 + 标签块同时在场的样子，只有一级时那一档上面已经按断言查过
    testWidgets('organize 两级树 桌面 1440x900', (tester) async {
      _seedTree();
      await openOrganize(tester);
      await expectLater(
        find.byType(LedgerOrganizeScreen),
        matchesGoldenFile('goldens/ledger_organize_tree_desktop.png'),
      );
      await unmountPage(tester);
    }, tags: <String>['golden']);
  });

  // 模板与定时：模板在桩仓库，按模板记下来的那一笔进真账（Rust 的账本）。
  // 所以这一组既钉"演示的那半"（回写模板、规则开关），也钉"真的那半"（查重→入账→计数）。
  group('模板与定时页', () {
    setUp(() async {
      await LedgerStubStore.instance.resetForTest();
    });

    Future<void> openTemplates(WidgetTester tester) async {
      await _pumpLedger(
        tester,
        const LedgerTemplatesScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
    }

    Finder templatesList() => find.descendant(
      of: find.byType(LedgerTemplatesScreen),
      matching: find.byType(Scrollable),
    ).first;

    Future<void> scrollToTop(WidgetTester tester) async {
      await tester.drag(templatesList(), const Offset(0, 2400));
      await advance(tester);
    }

    /// 把懒建的 ListView 一格一格往下推，直到目标出现为止
    ///
    /// 不用 `scrollUntilVisible`：它找到之后还会再 `element()` 取一次那个 widget，
    /// 而这一页项目多、滚得远，取的时候卡片已经被回收了，报出来的是没头没尾的
    /// "Bad state: No element"，看不出到底是哪一行没渲染。
    Future<void> reveal(WidgetTester tester, Finder target) async {
      for (var i = 0; i < 24 && target.evaluate().isEmpty; i++) {
        await tester.drag(templatesList(), const Offset(0, -260));
        await advance(tester);
      }
    }

    /// 弹窗背后的页面还挂在树上，同名的文字（模板标题、按钮文案）会一起被查到，
    /// 所以凡是要点弹窗里的东西都先收进 Dialog 这一层
    Finder dialogText(String value) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(value));

    /// 记一笔那套候选项是私有 widget（`_ChoicePill`），测试够不着它的类型，
    /// 只能从装饰上找证据。而证据要取**边框**那一侧：测试主题走的是
    /// `_buildBase(AppSemantic.light)`，没经过按用户强调色重算容器色的那一步，
    /// 于是选中底色 accentContainer 和未选中底色 surfaceSunken 在亮色档都是
    /// #F5F5F5——比底色等于什么都没测。边框那一侧才是两个值
    /// （选中 #E5E5E5 / 未选中 5% 黑）。
    Color pillColor(WidgetTester tester, String label) {
      final pill = find.ancestor(of: dialogText(label), matching: find.byType(InkWell)).first;
      final box = find.descendant(of: pill, matching: find.byType(Container)).first;
      final deco = tester.widget<Container>(box).decoration! as BoxDecoration;
      return (deco.border! as Border).top.color;
    }

    /// 按下卡片主体就是"用这张模板记一笔"。点标题文字不行：模板的标题和商户
    /// 常常是同一个词（咖啡/咖啡），同名文字会把命中数撑到两个以上。
    Future<void> tapCard(WidgetTester tester, String title) async {
      await reveal(tester, find.text(title));
      await tester.tap(find.ancestor(of: find.text(title), matching: find.byType(AppCard)).first);
      await advance(tester);
    }

    /// 卡片上的动作按钮只有图标，得先按标题滚到那张卡，再在卡里找那颗按钮
    Future<void> tapOnCard(WidgetTester tester, String title, String tooltip) async {
      await reveal(tester, find.text(title));
      final card = find.ancestor(of: find.text(title), matching: find.byType(AppCard)).first;
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip(tooltip)).first,
      );
      await advance(tester);
    }

    testWidgets('模板按使用次数排，同次数再按名字：顺序不能跟着排序算法抖', (tester) async {
      await openTemplates(tester);
      // 桩里 6 张：地铁通勤/视频会员/话费充值各 12 次，午餐/咖啡/房租各 6 次
      expect(find.text('6 张模板，一共按过 54 次'), findsOneWidget);
      await reveal(tester, find.text('午餐'));
      double dyOf(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(dyOf('地铁通勤'), lessThan(dyOf('视频会员')), reason: '同为 12 次时按名字排');
      expect(dyOf('视频会员'), lessThan(dyOf('话费充值')));
      expect(dyOf('话费充值'), lessThan(dyOf('午餐')), reason: '12 次的整组都在 6 次的前面');
      // 两块各自说明自己是不是演示数据，别让水印盖到真账那半
      expect(
        find.text('模板与规则是演示数据 · 后端未接入；按模板记下来的那一笔是真账'),
        findsOneWidget,
      );
      await unmountPage(tester);
    });

    testWidgets('规则：开着的排前面，停用的不说"下次"', (tester) async {
      await openTemplates(tester);
      await reveal(tester, find.text('视频会员续费'));
      expect(
        tester.getTopLeft(find.text('每月房租')).dy,
        lessThan(tester.getTopLeft(find.text('视频会员续费')).dy),
      );
      expect(find.textContaining('下次 2026-04-01 09:00'), findsOneWidget);
      expect(find.textContaining('现在是停用状态'), findsOneWidget);
      expect(find.textContaining('下次 2026-04-15'), findsNothing);
      // 统计行排在所有规则下面，不滚过去根本没建出来
      await reveal(tester, find.text('2 条规则，1 条在跑'));
      expect(find.text('2 条规则，1 条在跑'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('模板只带名字时按名字回认账户与类别，对不上就留空', (tester) async {
      final store = LedgerStubStore.instance;
      await store.init();
      // '餐饮'/'现金钱包' 是这批桩数据里真有的名字，'居家缴费' 不在
      await store.upsertTxTemplate(
        const LedgerTxTemplate(
          title: '打卡咖啡',
          amount: 21,
          categoryName: '餐饮',
          accountName: '现金钱包',
        ),
      );
      await openTemplates(tester);

      await tapCard(tester, '打卡咖啡');
      expect(dialogText('记一笔'), findsOneWidget);
      expect(
        pillColor(tester, '餐饮'),
        isNot(pillColor(tester, '交通')),
        reason: '模板里的类别名按名字认回来了，只有它换了选中边框',
      );
      expect(pillColor(tester, '现金钱包'), isNot(pillColor(tester, '信用卡')), reason: '账户同理');
      // 按模板开的那一单日期就是今天：模板里没有日期，日期归当天
      expect(find.text(ledgerDateOf(DateTime.now())), findsOneWidget);
      await tester.tap(dialogText('取消'));
      await advance(tester);

      // 名字在这批类别/账户里一个都对不上（桩里的房租写的是'居家缴费'+'现金'）：
      // 宁可一个都不选，也不预选到一个不相干的类别上——所有候选就都是未选中的同一种底色
      await tapCard(tester, '房租');
      expect(pillColor(tester, '餐饮'), equals(pillColor(tester, '交通')));
      expect(pillColor(tester, '餐饮'), equals(pillColor(tester, '其他')));
      expect(pillColor(tester, '现金钱包'), equals(pillColor(tester, '信用卡')));
      expect(pillColor(tester, '餐饮'), equals(pillColor(tester, '其他')));
      expect(pillColor(tester, '现金钱包'), equals(pillColor(tester, '信用卡')));
      await tester.tap(dialogText('取消'));
      await advance(tester);
      await unmountPage(tester);
    });

    testWidgets('点模板记下来走的是真账：入账回执 + 使用次数 +1', (tester) async {
      await openTemplates(tester);
      await tapCard(tester, '咖啡');
      expect(dialogText('记一笔'), findsOneWidget);
      await tester.tap(dialogText('记下来'));
      // 查重与写入是同步 FFI，但 SnackBar 的浮起动画要过几帧才画出来
      await advance(tester);
      expect(find.text('已记下一笔'), findsOneWidget);
      await scrollToTop(tester);
      expect(find.text('用过 7 次'), findsOneWidget, reason: '桩里给咖啡记的是 6 次');
      await unmountPage(tester);
    });

    testWidgets('改模板只回写模板，不会多记一笔', (tester) async {
      await openTemplates(tester);
      await tapOnCard(tester, '咖啡', '改这张模板');
      expect(dialogText('编辑模板'), findsOneWidget);
      // 模板里没有日期这一栏，画出来只会让人以为这张模板固定在某天
      expect(find.text(ledgerDateOf(DateTime.now())), findsNothing);
      expect(find.text('同时存为模板'), findsNothing);
      await tester.enterText(find.widgetWithText(AppTextField, '商户 / 说明'), '手冲咖啡');
      await tester.tap(dialogText('保存模板'));
      await advance(tester);
      expect(find.text('已记下一笔'), findsNothing);
      await reveal(tester, find.textContaining('手冲咖啡').first);
      expect(find.textContaining('咖啡 · 手冲咖啡'), findsNothing);
      // 改模板不改使用次数：咖啡还是 6 次
      expect(find.text('用过 6 次'), findsWidgets);
      await unmountPage(tester);
    });

    testWidgets('删模板会说清带走几条规则，删完那条规则也没了', (tester) async {
      await openTemplates(tester);
      await tapOnCard(tester, '房租', '删除模板');
      expect(find.textContaining('有 1 条定时规则挂着它'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await advance(tester);
      expect(find.text('房租'), findsNothing);
      // 汇总行和规则统计都排在被删掉的那一块后面，滚到位才算建出来
      await reveal(tester, find.textContaining('5 张模板'));
      expect(find.textContaining('5 张模板'), findsOneWidget);
      await reveal(tester, find.textContaining('1 条规则，0 条在跑'));
      expect(find.text('每月房租'), findsNothing);
      await unmountPage(tester);
    });

    testWidgets('规则开关就地生效，回执写在页顶', (tester) async {
      await openTemplates(tester);
      await reveal(tester, find.text('每月房租'));
      final card = find.ancestor(of: find.text('每月房租'), matching: find.byType(AppCard)).first;
      await tester.tap(find.descendant(of: card, matching: find.byType(Switch)));
      await advance(tester);
      // 停用之后这条规则会排到开着的后面，卡片不一定还在可视区里
      await reveal(tester, find.text('已停用'));
      expect(find.descendant(of: card, matching: find.text('已停用')), findsOneWidget);
      // 统计行排在所有规则下面，不滚过去根本没建出来
      await reveal(tester, find.text('2 条规则，0 条在跑'));
      await scrollToTop(tester);
      expect(find.text('规则「每月房租」已停用，到点不会记账'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('新建规则：选一张模板、填个名字，保存就当场可见', (tester) async {
      await openTemplates(tester);
      await reveal(tester, find.text('新建规则'));
      await tester.tap(find.text('新建规则'));
      await advance(tester);
      expect(dialogText('新建定时规则'), findsOneWidget);
      // LedgerField 的标签是独立 Text，不是 labelText：弹窗里第一个输入框就是名字
      await tester.enterText(
        find.descendant(of: find.byType(Dialog), matching: find.bySubtype<TextField>()).first,
        '每月宽带',
      );
      final chips = tester.widgetList<TagChip>(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TagChip)),
      );
      expect(
        chips.firstWhere((TagChip chip) => chip.label == '话费充值').selected,
        isFalse,
        reason: '默认不落任何模板，忘了选就弹回这一栏',
      );
      await tester.tap(dialogText('话费充值'));
      await advance(tester);
      await tester.tap(dialogText('保存'));
      await advance(tester);
      // 回执写在页面最顶上，而新建按钮在同一条列表的下面：不滚回去它根本没建出来
      await scrollToTop(tester);
      expect(find.text('规则「每月宽带」已添加'), findsOneWidget);
      await reveal(tester, find.text('3 条规则，2 条在跑'));
      expect(find.textContaining('模板「话费充值」'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('一张模板都没有时，新建规则先把人领去记一笔', (tester) async {
      final store = LedgerStubStore.instance;
      await store.init();
      for (final t in await store.listTxTemplates()) {
        await store.deleteTxTemplate(t.id);
      }
      await openTemplates(tester);
      expect(find.text('还没有模板'), findsOneWidget);
      await tester.tap(find.text('新建规则'));
      await advance(tester);
      expect(dialogText('还没有模板'), findsOneWidget);
      await tester.tap(dialogText('去记一笔'));
      await advance(tester);
      expect(dialogText('记一笔'), findsOneWidget);
      await tester.tap(dialogText('取消'));
      await advance(tester);
      await unmountPage(tester);
    });
  });

  group('导入导出页', () {
    /// 补记用的样例表格（内容全是编的）。四行各管一件事，一份表就把预览要说清的
    /// 几句话全踩到了：两级类别按名字认回、停用账户算"对不上"、没写账户 + 带标签、
    /// 日期那一格写的是"待补"。商户里那对引号是故意的——逗号必须靠引号兜住。
    const csv = '''
日期,类型,方向,金额,账户,对方账户,类别,标签,商户,备注,来源
2026-03-05,支出,支出,18.00,现金钱包,,交通/打车,出差|报销,滴滴打车,周一早高峰,手动
2026-03-06,支出,支出,52.00,已经停用的副卡,,餐饮,,"老街坊,二楼店",请客,手动
2026-03-07,支出,支出,99.00,,,二手书,加班,旧书店,闲鱼淘的,手动
待补,支出,支出,10.00,现金钱包,,餐饮,,现金支出,,手动
''';

    Future<LedgerDataViewModel> openData(WidgetTester tester) async {
      await _pumpLedger(
        tester,
        const LedgerDataScreen(),
        window: _desktopWindow,
        design: _desktopDesign,
      );
      return (tester.state(find.byType(LedgerDataScreen)) as dynamic).viewModel;
    }

    Finder dataScrollable() => find.descendant(
      of: find.byType(LedgerDataScreen),
      matching: find.byType(Scrollable),
    ).first;

    /// 导出卡片在上、导入卡片在下：不滚过去另一头根本没建出来，
    /// 而点一个建出来却不在屏幕里的东西，报出来的是"命不中"，看不出是没建还是没画
    Future<void> scrollTo(WidgetTester tester, {required bool end}) async {
      await tester.drag(dataScrollable(), Offset(0, end ? -1200 : 1200));
      await advance(tester);
    }

    /// 页面上一枚候选胶囊的选中态
    ///
    /// 读 `selected` 这个字段而不是比底色：测试主题没走按强调色重算容器色那一步，
    /// 亮色档下选中色和未选中色都是 #F5F5F5，比颜色等于什么都没测。
    bool chipSelected(WidgetTester tester, String label) =>
        tester.widget<TagChip>(find.widgetWithText(TagChip, label).first).selected;

    Future<void> tapChip(WidgetTester tester, String label) async {
      await scrollTo(tester, end: false);
      await tester.tap(find.widgetWithText(TagChip, label).first);
      await advance(tester);
    }

    Future<void> loadCsv(WidgetTester tester, LedgerDataViewModel vm, String text) async {
      // loadCsv 里那几趟查重是真异步：先等它跑完再 pump，否则断言读到的是半成品
      await vm.loadCsv(text, '三月补记.csv');
      await advance(tester);
      await scrollTo(tester, end: true);
    }

    /// 弹窗背后的页面还挂在树上，页面上同名的按钮（'导入'）会一起被查到
    Finder dialogText(String value) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(value));

    Finder dialogTextContaining(String value) =>
        find.descendant(of: find.byType(Dialog), matching: find.textContaining(value));

    testWidgets('导出：区间真的带进筛选，格式只换个按钮文案', (tester) async {
      final vm = await openData(tester);
      await scrollTo(tester, end: false);
      // '全部' 区间桩里 10 笔，全已入账，所以那半句"另有 N 笔待确认"不该出现
      expect(find.text('这个区间里有 10 笔已入账。'), findsOneWidget);
      expect(chipSelected(tester, 'CSV 表格'), isTrue);

      await tapChip(tester, 'JSON');
      expect(find.text('导出 JSON'), findsOneWidget);
      expect(chipSelected(tester, 'JSON'), isTrue);
      expect(chipSelected(tester, 'CSV 表格'), isFalse);
      // 没选自定义之前，那两枚日期按钮根本不该占位置
      expect(find.text('开始日期'), findsNothing);
      await tapChip(tester, '自定义');
      expect(find.text('开始日期'), findsOneWidget);
      expect(find.text('结束日期'), findsOneWidget);

      // 日期按钮开的是系统日历选择器，测试里不演那一段，直接把选好的值喂进去：
      // 这一句要证的是"换了区间，笔数就跟着变"
      await vm.setCustom(start: '2026-03-01', end: '2026-03-20');
      await advance(tester);
      await scrollTo(tester, end: false);
      expect(find.text('2026-03-01'), findsOneWidget);
      expect(find.text('这个区间里有 6 笔已入账。'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('区间里有待确认的，导出卡片先说清文件里为什么少了这几笔', (tester) async {
      final vm = await openData(tester);
      // 桩里 10 笔全是已入账，得临时加一笔待确认的才看得到那半句；用完拿走，
      // 这份 _txs 是所有桩共享的，漏下去会把别的用例带歪
      final pending = <String, dynamic>{
        ..._tx(id: 11, date: '2026-03-19', merchant: '外卖（还没确认）', amount: 33.0),
        'status': 'pending',
      };
      _txs.add(pending);
      addTearDown(() => _txs.remove(pending));
      await vm.refreshExportCount();
      await advance(tester);
      await scrollTo(tester, end: false);
      expect(find.textContaining('这个区间里有 10 笔已入账，另有 1 笔待确认——'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('预览把每一行的去向说清楚：类别按名字认回两级，对不上的一一列出来', (tester) async {
      _seedTree();
      final vm = await openData(tester);
      await loadCsv(tester, vm, csv);

      expect(find.text('三月补记.csv'), findsOneWidget);
      expect(find.text('能读 3 笔 · 认出了表头'), findsOneWidget);
      expect(find.text('1 行日期或金额读不出来，已经丢掉'), findsOneWidget);
      expect(find.text('第 5 行：日期或金额读不出来'), findsOneWidget);
      expect(find.text('1 笔对不上类别，会落在未分类'), findsOneWidget);
      expect(find.text('1 笔没写账户'), findsOneWidget);
      expect(find.text('标签那一列暂时存不住，导进来会丢掉'), findsOneWidget);
      // 表里写的是"交通/打车"：认回父类还得带上子类，预览里这一对就是真要写进库的那一对
      expect(find.text('现金钱包 · 打车 · 滴滴打车'), findsOneWidget);
      expect(find.text('没有账户 · 未分类 · 旧书店'), findsOneWidget);
      // 逗号在引号里：认不出来就会多切出一列，整行串行
      expect(find.textContaining('老街坊,二楼店'), findsOneWidget);

      // 停用账户不算"对上了"，所以这一栏才会出现；默认不落账户
      expect(find.text('账户名对不上时落到'), findsOneWidget);
      expect(chipSelected(tester, '不落账户'), isTrue);
      await tester.tap(find.widgetWithText(TagChip, '信用卡').first);
      await advance(tester);
      // 没写账户的那一行也一起落到兜底：这一栏管的是所有落不上账户的行
      expect(find.text('信用卡 · 餐饮 · 老街坊,二楼店'), findsOneWidget);
      expect(find.text('信用卡 · 未分类 · 旧书店'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('按下去才落库：回执说清跳过了什么，页面退回选文件那一步', (tester) async {
      _seedTree();
      final vm = await openData(tester);
      await loadCsv(tester, vm, csv);

      await tester.tap(find.text('导入 3 笔'));
      await advance(tester);
      expect(dialogText('导入 3 笔？'), findsOneWidget);
      expect(dialogTextContaining('1 笔对不上类别，会先留在未分类里。'), findsOneWidget);
      expect(dialogTextContaining('1 笔的账户名对不上，按你刚选的兜底账户落。'), findsOneWidget);
      await tester.tap(dialogText('导入'));
      await advance(tester);

      // 回执同时挂在页顶和 SnackBar 上（滚走的人回来还看得见），所以是 findsWidgets
      expect(
        find.textContaining('已导入 3 笔 · 跳过 1 行读不出日期的 · 1 笔没落类别 · 标签暂时存不住，已丢掉'),
        findsWidgets,
      );
      expect(find.text('选择 CSV 文件'), findsOneWidget, reason: '导完了就别让人再按一次同一个导入');
      expect(vm.preview.value, isNull);
      await unmountPage(tester);
    });

    testWidgets('查重说"像同一笔"时只在预览和确认框里各说一句，不逐行弹窗', (tester) async {
      // responder 比 responses 先查，这样覆盖才有效
      _api.responders[fn('ledgerCheckDuplicate')] =
          (_) => '{"duplicated": true, "existing_id": 7, "existing_desc": "星巴克"}';
      final vm = await openData(tester);
      await loadCsv(tester, vm, csv);
      expect(find.text('3 笔和已入账的很像'), findsOneWidget);

      await tester.tap(find.text('导入 3 笔'));
      await advance(tester);
      expect(
        dialogTextContaining('其中有 3 笔和已入账的很像（同日、同账户、同商户、同金额），导入不会替你合并。'),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await advance(tester);
      expect(find.textContaining('已导入'), findsNothing);
      // 取消之后预览得原地留着：人要改兜底账户再导一次，不该从头再来
      expect(find.text('能读 3 笔 · 认出了表头'), findsOneWidget);
      await unmountPage(tester);
    });

    testWidgets('表头对不上时不摆"能读 0 笔"的空预览，只说缺哪两列', (tester) async {
      final vm = await openData(tester);
      // '交易日期' 不在认的列名里：只有金额一列对得上
      await vm.loadCsv('交易日期,金额,说明\n2026-03-05,18.00,打车\n', '银行流水.csv');
      await advance(tester);
      await scrollTo(tester, end: true);
      expect(find.text('至少要能对上"日期"和"金额"两列'), findsOneWidget);
      expect(find.text('选择 CSV 文件'), findsOneWidget);
      expect(find.text('表格要长什么样'), findsOneWidget);

      await vm.loadCsv('   \n', '空白.csv');
      await advance(tester);
      expect(find.text('文件是空的'), findsOneWidget);

      // 换一份对得上的：上一句错误不能赖在页上不走
      await loadCsv(tester, vm, csv);
      expect(find.text('文件是空的'), findsNothing);
      expect(find.text('至少要能对上"日期"和"金额"两列'), findsNothing);
      expect(find.text('能读 3 笔 · 认出了表头'), findsOneWidget);
      await unmountPage(tester);
    });
  });
}
