import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/src/rust/api/aliyun_ddns.dart' as rust_api;

const Loggers _logger = Loggers(name: '阿里云DDNS');

class WatchDomain {
  final String domainName;
  final String rr;
  final String recordType;

  WatchDomain({required this.domainName, required this.rr, this.recordType = 'A'});

  Map<String, dynamic> toMap() => {'domain_name': domainName, 'rr': rr, 'record_type': recordType};

  factory WatchDomain.fromMap(Map<String, dynamic> m) => WatchDomain(
    domainName: m['domain_name'] as String? ?? '',
    rr: m['rr'] as String? ?? '@',
    recordType: m['record_type'] as String? ?? 'A',
  );

  String get fullDomain => rr == '@' ? domainName : '$rr.$domainName';
}

class AliyunDdnsService extends GetxService {
  static const String _keyAccessKeyId = 'aliyun_access_key_id';
  static const String _keyAccessKeySecret = 'aliyun_access_key_secret';
  static const String _keyWatchDomains = 'aliyun_watch_domains';
  static const String _keyIntervalSecs = 'aliyun_interval_secs';
  static const String _keyEnabled = 'aliyun_ddns_enabled';
  static const String _keySelectedNodeId = 'aliyun_selected_node_id';

  final RxString accessKeyId = ''.obs;
  final RxString accessKeySecret = ''.obs;
  final RxList<WatchDomain> watchDomains = <WatchDomain>[].obs;
  final RxInt intervalSecs = 300.obs;
  final RxBool enabled = false.obs;

  final RxString currentIp = ''.obs;
  final RxString lastUpdate = ''.obs;
  final RxString lastResult = ''.obs;
  final RxList<Map<String, dynamic>> domainStatuses = <Map<String, dynamic>>[].obs;

  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;

  final RxString selectedNodeId = ''.obs;

  SharedPreferences? _prefs;
  Timer? _checkTimer;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  bool get isInitialized => _isInitialized;
  bool get isLocal => selectedNodeId.value.isEmpty;

  String? get currentNodeBaseUrl {
    if (isLocal) return null;
    final nodeService = GetIt.instance.get<NodeSettingsService>();
    final node = nodeService.getNodeById(selectedNodeId.value);
    return node?.effectiveApiBaseUrl;
  }

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    _initCompleter = Completer<void>();
    await _loadPrefs();
    await _initRustModule();
    if (enabled.value && accessKeyId.value.isNotEmpty) {
      startCheckTimer();
    }
    _isInitialized = true;
    _initCompleter!.complete();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    accessKeyId.value = _prefs?.getString(_keyAccessKeyId) ?? '';
    accessKeySecret.value = _prefs?.getString(_keyAccessKeySecret) ?? '';
    intervalSecs.value = _prefs?.getInt(_keyIntervalSecs) ?? 300;
    enabled.value = _prefs?.getBool(_keyEnabled) ?? false;
    selectedNodeId.value = _prefs?.getString(_keySelectedNodeId) ?? '';

    final domainsJson = _prefs?.getString(_keyWatchDomains) ?? '[]';
    try {
      final list = jsonDecode(domainsJson) as List<dynamic>;
      watchDomains.value = list.map((e) => WatchDomain.fromMap(e as Map<String, dynamic>)).toList();
    } catch (_) {
      watchDomains.value = [];
    }
  }

  Future<void> _savePrefs() async {
    await _prefs?.setString(_keyAccessKeyId, accessKeyId.value);
    await _prefs?.setString(_keyAccessKeySecret, accessKeySecret.value);
    await _prefs?.setInt(_keyIntervalSecs, intervalSecs.value);
    await _prefs?.setBool(_keyEnabled, enabled.value);
    await _prefs?.setString(_keySelectedNodeId, selectedNodeId.value);
    final domainsJson = jsonEncode(watchDomains.map((e) => e.toMap()).toList());
    await _prefs?.setString(_keyWatchDomains, domainsJson);
  }

  Future<void> setAccessKeyId(String value) async {
    accessKeyId.value = value;
    await _prefs?.setString(_keyAccessKeyId, value);
  }

  Future<void> setAccessKeySecret(String value) async {
    accessKeySecret.value = value;
    await _prefs?.setString(_keyAccessKeySecret, value);
  }

  Future<void> setIntervalSecs(int value) async {
    intervalSecs.value = value;
    await _prefs?.setInt(_keyIntervalSecs, value);
    if (enabled.value) _restartTimer();
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _prefs?.setBool(_keyEnabled, value);
    try {
      rust_api.aliyunDdnsSetEnabled(enabled: value);
    } catch (e) {
      _logger.error('同步DDNS开关状态失败: $e');
    }
    if (value) {
      startCheckTimer();
    } else {
      stopCheckTimer();
    }
  }

  Future<void> setSelectedNodeId(String nodeId) async {
    selectedNodeId.value = nodeId;
    await _prefs?.setString(_keySelectedNodeId, nodeId);
  }

  Future<void> addWatchDomain(WatchDomain domain) async {
    watchDomains.add(domain);
    await _savePrefs();
    await updateConfig();
  }

  Future<void> removeWatchDomain(int index) async {
    watchDomains.removeAt(index);
    await _savePrefs();
    await updateConfig();
  }

  String _buildConfigJson() {
    return jsonEncode({
      'access_key_id': accessKeyId.value,
      'access_key_secret': accessKeySecret.value,
      'watch_domains': watchDomains.map((e) => e.toMap()).toList(),
      'interval_secs': intervalSecs.value,
      'enabled': enabled.value,
    });
  }

  Future<void> initRustModule() async {
    try {
      rust_api.aliyunDdnsInit(configJson: _buildConfigJson());
      _logger.info('阿里云DDNS模块初始化完成');
    } catch (e) {
      _logger.error('阿里云DDNS模块初始化失败: $e');
    }
  }

  Future<void> _initRustModule() async {
    await initRustModule();
  }

  Future<void> updateConfig() async {
    try {
      rust_api.aliyunDdnsUpdateConfig(configJson: _buildConfigJson());
      await _savePrefs();
      _logger.info('阿里云DDNS配置已更新');
    } catch (e) {
      _logger.error('阿里云DDNS配置更新失败: $e');
    }
  }

  Future<String> checkAndUpdate() async {
    try {
      final result = await rust_api.aliyunDdnsCheckAndUpdate();
      await refreshStatus();
      await refreshLogs();
      _logger.info('DDNS检查完成: $result');
      return result;
    } catch (e) {
      _logger.error('DDNS检查失败: $e');
      lastResult.value = '检查失败: $e';
      return '检查失败: $e';
    }
  }

  Future<void> refreshStatus() async {
    try {
      final statusJson = rust_api.aliyunDdnsGetStatus();
      final status = jsonDecode(statusJson) as Map<String, dynamic>;
      currentIp.value = status['current_ip'] as String? ?? '';
      lastUpdate.value = status['last_update'] as String? ?? '';
      lastResult.value = status['last_result'] as String? ?? '';
      final ds = status['domain_statuses'] as List<dynamic>? ?? [];
      domainStatuses.value = ds.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      _logger.error('获取DDNS状态失败: $e');
    }
  }

  Future<void> refreshLogs() async {
    try {
      final logsJson = rust_api.aliyunDdnsGetLogs();
      final list = jsonDecode(logsJson) as List<dynamic>;
      logs.value = list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      _logger.error('获取DDNS日志失败: $e');
    }
  }

  Future<void> clearLogs() async {
    try {
      rust_api.aliyunDdnsClearLogs();
      logs.clear();
    } catch (e) {
      _logger.error('清除DDNS日志失败: $e');
    }
  }

  void startCheckTimer() {
    stopCheckTimer();
    if (!enabled.value) return;

    _checkTimer = Timer.periodic(Duration(seconds: intervalSecs.value), (_) async {
      await checkAndUpdate();
    });

    checkAndUpdate();
    _logger.info('DDNS定时检查已启动，间隔${intervalSecs.value}秒');
  }

  void stopCheckTimer() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  void _restartTimer() {
    if (enabled.value) startCheckTimer();
  }

  // ── 远程节点 API ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchRemoteStatus() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<Map<String, dynamic>>('$baseUrl/aliyun/status');
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw Exception(body['error']?.toString() ?? '获取远程状态失败');
  }

  Future<List<Map<String, dynamic>>> fetchRemoteLogs() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<Map<String, dynamic>>('$baseUrl/aliyun/logs');
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true && body['data'] is List) {
      return (body['data'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw Exception(body['error']?.toString() ?? '获取远程日志失败');
  }

  Future<List<WatchDomain>> fetchRemoteWatchDomains() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<Map<String, dynamic>>('$baseUrl/aliyun/watch_domains');
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true && body['data'] is List) {
      return (body['data'] as List)
          .whereType<Map>()
          .map((e) => WatchDomain.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw Exception(body['error']?.toString() ?? '获取远程监控域名失败');
  }

  Future<String> remoteCheckAndUpdate() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.post<Map<String, dynamic>>('$baseUrl/aliyun/check_and_update');
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true && body['data'] is Map) {
      return (body['data'] as Map)['result']?.toString() ?? '检查完成';
    }
    throw Exception(body['error']?.toString() ?? '远程检查更新失败');
  }

  Future<bool> checkNodeAliyunAvailable(String baseUrl) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/aliyun/status',
        options: Options(
          connectTimeout: const Duration(milliseconds: 200),
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      return response.statusCode == 200 && response.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void onClose() {
    stopCheckTimer();
    super.onClose();
  }
}
