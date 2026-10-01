// 流水账服务层（LedgerService）单测：FFI 用 RustLib.initMock 桩掉，
// 节点中转用本机环回端口上的假节点服务器（复用 test/helpers/fake_node_server.dart）。
//
// 可测性结论（读码验证过，不改生产代码）：
// - 所有本地数据方法都经 `rust_api.ledgerXxx()` 出 FFI，返回的是 JSON 文本；
//   FRB 2.11 的官方注入点 `RustLib.initMock(api:)` 足以桩掉整条链，
//   于是 _list/_listRaw/_map/_text/_id/_bool/_run 这 7 种包装的折叠规则全部可观察。
// - 远程分支要 `GetIt.instance.get<NodeSettingsService>()` 拿节点地址：
//   直接 new 一个 NodeSettingsService（不跑 init()），把 NodeEndpoint 塞进它的
//   remoteNodes 列表即可，无需真节点；Dio 不可注入（私有 _dio），所以用真 socket 打假服务器。
// - flutter_secure_storage 有官方测试替身（setMockInitialValues + 平台接口子类），
//   所以"口令只进安全存储、不进数据库、不进日志"是可断言的行为，不是放弃项。
//
// 失败路径一律按**现状**锁定：LedgerService 不吞 FFI 异常（只有 readRulePassword 和
// onClose 吞），格式异常则被 _decodeList 静默降级成空列表。
// 样例数据全部脱敏：假尾号 0000、假金额 12.34、假商户「测试商户」、假口令哨兵串。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

import 'helpers/fake_node_server.dart';

// ── FRB mock 后端 ────────────────────────────────────────────────────────────

/// `ledgerXxx()` 顶层函数名 → 生成的 `crateApiLedgerLedgerXxx` 方法名。
String fn(String apiName) =>
    'crateApiLedger${apiName[0].toUpperCase()}${apiName.substring(1)}';

String _symbolName(Symbol symbol) {
  final String text = symbol.toString();
  final RegExpMatch? match = RegExp(r'Symbol\("(.+?)"\)').firstMatch(text);
  return match?.group(1) ?? text;
}

/// 一次 FFI 调用记录（方法名 + 具名参数）。
class _MockCall {
  _MockCall(this.method, this.args);

  final String method;
  final Map<Symbol, Object?> args;

  Object? arg(String name) => args[Symbol(name)];
}

/// 让某个 FFI 方法抛错而不是返回：sync 方法在调用点抛，async 方法返回失败 Future。
class _MockFailure {
  _MockFailure(this.error, {required this.isAsync});

  final Object error;
  final bool isAsync;
}

/// FRB mock 后端：按方法名注入返回值，未配置的方法直接抛错，避免桩名写错时"静默通过"。
class _MockLedgerApi implements RustLibApi {
  final Map<String, Object?> responses = <String, Object?>{};
  final List<_MockCall> calls = <_MockCall>[];

  List<_MockCall> callsOf(String apiName) {
    final String method = fn(apiName);
    return calls.where((_MockCall c) => c.method == method).toList(growable: false);
  }

  int callCount(String apiName) => callsOf(apiName).length;

  _MockCall lastCall(String apiName) {
    final List<_MockCall> list = callsOf(apiName);
    expect(list, isNotEmpty, reason: '没有记录到 ${fn(apiName)} 调用');
    return list.last;
  }

  /// 同步返回 String 的 FFI（列表/统计/文本类接口）
  void stubString(String apiName, String value) => responses[fn(apiName)] = value;

  /// 同步返回 int（PlatformInt64）的 FFI（upsert/count/id 类接口）
  void stubInt(String apiName, int value) => responses[fn(apiName)] = value;

  /// 同步返回 bool 的 FFI
  void stubBool(String apiName, bool value) => responses[fn(apiName)] = value;

  /// 同步返回 void 的 FFI
  void stubVoid(String apiName) => responses[fn(apiName)] = null;

  /// async FFI（联网那几个：checkRule/fetchEmails/testConnection），返回 `Future<String>`
  void stubAsyncString(String apiName, String value) =>
      responses[fn(apiName)] = Future<String>.value(value);

  void failSync(String apiName, Object error) =>
      responses[fn(apiName)] = _MockFailure(error, isAsync: false);

  void failAsync(String apiName, Object error) =>
      responses[fn(apiName)] = _MockFailure(error, isAsync: true);

  /// 解出某个 json 入参（account_json/tx_json/filter_json…）
  Object? decodedArg(String apiName, String argName) {
    final Object? raw = lastCall(apiName).arg(argName);
    return raw is String ? jsonDecode(raw) : raw;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final String method = _symbolName(invocation.memberName);
    calls.add(_MockCall(method, invocation.namedArguments));
    final Object? value = responses[method];
    if (value is _MockFailure) {
      if (value.isAsync) return Future<String>.error(value.error, StackTrace.current);
      throw value.error;
    }
    if (responses.containsKey(method)) return value;
    throw StateError('mock 后端未配置该 FFI 方法: $method');
  }
}

// ── 安全存储替身 ─────────────────────────────────────────────────────────────

/// 只让读写抛错，用来验证"钥匙串挂了不阻断页面"的现状。
class _ThrowingSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({required String key, required Map<String, String> options}) async =>
      throw StateError('钥匙串不可用');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => throw StateError('钥匙串不可用');

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async =>
      throw StateError('钥匙串不可用');

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      throw StateError('钥匙串不可用');

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async =>
      throw StateError('钥匙串不可用');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw StateError('钥匙串不可用');
}

// ── path_provider 替身 ───────────────────────────────────────────────────────

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportDir);

  final String supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

// ── 样例数据（脱敏：假卡尾号 0000、假金额 12.34、假商户「测试商户」） ────────

/// 口令哨兵串：只在断言"没进日志/没进数据库 JSON"时使用
const String kFakeSecret = 'SENTINEL-fake-passwd-勿外泄';

Map<String, dynamic> accountJson([Map<String, dynamic>? overrides]) {
  return <String, dynamic>{
    'id': 1,
    'name': '测试卡',
    'type': 'credit_card',
    'last4': '0000',
    'currency': 'CNY',
    'credit_limit': 1000.0,
    'balance': 12.34,
    'sort_order': 0,
    'enabled': true,
    'created_at': '2026-01-01 10:00:00',
    ...?overrides,
  };
}

Map<String, dynamic> txJson([Map<String, dynamic>? overrides]) {
  return <String, dynamic>{
    'id': 11,
    'occurred_at': '2026-09-29 10:30:00',
    'bill_date': '2026-09-29',
    'direction': 'expense',
    'amount': 12.34,
    'currency': 'CNY',
    'account_id': 1,
    'category_id': 2,
    'merchant': '测试商户',
    'note': '',
    'source': 'manual',
    'rule_id': 0,
    'email_uid': '',
    'status': 'posted',
    'account_name': '测试卡',
    'category_name': '餐饮美食',
    'category_icon': 'restaurant',
    'category_direction': 'expense',
    ...?overrides,
  };
}

String listJson(List<Map<String, dynamic>> items) => jsonEncode(items);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _MockLedgerApi mock = _MockLedgerApi();
  late LedgerService service;

  setUpAll(() {
    // 官方 mock 注入：不加载 Rust 动态库，全部 crateApi 方法走 noSuchMethod。
    RustLib.initMock(api: mock);
    // TestWidgetsFlutterBinding 默认拦截所有 HttpClient（一律回 400），
    // 摘掉它才能让 Dio 打本机假节点。
    HttpOverrides.global = null;
  });

  setUp(() async {
    mock.responses.clear();
    mock.calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    // get_it 9 的 reset() 返回 Future：不 await 会把后面注册的单例擦掉
    await GetIt.instance.reset();
    service = LedgerService();
  });

  tearDown(() async {
    await GetIt.instance.reset();
    // 还原平台替身，避免抛错实现泄漏到下一个用例
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 本地模式：FFI 的 JSON 文本 → 模型
  // ══════════════════════════════════════════════════════════════════════════

  group('本地模式 - _list 折叠', () {
    test('listAccounts 把 JSON 数组折成模型列表', () async {
      mock.stubString(
        'ledgerListAccounts',
        listJson(<Map<String, dynamic>>[
          accountJson(),
          accountJson(<String, dynamic>{'id': 2, 'name': '现金', 'type': 'cash', 'last4': ''}),
        ]),
      );
      final List<LedgerAccount> accounts = await service.listAccounts();
      expect(accounts, hasLength(2));
      expect(accounts[0].name, '测试卡');
      expect(accounts[0].displaySuffix, '尾号0000');
      expect(accounts[1].type, 'cash');
      expect(mock.lastCall('ledgerListAccounts').args, isEmpty);
    });

    test('现状锁定：非 Map 条目不被丢弃，而是变成"默认值空对象"（与游戏库的过滤策略不同）', () async {
      mock.stubString(
        'ledgerListAccounts',
        jsonEncode(<Object?>[accountJson(), '坏条目', 42, null]),
      );
      final List<LedgerAccount> accounts = await service.listAccounts();
      expect(accounts, hasLength(4));
      expect(accounts[0].name, '测试卡');
      // 坏条目 → {} → fromJson 全默认
      expect(accounts[1].id, 0);
      expect(accounts[1].type, 'credit_card');
      expect(accounts[1].name, '');
      expect(accounts[2].currency, 'CNY');
      expect(accounts[3].enabled, isTrue);
    });

    test('现状锁定：返回的不是数组时静默降级成空列表，不报错', () async {
      mock.stubString('ledgerListAccounts', '{}');
      expect(await service.listAccounts(), isEmpty);
      mock.stubString('ledgerListAccounts', '{"data": []}');
      expect(await service.listAccounts(), isEmpty);
      mock.stubString('ledgerListAccounts', 'null');
      expect(await service.listAccounts(), isEmpty);
    });

    test('现状锁定：返回的不是合法 JSON 文本时 FormatException 直接向外抛', () async {
      mock.stubString('ledgerListAccounts', '不是 JSON');
      await expectLater(service.listAccounts(), throwsA(isA<FormatException>()));
    });

    test('空数组就是空列表', () async {
      mock.stubString('ledgerListAccounts', '[]');
      expect(await service.listAccounts(), isEmpty);
    });

    test('listCategories 把 direction 原样带给 Rust（空串=收支都要）', () async {
      mock.stubString(
        'ledgerListCategories',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'name': '餐饮美食', 'icon': 'restaurant', 'direction': 'expense'},
        ]),
      );
      final List<LedgerCategory> cats = await service.listCategories(direction: 'income');
      expect(mock.lastCall('ledgerListCategories').arg('direction'), 'income');
      expect(cats.single.direction, 'expense');

      await service.listCategories();
      expect(mock.lastCall('ledgerListCategories').arg('direction'), '');
    });

    test('listTransactions 带 filter.json，模型字段完整折出来', () async {
      mock.stubString('ledgerListTransactions', listJson(<Map<String, dynamic>>[txJson()]));
      const LedgerFilter filter = LedgerFilter(keyword: '测试商户', accountId: 1, limit: 20);
      final List<LedgerTx> txs = await service.listTransactions(filter);
      expect(mock.lastCall('ledgerListTransactions').arg('filterJson'), filter.json);
      expect(txs.single.amount, 12.34);
      expect(txs.single.merchant, '测试商户');
      // JOIN 出来的关联名在本地模式下也能读出来
      expect(txs.single.accountName, '测试卡');
      expect(txs.single.categoryIcon, 'restaurant');
    });

    test('listMerchantMemory 走 _listRaw：不解成模型，直接给 Map 列表', () async {
      mock.stubString(
        'ledgerListMerchantMemory',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'merchant_key': '测试商户', 'category_id': 3, 'hit_count': 7},
        ]),
      );
      final List<Map<String, dynamic>> rows = await service.listMerchantMemory();
      expect(rows.single['merchant_key'], '测试商户');
      expect(rows.single['hit_count'], 7);
    });

    test('listRules / listTemplates / listLogs / listPending 各自的解析入口', () async {
      mock.stubString(
        'ledgerListRules',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 5, 'name': '银行邮件', 'protocol': 'imap', 'enabled': true},
        ]),
      );
      final List<LedgerRule> rules = await service.listRules();
      expect(rules.single.name, '银行邮件');
      expect(rules.single.protocolSupported, isTrue);

      mock.stubString(
        'ledgerTemplates',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 'auto', 'name': '自动识别', 'description': '按模板表逐个试'},
        ]),
      );
      expect((await service.listTemplates()).single.id, 'auto');

      mock.stubString(
        'ledgerGetLogs',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'rule_id': 5, 'ok': true, 'new_tx': 3, 'detail': '成功'},
        ]),
      );
      final List<LedgerFetchLog> logs = await service.listLogs(limit: 10);
      expect(mock.lastCall('ledgerGetLogs').arg('limit'), 10);
      expect(logs.single.newTx, 3);
      expect(logs.single.detail, '成功');

      mock.stubString(
        'ledgerListPending',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'subject': '信用卡账单', 'tx_count': 4, 'warnings': <String>['模板未命中']},
        ]),
      );
      final List<LedgerPendingEmail> pending = await service.listPending(limit: 5);
      expect(mock.lastCall('ledgerListPending').arg('limit'), 5);
      expect(pending.single.txCount, 4);
      expect(pending.single.warnings, <String>['模板未命中']);

      mock.stubString('ledgerListReceivedEmails', listJson(<Map<String, dynamic>>[{'id': 8, 'applied': true}]));
      expect((await service.listReceivedEmails()).single.applied, isTrue);

      mock.stubString('ledgerEmailTransactions', listJson(<Map<String, dynamic>>[txJson()]));
      final List<LedgerTx> ofEmail = await service.transactionsOfEmail(8);
      expect(mock.lastCall('ledgerEmailTransactions').arg('emailId'), 8);
      expect(ofEmail.single.id, 11);
    });

    test('默认 limit 值就是方法签名里的 50/100', () async {
      mock.stubString('ledgerGetLogs', '[]');
      mock.stubString('ledgerListPending', '[]');
      mock.stubString('ledgerListReceivedEmails', '[]');
      await service.listLogs();
      await service.listPending();
      await service.listReceivedEmails();
      expect(mock.lastCall('ledgerGetLogs').arg('limit'), 50);
      expect(mock.lastCall('ledgerListPending').arg('limit'), 100);
      expect(mock.lastCall('ledgerListReceivedEmails').arg('limit'), 100);
    });
  });

  group('本地模式 - _map 折叠（单对象接口）', () {
    test('statsSummary 解成 LedgerSummary', () async {
      mock.stubString(
        'ledgerStatsSummary',
        jsonEncode(<String, dynamic>{
          'income': 100.0,
          'expense': 12.34,
          'net': 87.66,
          'count': 3,
          'min_date': '2026-09-01',
          'max_date': '2026-09-29',
          'month': '2026-09',
          'month_income': 100.0,
          'month_expense': 12.34,
          'month_net': 87.66,
        }),
      );
      final LedgerSummary summary = await service.statsSummary(const LedgerFilter());
      expect(summary.count, 3);
      expect(summary.net, 87.66);
      expect(summary.minDate, '2026-09-01');
    });

    test('schedulerStatus 缺字段时是 0/false，而不是构造器默认值', () async {
      mock.stubString('ledgerSchedulerStatus', '{}');
      final LedgerSchedulerStatus status = await service.schedulerStatus();
      expect(status.running, isFalse);
      expect(status.checkIntervalSecs, 0);
    });

    test('checkDuplicate 序列化的 dup_json 键名是 snake_case，且带默认 account_id', () async {
      mock.stubString('ledgerCheckDuplicate', '{"duplicated":true,"existing_id":4,"existing_desc":"测试商户 12.34"}');
      final LedgerDupCheck dup = await service.checkDuplicate(
        merchant: '测试商户',
        amount: 12.34,
        billDate: '2026-09-29',
      );
      final Map<String, dynamic> sent = mock.decodedArg('ledgerCheckDuplicate', 'dupJson')! as Map<String, dynamic>;
      expect(sent, <String, dynamic>{
        'merchant': '测试商户',
        'amount': 12.34,
        'bill_date': '2026-09-29',
        'account_id': 0,
      });
      expect(dup.duplicated, isTrue);
      expect(dup.existingId, 4);
      expect(dup.existingDesc, '测试商户 12.34');
    });

    test('现状锁定：_map 收到数组时抛 StateError（与 _list 的静默降级不对称）', () async {
      mock.stubString('ledgerStatsSummary', '[]');
      await expectLater(
        service.statsSummary(const LedgerFilter()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('本地模式 - 统计接口参数', () {
    test('statsByDay/statsByCategory 只带 filter_json', () async {
      mock.stubString('ledgerStatsByDay', listJson(<Map<String, dynamic>>[
        <String, dynamic>{'bill_date': '2026-09-29', 'income': 0, 'expense': 12.34, 'count': 1},
      ]));
      mock.stubString('ledgerStatsByCategory', listJson(<Map<String, dynamic>>[
        <String, dynamic>{'category_id': 2, 'category_name': '餐饮美食', 'total': 12.34, 'count': 1},
      ]));
      const LedgerFilter f = LedgerFilter(startDate: '2026-09-01', endDate: '2026-09-30');
      final List<LedgerDayRow> days = await service.statsByDay(f);
      expect(mock.lastCall('ledgerStatsByDay').arg('filterJson'), f.json);
      expect(days.single.net, -12.34);

      final List<LedgerCategoryRow> rows = await service.statsByCategory(f);
      expect(mock.lastCall('ledgerStatsByCategory').arg('filterJson'), f.json);
      expect(rows.single.total, 12.34);
    });

    test('statsByMerchant 带 top，statsByMonth 带 months', () async {
      mock.stubString('ledgerStatsByMerchant', '[]');
      mock.stubString('ledgerStatsByMonth', '[]');
      await service.statsByMerchant(const LedgerFilter(), top: 5);
      await service.statsByMonth(months: 6);
      expect(mock.lastCall('ledgerStatsByMerchant').arg('top'), 5);
      expect(mock.lastCall('ledgerStatsByMonth').arg('months'), 6);
      // 默认值
      await service.statsByMerchant(const LedgerFilter());
      await service.statsByMonth();
      expect(mock.lastCall('ledgerStatsByMerchant').arg('top'), 10);
      expect(mock.lastCall('ledgerStatsByMonth').arg('months'), 12);
    });

    test('countTransactions 走 _id，参数同样是 filter_json', () async {
      mock.stubInt('ledgerCountTransactions', 42);
      const LedgerFilter f = LedgerFilter(direction: 'expense');
      expect(await service.countTransactions(f), 42);
      expect(mock.lastCall('ledgerCountTransactions').arg('filterJson'), f.json);
    });
  });

  group('本地模式 - _text / _id / _bool / _run', () {
    test('_text：Rust 的中文影响面说明原样透传，不做 JSON 解析', () async {
      mock.stubString('ledgerDeleteAccount', '账户已删除（3 笔流水归入其他）');
      expect(await service.deleteAccount(7), '账户已删除（3 笔流水归入其他）');
      expect(mock.lastCall('ledgerDeleteAccount').arg('id'), 7);

      mock.stubString('ledgerDeleteCategory', '{"text":"类别已删除"}');
      // 即使文本本身是合法 JSON，本地路径也不解包
      expect(await service.deleteCategory(3), '{"text":"类别已删除"}');
    });

    test('_id：新主键直接是 Rust 返回的整数', () async {
      mock.stubInt('ledgerUpsertAccount', 12);
      mock.stubInt('ledgerUpsertCategory', 13);
      mock.stubInt('ledgerAddTransaction', 14);
      mock.stubInt('ledgerPendingCount', 2);
      mock.stubInt('ledgerConfirmAll', 4);
      mock.stubInt('ledgerIgnoreEmail', 1);
      mock.stubInt('ledgerPurgeEmail', 6);

      final LedgerAccount account = LedgerAccount.fromJson(accountJson(<String, dynamic>{'id': 0}));
      expect(await service.upsertAccount(account), 12);
      expect(
        mock.decodedArg('ledgerUpsertAccount', 'accountJson'),
        account.toJson(),
      );

      expect(
        await service.upsertCategory(const LedgerCategory(id: 0, name: '自定义', icon: 'dots')),
        13,
      );
      expect(
        mock.decodedArg('ledgerUpsertCategory', 'categoryJson'),
        const LedgerCategory(id: 0, name: '自定义', icon: 'dots').toJson(),
      );

      final LedgerTx tx = LedgerTx.fromJson(txJson(<String, dynamic>{'id': 0}));
      expect(await service.addTransaction(tx), 14);
      expect(mock.decodedArg('ledgerAddTransaction', 'txJson'), tx.toJson());

      expect(await service.pendingCount(), 2);
      expect(await service.confirmAll(9, patch: <String, dynamic>{'account_id': 1}), 4);
      expect(mock.lastCall('ledgerConfirmAll').arg('patchJson'), '{"account_id":1}');
      expect(await service.ignoreEmail(9), 1);
      expect(await service.purgeEmail(9), 6);
    });

    test('_bool：删除流水返回 Rust 的布尔', () async {
      mock.stubBool('ledgerDeleteTransaction', true);
      expect(await service.deleteTransaction(5), isTrue);
      expect(mock.lastCall('ledgerDeleteTransaction').arg('id'), 5);
      mock.stubBool('ledgerDeleteTransaction', false);
      expect(await service.deleteTransaction(5), isFalse);
    });

    test('_run：void 接口只保证参数送达', () async {
      mock.stubVoid('ledgerUpdateTransaction');
      mock.stubVoid('ledgerForgetMerchant');
      mock.stubVoid('ledgerConfirmTx');
      mock.stubVoid('ledgerIgnoreTx');
      mock.stubVoid('ledgerClearLogs');
      mock.stubVoid('ledgerSchedulerStart');
      mock.stubVoid('ledgerSchedulerStop');

      final LedgerTx tx = LedgerTx.fromJson(txJson());
      await service.updateTransaction(tx);
      expect(mock.decodedArg('ledgerUpdateTransaction', 'txJson'), tx.toJson());

      await service.forgetMerchant('测试商户');
      expect(mock.lastCall('ledgerForgetMerchant').arg('merchantKey'), '测试商户');

      await service.confirmTx(3, patch: <String, dynamic>{'category_id': 2});
      expect(mock.lastCall('ledgerConfirmTx').arg('txId'), 3);
      expect(mock.lastCall('ledgerConfirmTx').arg('patchJson'), '{"category_id":2}');

      await service.ignoreTx(3);
      expect(mock.lastCall('ledgerIgnoreTx').arg('txId'), 3);

      await service.clearLogs();
      await service.startScheduler();
      await service.stopScheduler();
      expect(mock.callCount('ledgerClearLogs'), 1);
      expect(mock.callCount('ledgerSchedulerStart'), 1);
      expect(mock.callCount('ledgerSchedulerStop'), 1);
    });

    test('setRuleEnabled 把 id 与 enabled 一起带给 Rust', () async {
      mock.stubVoid('ledgerSetRuleEnabled');
      await service.setRuleEnabled(6, false);
      expect(mock.lastCall('ledgerSetRuleEnabled').arg('id'), 6);
      expect(mock.lastCall('ledgerSetRuleEnabled').arg('enabled'), isFalse);
    });

    test('moduleVersion 不经任何包装，直接透传 Rust 文本', () {
      mock.stubString('ledgerVersion', '1.2.3');
      expect(service.moduleVersion(), '1.2.3');
      expect(mock.callCount('ledgerVersion'), 1);
    });
  });

  group('本地模式 - 预览与解析', () {
    test('parsePreviewRaw 把 html/template_id/template_config 三个参数送出去', () async {
      mock.stubString('ledgerParsePreview', '{"transactions":[]}');
      final String raw = await service.parsePreviewRaw(html: '<html>账单</html>', templateId: 'auto');
      expect(mock.lastCall('ledgerParsePreview').arg('html'), '<html>账单</html>');
      expect(mock.lastCall('ledgerParsePreview').arg('templateId'), 'auto');
      expect(mock.lastCall('ledgerParsePreview').arg('templateConfig'), '{}');
      // 本地 _text 原样返回，因此这里拿到的就是 Rust 的 JSON 文本
      expect(raw, '{"transactions":[]}');
    });

    test('parsePreview 在 _text 之上再解一层模型', () async {
      mock.stubString(
        'ledgerParsePreview',
        jsonEncode(<String, dynamic>{
          'template_id': 'cmb',
          'bill_date': '2026-09-01',
          'transactions': <dynamic>[
            <String, dynamic>{'amount': 12.34, 'description': '测试商户', 'card_tail': '0000'},
          ],
          'warnings': <dynamic>['模板未命中'],
        }),
      );
      final LedgerParseResult result = await service.parsePreview(html: '<html/>', templateId: 'cmb');
      expect(result.templateId, 'cmb');
      expect(result.isEmpty, isFalse);
      expect(result.transactions.single.amount, 12.34);
      expect(result.warnings, <String>['模板未命中']);
    });

    test('现状锁定：预览文本不是 JSON 时 parsePreview 抛 FormatException', () async {
      mock.stubString('ledgerParsePreview', '解析失败：模板未命中');
      await expectLater(
        service.parsePreview(html: '<html/>', templateId: 'auto'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 失败路径（按现状锁定）
  // ══════════════════════════════════════════════════════════════════════════

  group('FFI 抛错时的行为', () {
    test('现状锁定：_list 不吞异常，直接向外抛（不是返回空列表）', () async {
      mock.failSync('ledgerListAccounts', StateError('db 未打开'));
      await expectLater(service.listAccounts(), throwsA(isStateError));

      mock.failSync('ledgerListMerchantMemory', StateError('db 未打开'));
      await expectLater(service.listMerchantMemory(), throwsA(isStateError));
    });

    test('现状锁定：_map/_text/_id/_bool/_run 同样向外抛', () async {
      mock.failSync('ledgerStatsSummary', StateError('a'));
      await expectLater(service.statsSummary(const LedgerFilter()), throwsA(isStateError));

      mock.failSync('ledgerDeleteAccount', StateError('b'));
      await expectLater(service.deleteAccount(1), throwsA(isStateError));

      mock.failSync('ledgerUpsertAccount', StateError('c'));
      await expectLater(
        service.upsertAccount(LedgerAccount.fromJson(accountJson())),
        throwsA(isStateError),
      );

      mock.failSync('ledgerDeleteTransaction', StateError('d'));
      await expectLater(service.deleteTransaction(1), throwsA(isStateError));

      mock.failSync('ledgerUpdateTransaction', StateError('e'));
      await expectLater(service.updateTransaction(LedgerTx.fromJson(txJson())), throwsA(isStateError));

      mock.failSync('ledgerVersion', StateError('f'));
      expect(() => service.moduleVersion(), throwsA(isStateError));
    });

    test('联网类 async FFI 抛错也是向外抛', () async {
      mock.failAsync('ledgerTestConnection', StateError('连不上'));
      await expectLater(
        service.testConnection(config: <String, dynamic>{'host': 'imap.example.test', 'port': 993}),
        throwsA(isStateError),
      );

      mock.failAsync('ledgerFetchEmails', StateError('收信失败'));
      await expectLater(
        service.fetchEmails(config: <String, dynamic>{'host': 'imap.example.test'}),
        throwsA(isStateError),
      );
    });

    test('onClose 会把 schedulerStop 的异常吞掉（关闭时不打扰用户）', () {
      mock.failSync('ledgerSchedulerStop', StateError('已经关了'));
      expect(() => service.onClose(), returnsNormally);
      expect(mock.callCount('ledgerSchedulerStop'), 1);
    });

    test('现状锁定：远程模式下 _run/_text 等出错时不会回退到本地 FFI', () async {
      // 节点被选中但地址拿不到（没注册 NodeSettingsService 的兜底路径也走不通）
      GetIt.instance.registerSingleton<NodeSettingsService>(NodeSettingsService());
      service.selectedNodeId.value = 'node-missing';
      mock.stubString('ledgerListAccounts', '[]');
      await expectLater(service.listAccounts(), throwsA(isStateError));
      // 一次都没碰本地
      expect(mock.calls, isEmpty);
      GetIt.instance.reset();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 口令：只进安全存储
  // ══════════════════════════════════════════════════════════════════════════

  group('邮箱口令的处理', () {
    test('secretKey 的键前缀就是 Rust 侧 secret_ref 的口径', () {
      expect(LedgerService.secretKey(1), 'ledger_rule_1');
      expect(LedgerService.secretKey(42), 'ledger_rule_42');
    });

    test('写入→读回→清空（空口令是删除而不是写空串）', () async {
      await service.saveRulePassword(1, kFakeSecret);
      expect(await service.readRulePassword(1), kFakeSecret);

      await service.saveRulePassword(1, '');
      expect(await service.readRulePassword(1), '');
    });

    test('不同规则的口令互不干扰', () async {
      await service.saveRulePassword(1, 'A');
      await service.saveRulePassword(2, 'B');
      expect(await service.readRulePassword(1), 'A');
      expect(await service.readRulePassword(2), 'B');
      expect(await service.readRulePassword(3), '');
    });

    test('现状锁定：安全存储抛错时 readRulePassword 吞掉异常返回空串', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
      expect(await service.readRulePassword(1), '');
    });

    test('现状锁定：saveRulePassword 会把异常重抛（不能假装存成功）', () async {
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
      await expectLater(service.saveRulePassword(1, kFakeSecret), throwsA(isStateError));
    });

    test('口令不进日志', () async {
      await service.saveRulePassword(7, kFakeSecret);
      await service.readRulePassword(7);
      mock.stubBool('ledgerHasRulePassword', true);
      await service.hasRulePassword(7);
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
      await service.readRulePassword(7);
      expect(Loggers.allLogs.where((String line) => line.contains(kFakeSecret)), isEmpty);
    });

    test('hasRulePassword：ruleId<=0 直接 false，不发 FFI', () async {
      expect(await service.hasRulePassword(0), isFalse);
      expect(await service.hasRulePassword(-1), isFalse);
      expect(mock.calls, isEmpty);
    });

    test('hasRulePassword：安全存储里有就不再问 Rust', () async {
      await service.saveRulePassword(4, kFakeSecret);
      mock.stubBool('ledgerHasRulePassword', false);
      expect(await service.hasRulePassword(4), isTrue);
      expect(mock.calls, isEmpty);
    });

    test('hasRulePassword：安全存储没有时改问 Rust（Rust 里可能还留着上次运行的口令）', () async {
      mock.stubBool('ledgerHasRulePassword', true);
      expect(await service.hasRulePassword(4), isTrue);
      expect(mock.lastCall('ledgerHasRulePassword').arg('ruleId'), 4);
      mock.stubBool('ledgerHasRulePassword', false);
      expect(await service.hasRulePassword(4), isFalse);
    });

    test('upsertRule 带口令：先拿新 id → 存安全存储 → 本地再推进 Rust 内存', () async {
      mock.stubInt('ledgerUpsertRule', 8);
      mock.stubVoid('ledgerSetRulePassword');
      final LedgerRule rule = LedgerRule.fromJson(<String, dynamic>{
        'id': 0,
        'name': '银行邮件',
        'host': 'imap.example.test',
      });
      final int id = await service.upsertRule(rule, password: kFakeSecret);
      expect(id, 8);

      // 发给 Rust 的 rule_json 里不能有口令（口令只走独立参数与安全存储）
      final Map<String, dynamic> sent = mock.decodedArg('ledgerUpsertRule', 'ruleJson')! as Map<String, dynamic>;
      expect(sent.containsKey('password'), isFalse);
      expect(sent.containsKey('secret_ref'), isFalse);
      expect(mock.lastCall('ledgerUpsertRule').arg('password'), kFakeSecret);

      // 安全存储用的是 Rust 回填的新 id，而不是入参里的 0
      expect(await service.readRulePassword(8), kFakeSecret);
      expect(await service.readRulePassword(0), '');

      // 本地模式下把口令推进 Rust 内存，后台调度才跑得住
      final _MockCall pushed = mock.lastCall('ledgerSetRulePassword');
      expect(pushed.arg('ruleId'), 8);
      expect(pushed.arg('password'), kFakeSecret);
    });

    test('upsertRule 不带口令时不写安全存储、也不调 setRulePassword', () async {
      mock.stubInt('ledgerUpsertRule', 9);
      final int id = await service.upsertRule(
        LedgerRule.fromJson(<String, dynamic>{'id': 9, 'name': '银行邮件'}),
      );
      expect(id, 9);
      expect(await service.readRulePassword(9), '');
      expect(mock.callsOf('ledgerSetRulePassword'), isEmpty);
    });

    test('deleteRule 连安全存储一起清掉', () async {
      await service.saveRulePassword(3, kFakeSecret);
      mock.stubVoid('ledgerDeleteRule');
      await service.deleteRule(3);
      expect(mock.lastCall('ledgerDeleteRule').arg('id'), 3);
      expect(await service.readRulePassword(3), '');
    });

    test('现状锁定：deleteRule 的 FFI 失败会留下安全存储里的孤儿口令', () async {
      await service.saveRulePassword(3, kFakeSecret);
      mock.failSync('ledgerDeleteRule', StateError('删除失败'));
      await expectLater(service.deleteRule(3), throwsA(isStateError));
      expect(await service.readRulePassword(3), kFakeSecret);
    });

    test('setRulePassword：非空口令才推进 Rust，清空时只动安全存储', () async {
      mock.stubVoid('ledgerSetRulePassword');
      await service.setRulePassword(2, kFakeSecret);
      expect(await service.readRulePassword(2), kFakeSecret);
      expect(mock.lastCall('ledgerSetRulePassword').arg('ruleId'), 2);

      mock.calls.clear();
      await service.setRulePassword(2, '');
      expect(await service.readRulePassword(2), '');
      expect(mock.callsOf('ledgerSetRulePassword'), isEmpty);
    });

    test('checkRule：不显式给口令就用安全存储里的那份', () async {
      await service.saveRulePassword(5, kFakeSecret);
      mock.stubAsyncString('ledgerCheckRule', '新增 2 笔');
      final String summary = await service.checkRule(5);
      expect(summary, '新增 2 笔');
      expect(mock.lastCall('ledgerCheckRule').arg('ruleId'), 5);
      expect(mock.lastCall('ledgerCheckRule').arg('password'), kFakeSecret);

      // 显式口令优先
      mock.calls.clear();
      await service.checkRule(5, password: '表单里现填的');
      expect(mock.lastCall('ledgerCheckRule').arg('password'), '表单里现填的');
    });

    test('backfillHistory：口令同 checkRule，limit 0 交给 Rust 侧默认，走 BigInt', () async {
      await service.saveRulePassword(5, kFakeSecret);
      mock.stubAsyncString('ledgerBackfillRule', '历史回补：扫描 200 封，新增 3 封');
      expect(await service.backfillHistory(5), '历史回补：扫描 200 封，新增 3 封');
      final _MockCall auto = mock.lastCall('ledgerBackfillRule');
      expect(auto.arg('password'), kFakeSecret);
      expect(auto.arg('limit'), BigInt.zero);

      mock.calls.clear();
      await service.backfillHistory(5, password: '现填的', limit: 500);
      final _MockCall given = mock.lastCall('ledgerBackfillRule');
      expect(given.arg('password'), '现填的');
      expect(given.arg('limit'), BigInt.from(500));
    });

    test('fetchEmails/testConnection：rule_id>0 才回落安全存储，limit 走 BigInt', () async {
      await service.saveRulePassword(6, kFakeSecret);
      mock.stubAsyncString('ledgerFetchEmails', '[]');
      mock.stubAsyncString('ledgerTestConnection', '{"ok":true}');

      await service.fetchEmails(config: <String, dynamic>{'rule_id': 6}, limit: 3);
      final _MockCall fetch = mock.lastCall('ledgerFetchEmails');
      expect(fetch.arg('password'), kFakeSecret);
      expect(fetch.arg('limit'), BigInt.from(3));

      await service.testConnection(config: <String, dynamic>{'host': 'imap.example.test'});
      expect(mock.lastCall('ledgerTestConnection').arg('password'), '');
      expect(mock.lastCall('ledgerTestConnection').arg('wantFolders'), isFalse);

      await service.testConnection(
        config: <String, dynamic>{'rule_id': 6},
        wantFolders: true,
      );
      expect(mock.lastCall('ledgerTestConnection').arg('wantFolders'), isTrue);
    });

    test('现状锁定：config 里 rule_id 写成字符串会在 Dart 侧就抛 TypeError（没到 Rust）', () async {
      mock.stubAsyncString('ledgerFetchEmails', '[]');
      await expectLater(
        service.fetchEmails(config: <String, dynamic>{'rule_id': '6'}),
        throwsA(isA<TypeError>()),
      );
      expect(mock.callsOf('ledgerFetchEmails'), isEmpty);
    });

    test('listFolders 只是 testConnection(wantFolders:true) 的 folders 取值', () async {
      mock.stubAsyncString(
        'ledgerTestConnection',
        '{"ok":true,"folders":["INBOX","Archive"],"capabilities":["IDLE"]}',
      );
      final List<String> folders = await service.listFolders(config: <String, dynamic>{'host': 'x'});
      expect(folders, <String>['INBOX', 'Archive']);
      expect(mock.lastCall('ledgerTestConnection').arg('wantFolders'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 初始化
  // ══════════════════════════════════════════════════════════════════════════

  group('ensureInitialized', () {
    test('Rust 侧已就绪时只置位 ready，不再建库', () async {
      mock.stubBool('ledgerIsReady', true);
      await service.ensureInitialized();
      expect(service.ready.value, isTrue);
      expect(service.isInitialized, isTrue);
      expect(mock.callsOf('ledgerInit'), isEmpty);
      expect(mock.callsOf('ledgerListRules'), isEmpty);
    });

    test('未就绪时按 support 目录推导 dbPath 并建库', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {
          // 清理失败不影响断言
        }
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      mock.stubBool('ledgerIsReady', false);
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      mock.stubString('ledgerListRules', '[]');

      await service.ensureInitialized();

      final _MockCall init = mock.lastCall('ledgerInit');
      final Map<String, dynamic> sent =
          jsonDecode(init.arg('dbPathJson')! as String) as Map<String, dynamic>;
      expect(sent['db_path'], '${tmp.path}/ledger/ledger.db');
      expect(Directory('${tmp.path}/ledger').existsSync(), isTrue);
      expect(service.ready.value, isTrue);
      // 没有启用的规则就不拉起每分钟的唤醒
      expect(mock.callsOf('ledgerSchedulerStart'), isEmpty);
    });

    test('建库后预热口令并拉起调度：只统计"启用 + 协议真的能跑"的规则', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path2');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      mock.stubBool('ledgerIsReady', false);
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      mock.stubVoid('ledgerSetRulePassword');
      mock.stubVoid('ledgerSchedulerStart');
      mock.stubString(
        'ledgerListRules',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'name': '邮箱A', 'protocol': 'imap', 'enabled': true},
          <String, dynamic>{'id': 2, 'name': '占位EAS', 'protocol': 'eas', 'enabled': true},
          <String, dynamic>{'id': 3, 'name': '邮箱B', 'protocol': 'imap', 'enabled': false},
        ]),
      );
      await service.saveRulePassword(1, kFakeSecret);

      await service.ensureInitialized();

      expect(service.ready.value, isTrue);
      // 规则 1 的口令被推进 Rust 内存
      final _MockCall pushed = mock.lastCall('ledgerSetRulePassword');
      expect(pushed.arg('ruleId'), 1);
      expect(pushed.arg('password'), kFakeSecret);
      // 有可跑的规则 → 拉起调度
      expect(mock.callCount('ledgerSchedulerStart'), 1);
    });

    test('只有 EAS/禁用规则时不拉起调度', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path3');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      mock.stubBool('ledgerIsReady', false);
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      mock.stubString(
        'ledgerListRules',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 2, 'protocol': 'eas', 'enabled': true},
        ]),
      );
      await service.ensureInitialized();
      expect(mock.callsOf('ledgerSchedulerStart'), isEmpty);
      expect(service.ready.value, isTrue);
    });

    test('autoOpenScheduler=false 时不拉起调度（默认是 true）', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path4');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ledger_scheduler_auto_open': false,
      });
      mock.stubBool('ledgerIsReady', false);
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      mock.stubString(
        'ledgerListRules',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'protocol': 'imap', 'enabled': true},
        ]),
      );
      expect(service.autoOpenScheduler, isTrue); // 未初始化时 _prefs 为空 → 默认 true
      await service.ensureInitialized();
      expect(service.autoOpenScheduler, isFalse);
      expect(mock.callsOf('ledgerSchedulerStart'), isEmpty);
    });

    test('setAutoOpenScheduler 落盘后可被下一次初始化读回', () async {
      mock.stubBool('ledgerIsReady', true);
      await service.ensureInitialized();
      await service.setAutoOpenScheduler(false);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ledger_scheduler_auto_open'), isFalse);
      expect(service.autoOpenScheduler, isFalse);
      await service.setAutoOpenScheduler(true);
      expect(service.autoOpenScheduler, isTrue);
    });

    test('ensureInitialized 幂等：第二次不再发任何 FFI', () async {
      mock.stubBool('ledgerIsReady', true);
      await service.ensureInitialized();
      final int before = mock.calls.length;
      await service.ensureInitialized();
      expect(mock.calls.length, before);
    });

    test('现状锁定：口令预热失败不影响 ready（每条规则各自 try/catch）', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path5');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      mock.stubBool('ledgerIsReady', false);
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      mock.stubString(
        'ledgerListRules',
        listJson(<Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'protocol': 'imap', 'enabled': false},
        ]),
      );
      FlutterSecureStoragePlatform.instance = _ThrowingSecureStorage();
      await service.ensureInitialized();
      expect(service.ready.value, isTrue);
    });

    test('初始化失败要能重试：不把带错的状态缓存下来', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('ledger_db_path6');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      mock.stubBool('ledgerIsReady', false);
      mock.failSync('ledgerInit', StateError('建库失败'));
      mock.stubString('ledgerListRules', '[]');

      // 现状锁定：ensureInitialized 自己并不抛——错误只灌进没人监听的 completer，
      // 于是变成一次「未捕获的异步错误」，调用方只能靠 ready/isInitialized 判断成败。
      Object? uncaught;
      await runZonedGuarded(() async {
        await service.ensureInitialized();
        // 未监听的 completer 错误是在微任务里投递的，转一圈才能让 zone 收到
        await Future<void>.delayed(Duration.zero);
      }, (Object e, StackTrace s) => uncaught ??= e);
      expect(uncaught, isStateError);
      expect(service.ready.value, isFalse);
      expect(service.isInitialized, isFalse);

      // 修好后第二次能真正完成
      mock.stubString('ledgerInit', '{"ok":true}'); // ledgerInit 返回 String，桩成 null 会 TypeError
      await service.ensureInitialized();
      expect(service.ready.value, isTrue);
      expect(service.isInitialized, isTrue);
    });

    test('prefs 里已选远程节点时不碰本地库，也不建库', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ledger_selected_node_id': 'node-a',
      });
      mock.stubBool('ledgerIsReady', true);
      await service.ensureInitialized();
      expect(service.isLocal, isFalse);
      expect(service.selectedNodeId.value, 'node-a');
      expect(mock.callsOf('ledgerIsReady'), isEmpty);
      expect(mock.callsOf('ledgerInit'), isEmpty);
      // ready 保持 false：远程模式下本地模块确实没起来
      expect(service.ready.value, isFalse);
    });

    test('setSelectedNodeId 切回本地并落盘', () async {
      mock.stubBool('ledgerIsReady', true);
      await service.ensureInitialized();
      await service.setSelectedNodeId('node-a');
      expect(service.isLocal, isFalse);
      // 注：这里刻意不查 currentNodeBaseUrl——GetIt 里没注册 NodeSettingsService，
      // getter 会抛 NotRegistered（远程分支的断言都在下面那组里带注册地做）。
      await service.setSelectedNodeId('');
      expect(service.isLocal, isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ledger_selected_node_id'), '');
    });

    test('未初始化时 setSelectedNodeId 只改内存（_prefs 为空不炸）', () async {
      await service.setSelectedNodeId('node-a');
      expect(service.selectedNodeId.value, 'node-a');
      expect(service.isLocal, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 远程模式：走节点，不走本地 FFI
  // ══════════════════════════════════════════════════════════════════════════

  group('远程模式（假节点）', () {
    late FakeNodeServer server;

    setUp(() async {
      server = await FakeNodeServer.start();
      final NodeSettingsService nodeService = NodeSettingsService();
      nodeService.remoteNodes.add(
        NodeEndpoint(id: 'node-a', name: '测试节点', apiBaseUrl: server.baseUrl),
      );
      GetIt.instance.registerSingleton<NodeSettingsService>(nodeService);
      service.selectedNodeId.value = 'node-a';
    });

    tearDown(() async {
      await server.dispose();
    });

    test('listAccounts 打到 /node/call，params 是 action 声明的那份', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<dynamic>[
            accountJson(),
            accountJson(<String, dynamic>{'id': 2, 'name': '现金', 'type': 'cash'}),
          ]);
      final List<LedgerAccount> accounts = await service.listAccounts();
      expect(server.lastRequest.method, 'POST');
      expect(server.lastRequest.path, '/node/call');
      expect(server.lastRequest.action, 'ledger_list_accounts');
      expect(server.lastRequest.params, <String, dynamic>{});
      expect(accounts, hasLength(2));
      expect(accounts[1].type, 'cash');
      // 远程模式一次 FFI 都不发
      expect(mock.calls, isEmpty);
    });

    test('现状锁定：远程请求不带 X-SW-Auth（节点配了授权码就会被拒）', () async {
      expect(server.requestCount(), 0);
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<dynamic>[]);
      await service.listAccounts();
      expect(server.lastRequest.header('x-sw-auth'), isNull);
    });

    test('_list 的坏条目在远程路径上同样降级成默认对象', () async {
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<dynamic>[txJson(), '坏条目']);
      final List<LedgerTx> txs = await service.listTransactions(const LedgerFilter());
      expect(txs, hasLength(2));
      expect(txs.first.merchant, '测试商户');
      expect(txs.last.id, 0);
      expect(txs.last.direction, kLedgerDirectionExpense);
    });

    test('listCategories/listTransactions 的 params 键名是节点侧的 snake_case', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<dynamic>[]);
      await service.listCategories(direction: 'income');
      expect(server.lastRequest.action, 'ledger_list_categories');
      expect(server.lastRequest.params, <String, dynamic>{'direction': 'income'});

      const LedgerFilter f = LedgerFilter(accountId: 1, limit: 20);
      await service.listTransactions(f);
      expect(server.lastRequest.action, 'ledger_list_transactions');
      expect(server.lastRequest.params, <String, dynamic>{'filter_json': f.json});
    });

    test('_text：节点回 {text: ...} 时取 text', () async {
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'text': '账户已删除（3 笔流水归入其他）'});
      expect(await service.deleteAccount(7), '账户已删除（3 笔流水归入其他）');
      expect(server.lastRequest.action, 'ledger_delete_account');
      expect(server.lastRequest.params, <String, dynamic>{'id': 7});
    });

    test('backfillHistory：远程只发 snake_case 的 rule_id/password/limit', () async {
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'text': '历史回补：扫描 200 封，新增 3 封'});
      expect(
        await service.backfillHistory(9, password: '现填的', limit: 50),
        '历史回补：扫描 200 封，新增 3 封',
      );
      expect(server.lastRequest.action, 'ledger_backfill_rule');
      expect(
        server.lastRequest.params,
        <String, dynamic>{'rule_id': 9, 'password': '现填的', 'limit': 50},
      );
      expect(mock.calls, isEmpty);
    });

    test('_text：节点回裸字符串时原样返回，回别的结构时重新编码成 JSON 文本', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData('纯文本概况');
      expect(await service.deleteCategory(1), '纯文本概况');

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'a': 1});
      expect(await service.deleteCategory(1), '{"a":1}');

      // parsePreview 依赖这条：节点直接把解析结果当 data 回也能工作
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<String, dynamic>{
            'template_id': 'cmb',
            'bill_date': '2026-09-01',
            'transactions': <dynamic>[
              <String, dynamic>{'amount': 12.34},
            ],
          });
      final LedgerParseResult result =
          await service.parsePreview(html: '<html/>', templateId: 'cmb');
      expect(result.templateId, 'cmb');
      expect(result.transactions.single.amount, 12.34);
    });

    test('_id：数字/带 id 的 Map/带 count 的 Map/数字字符串都能折成整数', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(12);
      expect(await service.upsertAccount(LedgerAccount.fromJson(accountJson())), 12);

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'id': 13});
      expect(await service.upsertAccount(LedgerAccount.fromJson(accountJson())), 13);

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'count': 42});
      expect(await service.countTransactions(const LedgerFilter()), 42);

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'value': 2});
      expect(await service.pendingCount(), 2);

      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData('9');
      expect(await service.purgeEmail(1), 9);

      // 折不出整数时是 0，而不是抛错
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'text': 'ok'});
      expect(await service.pendingCount(), 0);
    });

    test('_bool：布尔和 {value}/{ok} 可识别，字符串与 null 一律 false（现状）', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(true);
      expect(await service.deleteTransaction(5), isTrue);

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'value': false});
      expect(await service.deleteTransaction(5), isFalse);

      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'ok': 1});
      expect(await service.deleteTransaction(5), isTrue);

      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData('true');
      expect(await service.deleteTransaction(5), isFalse);

      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(null);
      expect(await service.deleteTransaction(5), isFalse);
    });

    test('_run 只管发请求，不解读返回值', () async {
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'ignored': true});
      await service.updateTransaction(LedgerTx.fromJson(txJson()));
      expect(server.lastRequest.action, 'ledger_update_transaction');
      expect(
        jsonDecode((server.lastRequest.params['tx_json'] ?? '') as String),
        LedgerTx.fromJson(txJson()).toJson(),
      );

      await service.forgetMerchant('测试商户');
      expect(server.lastRequest.action, 'ledger_forget_merchant');
      expect(server.lastRequest.params, <String, dynamic>{'merchant_key': '测试商户'});

      await service.startScheduler();
      expect(server.lastRequest.action, 'ledger_scheduler_start');
      expect(server.lastRequest.params, <String, dynamic>{});
    });

    test('statsByMonth/Summary/DupCheck 在远程路径上的参数与解码', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(
            <String, dynamic>{'income': 100.0, 'expense': 12.34, 'net': 87.66, 'count': 3},
          );
      final LedgerSummary summary = await service.statsSummary(const LedgerFilter());
      expect(summary.net, 87.66);
      expect(server.lastRequest.action, 'ledger_stats_summary');

      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<dynamic>[
            <String, dynamic>{'month': '2026-09', 'income': 0, 'expense': 12.34, 'net': -12.34, 'count': 1},
          ]);
      final List<LedgerMonthRow> rows = await service.statsByMonth(months: 3);
      expect(server.lastRequest.action, 'ledger_stats_by_month');
      expect(server.lastRequest.params, <String, dynamic>{'months': 3});
      expect(rows.single.shortLabel, '9月');

      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(
            <String, dynamic>{'duplicated': true, 'existing_id': 4, 'existing_desc': '测试商户 12.34'},
          );
      final LedgerDupCheck dup = await service.checkDuplicate(
        merchant: '测试商户',
        amount: 12.34,
        billDate: '2026-09-29',
        accountId: 1,
      );
      expect(dup.duplicated, isTrue);
      expect(dup.existingId, 4);
      expect(server.lastRequest.action, 'ledger_check_duplicate');
    });

    test('远程 upsertRule 也带 password，但同样不写进 rule_json', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(8);
      final int id = await service.upsertRule(
        LedgerRule.fromJson(<String, dynamic>{'id': 0, 'name': '银行邮件'}),
        password: kFakeSecret,
      );
      expect(id, 8);
      final Map<String, dynamic> params = server.lastRequest.params;
      expect(params['password'], kFakeSecret);
      expect((jsonDecode(params['rule_json']! as String) as Map<String, dynamic>).containsKey('password'), isFalse);
      // 远程模式不把口令推进本地 Rust 内存（本机没跑服务）
      expect(mock.calls, isEmpty);
      // 安全存储仍然落在本机
      expect(await service.readRulePassword(8), kFakeSecret);
    });

    test('远程 hasRulePassword 认节点的 {value}，也认本机安全存储', () async {
      server.responder = (FakeNodeRequest req) =>
          FakeNodeReply.successData(<String, dynamic>{'value': true});
      expect(await service.hasRulePassword(3), isTrue);
      expect(server.lastRequest.action, 'ledger_has_rule_password');
      expect(server.lastRequest.params, <String, dynamic>{'rule_id': 3});

      await service.saveRulePassword(3, kFakeSecret);
      expect(await service.hasRulePassword(3), isTrue);
      // 命中本机后不再打节点
      expect(server.requestCount(action: 'ledger_has_rule_password'), 1);
    });

    test('节点回 success:false 时抛业务错误文案', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.businessError('该模块未启用');
      final Future<List<LedgerAccount>> future = service.listAccounts();
      await expectLater(future, throwsA(isA<Exception>()));
      Object? caught;
      try {
        await future;
      } catch (e) {
        caught = e;
      }
      expect(caught.toString(), contains('该模块未启用'));
    });

    test('现状锁定：_map 类接口收到数组时抛"返回格式异常"', () async {
      server.responder = (FakeNodeRequest req) => FakeNodeReply.successData(<dynamic>[]);
      await expectLater(
        service.statsSummary(const LedgerFilter()),
        throwsA(isStateError),
      );
    });

    test('selectedNodeId 指向不存在的节点时 currentNodeBaseUrl 为 null，调用抛 StateError', () async {
      service.selectedNodeId.value = 'node-不存在';
      expect(service.currentNodeBaseUrl, isNull);
      await expectLater(service.listAccounts(), throwsA(isStateError));
      expect(service.isLocal, isFalse);
    });

    test('节点地址为空串时同样判定为不可用', () async {
      // 换一份「地址为空」的节点表：先摘掉组里 setUp 注册的那个
      GetIt.instance.unregister<NodeSettingsService>();
      final NodeSettingsService nodeService = NodeSettingsService();
      nodeService.remoteNodes.add(const NodeEndpoint(id: 'node-a', name: '空地址', apiBaseUrl: ''));
      GetIt.instance.registerSingleton<NodeSettingsService>(nodeService);
      expect(service.currentNodeBaseUrl, isNull);
      await expectLater(service.listAccounts(), throwsA(isStateError));
    });

    test('currentNodeBaseUrl 命中节点时给出节点基地址', () {
      expect(service.currentNodeBaseUrl, server.baseUrl);
    });
  });
}
