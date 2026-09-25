import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/power_stats_service.dart';

import 'helpers/fake_node_server.dart';

/// 说明（可达性结论，对应补测任务第 2/3/5 项）：
/// - PowerStatsService._computeDbPath/_buildConfigJson、AliyunDdnsService._buildConfigJson
///   均为私有且产物只流向 FFI 调用（Rust 侧接收），Dart 侧不可观测 → 不直测；
///   配置 JSON 的字段形态经公开的 PowerStatsConfig（_buildConfigJson 的内部依赖）覆盖；
/// - fetchOnce/refresh* 的本地分支直触 FFI 不测；远程分支经假节点夹具覆盖；
/// - updateConfig 的「合并语义」发生在 Rust 侧（Dart 只发送整包 configJson），
///   Dart 可达部分仅为「不抛异常 + prefs 落盘」，已在用例中锁定；
/// - AppUpdateService._parseAppcast 不可达：_fetchAppcast 使用私有 Dio 与写死的
///   static const _feedUrl，无 HTTP 注入口；且 flutter test 处于 kDebugMode，
///   checkForUpdates/loadPrefs 在入口即早退。本文件只测 Debug 守卫行为本身，
///   解析逻辑建议重构（注入 Dio/BaseOptions 或顶层化）后再补测。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TestWidgetsFlutterBinding 默认会给所有 HttpClient 装上 mock（一律回 400），
  // 这里参照 node_call_integration_test 的做法解除拦截，让假节点（环回端口）可被真实访问。
  setUpAll(() {
    HttpOverrides.global = null;
  });

  // ── PowerStatsConfig（_buildConfigJson 的纯 Dart 内核） ─────────────────

  group('PowerStatsConfig 编解码', () {
    test('toMap 使用 snake_case 键且与 fromMap 精确往返', () {
      const PowerStatsConfig src = PowerStatsConfig(
        meterId: '_meter-123',
        enabled: true,
        intervalSecs: 45,
        persist: false,
        dbPath: '/tmp/x/power.db',
      );
      final Map<String, dynamic> map = src.toMap();
      expect(map.keys.toSet(), <String>{
        'meter_id',
        'enabled',
        'interval_secs',
        'persist',
        'db_path',
      });
      expect(PowerStatsConfig.fromMap(map), isA<PowerStatsConfig>());
      expect(PowerStatsConfig.fromMap(map).toMap(), map);
    });

    test('fromMap 缺字段/类型不符时回落默认值', () {
      final PowerStatsConfig d = PowerStatsConfig.fromMap(<String, dynamic>{});
      expect(d.meterId, '');
      expect(d.enabled, isFalse);
      expect(d.intervalSecs, 60);
      expect(d.persist, isTrue);
      expect(d.dbPath, '');
    });

    test('copyWith 只覆盖显式传入字段', () {
      const PowerStatsConfig base = PowerStatsConfig(meterId: 'm', intervalSecs: 10);
      final PowerStatsConfig next = base.copyWith(enabled: true, dbPath: '/d');
      expect(next.meterId, 'm');
      expect(next.intervalSecs, 10);
      expect(next.enabled, isTrue);
      expect(next.dbPath, '/d');
    });

    test('toJson 为合法 JSON 文本', () {
      final Map<String, dynamic> decoded =
          jsonDecode(const PowerStatsConfig(meterId: '中/文').toJson()) as Map<String, dynamic>;
      expect(decoded['meter_id'], '中/文');
    });
  });

  // ── PowerStatsService prefs 持久化（经 ensureInitialized + set* 公开入口） ──

  group('PowerStatsService 偏好持久化', () {
    test('ensureInitialized 读取种子值到响应式字段', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'power_stats_meter_id': '电表A',
        'power_stats_enabled': true,
        'power_stats_interval_secs': 90,
        'power_stats_selected_node_id': 'node-9',
      });
      final PowerStatsService svc = PowerStatsService();
      await svc.ensureInitialized();

      expect(svc.isInitialized, isTrue);
      expect(svc.meterId.value, '电表A');
      expect(svc.enabled.value, isTrue);
      expect(svc.intervalSecs.value, 90);
      expect(svc.selectedNodeId.value, 'node-9');
      expect(svc.isLocal, isFalse);
      svc.onClose();
    });

    test('空 prefs 时读取默认值（""/false/60/""）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PowerStatsService svc = PowerStatsService();
      await svc.ensureInitialized();
      expect(svc.meterId.value, '');
      expect(svc.enabled.value, isFalse);
      expect(svc.intervalSecs.value, 60);
      expect(svc.selectedNodeId.value, '');
      expect(svc.isLocal, isTrue);
      svc.onClose();
    });

    test('4 个 set* 写入后重建实例可无损读回（持久化往返）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PowerStatsService svc = PowerStatsService();
      await svc.ensureInitialized(); // 只有初始化后 _prefs 才非空，setter 才会落盘

      await svc.setMeterId('电表B');
      await svc.setIntervalSecs(15);
      await svc.setEnabled(false); // false：只触发 stopPolling（FFI 异常被服务内部吞掉）
      await svc.setSelectedNodeId('');

      // 原始 prefs 键校验（防止字段间互相覆盖）
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('power_stats_meter_id'), '电表B');
      expect(prefs.getInt('power_stats_interval_secs'), 15);
      expect(prefs.getBool('power_stats_enabled'), isFalse);

      final PowerStatsService reloaded = PowerStatsService();
      await reloaded.ensureInitialized();
      expect(reloaded.meterId.value, '电表B');
      expect(reloaded.intervalSecs.value, 15);
      expect(reloaded.enabled.value, isFalse);
      svc.onClose();
      reloaded.onClose();
    });

    test('setEnabled(true) 本地分支：字段与 prefs 更新，轮询启动失败不留脏状态', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PowerStatsService svc = PowerStatsService();
      await svc.ensureInitialized();
      await svc.setEnabled(true); // 触发 FFI startPolling → 测试环境抛错被内部捕获
      expect(svc.enabled.value, isTrue);
      expect(svc.isPolling.value, isFalse); // FFI 失败时不应谎报在轮询
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('power_stats_enabled'), isTrue);
      svc.onClose();
    });

    test('ensureInitialized 幂等：并发双调用只初始化一次，后续不重读新写入的 prefs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final PowerStatsService svc = PowerStatsService();
      await Future.wait(<Future<void>>[svc.ensureInitialized(), svc.ensureInitialized()]);
      expect(svc.isInitialized, isTrue);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('power_stats_meter_id', '晚到值');
      await svc.ensureInitialized(); // 已初始化 → 直接返回，不重读
      expect(svc.meterId.value, '');
      svc.onClose();
    });
  });

  // ── checkNodePowerStatsAvailable（复用假节点夹具） ──────────────────────

  group('PowerStatsService.checkNodePowerStatsAvailable', () {
    late FakeNodeServer server;
    late PowerStatsService svc;
    late int deadPort;

    setUp(() async {
      server = await FakeNodeServer.start();
      deadPort = await freeLoopbackPort();
      svc = PowerStatsService();
    });

    tearDown(() async {
      await server.dispose();
      svc.onClose();
    });

    test('节点回 {success:true} 判为可用，且请求打 /node/call + 正确 action', () async {
      expect(await svc.checkNodePowerStatsAvailable(server.baseUrl), isTrue);
      final FakeNodeRequest req = server.lastRequest;
      expect(req.path, '/node/call');
      expect(req.action, 'power_stats_get_status');
      expect(req.params, isEmpty);
    });

    test('节点回 success:false 判为不可用', () async {
      server.responder = (FakeNodeRequest r) => FakeNodeReply.businessError('未启用电力统计');
      expect(await svc.checkNodePowerStatsAvailable(server.baseUrl), isFalse);
    });

    test('HTTP 500 判为不可用（Dio 状态码校验抛错被捕获）', () async {
      server.responder = (FakeNodeRequest r) =>
          FakeNodeReply(statusCode: 500, json: <String, dynamic>{'error': 'boom'});
      expect(await svc.checkNodePowerStatsAvailable(server.baseUrl), isFalse);
    });

    test('无人监听的端口判为不可用且不抛', () async {
      expect(await svc.checkNodePowerStatsAvailable('http://127.0.0.1:$deadPort'), isFalse);
    });

    test('空 baseUrl 等异常输入不抛（返回 false）', () async {
      expect(await svc.checkNodePowerStatsAvailable('不是URL'), isFalse);
    });
  });

  // ── 远程节点数据链路（refresh* / fetchOnce 的 remote 分支） ─────────────

  group('PowerStatsService 远程节点调用', () {
    late FakeNodeServer server;
    late PowerStatsService svc;

    setUp(() async {
      server = await FakeNodeServer.start();
      // currentNodeBaseUrl 经 GetIt 查 NodeSettingsService，节点地址指向假服务器
      final NodeSettingsService nodeService = NodeSettingsService();
      nodeService.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '假节点', apiBaseUrl: server.baseUrl, authCode: ''),
      );
      getIt.registerSingleton<NodeSettingsService>(nodeService);

      svc = PowerStatsService();
      svc.selectedNodeId.value = 'n1'; // 非本地 → 走远程分支，绕开全部 FFI
    });

    tearDown(() async {
      await server.dispose();
      svc.onClose();
      getIt.unregister<NodeSettingsService>();
    });

    test('refreshStatus 远程：解析 data 各字段并写入响应式状态', () async {
      server.responder = (FakeNodeRequest r) => FakeNodeReply.successData(<String, dynamic>{
        'meter_name': '总表',
        'current_kwh': 1234.5,
        'current_yuan': 617.25,
        'price': 0.5,
        'last_fetch': '2026-09-25T10:00:00Z',
        'last_result': 'ok',
        'sample_count': 42,
      });
      await svc.refreshStatus();
      expect(svc.meterName.value, '总表');
      expect(svc.currentKwh.value, 1234.5);
      expect(svc.price.value, 0.5);
      expect(svc.sampleCount.value, 42);
    });

    test('refreshLogs 远程：data 为 List 时被包成 {data: [...]} 再映射', () async {
      server.responder = (FakeNodeRequest r) => FakeNodeReply.successData(<Map<String, dynamic>>[
        <String, dynamic>{'ts': 'a', 'kwh': 1},
        <String, dynamic>{'ts': 'b', 'kwh': 2},
      ]);
      await svc.refreshLogs();
      expect(svc.logs.length, 2);
      expect(svc.logs.first['ts'], 'a');
    });

    test('refreshAggregated 远程：range 参数原样透传到 params', () async {
      server.responder = (FakeNodeRequest r) => FakeNodeReply.successData(<String, dynamic>{
        'labels': <String>['d1'],
      });
      await svc.refreshAggregated('day');
      expect(server.lastRequest.action, 'power_stats_get_aggregated');
      expect(server.lastRequest.params['range'], 'day');
      expect(svc.aggregated['labels'], <String>['d1']);
    });

    test('fetchOnce 远程成功：依次调用抓取+状态+汇总+日志，返回固定文案', () async {
      server.responder = (FakeNodeRequest r) {
        switch (r.action) {
          case 'power_stats_fetch_once':
            return FakeNodeReply.successData(<String, dynamic>{'result': 'done'});
          case 'power_stats_get_logs':
            return FakeNodeReply.successData(<Map<String, dynamic>>[]);
          default:
            return FakeNodeReply.successData(<String, dynamic>{'meter_name': 'ok'});
        }
      };
      final String msg = await svc.fetchOnce();
      expect(msg, '远程抓取完成');
      expect(server.requestCount(action: 'power_stats_fetch_once'), 1);
      expect(server.requestCount(action: 'power_stats_get_status'), 1);
      expect(server.requestCount(action: 'power_stats_get_summary'), 1);
      expect(server.requestCount(action: 'power_stats_get_logs'), 1);
    });

    test('fetchOnce 远程业务失败：返回「抓取失败」文案并写入 lastResult', () async {
      server.responder = (FakeNodeRequest r) => FakeNodeReply.businessError('电表离线');
      final String msg = await svc.fetchOnce();
      expect(msg, contains('抓取失败'));
      expect(msg, contains('电表离线'));
      expect(svc.lastResult.value, contains('电表离线'));
    });

    test('未选择节点（nodeId 不存在）：refreshStatus 静默捕获，不改写字段', () async {
      svc.selectedNodeId.value = 'ghost';
      await svc.refreshStatus(); // _remoteCall 抛 StateError → 内部 catch
      expect(svc.meterName.value, '');
    });
  });

  // ── AliyunDdnsService 偏好与监控域名持久化 ──────────────────────────────

  group('WatchDomain 模型', () {
    test('toMap/fromMap 往返 + 缺字段默认值（rr=@、类型 A）', () {
      final WatchDomain d = WatchDomain(domainName: 'abc.com', rr: 'home');
      expect(d.toMap(), <String, dynamic>{
        'domain_name': 'abc.com',
        'rr': 'home',
        'record_type': 'A',
      });
      final WatchDomain back = WatchDomain.fromMap(<String, dynamic>{});
      expect(back.domainName, '');
      expect(back.rr, '@');
      expect(back.recordType, 'A');
      expect(WatchDomain.fromMap(d.toMap()).fullDomain, 'home.abc.com');
    });

    test('rr 为 @ 时 fullDomain 即裸域名', () {
      expect(WatchDomain(domainName: 'abc.com', rr: '@').fullDomain, 'abc.com');
    });
  });

  group('AliyunDdnsService 持久化（set* + 重建实例 init 往返）', () {
    test('5 个 set* 写入后新实例读回一致（enabled=false，不启动定时器）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized(); // 填充内部 _prefs，setter 才能落盘

      await svc.setAccessKeyId('LTAI-test-id');
      await svc.setAccessKeySecret('secret-test');
      await svc.setIntervalSecs(120);
      await svc.setSelectedNodeId('node-7');
      await svc.setEnabled(false); // false → stopCheckTimer，无定时器残留

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('aliyun_access_key_id'), 'LTAI-test-id');
      expect(prefs.getString('aliyun_access_key_secret'), 'secret-test');
      expect(prefs.getInt('aliyun_interval_secs'), 120);
      expect(prefs.getString('aliyun_selected_node_id'), 'node-7');
      expect(prefs.getBool('aliyun_ddns_enabled'), isFalse);

      final AliyunDdnsService reloaded = AliyunDdnsService();
      await reloaded.ensureInitialized();
      expect(reloaded.accessKeyId.value, 'LTAI-test-id');
      expect(reloaded.accessKeySecret.value, 'secret-test');
      expect(reloaded.intervalSecs.value, 120);
      expect(reloaded.selectedNodeId.value, 'node-7');
      expect(reloaded.enabled.value, isFalse);
      svc.onClose();
      reloaded.onClose();
    });

    test('ensureInitialized 解析种子 watch_domains JSON 列表', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aliyun_watch_domains': jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'domain_name': 'a.com', 'rr': '@'},
          <String, dynamic>{'domain_name': 'b.com', 'rr': 'ddns', 'record_type': 'AAAA'},
        ]),
      });
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();
      expect(svc.watchDomains.length, 2);
      expect(svc.watchDomains[1].fullDomain, 'ddns.b.com');
      expect(svc.watchDomains[1].recordType, 'AAAA');
      svc.onClose();
    });

    test('watch_domains 损坏 JSON：清空列表且 init 不抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aliyun_watch_domains': '{不是列表!!!',
      });
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();
      expect(svc.watchDomains, isEmpty);
      svc.onClose();
    });

    test('addWatchDomain/removeWatchDomain：增删顺序正确且持久化可往返', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();

      await svc.addWatchDomain(WatchDomain(domainName: 'x.com', rr: '@'));
      await svc.addWatchDomain(WatchDomain(domainName: 'y.com', rr: 'home'));
      expect(svc.watchDomains.map((WatchDomain d) => d.domainName), <String>['x.com', 'y.com']);

      await svc.removeWatchDomain(0);
      expect(svc.watchDomains.map((WatchDomain d) => d.domainName), <String>['y.com']);

      // addWatchDomain/removeWatchDomain 内部先直调 _savePrefs，落盘不依赖 FFI
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<dynamic> saved =
          jsonDecode(prefs.getString('aliyun_watch_domains')!) as List<dynamic>;
      expect(saved.single['domain_name'], 'y.com');

      final AliyunDdnsService reloaded = AliyunDdnsService();
      await reloaded.ensureInitialized();
      expect(reloaded.watchDomains.single.fullDomain, 'home.y.com');
      svc.onClose();
      reloaded.onClose();
    });

    test('removeWatchDomain 越界索引抛 RangeError', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();
      expect(() => svc.removeWatchDomain(3), throwsRangeError);
      svc.onClose();
    });
  });

  group('AliyunDdnsService 定时器管理（只测幂等与状态，不真等定时器）', () {
    tearDown(() {
      // 兜底：任何用例若启动了 periodic 定时器都应自行 stopCheckTimer，
      // 这里不再跨用例持有服务实例
    });

    test('setEnabled(true) 启动定时器后 setEnabled(false) 干净停止，无异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aliyun_ddns_enabled': false,
        'aliyun_interval_secs': 3600, // 周期远大于测试时长，即使触发也无外部请求
      });
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();

      await svc.setEnabled(true); // startCheckTimer：立即 checkAndUpdate(FFI 被内部捕获) + 建定时器
      expect(svc.enabled.value, isTrue);
      await svc.setEnabled(false); // stopCheckTimer
      expect(svc.enabled.value, isFalse);

      svc.stopCheckTimer(); // 幂等：重复停止不抛
      svc.onClose();
    });

    test('ensureInitialized 时 enabled=true 且已配置 AK：自动启动定时器后可手动停', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'aliyun_ddns_enabled': true,
        'aliyun_access_key_id': 'LTAI-auto',
        'aliyun_interval_secs': 3600,
      });
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();
      expect(svc.isInitialized, isTrue);
      expect(svc.enabled.value, isTrue);
      svc.stopCheckTimer(); // 用例结束前必须取消，避免 pending timer
      svc.onClose();
    });

    test('enabled=false 时 startCheckTimer 只清理不启动；setIntervalSecs 不重建定时器', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AliyunDdnsService svc = AliyunDdnsService();
      await svc.ensureInitialized();
      await svc.setEnabled(false);

      svc.startCheckTimer(); // 未启用 → 立即 return，不建定时器
      await svc.setIntervalSecs(123); // enabled=false → 不触发 _restartTimer
      expect(svc.intervalSecs.value, 123);
      svc.stopCheckTimer();
      svc.onClose();
    });
  });

  // ── AppUpdateService：Debug 守卫（_parseAppcast 不可注入，见文件头说明） ──

  group('AppUpdateService flutter test(Debug) 下的早退守卫', () {
    test('checkForUpdates 在 Debug 模式直接返回：不检查、不产生更新信息', () async {
      final AppUpdateService svc = AppUpdateService();
      await svc.checkForUpdates();
      expect(svc.isChecking.value, isFalse);
      expect(svc.updateInfo.value, isNull);
      expect(svc.lastCheckHadUpdate, isFalse);
    });

    test('loadPrefs 在 Debug 模式为 no-op：即使 prefs 有值也不读取', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auto_update_enabled': true,
      });
      final AppUpdateService svc = AppUpdateService();
      await svc.loadPrefs();
      expect(svc.autoUpdateEnabled.value, isFalse);
    });
  });
}
