import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';

class SentrySettingsService extends GetxService {
  static const String _keyEnabled = 'sentry_enabled';
  static const String _keySelectedNodeId = 'sentry_selected_node_id';
  static const String _keyAutoRefresh = 'sentry_auto_refresh';
  static const String _keyRefreshInterval = 'sentry_refresh_interval';

  final Loggers _logger = Loggers(name: 'SentrySettings');

  final RxBool enabled = true.obs;
  final RxString selectedNodeId = ''.obs;
  final RxBool autoRefresh = false.obs;
  final RxInt refreshIntervalSeconds = 30.obs;

  SharedPreferences? _prefs;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _load();
    _isInitialized = true;
    _logger.info('Sentry设置服务初始化完成');
  }

  void _load() {
    enabled.value = _prefs?.getBool(_keyEnabled) ?? true;
    selectedNodeId.value = _prefs?.getString(_keySelectedNodeId) ?? '';
    autoRefresh.value = _prefs?.getBool(_keyAutoRefresh) ?? false;
    refreshIntervalSeconds.value = _prefs?.getInt(_keyRefreshInterval) ?? 30;
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _prefs?.setBool(_keyEnabled, value);
  }

  Future<void> setSelectedNodeId(String nodeId) async {
    selectedNodeId.value = nodeId;
    await _prefs?.setString(_keySelectedNodeId, nodeId);
  }

  Future<void> setAutoRefresh(bool value) async {
    autoRefresh.value = value;
    await _prefs?.setBool(_keyAutoRefresh, value);
  }

  Future<void> setRefreshInterval(int seconds) async {
    refreshIntervalSeconds.value = seconds;
    await _prefs?.setInt(_keyRefreshInterval, seconds);
  }

  bool get isLocal => selectedNodeId.value.isEmpty;

  String? get currentNodeBaseUrl {
    if (isLocal) return null;
    final nodeService = GetIt.instance.get<NodeSettingsService>();
    final node = nodeService.getNodeById(selectedNodeId.value);
    return node?.apiBaseUrl;
  }

  String get currentDsn {
    if (isLocal) {
      final nodeService = GetIt.instance.get<NodeSettingsService>();
      if (nodeService.localNodeEnabled.value && nodeService.localNodeApiList.isNotEmpty) {
        return 'http://${nodeService.localNodeApiList.first}/<project_id>';
      }
      return 'http://127.0.0.1:17888/<project_id>';
    }
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) return 'http://127.0.0.1:17888/<project_id>';
    final uri = Uri.parse(baseUrl);
    return 'http://${uri.host}:${uri.port}/<project_id>';
  }

  Future<Map<String, dynamic>> fetchRemoteLogs({
    String? projectId,
    String? level,
    String? query,
    String? environment,
    String? startTime,
    String? endTime,
    required int offset,
    required int limit,
  }) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final queryParams = <String, String>{};
    if (projectId != null) queryParams['project_id'] = projectId;
    if (level != null) queryParams['level'] = level;
    if (query != null) queryParams['query'] = query;
    if (environment != null) queryParams['environment'] = environment;
    if (startTime != null) queryParams['start_time'] = startTime;
    if (endTime != null) queryParams['end_time'] = endTime;
    queryParams['offset'] = offset.toString();
    queryParams['limit'] = limit.toString();

    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/sentry/logs',
      queryParameters: queryParams,
    );
    return response.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchRemoteStats() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<Map<String, dynamic>>('$baseUrl/sentry/stats');
    return response.data ?? <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> fetchRemoteProjects() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<List<dynamic>>('$baseUrl/sentry/projects');
    return (response.data ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> fetchRemoteEvent(String eventId) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.get<Map<String, dynamic>>('$baseUrl/sentry/events/$eventId');
    return response.data ?? <String, dynamic>{};
  }

  Future<bool> deleteRemoteEvent(String eventId) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.delete<Map<String, dynamic>>('$baseUrl/sentry/events/$eventId');
    return response.data?['success'] == true;
  }

  Future<int> deleteRemoteEvents(List<String> eventIds) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/sentry/events/delete_batch',
      data: jsonEncode({'event_ids': eventIds}),
      options: Options(contentType: 'application/json'),
    );
    return (response.data?['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<String> exportRemoteLogs({
    String? projectId,
    String? level,
    String? query,
    String? environment,
    String? startTime,
    String? endTime,
  }) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');

    final filter = <String, dynamic>{};
    if (projectId != null) filter['project_id'] = projectId;
    if (level != null) filter['level'] = level;
    if (query != null) filter['query'] = query;
    if (environment != null) filter['environment'] = environment;
    if (startTime != null) filter['start_time'] = startTime;
    if (endTime != null) filter['end_time'] = endTime;

    final response = await _dio.post<String>(
      '$baseUrl/sentry/export',
      data: jsonEncode(filter),
      options: Options(contentType: 'application/json'),
    );
    return response.data ?? '';
  }

  Future<bool> checkNodeSentryAvailable(String baseUrl) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/sentry/stats',
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
