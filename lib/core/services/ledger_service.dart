import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/src/rust/api/ledger.dart' as rust_api;
import 'package:slime_works/src/rust/frb_generated.dart';

const Loggers _logger = Loggers(name: '流水账');

/// 流水账服务。
///
/// 数据都在 Rust/SQLite 里，这里只做三件事：把 FFI 的 JSON 文本解成模型、
/// 把邮箱口令放在系统安全存储（绝不写进 SharedPreferences，也绝不进日志），
/// 以及在移动端把调用中转给节点服务器。
///
/// 移动端限制：定时自动收信需要口令常驻 Rust 内存，只有本机跑过服务才具备；
/// 走远程节点时口令只能随单次请求带过去，节点侧不落盘。
class LedgerService extends GetxService {
  static const String _keySelectedNodeId = 'ledger_selected_node_id';
  static const String _keyAutoOpen = 'ledger_scheduler_auto_open';

  /// Rust 侧 secret_ref 记的就是这个前缀，两边必须一致
  static String secretKey(int ruleId) => 'ledger_rule_$ruleId';

  final RxString selectedNodeId = ''.obs;

  /// UI 用来显示"模块是否可用"；初始化失败时保持 false
  final RxBool ready = false.obs;

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  bool get isInitialized => _isInitialized;
  bool get isLocal => selectedNodeId.value.isEmpty;

  /// 初始化时是否顺手拉起后台收信调度
  bool get autoOpenScheduler => _prefs?.getBool(_keyAutoOpen) ?? true;

  String? get currentNodeBaseUrl {
    if (isLocal) return null;
    final nodeService = GetIt.instance.get<NodeSettingsService>();
    final base = nodeService.getNodeEffectiveBaseUrl(selectedNodeId.value);
    return base.isEmpty ? null : base;
  }

  Future<void> setSelectedNodeId(String nodeId) async {
    selectedNodeId.value = nodeId;
    await _prefs?.setString(_keySelectedNodeId, nodeId);
  }

  Future<void> setAutoOpenScheduler(bool value) async {
    await _prefs?.setBool(_keyAutoOpen, value);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 初始化
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    final completer = Completer<void>();
    _initCompleter = completer;
    try {
      await _loadPrefs();
      // 增强部分（标签/模板/定时/附件）现在还是本机桩数据，但和账本共用同一次初始化：
      // 分两处加载就会出现"页面先建、数据后到"的空白帧。
      await LedgerStubStore.instance.init();
      if (isLocal) await _initLocal();
      _isInitialized = true;
      completer.complete();
    } catch (e) {
      _logger.error('流水账初始化失败: $e');
      // 失败要能重试：缓存的 completer 一旦留着错误，后面每次进页面都只会重放同一次失败
      _initCompleter = null;
      ready.value = false;
      completer.completeError(e);
    }
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    selectedNodeId.value = _prefs?.getString(_keySelectedNodeId) ?? '';
  }

  Future<void> _initLocal() async {
    if (!RustLib.instance.initialized) await RustLib.init();
    if (rust_api.ledgerIsReady()) {
      ready.value = true;
      return;
    }
    final dir = await getApplicationSupportDirectory();
    final ledgerDir = Directory('${dir.path}/ledger');
    await ledgerDir.create(recursive: true);
    final dbPath = '${ledgerDir.path}/ledger.db';
    rust_api.ledgerInit(dbPathJson: jsonEncode(<String, dynamic>{'db_path': dbPath}));
    ready.value = true;
    _logger.info('流水账数据库已打开: $dbPath');
    final rules = await listRules();
    await _warmRuleSecrets(rules);
    // 没有启用的规则就别拉起每分钟的唤醒
    if (autoOpenScheduler && rules.any((r) => r.enabled && r.protocolSupported)) {
      await startScheduler();
    }
  }

  /// 把安全存储里的口令推进 Rust 内存，后台调度才跑得住
  Future<void> _warmRuleSecrets(List<LedgerRule> rules) async {
    for (final rule in rules) {
      try {
        final pwd = await readRulePassword(rule.id);
        if (pwd.isNotEmpty) rust_api.ledgerSetRulePassword(ruleId: rule.id, password: pwd);
      } catch (e) {
        _logger.error('邮箱规则 ${rule.name} 口令预热失败: $e');
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 口令：只进安全存储，读取时按需返回，永不写日志
  // ───────────────────────────────────────────────────────────────────────────

  Future<String> readRulePassword(int ruleId) async {
    try {
      return await _storage.read(key: secretKey(ruleId)) ?? '';
    } catch (e) {
      _logger.error('读取邮箱口令失败: $e');
      return '';
    }
  }

  Future<void> saveRulePassword(int ruleId, String password) async {
    try {
      if (password.isEmpty) {
        await _storage.delete(key: secretKey(ruleId));
      } else {
        await _storage.write(key: secretKey(ruleId), value: password);
      }
    } catch (e) {
      _logger.error('保存邮箱口令失败: $e');
      rethrow;
    }
  }

  Future<bool> hasRulePassword(int ruleId) async {
    if (ruleId <= 0) return false;
    if ((await readRulePassword(ruleId)).isNotEmpty) return true;
    return _bool(
      'ledger_has_rule_password',
      <String, dynamic>{'rule_id': ruleId},
      () => rust_api.ledgerHasRulePassword(ruleId: ruleId),
    );
  }

  /// 调用方没显式给口令时，从安全存储补一次
  Future<String> _passwordFor(int ruleId, String password) async =>
      password.isNotEmpty || ruleId <= 0 ? password : await readRulePassword(ruleId);

  // ───────────────────────────────────────────────────────────────────────────
  // 账户
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<LedgerAccount>> listAccounts() async =>
      _list('ledger_list_accounts', <String, dynamic>{}, () => rust_api.ledgerListAccounts(),
          LedgerAccount.fromJson);

  Future<int> upsertAccount(LedgerAccount account) async =>
      _id(
        'ledger_upsert_account',
        <String, dynamic>{'account_json': jsonEncode(account.toJson())},
        () => rust_api.ledgerUpsertAccount(accountJson: jsonEncode(account.toJson())),
      );

  /// Rust 返回的是"这个账户有 N 笔流水，已改为停用"这类中文说明，
  /// 影响面必须原样透到界面上，不能当没有返回值的调用丢掉。
  Future<String> deleteAccount(int id) async => _text(
        'ledger_delete_account',
        <String, dynamic>{'id': id},
        () => rust_api.ledgerDeleteAccount(id: id),
      );

  // ───────────────────────────────────────────────────────────────────────────
  // 类别
  // ───────────────────────────────────────────────────────────────────────────

  /// direction 传空串表示收支都要
  Future<List<LedgerCategory>> listCategories({String direction = ''}) async =>
      _list(
        'ledger_list_categories',
        <String, dynamic>{'direction': direction},
        () => rust_api.ledgerListCategories(direction: direction),
        LedgerCategory.fromJson,
      );

  Future<int> upsertCategory(LedgerCategory category) async =>
      _id(
        'ledger_upsert_category',
        <String, dynamic>{'category_json': jsonEncode(category.toJson())},
        () => rust_api.ledgerUpsertCategory(categoryJson: jsonEncode(category.toJson())),
      );

  Future<String> deleteCategory(int id) async => _text(
        'ledger_delete_category',
        <String, dynamic>{'id': id},
        () => rust_api.ledgerDeleteCategory(id: id),
      );

  /// 商户→类别的学习表，记账时用来猜类别
  Future<List<Map<String, dynamic>>> listMerchantMemory() async =>
      _listRaw(
        'ledger_list_merchant_memory',
        () => rust_api.ledgerListMerchantMemory(),
      );

  Future<void> forgetMerchant(String merchantKey) async =>
      _run(
        'ledger_forget_merchant',
        <String, dynamic>{'merchant_key': merchantKey},
        () => rust_api.ledgerForgetMerchant(merchantKey: merchantKey),
      );

  // ───────────────────────────────────────────────────────────────────────────
  // 流水
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<LedgerTx>> listTransactions(LedgerFilter filter) async =>
      _list(
        'ledger_list_transactions',
        <String, dynamic>{'filter_json': filter.json},
        () => rust_api.ledgerListTransactions(filterJson: filter.json),
        LedgerTx.fromJson,
      );

  Future<int> countTransactions(LedgerFilter filter) async =>
      _id(
        'ledger_count_transactions',
        <String, dynamic>{'filter_json': filter.json},
        () => rust_api.ledgerCountTransactions(filterJson: filter.json),
      );

  Future<int> addTransaction(LedgerTx tx) async =>
      _id(
        'ledger_add_transaction',
        <String, dynamic>{'tx_json': jsonEncode(tx.toJson())},
        () => rust_api.ledgerAddTransaction(txJson: jsonEncode(tx.toJson())),
      );

  Future<void> updateTransaction(LedgerTx tx) async =>
      _run(
        'ledger_update_transaction',
        <String, dynamic>{'tx_json': jsonEncode(tx.toJson())},
        () => rust_api.ledgerUpdateTransaction(txJson: jsonEncode(tx.toJson())),
      );

  Future<bool> deleteTransaction(int id) async => _bool(
        'ledger_delete_transaction',
        <String, dynamic>{'id': id},
        () => rust_api.ledgerDeleteTransaction(id: id),
      );

  Future<LedgerDupCheck> checkDuplicate({
    required String merchant,
    required double amount,
    required String billDate,
    int accountId = 0,
  }) async {
    final dup = <String, dynamic>{
      'merchant': merchant,
      'amount': amount,
      'bill_date': billDate,
      'account_id': accountId,
    };
    final raw = jsonEncode(dup);
    return LedgerDupCheck.fromJson(
      await _map(
        'ledger_check_duplicate',
        <String, dynamic>{'dup_json': raw},
        () => rust_api.ledgerCheckDuplicate(dupJson: raw),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 统计
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<LedgerDayRow>> statsByDay(LedgerFilter filter) async =>
      _list(
        'ledger_stats_by_day',
        <String, dynamic>{'filter_json': filter.json},
        () => rust_api.ledgerStatsByDay(filterJson: filter.json),
        LedgerDayRow.fromJson,
      );

  Future<List<LedgerCategoryRow>> statsByCategory(LedgerFilter filter) async =>
      _list(
        'ledger_stats_by_category',
        <String, dynamic>{'filter_json': filter.json},
        () => rust_api.ledgerStatsByCategory(filterJson: filter.json),
        LedgerCategoryRow.fromJson,
      );

  Future<List<LedgerMerchantRow>> statsByMerchant(LedgerFilter filter, {int top = 10}) async =>
      _list(
        'ledger_stats_by_merchant',
        <String, dynamic>{'filter_json': filter.json, 'top': top},
        () => rust_api.ledgerStatsByMerchant(filterJson: filter.json, top: top),
        LedgerMerchantRow.fromJson,
      );

  Future<List<LedgerMonthRow>> statsByMonth({int months = 12}) async =>
      _list(
        'ledger_stats_by_month',
        <String, dynamic>{'months': months},
        () => rust_api.ledgerStatsByMonth(months: months),
        LedgerMonthRow.fromJson,
      );

  Future<LedgerSummary> statsSummary(LedgerFilter filter) async => LedgerSummary.fromJson(
        await _map(
          'ledger_stats_summary',
          <String, dynamic>{'filter_json': filter.json},
          () => rust_api.ledgerStatsSummary(filterJson: filter.json),
        ),
      );

  // ───────────────────────────────────────────────────────────────────────────
  // 邮箱规则
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<LedgerRule>> listRules() async =>
      _list('ledger_list_rules', <String, dynamic>{}, () => rust_api.ledgerListRules(),
          LedgerRule.fromJson);

  /// password 为空表示沿用已存口令；非空时先落安全存储再交给 Rust
  Future<int> upsertRule(LedgerRule rule, {String password = ''}) async {
    final id = await _id(
      'ledger_upsert_rule',
      <String, dynamic>{'rule_json': jsonEncode(rule.toJson()), 'password': password},
      () => rust_api.ledgerUpsertRule(ruleJson: jsonEncode(rule.toJson()), password: password),
    );
    if (password.isNotEmpty) {
      await saveRulePassword(id, password);
      if (isLocal) rust_api.ledgerSetRulePassword(ruleId: id, password: password);
    }
    return id;
  }

  Future<void> deleteRule(int id) async {
    await _run('ledger_delete_rule', <String, dynamic>{'id': id}, () => rust_api.ledgerDeleteRule(id: id));
    await saveRulePassword(id, '');
  }

  Future<void> setRuleEnabled(int id, bool enabled) async => _run(
        'ledger_set_rule_enabled',
        <String, dynamic>{'id': id, 'enabled': enabled},
        () => rust_api.ledgerSetRuleEnabled(id: id, enabled: enabled),
      );

  /// 改口令（规则编辑页走这里，upsert 不带口令时用）
  Future<void> setRulePassword(int ruleId, String password) async {
    await saveRulePassword(ruleId, password);
    if (isLocal && password.isNotEmpty) {
      rust_api.ledgerSetRulePassword(ruleId: ruleId, password: password);
    }
  }

  Future<List<LedgerTemplate>> listTemplates() async =>
      _list('ledger_templates', <String, dynamic>{}, () => rust_api.ledgerTemplates(),
          LedgerTemplate.fromJson);

  /// 把一段 HTML 直接喂模板引擎，改版时先验证再改规则
  Future<String> parsePreviewRaw({
    required String html,
    required String templateId,
    String templateConfig = '{}',
  }) async =>
      _text(
        'ledger_parse_preview',
        <String, dynamic>{
          'html': html,
          'template_id': templateId,
          'template_config': templateConfig,
        },
        () => rust_api.ledgerParsePreview(
          html: html,
          templateId: templateId,
          templateConfig: templateConfig,
        ),
      );

  Future<LedgerParseResult> parsePreview({
    required String html,
    required String templateId,
    String templateConfig = '{}',
  }) async =>
      LedgerParseResult.fromJson(
        jsonDecode(
          await parsePreviewRaw(
            html: html,
            templateId: templateId,
            templateConfig: templateConfig,
          ),
        ) as Map<String, dynamic>,
      );

  // ───────────────────────────────────────────────────────────────────────────
  // 收取（联网，远程节点也走这一组）
  // ───────────────────────────────────────────────────────────────────────────

  /// 按已存规则收一次，返回本次落库概况
  Future<String> checkRule(int ruleId, {String password = ''}) async {
    final pwd = await _passwordFor(ruleId, password);
    return _text(
      'ledger_check_rule',
      <String, dynamic>{'rule_id': ruleId, 'password': pwd},
      () => rust_api.ledgerCheckRule(ruleId: ruleId, password: pwd),
    );
  }

  /// 历史回补：从收件箱最近的 [limit] 封里（0 用 Rust 侧默认 200 封）把命中规则的
  /// 账单邮件全部补录入账，返回概况文本。
  ///
  /// 日常定时收取只看最新 10 封，够快但补不了过去：第一次配规则、口令失效停摆
  /// 几天，历史账单就永远进不来。这一路是幂等的（已收 UID 跳过 + 流水唯一索引），
  /// 所以点两次不会记两遍。
  Future<String> backfillHistory(
    int ruleId, {
    String password = '',
    int limit = 0,
  }) async {
    final pwd = await _passwordFor(ruleId, password);
    return _text(
      'ledger_backfill_rule',
      <String, dynamic>{'rule_id': ruleId, 'password': pwd, 'limit': limit},
      () => rust_api.ledgerBackfillRule(
        ruleId: ruleId,
        password: pwd,
        limit: BigInt.from(limit),
      ),
    );
  }

  /// 试收取：规则还没保存时也能用当前表单直接连一次
  Future<List<LedgerFetchedEmail>> fetchEmails({
    required Map<String, dynamic> config,
    String password = '',
    int limit = 20,
  }) async {
    final pwd = await _passwordFor((config['rule_id'] as int? ?? 0), password);
    final cfgJson = jsonEncode(config);
    return _list(
      'ledger_fetch_emails',
      <String, dynamic>{'config_json': cfgJson, 'password': pwd, 'limit': limit},
      () => rust_api.ledgerFetchEmails(configJson: cfgJson, password: pwd, limit: BigInt.from(limit)),
      LedgerFetchedEmail.fromJson,
    );
  }

  Future<LedgerProbeReport> testConnection({
    required Map<String, dynamic> config,
    String password = '',
    bool wantFolders = false,
  }) async {
    final pwd = await _passwordFor((config['rule_id'] as int? ?? 0), password);
    final cfgJson = jsonEncode(config);
    return LedgerProbeReport.fromJson(
      await _map(
        'ledger_test_connection',
        <String, dynamic>{
          'config_json': cfgJson,
          'password': pwd,
          'want_folders': wantFolders,
        },
        () => rust_api.ledgerTestConnection(
          configJson: cfgJson,
          password: pwd,
          wantFolders: wantFolders,
        ),
      ),
    );
  }

  Future<List<String>> listFolders({
    required Map<String, dynamic> config,
    String password = '',
  }) async {
    final report = await testConnection(config: config, password: password, wantFolders: true);
    return report.folders;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 待确认队列
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<LedgerPendingEmail>> listPending({int limit = 100}) async =>
      _list(
        'ledger_list_pending',
        <String, dynamic>{'limit': limit},
        () => rust_api.ledgerListPending(limit: limit),
        LedgerPendingEmail.fromJson,
      );

  /// 含已入账的历史邮件，用于溯源
  Future<List<LedgerPendingEmail>> listReceivedEmails({int limit = 100}) async =>
      _list(
        'ledger_list_received_emails',
        <String, dynamic>{'limit': limit},
        () => rust_api.ledgerListReceivedEmails(limit: limit),
        LedgerPendingEmail.fromJson,
      );

  Future<List<LedgerTx>> transactionsOfEmail(int emailId) async =>
      _list(
        'ledger_email_transactions',
        <String, dynamic>{'email_id': emailId},
        () => rust_api.ledgerEmailTransactions(emailId: emailId),
        LedgerTx.fromJson,
      );

  Future<int> pendingCount() async =>
      _id('ledger_pending_count', <String, dynamic>{}, () => rust_api.ledgerPendingCount());

  /// patch 可带 account_id / category_id 覆盖解析默认值
  Future<void> confirmTx(int txId, {Map<String, dynamic> patch = const <String, dynamic>{}}) async =>
      _run(
        'ledger_confirm_tx',
        <String, dynamic>{'tx_id': txId, 'patch_json': jsonEncode(patch)},
        () => rust_api.ledgerConfirmTx(txId: txId, patchJson: jsonEncode(patch)),
      );

  Future<int> confirmAll(int emailId, {Map<String, dynamic> patch = const <String, dynamic>{}}) async =>
      _id(
        'ledger_confirm_all',
        <String, dynamic>{'email_id': emailId, 'patch_json': jsonEncode(patch)},
        () => rust_api.ledgerConfirmAll(emailId: emailId, patchJson: jsonEncode(patch)),
      );

  Future<void> ignoreTx(int txId) async =>
      _run('ledger_ignore_tx', <String, dynamic>{'tx_id': txId}, () => rust_api.ledgerIgnoreTx(txId: txId));

  Future<int> ignoreEmail(int emailId) async =>
      _id(
        'ledger_ignore_email',
        <String, dynamic>{'email_id': emailId},
        () => rust_api.ledgerIgnoreEmail(emailId: emailId),
      );

  /// 删掉这封邮件带来的全部流水（含已入账）
  Future<int> purgeEmail(int emailId) async =>
      _id('ledger_purge_email', <String, dynamic>{'email_id': emailId},
          () => rust_api.ledgerPurgeEmail(emailId: emailId));

  // ───────────────────────────────────────────────────────────────────────────
  // 调度与日志
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> startScheduler() async =>
      _run('ledger_scheduler_start', <String, dynamic>{}, () => rust_api.ledgerSchedulerStart());

  Future<void> stopScheduler() async =>
      _run('ledger_scheduler_stop', <String, dynamic>{}, () => rust_api.ledgerSchedulerStop());

  Future<LedgerSchedulerStatus> schedulerStatus() async => LedgerSchedulerStatus.fromJson(
        await _map('ledger_scheduler_status', <String, dynamic>{}, () => rust_api.ledgerSchedulerStatus()),
      );

  Future<List<LedgerFetchLog>> listLogs({int limit = 50}) async =>
      _list(
        'ledger_get_logs',
        <String, dynamic>{'limit': limit},
        () => rust_api.ledgerGetLogs(limit: limit),
        LedgerFetchLog.fromJson,
      );

  Future<void> clearLogs() async =>
      _run('ledger_clear_logs', <String, dynamic>{}, () => rust_api.ledgerClearLogs());

  String moduleVersion() => rust_api.ledgerVersion();

  // ───────────────────────────────────────────────────────────────────────────
  // 本地/远程统一收口
  // ───────────────────────────────────────────────────────────────────────────

  bool get _useLocal => isLocal;

  Future<List<T>> _list<T>(
    String action,
    Map<String, dynamic> params,
    FutureOr<String> Function() local,
    T Function(Map<String, dynamic>) parse,
  ) async =>
      _decodeList(await _raw(action, params, local)).map(parse).toList(growable: false);

  Future<List<Map<String, dynamic>>> _listRaw(
    String action,
    FutureOr<String> Function() local,
  ) async =>
      _decodeList(await _raw(action, <String, dynamic>{}, local));

  Future<Map<String, dynamic>> _map(
    String action,
    Map<String, dynamic> params,
    FutureOr<String> Function() local,
  ) async =>
      _decodeMap(await _raw(action, params, local));

  /// 返回文本的接口（概况、预览原文）
  Future<String> _text(
    String action,
    Map<String, dynamic> params,
    FutureOr<String> Function() local,
  ) async {
    if (_useLocal) return await local();
    final data = await _nodeCall(action, params);
    if (data is Map<String, dynamic> && data['text'] != null) return data['text'].toString();
    return data is String ? data : jsonEncode(data);
  }

  Future<int> _id(
    String action,
    Map<String, dynamic> params,
    FutureOr<int> Function() local,
  ) async {
    if (_useLocal) return await local();
    final data = await _nodeCall(action, params);
    return _asInt(data);
  }

  Future<bool> _bool(
    String action,
    Map<String, dynamic> params,
    FutureOr<bool> Function() local,
  ) async {
    if (_useLocal) return await local();
    final data = await _nodeCall(action, params);
    if (data is bool) return data;
    if (data is Map<String, dynamic>) return _asBool(data['value'] ?? data['ok']);
    return false;
  }

  Future<void> _run(
    String action,
    Map<String, dynamic> params,
    FutureOr<Object?> Function() local,
  ) async {
    if (_useLocal) {
      await local();
      return;
    }
    await _nodeCall(action, params);
  }

  /// 本地拿 Rust 的 JSON 文本，远程拿节点的 data 再回编码，解码只有一条路。
  /// 联网那几个 FFI 是 async、其余是 sync，所以闭包统一按 FutureOr 收。
  Future<String> _raw(
    String action,
    Map<String, dynamic> params,
    FutureOr<String> Function() local,
  ) async {
    if (_useLocal) return await local();
    return jsonEncode(await _nodeCall(action, params));
  }

  Future<Object?> _nodeCall(String action, Map<String, dynamic> params) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点，或节点地址不可用');
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/node/call',
      data: <String, dynamic>{'action': action, 'params': params},
    );
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true) return body['data'];
    throw Exception(body['error']?.toString() ?? '节点调用失败: $action');
  }

  static int _asInt(Object? data) => switch (data) {
    num n => n.toInt(),
    Map<String, dynamic> m => _asInt(m['id'] ?? m['count'] ?? m['value']),
    String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  static bool _asBool(Object? data) => switch (data) {
    bool b => b,
    num n => n != 0,
    String s => s == 'true' || s == '1',
    _ => false,
  };

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    return switch (decoded) {
      Map<String, dynamic> m => m,
      Map m => m.map((k, v) => MapEntry(k.toString(), v)),
      _ => throw StateError('流水账返回格式异常'),
    };
  }

  List<Map<String, dynamic>> _decodeList(String raw) {
    final decoded = jsonDecode(raw);
    return switch (decoded) {
      List list => list
          .map((e) => switch (e) {
                Map<String, dynamic> m => m,
                Map m => m.map((k, v) => MapEntry(k.toString(), v)),
                _ => <String, dynamic>{},
              })
          .toList(growable: false),
      _ => const <Map<String, dynamic>>[],
    };
  }

  @override
  void onClose() {
    if (_useLocal) {
      try {
        rust_api.ledgerSchedulerStop();
      } catch (e) {
        _logger.error('关闭流水账调度失败: $e');
      }
    }
    super.onClose();
  }
}
