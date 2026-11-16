import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;

const Loggers _logger = Loggers(name: '系统指标');

/// 折线图历史点数量（每秒采样 1 次，保留 60 秒）
const int kMetricsHistoryLength = 60;

/// 系统资源监控服务
///
/// 将资源监控数据采集从 Dashboard 页面提升到 Service 层，
/// 即使 Dashboard 页面未打开也持续采集，确保打开时即可看到完整历史曲线。
class SystemMetricsService extends ChangeNotifier {
  Timer? _timer;
  rust_sys.SystemResourceSnapshot? _lastSnapshot;
  final NodeSettingsService _nodeSettingsService = getIt<NodeSettingsService>();

  /// 历史数据缓冲区（CPU%、内存MB、下行kbps、上行kbps、节点请求数/s）
  final List<double> cpuHistory = [];
  final List<double> memHistory = [];
  final List<double> rxHistory = [];
  final List<double> txHistory = [];
  final List<double> reqHistory = [];

  /// 最新一次快照的流量与节点数据
  double _appRxKbps = 0;
  double _appTxKbps = 0;
  bool _isLocalServerRunning = false;
  int _nodeRequestCount = 0;
  int _lastNodeRequestCount = 0;

  /// 是否已初始化（Timer 已启动）
  bool _isRunning = false;

  /// 最后一次采集是否成功
  bool _hasData = false;

  rust_sys.SystemResourceSnapshot? get lastSnapshot => _lastSnapshot;
  double get appRxKbps => _appRxKbps;
  double get appTxKbps => _appTxKbps;
  bool get isLocalServerRunning => _isLocalServerRunning;
  int get nodeRequestCount => _nodeRequestCount;
  bool get hasData => _hasData;

  void _appendHistory(List<double> buf, double value) {
    buf.add(value);
    if (buf.length > kMetricsHistoryLength) buf.removeAt(0);
  }

  /// 启动定时采集（应用启动时调用一次即可）
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_refresh());
    });
  }

  /// 停止定时采集（通常不需要调用，除非应用退出）
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  /// 窗口最小化/隐藏到托盘时暂停采集，回到前台再恢复。
  /// 后台每秒采一次 sysinfo 是纯浪费，也是常驻内存的主要抖动来源。
  void setBackground(bool background) {
    if (background) {
      stop();
    } else {
      start();
    }
  }

  /// 连续采集失败的次数，用于限制错误日志的刷屏。
  int _consecutiveFailures = 0;

  /// 当前数据源标识：空串=本机，否则为节点 ID。
  /// 切换后必须清空曲线，否则会拿上一个源的旧数据继续画。
  String? _sourceKey;

  /// 失败日志的节流间隔：每 30 次连续失败只写一条，避免每秒一条噪声。
  static const int _kFailureLogEvery = 30;

  /// 清空所有指标曲线与快照，供切换数据源时使用。
  void _resetSeries() {
    cpuHistory.clear();
    memHistory.clear();
    rxHistory.clear();
    txHistory.clear();
    reqHistory.clear();
    _lastSnapshot = null;
    _hasData = false;
  }

  /// 远程节点模式：向节点要它自己机器的指标。
  Future<rust_sys.SystemResourceSnapshot> _fetchRemoteSnapshot(
    String nodeId,
  ) async {
    final response = await _nodeSettingsService.callNodeAction(
      nodeId: nodeId,
      action: 'get_system_metrics',
    );
    final raw = response['data'];
    final data = raw is Map ? raw : response;
    double asDouble(String key) => (data[key] as num?)?.toDouble() ?? 0;
    int asInt(String key) => (data[key] as num?)?.toInt() ?? 0;
    return rust_sys.SystemResourceSnapshot(
      cpuUsagePercent: asDouble('cpu_usage_percent'),
      memoryUsedMb: BigInt.from(asInt('memory_used_mb')),
      memoryTotalMb: BigInt.from(asInt('memory_total_mb')),
      rxKbps: asDouble('rx_kbps'),
      txKbps: asDouble('tx_kbps'),
    );
  }

  /// 是否有一轮采集在途：远程模式下每轮是一次 HTTP 往返，
  /// 不能让 1s 定时器把请求叠起来。
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final sourceKey = _nodeSettingsService.activeNodeId.value;
      if (_sourceKey != sourceKey) {
        _sourceKey = sourceKey;
        _resetSeries();
      }
      final remoteNode = _nodeSettingsService.activeNode;
      // 全局远程节点模式下，概览必须显示节点机器的资源，而不是本机进程的
      final next = remoteNode == null
          ? rust_sys.getSystemResourceSnapshot()
          : await _fetchRemoteSnapshot(remoteNode.id);
      _nodeSettingsService.syncTrafficDisplayNow();
      final rxKbps = remoteNode == null
          ? _nodeSettingsService.appRxKbps.value
          : next.rxKbps;
      final txKbps = remoteNode == null
          ? _nodeSettingsService.appTxKbps.value
          : next.txKbps;
      final reqCount = _nodeSettingsService.nodeRequestCount.value;
      final reqDelta = (reqCount - _lastNodeRequestCount).clamp(0, 999999).toDouble();

      _lastSnapshot = next;
      _appRxKbps = rxKbps;
      _appTxKbps = txKbps;
      _lastNodeRequestCount = reqCount;
      _isLocalServerRunning = _nodeSettingsService.isLocalServerRunning;
      _nodeRequestCount = reqCount;
      _hasData = true;

      _appendHistory(cpuHistory, next.cpuUsagePercent);
      _appendHistory(memHistory, next.memoryUsedMb.toDouble());
      _appendHistory(rxHistory, rxKbps);
      _appendHistory(txHistory, txKbps);
      _appendHistory(reqHistory, reqDelta);
      // 采集成功：清零失败计数
      _consecutiveFailures = 0;
      // 通知订阅者（Dashboard 指标区）指标已更新，让 UI 按需重建
      notifyListeners();
    } catch (e) {
      // 采集失败不能再静默吞掉：上一次“看板停更”就是被 catch (_) {} 掩盖的。
      // 用节流计数记录，既不刷屏也留出可诊断的痕迹。
      _consecutiveFailures++;
      if (_consecutiveFailures == 1 || _consecutiveFailures % _kFailureLogEvery == 0) {
        _logger.error('系统资源快照采集失败', error: e);
      }
    } finally {
      _refreshing = false;
    }
  }
}
