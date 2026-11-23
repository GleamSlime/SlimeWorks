import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';

/// 把客户端本地日志上报到远程节点，让远程问题在节点侧可查。
///
/// ═══════════════════════════════════════════════════════════════════════════
/// 为什么要有这个
/// ═══════════════════════════════════════════════════════════════════════════
/// 移动端出问题时，界面上往往只剩「没有数据」，而排查真正需要的上下文
/// （请求了哪个地址、返回了什么、有没有异常）全在**客户端本地日志**里。
/// 用户没法把那台手机的日志给你，于是只能靠猜——「书库空的」这个症状
/// 就因此反复定位不到根因。
///
/// 这个服务在出错时主动把最近一批日志推给当前远程节点，节点落到
/// `logs/client_<日期>.log`。之后只要在节点机器上 `tail -f` 就能看到
/// 客户端当时到底发生了什么。
///
/// ★ 上报自身绝不能抛错/阻塞界面：日志上报失败不应该让原本的故障更糟。
/// ★ 要限流：一个持续失败的操作可能每秒触发一次上报，把节点日志写爆。
/// ═══════════════════════════════════════════════════════════════════════════
class NodeLogReporter {
  final NodeSettingsService _nodeSettings;

  NodeLogReporter(this._nodeSettings);

  /// 同一类错误在这段时间内只上报一次（避免死循环式刷屏）
  static const Duration _throttleWindow = Duration(minutes: 2);

  /// 单次最多上报多少行（节点侧也有上限，这里先截断省带宽）
  static const int _maxLinesPerReport = 300;

  final Map<String, DateTime> _lastReportAt = <String, DateTime>{};
  Future<void>? _inFlight;

  /// 是否启用（默认开启；调试时可关掉避免污染节点日志）
  bool enabled = true;

  /// 上报一次故障现场。
  ///
  /// [tag] 用来做限流键，同类问题（如「书库取数失败」）走同一个 tag。
  /// [extra] 是额外上下文，会拼成一行附在日志前面。
  ///
  /// 返回是否真的发出去了（被限流/无节点/上报失败都返回 false）。
  /// 调用方**不需要** await 它，失败也不该影响原流程。
  Future<bool> reportFailure(
    String tag, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    if (!enabled) return false;

    // 限流：同一 tag 在窗口内只报一次
    final now = DateTime.now();
    final last = _lastReportAt[tag];
    if (last != null && now.difference(last) < _throttleWindow) {
      return false;
    }
    _lastReportAt[tag] = now;

    // 已有一次在飞就跳过（网络差时别堆请求）
    if (_inFlight != null) return false;

    final node = _nodeSettings.activeNode ?? _nodeSettings.enabledRemoteNodes.firstOrNull;
    if (node == null) return false; // 本机模式没有节点可报

    final lines = <String>[
      '=== 客户端故障上报 [$tag] ===',
      if (extra.isNotEmpty) '上下文: ${extra.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
      if (error != null) '错误: $error',
      if (stackTrace != null)
        // 栈只留前若干帧，太长会把节点日志写爆
        '栈: ${stackTrace.toString().split('\n').take(12).join(' | ')}',
      '--- 最近本地日志（最多 $_maxLinesPerReport 行）---',
      ..._recentLogs(),
    ];

    final future = _send(node, lines);
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  /// 清空限流记录。
  ///
  /// 用户主动点「上报」时用：那是明确意图，不该被出错时的自动限流挡掉。
  void resetThrottle() => _lastReportAt.clear();

  /// 取最近一批本地日志（越近越有价值，取尾部）。
  List<String> _recentLogs() {
    final all = Loggers.allLogs;
    if (all.length <= _maxLinesPerReport) return all.toList();
    return all.sublist(all.length - _maxLinesPerReport);
  }

  Future<bool> _send(NodeEndpoint node, List<String> lines) async {
    try {
      await _nodeSettings.callNodeAction(
        nodeId: node.id,
        action: 'report_client_log',
        params: <String, dynamic>{
          'client': _clientTag(),
          'app_version': _appVersion(),
          'lines': lines,
        },
      );
      return true;
    } catch (e) {
      // 上报失败只能本地记一笔，绝不能再往外抛（否则会触发更多上报）
      debugPrint('客户端日志上报失败: $e');
      return false;
    }
  }

  String _clientTag() {
    if (kIsWeb) return 'web';
    // 不引 dart:io 的 Platform，避免 web 端编译问题
    final os = defaultTargetPlatform;
    switch (os) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _appVersion() {
    // 版本号由调用方在 main() 里注入更准；这里给个保守默认值
    return _versionOverride ?? 'unknown';
  }

  /// main() 可注入真实版本号
  String? _versionOverride;
  set appVersion(String? v) => _versionOverride = v;
}
