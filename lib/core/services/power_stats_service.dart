import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/src/rust/api/power_stats.dart' as rust_api;

const Loggers _logger = Loggers(name: '电力统计');

/// 电力统计配置
class PowerStatsConfig {
  final String meterId;
  final bool enabled;
  final int intervalSecs;
  final bool persist;
  final String dbPath;

  const PowerStatsConfig({
    this.meterId = '',
    this.enabled = false,
    this.intervalSecs = 60,
    this.persist = true,
    this.dbPath = '',
  });

  Map<String, dynamic> toMap() => {
    'meter_id': meterId,
    'enabled': enabled,
    'interval_secs': intervalSecs,
    'persist': persist,
    'db_path': dbPath,
  };

  factory PowerStatsConfig.fromMap(Map<String, dynamic> m) => PowerStatsConfig(
    meterId: m['meter_id'] as String? ?? '',
    enabled: m['enabled'] as bool? ?? false,
    intervalSecs: m['interval_secs'] as int? ?? 60,
    persist: m['persist'] as bool? ?? true,
    dbPath: m['db_path'] as String? ?? '',
  );

  String toJson() => jsonEncode(toMap());

  PowerStatsConfig copyWith({
    String? meterId,
    bool? enabled,
    int? intervalSecs,
    bool? persist,
    String? dbPath,
  }) => PowerStatsConfig(
    meterId: meterId ?? this.meterId,
    enabled: enabled ?? this.enabled,
    intervalSecs: intervalSecs ?? this.intervalSecs,
    persist: persist ?? this.persist,
    dbPath: dbPath ?? this.dbPath,
  );
}

/// 电力统计服务
class PowerStatsService extends GetxService {
  static const String _keyMeterId = 'power_stats_meter_id';
  static const String _keyEnabled = 'power_stats_enabled';
  static const String _keyInterval = 'power_stats_interval_secs';
  static const String _keySelectedNodeId = 'power_stats_selected_node_id';

  final RxString meterId = ''.obs;
  final RxBool enabled = false.obs;
  final RxInt intervalSecs = 60.obs;
  final RxString selectedNodeId = ''.obs;

  // 运行时状态
  final RxString meterName = ''.obs;
  final RxDouble currentKwh = 0.0.obs;
  final RxDouble currentYuan = 0.0.obs;
  final RxDouble price = 1.0.obs;
  final RxString lastFetch = ''.obs;
  final RxString lastResult = ''.obs;
  final RxInt sampleCount = 0.obs;
  final RxBool isPolling = false.obs;

  // 统计数据
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;
  final RxMap<String, dynamic> aggregated = <String, dynamic>{}.obs;
  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  /// 节点请求专用 Dio：向 [NodeSettingsService] 要，那条路上才带 `X-SW-Auth`
  /// 摘要并绕开系统代理直连。裸 `Dio(...)` 少了授权头，节点一设授权码，
  /// 远程抓取/状态查询连同"该节点支持不支持"的探测会全部吃 401。
  /// late：构造本服务时 NodeSettingsService 未必已注册，第一次发请求才组装。
  late final Dio _dio = GetIt.instance.get<NodeSettingsService>().createNodeDio(
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
    // 走服务层的"最近应答地址"：直接读 effectiveApiBaseUrl 会永远压在失效的内网那一路
    final base = nodeService.getNodeEffectiveBaseUrl(selectedNodeId.value);
    return base.isEmpty ? null : base;
  }

  /// 计算数据库路径
  String _computeDbPath() {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      return '$home/.slime_works/power_stats.db';
    }
    if (Platform.isWindows) {
      final appdata = Platform.environment['APPDATA'] ?? '.';
      return '$appdata/slime_works/power_stats.db';
    }
    // 移动端默认不持久化
    return '';
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
    _isInitialized = true;
    _initCompleter!.complete();
  }

  Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    meterId.value = _prefs?.getString(_keyMeterId) ?? '';
    enabled.value = _prefs?.getBool(_keyEnabled) ?? false;
    intervalSecs.value = _prefs?.getInt(_keyInterval) ?? 60;
    selectedNodeId.value = _prefs?.getString(_keySelectedNodeId) ?? '';
  }

  Future<void> _savePrefs() async {
    await _prefs?.setString(_keyMeterId, meterId.value);
    await _prefs?.setBool(_keyEnabled, enabled.value);
    await _prefs?.setInt(_keyInterval, intervalSecs.value);
    await _prefs?.setString(_keySelectedNodeId, selectedNodeId.value);
  }

  /// 构建配置JSON（持久化标志由是否本地+桌面端决定）
  String _buildConfigJson() {
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final persist = isLocal && isDesktop;
    final dbPath = persist ? _computeDbPath() : '';
    final config = PowerStatsConfig(
      meterId: meterId.value,
      enabled: enabled.value,
      intervalSecs: intervalSecs.value,
      persist: persist,
      dbPath: dbPath,
    );
    return config.toJson();
  }

  Future<void> _initRustModule() async {
    try {
      rust_api.powerStatsInit(configJson: _buildConfigJson());
      _logger.info('电力统计模块初始化完成');
    } catch (e) {
      _logger.error('电力统计模块初始化失败: $e');
    }
  }

  /// 应用启动预热：建库 + 按已保存的配置把定时轮询拉起来。
  ///
  /// 表号一旦存过，"要不要采样"就已经是用户的决定了，不该每天开机再进页面
  /// 点一次"启动轮询"。这里排在 runApp 之后跑，页面开不开都照采。
  /// [enabled] 仍是唯一的总开关：手动关掉的人不该在下次启动时被偷偷打开。
  Future<void> warmUpAfterLaunch() async {
    await ensureInitialized();
    if (!isLocal) return;
    if (meterId.value.trim().isEmpty) return;
    if (!enabled.value) {
      _logger.info('电力统计开关已关闭，跳过启动轮询');
      return;
    }
    await startPolling();
  }

  /// 保存表号。
  ///
  /// 填了表号就等于"我要统计"：顺手把总开关打开并拉起轮询，不再要求用户
  /// 回页面里手动点一次"启动轮询"。清空表号则反过来——没什么可采的了。
  Future<void> setMeterId(String value) async {
    meterId.value = value.trim();
    if (meterId.value.isNotEmpty) enabled.value = true;
    await _savePrefs();
    await updateConfig();
    if (!isLocal) return;
    if (meterId.value.isEmpty) {
      await stopPolling();
    } else {
      await startPolling();
    }
  }

  Future<void> setIntervalSecs(int value) async {
    intervalSecs.value = value;
    await _savePrefs();
    await updateConfig();
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    await _savePrefs();
    try {
      rust_api.powerStatsSetEnabled(enabled: value);
    } catch (e) {
      _logger.error('同步开关状态失败: $e');
    }
    if (value && isLocal) {
      await startPolling();
    } else if (isLocal) {
      await stopPolling();
    }
  }

  Future<void> setSelectedNodeId(String nodeId) async {
    selectedNodeId.value = nodeId;
    await _savePrefs();
  }

  Future<void> updateConfig() async {
    try {
      rust_api.powerStatsUpdateConfig(configJson: _buildConfigJson());
    } catch (e) {
      _logger.error('配置更新失败: $e');
    }
  }

  /// 手动抓取一次
  Future<String> fetchOnce() async {
    try {
      if (isLocal) {
        final result = await rust_api.powerStatsFetchOnce();
        await refreshStatus();
        await refreshSummary();
        await refreshLogs();
        _logger.info('电力抓取完成: $result');
        return result;
      } else {
        return await _remoteFetchOnce();
      }
    } catch (e) {
      _logger.error('电力抓取失败: $e');
      lastResult.value = '抓取失败: $e';
      return '抓取失败: $e';
    }
  }

  /// 启动定时轮询（仅本地桌面端）
  Future<void> startPolling() async {
    if (!isLocal) return;
    try {
      await rust_api.powerStatsStartPolling();
      isPolling.value = true;
      _logger.info('电力定时轮询已启动');
    } catch (e) {
      _logger.error('启动轮询失败: $e');
    }
  }

  /// 停止定时轮询
  Future<void> stopPolling() async {
    if (!isLocal) return;
    try {
      await rust_api.powerStatsStopPolling();
      isPolling.value = false;
      _logger.info('电力定时轮询已停止');
    } catch (e) {
      _logger.error('停止轮询失败: $e');
    }
  }

  /// 刷新运行时状态
  Future<void> refreshStatus() async {
    try {
      if (isLocal) {
        final statusJson = rust_api.powerStatsGetStatus();
        final status = jsonDecode(statusJson) as Map<String, dynamic>;
        meterName.value = status['meter_name'] as String? ?? '';
        currentKwh.value = (status['current_kwh'] as num?)?.toDouble() ?? 0.0;
        currentYuan.value = (status['current_yuan'] as num?)?.toDouble() ?? 0.0;
        price.value = (status['price'] as num?)?.toDouble() ?? 1.0;
        lastFetch.value = status['last_fetch'] as String? ?? '';
        lastResult.value = status['last_result'] as String? ?? '';
        sampleCount.value = (status['sample_count'] as num?)?.toInt() ?? 0;
        isPolling.value = status['polling'] as bool? ?? false;
      } else {
        final status = await _remoteCall('power_stats_get_status', {});
        meterName.value = status['meter_name'] as String? ?? '';
        currentKwh.value = (status['current_kwh'] as num?)?.toDouble() ?? 0.0;
        currentYuan.value = (status['current_yuan'] as num?)?.toDouble() ?? 0.0;
        price.value = (status['price'] as num?)?.toDouble() ?? 1.0;
        lastFetch.value = status['last_fetch'] as String? ?? '';
        lastResult.value = status['last_result'] as String? ?? '';
        sampleCount.value = (status['sample_count'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      _logger.error('获取状态失败: $e');
    }
  }

  /// 刷新统计卡片汇总
  Future<void> refreshSummary() async {
    try {
      if (isLocal) {
        final json = rust_api.powerStatsGetSummary();
        summary.value = jsonDecode(json) as Map<String, dynamic>;
      } else {
        final data = await _remoteCall('power_stats_get_summary', {});
        summary.value = data;
      }
    } catch (e) {
      _logger.error('获取汇总失败: $e');
    }
  }

  /// 刷新图表聚合数据
  Future<void> refreshAggregated(String range) async {
    try {
      if (isLocal) {
        final json = rust_api.powerStatsGetAggregated(range: range);
        aggregated.value = jsonDecode(json) as Map<String, dynamic>;
      } else {
        final data = await _remoteCall('power_stats_get_aggregated', {'range': range});
        aggregated.value = data;
      }
    } catch (e) {
      _logger.error('获取聚合数据失败: $e');
    }
  }

  /// 刷新日志
  Future<void> refreshLogs() async {
    try {
      if (isLocal) {
        final json = rust_api.powerStatsGetLogs();
        final list = jsonDecode(json) as List<dynamic>;
        logs.value = list.map((e) => e as Map<String, dynamic>).toList();
      } else {
        final data = await _remoteCall('power_stats_get_logs', {});
        final list = data['data'] as List<dynamic>? ?? [];
        logs.value = list.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      _logger.error('获取日志失败: $e');
    }
  }

  Future<void> clearLogs() async {
    if (!isLocal) return;
    try {
      rust_api.powerStatsClearLogs();
      logs.clear();
    } catch (e) {
      _logger.error('清除日志失败: $e');
    }
  }

  /// 刷新全部数据
  Future<void> refreshAll() async {
    await Future.wait([refreshStatus(), refreshSummary(), refreshLogs()]);
  }

  // ── 远程节点 API ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _remoteCall(String action, Map<String, dynamic> params) async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/node/call',
      data: {'action': action, 'params': params},
    );
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body['success'] == true && body['data'] is List) {
      return {'data': body['data']};
    }
    throw Exception(body['error']?.toString() ?? '远程调用失败');
  }

  Future<String> _remoteFetchOnce() async {
    final baseUrl = currentNodeBaseUrl;
    if (baseUrl == null) throw StateError('未选择远程节点');
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/node/call',
      data: {'action': 'power_stats_fetch_once', 'params': {}},
    );
    final body = response.data ?? <String, dynamic>{};
    if (body['success'] == true) {
      await refreshStatus();
      await refreshSummary();
      await refreshLogs();
      return '远程抓取完成';
    }
    throw Exception(body['error']?.toString() ?? '远程抓取失败');
  }

  Future<bool> checkNodePowerStatsAvailable(String baseUrl) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/node/call',
        data: {'action': 'power_stats_get_status', 'params': {}},
        options: Options(
          // 能走到这一步说明节点已探到在线（离线的在面板上就被"节点不可达"拦下了），
          // 所以这里慢不等于不支持：原先照搬连通性快速档的 200ms，手机走外网时
          // DNS + 握手轻松超线，节点明明开着电力统计也被报成不支持。
          connectTimeout: NodeSettingsService.probeConfirmTimeout,
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.statusCode == 200 && response.data?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void onClose() {
    if (isLocal) {
      stopPolling();
    }
    super.onClose();
  }
}
