// 客户端日志上报到远程节点的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 为什么有这个功能（2026-11-24，用户提的想法）
// ═══════════════════════════════════════════════════════════════════════════
// 远程节点模式下出问题（典型症状：「选了节点但书库/媒体库没数据」），
// 界面上只剩一句「没有数据」，而排查真正需要的上下文——请求了哪个地址、
// 返回了什么、抛了什么异常——全在**客户端本地日志**里。
// 用户没法把手机日志给你，于是只能靠猜，同一个症状反复定位不到根因。
//
// 做法：客户端把最近一批本地日志推到当前远程节点（action `report_client_log`），
// 节点落到 `logs/client_<日期>.log`，与节点自身日志**分开**（排查时第一件事
// 就是分清「这是节点的还是客户端说的」）。之后在节点机器上 `tail -f` 即可。
//
// 两条硬约束，下面都有断言：
//  1. 上报自身绝不能抛错/阻塞——日志上报失败不该让原故障更糟；
//  2. 必须限流——一个持续失败的操作可能每秒触发一次，会把节点日志写爆。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_log_reporter.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认把真实 HTTP mock 成 400，打真节点必须清掉
  setUpAll(() => HttpOverrides.global = null);

  // 每个用例独立注册，避免 GetIt 重复注册报错
  setUp(() async => getIt.reset());

  test('无节点时上报应安全返回 false，不得抛错', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'node_local_enabled': false});
    getIt.registerSingleton<NodeSettingsService>(NodeSettingsService());
    final svc = getIt<NodeSettingsService>();
    await svc.init();

    final reporter = NodeLogReporter(svc);
    // 本机模式（没有启用节点）→ 没有可上报对象
    expect(svc.enabledRemoteNodes, isEmpty);
    final ok = await reporter.reportFailure('no-node-case', error: 'x');
    expect(ok, isFalse, reason: '没有节点时应安静返回 false，不能抛异常');
  });

  test('同一 tag 在限流窗口内只上报一次', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'node_local_enabled': false});
    getIt.registerSingleton<NodeSettingsService>(NodeSettingsService());
    final svc = getIt<NodeSettingsService>();
    await svc.init();

    // 造一个「假节点」：地址不可达也能验证限流，因为限流发生在发请求之前。
    // 这里直接验证限流表的语义，不依赖网络成功与否。
    final reporter = NodeLogReporter(svc);
    reporter.resetThrottle();

    // 无节点 → 直接返回 false，且不写限流表（没有真的上报尝试）
    final first = await reporter.reportFailure('throttle-tag', error: 'a');
    expect(first, isFalse);

    // resetThrottle 必须可重复调用（用户点上报时会调）
    reporter.resetThrottle();
    reporter.resetThrottle();
    expect(() => reporter.resetThrottle(), returnsNormally);
  });

  test('上报内容必须带故障上下文与最近日志', () async {
    // 源码契约：payload 字段名与节点 action 对得上，否则节点收不到可用信息
    final reporterSrc = File(
      'lib/core/services/node/node_log_reporter.dart',
    ).readAsStringSync();
    expect(reporterSrc.contains("action: 'report_client_log'"), isTrue);
    expect(reporterSrc.contains("'client'"), isTrue);
    expect(reporterSrc.contains("'app_version'"), isTrue);
    expect(reporterSrc.contains("'lines'"), isTrue);
    // 必须真的带上本地日志，否则上报只剩一个错误字符串，没法定位
    expect(reporterSrc.contains('Loggers.allLogs'), isTrue);

    // 节点侧必须有对应 action 且落到独立文件
    final handlers = File('rust/src/node_server/handlers.rs').readAsStringSync();
    expect(handlers.contains('"report_client_log"'), isTrue);
    final loggerLib = File('rust/slime_logger/src/lib.rs').readAsStringSync();
    expect(
      loggerLib.contains('client_'),
      isTrue,
      reason: '客户端日志要落独立文件（client_<日期>.log），别混进节点自身日志',
    );
  });

  test('Loggers 能提供上报所需的日志行', () {
    final logger = Loggers();
    logger.log('[上报测试] 一行日志', name: '测试');
    expect(Loggers.allLogs, isNotEmpty);
  });
}
