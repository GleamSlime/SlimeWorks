import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/pages/ledger/ledger_pending_screen.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

import 'helpers/page_golden.dart';

String fn(String apiName) =>
    'crateApiLedger${apiName[0].toUpperCase()}${apiName.substring(1)}';

String sym(Symbol s) =>
    RegExp(r'Symbol\("(.+?)"\)').firstMatch(s.toString())?.group(1) ?? s.toString();

class MockApi implements RustLibApi {
  final Map<String, Object?> responses = <String, Object?>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = sym(invocation.memberName);
    if (responses.containsKey(name)) return responses[name];
    throw StateError('缺桩: $name');
  }
}

final MockApi api = MockApi();

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

void seed() {
  final tx = <String, dynamic>{
    'id': 1, 'occurred_at': '2026-03-28 12:00:00', 'bill_date': '2026-03-28',
    'direction': 'expense', 'amount': 28.5, 'currency': 'CNY', 'account_id': 1,
    'category_id': 1, 'merchant': '全家便利店', 'note': '', 'source': 'manual',
    'rule_id': 0, 'email_uid': '', 'status': 'posted',
    'created_at': '2026-03-28 12:00:00', 'updated_at': '2026-03-28 12:00:00',
    'account_name': '现金钱包', 'category_name': '餐饮', 'category_icon': 'restaurant',
    'category_direction': 'expense',
  };
  api.responses
    ..clear()
    ..[fn('ledgerIsReady')] = true
    ..[fn('ledgerVersion')] = 'test'
    ..[fn('ledgerListAccounts')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': '现金钱包', 'kind': 'cash', 'currency': 'CNY',
        'opening_balance': 0.0, 'credit_limit': 0.0, 'bill_day': 0, 'repay_day': 0,
        'enabled': true, 'sort_order': 0, 'note': ''},
    ])
    ..[fn('ledgerListCategories')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': '餐饮', 'direction': 'expense',
        'icon': 'restaurant', 'parent_id': 0, 'sort_order': 0, 'enabled': true},
    ])
    ..[fn('ledgerListTransactions')] = jsonEncode(<Map<String, dynamic>>[tx])
    ..[fn('ledgerCountTransactions')] = 1
    ..[fn('ledgerStatsSummary')] = jsonEncode(<String, dynamic>{
      'income': 0.0, 'expense': 28.5, 'net': -28.5, 'count': 1,
      'min_date': '2026-03-28', 'max_date': '2026-03-28', 'month': '2026-03',
      'month_income': 0.0, 'month_expense': 28.5, 'month_net': -28.5,
    })
    ..[fn('ledgerStatsByDay')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'bill_date': '2026-03-28', 'income': 0.0, 'expense': 28.5, 'count': 1},
    ])
    ..[fn('ledgerStatsByCategory')] = '[]'
    ..[fn('ledgerStatsByMerchant')] = '[]'
    ..[fn('ledgerStatsByMonth')] = '[]'
    ..[fn('ledgerPendingCount')] = 1
    ..[fn('ledgerListPending')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{
        'email': <String, dynamic>{
          'id': 7, 'rule_id': 1, 'message_uid': 'UID 1', 'from_addr': 'no-reply@cmbchina.com',
          'subject': '信用卡账单', 'received_at': '2026-03-29 08:00:00', 'match_type': 'auto',
          'status': 'pending', 'html_sha': '', 'note': '',
        },
        'candidates': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1, 'tx': tx,
            'confidence': 0.9, 'matched_field': 'merchant', 'reason': '命中 1 封',
            'category_id': 1, 'account_id': 1, 'suggested_category': '餐饮',
            'suggested_account': '现金钱包',
          },
        ],
      },
    ])
    ..[fn('ledgerListReceivedEmails')] = '[]'
    ..[fn('ledgerEmailTransactions')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'email_id': 7, 'tx': tx, 'status': 'pending',
        'confidence': 0.9, 'reason': '命中 1 封'},
    ])
    ..[fn('ledgerListRules')] = jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': '信用卡账单收信', 'protocol': 'imap', 'host': '127.0.0.1',
        'port': 1143, 'use_ssl': false, 'username': 'me@example.com', 'secret_ref': '',
        'mailbox': 'INBOX', 'search_subject': '账单', 'search_from': '', 'match_mode': 'and',
        'template_id': 'cmb_daily_bill', 'auto_apply': false, 'account_id': 1,
        'enabled': true, 'last_run_at': '', 'last_error': '', 'note': ''},
    ])
    ..[fn('ledgerGetLogs')] = '[]'
    ..[fn('ledgerListMerchantMemory')] = '[]'
    ..[fn('ledgerSchedulerStatus')] = jsonEncode(<String, dynamic>{
      'check_interval_secs': 60, 'running': false, 'rules': <Map<String, dynamic>>[],
    })
    ..[fn('ledgerTemplates')] = '[]'
    ..[fn('ledgerHasRulePassword')] = true;
}

final File _out = File('/tmp/ledger_hunt.txt');

void hunt(Element root) {
  void visit(Element e, List<String> path) {
    final here = <String>[...path, '${e.widget.runtimeType}'];
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize && ro.size.width > 2000) {
      _out.writeAsStringSync(
        'HUGE ${ro.size} :: ${e.widget}\n path: ${here.join(' < ')}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
    e.visitChildren((child) => visit(child, here));
  }
  visit(root, const <String>[]);
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: api);
    _out.writeAsStringSync('');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    seed();
    if (!getIt.isRegistered<LedgerService>()) {
      getIt.registerSingleton<LedgerService>(LedgerService());
    }
    await getIt<LedgerService>().ensureInitialized();
    if (!Get.isRegistered<SidebarController>()) {
      Get.put<SidebarController>(
        SidebarController()
          ..isExpanded.value = true
          ..selectedRoute.value = '/ledger',
        permanent: true,
      );
    }
  });

  testWidgets('H 待确认桌面', (tester) async {
    _out.writeAsStringSync('--- begin ---\n', mode: FileMode.append, flush: true);
    await pumpAppPage(
      tester,
      const LedgerPendingScreen(),
      size: const Size(1440, 900),
      designSize: const Size(1920, 1080),
      withTopBar: true,
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    hunt(tester.binding.rootElement!);
    _out.writeAsStringSync('--- end, exceptions=${tester.takeException()} ---\n',
        mode: FileMode.append, flush: true);
    await unmountPage(tester);
  });
}
