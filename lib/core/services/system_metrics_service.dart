import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/src/rust/api/system_metrics.dart' as rust_sys;

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

  Future<void> _refresh() async {
    try {
      // 系统资源快照（sysinfo 的 CPU/内存/进程扫描）是较重的同步 FFI，
      // 直接放在主线程会在每周期造成一段阻塞，撞上 VS Code DDS 的 VM Service
      // 心跳导致“Lost connection to device”。改到后台 isolate 执行，不阻塞
      // 主线程 Dart 事件循环。生成的 SystemResourceSnapshot 是普通数据类，
      // 可跨 isolate 传递。
      final next = await Isolate.run(rust_sys.getSystemResourceSnapshot);
      _nodeSettingsService.syncTrafficDisplayNow();
      final rxKbps = _nodeSettingsService.appRxKbps.value;
      final txKbps = _nodeSettingsService.appTxKbps.value;
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
      // 通知订阅者（Dashboard 指标区）指标已更新，让 UI 按需重建
      notifyListeners();
    } catch (_) {}
  }
}
