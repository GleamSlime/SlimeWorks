import 'dart:async';

import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/core/services/power_stats_service.dart';

/// 电力统计时间范围选项
class PowerStatsRange {
  final String key;
  final String label;
  const PowerStatsRange(this.key, this.label);

  static const List<PowerStatsRange> all = [
    PowerStatsRange('hour', '小时'),
    PowerStatsRange('1day', '1天'),
    PowerStatsRange('7days', '7天'),
    PowerStatsRange('15days', '15天'),
    PowerStatsRange('30days', '30天'),
  ];
}

/// 电力统计图表数据桶
class PowerStatBucket {
  final String label;
  final int timestamp;
  final double consumptionKwh;
  final double costYuan;
  final double balanceYuan;
  final double balanceKwh;

  const PowerStatBucket({
    required this.label,
    required this.timestamp,
    required this.consumptionKwh,
    required this.costYuan,
    required this.balanceYuan,
    required this.balanceKwh,
  });

  factory PowerStatBucket.fromMap(Map<String, dynamic> m) => PowerStatBucket(
    label: m['label'] as String? ?? '',
    timestamp: (m['timestamp'] as num?)?.toInt() ?? 0,
    consumptionKwh: (m['consumption_kwh'] as num?)?.toDouble() ?? 0.0,
    costYuan: (m['cost_yuan'] as num?)?.toDouble() ?? 0.0,
    balanceYuan: (m['balance_yuan'] as num?)?.toDouble() ?? 0.0,
    balanceKwh: (m['balance_kwh'] as num?)?.toDouble() ?? 0.0,
  );
}

/// 图表展示维度
enum PowerChartMetric { consumption, balance, cost }

class PowerStatsViewModel extends GetxController {
  final PowerStatsService _service = GetIt.instance.get<PowerStatsService>();

  // 配置
  final RxString meterId = ''.obs;
  final RxBool isEnabled = false.obs;
  final RxInt intervalSecs = 60.obs;
  final RxString currentNodeId = ''.obs;

  // 运行时状态
  final RxString meterName = ''.obs;
  final RxDouble currentKwh = 0.0.obs;
  final RxDouble currentYuan = 0.0.obs;
  final RxDouble price = 1.0.obs;
  final RxString lastFetch = ''.obs;
  final RxString lastResult = ''.obs;
  final RxInt sampleCount = 0.obs;
  final RxBool isPolling = false.obs;

  // 汇总数据
  final RxMap<String, dynamic> summary = <String, dynamic>{}.obs;

  // 聚合数据
  final RxList<PowerStatBucket> buckets = <PowerStatBucket>[].obs;
  final RxDouble totalConsumption = 0.0.obs;
  final RxDouble totalCost = 0.0.obs;
  final RxDouble avgBalance = 0.0.obs;
  final RxInt aggregatedSampleCount = 0.obs;

  // 日志
  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;

  // 页面状态
  final RxString selectedRange = '1day'.obs;
  final Rx<PowerChartMetric> selectedMetric = PowerChartMetric.consumption.obs;
  final RxBool isFetching = false.obs;
  final RxBool isConfigLoaded = false.obs;

  bool get isLocal => currentNodeId.value.isEmpty;

  // 服务订阅
  late final StreamSubscription _meterIdSub;
  late final StreamSubscription _enabledSub;
  late final StreamSubscription _intervalSub;
  late final StreamSubscription _selectedNodeSub;
  late final StreamSubscription _meterNameSub;
  late final StreamSubscription _currentKwhSub;
  late final StreamSubscription _currentYuanSub;
  late final StreamSubscription _priceSub;
  late final StreamSubscription _lastFetchSub;
  late final StreamSubscription _lastResultSub;
  late final StreamSubscription _sampleCountSub;
  late final StreamSubscription _isPollingSub;
  late final StreamSubscription _summarySub;
  late final StreamSubscription _logsSub;

  Timer? _autoRefreshTimer;

  @override
  void onInit() {
    super.onInit();
    _service.ensureInitialized().then((_) {
      _bindService();
      _loadFromService();
      currentNodeId.value = _service.selectedNodeId.value;
      isConfigLoaded.value = true;
      // 首次加载聚合数据
      refreshAggregated();
      // 启动自动刷新定时器（30秒刷新状态）
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!isFetching.value) refreshStatus();
      });
    });
  }

  void _bindService() {
    _meterIdSub = _service.meterId.listen((v) => meterId.value = v);
    _enabledSub = _service.enabled.listen((v) => isEnabled.value = v);
    _intervalSub = _service.intervalSecs.listen((v) => intervalSecs.value = v);
    _selectedNodeSub = _service.selectedNodeId.listen((v) => currentNodeId.value = v);
    _meterNameSub = _service.meterName.listen((v) => meterName.value = v);
    _currentKwhSub = _service.currentKwh.listen((v) => currentKwh.value = v);
    _currentYuanSub = _service.currentYuan.listen((v) => currentYuan.value = v);
    _priceSub = _service.price.listen((v) => price.value = v);
    _lastFetchSub = _service.lastFetch.listen((v) => lastFetch.value = v);
    _lastResultSub = _service.lastResult.listen((v) => lastResult.value = v);
    _sampleCountSub = _service.sampleCount.listen((v) => sampleCount.value = v);
    _isPollingSub = _service.isPolling.listen((v) => isPolling.value = v);
    _summarySub = _service.summary.listen((v) => summary.value = v);
    _logsSub = _service.logs.listen((v) => logs.value = v);
  }

  void _loadFromService() {
    meterId.value = _service.meterId.value;
    isEnabled.value = _service.enabled.value;
    intervalSecs.value = _service.intervalSecs.value;
    meterName.value = _service.meterName.value;
    currentKwh.value = _service.currentKwh.value;
    currentYuan.value = _service.currentYuan.value;
    price.value = _service.price.value;
    lastFetch.value = _service.lastFetch.value;
    lastResult.value = _service.lastResult.value;
    sampleCount.value = _service.sampleCount.value;
    isPolling.value = _service.isPolling.value;
    summary.value = Map<String, dynamic>.from(_service.summary);
    logs.value = List<Map<String, dynamic>>.from(_service.logs);
  }

  /// 切换节点
  Future<void> switchNode(String nodeId) async {
    currentNodeId.value = nodeId;
    await _service.setSelectedNodeId(nodeId);
    // 清空缓存状态
    meterName.value = '';
    currentKwh.value = 0.0;
    currentYuan.value = 0.0;
    lastFetch.value = '';
    lastResult.value = '';
    sampleCount.value = 0;
    buckets.clear();
    summary.clear();
    logs.clear();
    await refreshAll();
  }

  /// 切换时间范围
  Future<void> setRange(String range) async {
    selectedRange.value = range;
    await refreshAggregated();
  }

  /// 切换图表维度
  void setMetric(PowerChartMetric metric) {
    selectedMetric.value = metric;
  }

  /// 刷新全部数据
  Future<void> refreshAll() async {
    await _service.ensureInitialized();
    await Future.wait([refreshStatus(), refreshSummary(), refreshLogs(), refreshAggregated()]);
  }

  Future<void> refreshStatus() async {
    if (!_service.isInitialized) return;
    try {
      await _service.refreshStatus();
    } catch (_) {}
  }

  Future<void> refreshSummary() async {
    if (!_service.isInitialized) return;
    try {
      await _service.refreshSummary();
      summary.value = Map<String, dynamic>.from(_service.summary);
    } catch (_) {}
  }

  Future<void> refreshAggregated() async {
    if (!_service.isInitialized) return;
    try {
      await _service.refreshAggregated(selectedRange.value);
      final data = _service.aggregated;
      final list = data['buckets'] as List<dynamic>? ?? [];
      buckets.value = list.map((e) => PowerStatBucket.fromMap(e as Map<String, dynamic>)).toList();
      totalConsumption.value = (data['total_consumption'] as num?)?.toDouble() ?? 0.0;
      totalCost.value = (data['total_cost'] as num?)?.toDouble() ?? 0.0;
      avgBalance.value = (data['avg_balance'] as num?)?.toDouble() ?? 0.0;
      aggregatedSampleCount.value = (data['sample_count'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> refreshLogs() async {
    if (!_service.isInitialized) return;
    try {
      await _service.refreshLogs();
      logs.value = List<Map<String, dynamic>>.from(_service.logs);
    } catch (_) {}
  }

  /// 手动抓取一次
  Future<String> fetchOnce() async {
    isFetching.value = true;
    try {
      final result = await _service.fetchOnce();
      await refreshAll();
      return result;
    } finally {
      isFetching.value = false;
    }
  }

  /// 切换启用状态
  Future<void> toggleEnabled(bool value) async {
    if (!isLocal) return;
    await _service.setEnabled(value);
  }

  /// 保存表号
  Future<void> saveMeterId(String value) async {
    if (!isLocal) return;
    await _service.setMeterId(value.trim());
  }

  /// 保存轮询间隔
  Future<void> saveIntervalSecs(int value) async {
    if (!isLocal) return;
    await _service.setIntervalSecs(value);
  }

  /// 启动定时轮询
  Future<void> startPolling() async {
    if (!isLocal) return;
    await _service.startPolling();
  }

  /// 停止定时轮询
  Future<void> stopPolling() async {
    if (!isLocal) return;
    await _service.stopPolling();
  }

  /// 清空日志
  Future<void> clearLogs() async {
    if (!isLocal) return;
    await _service.clearLogs();
  }

  /// 检查节点是否支持电力统计
  Future<bool> checkNodePowerStatsAvailable(String baseUrl) async {
    return _service.checkNodePowerStatsAvailable(baseUrl);
  }

  /// 获取汇总中的耗电量字段
  double getSummaryConsumption(String key) {
    return (summary[key] as num?)?.toDouble() ?? 0.0;
  }

  /// 获取汇总中的电费字段
  double getSummaryCost(String key) {
    return (summary[key] as num?)?.toDouble() ?? 0.0;
  }

  @override
  void onClose() {
    _autoRefreshTimer?.cancel();
    _meterIdSub.cancel();
    _enabledSub.cancel();
    _intervalSub.cancel();
    _selectedNodeSub.cancel();
    _meterNameSub.cancel();
    _currentKwhSub.cancel();
    _currentYuanSub.cancel();
    _priceSub.cancel();
    _lastFetchSub.cancel();
    _lastResultSub.cancel();
    _sampleCountSub.cancel();
    _isPollingSub.cancel();
    _summarySub.cancel();
    _logsSub.cancel();
    super.onClose();
  }
}
