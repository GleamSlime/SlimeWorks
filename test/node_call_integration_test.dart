import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

import 'helpers/fake_node_server.dart';

/// prefs 键名（与 NodeSettingsService 的私有常量保持一致）
const String _kLocalEnabledKey = 'node_local_enabled';

/// 假节点上 `/node/call` 的路径
const String _kCallPath = '/node/call';

/// 直接 new 出服务并只初始化到"可发 HTTP"的程度：
/// init() 负责挂 X-SW-Auth 拦截器 + 读 prefs，本机节点保持关闭以避开 Rust FFI。
Future<NodeSettingsService> createService({Map<String, Object> initialPrefs = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _kLocalEnabledKey: false,
    ...initialPrefs,
  });
  final service = NodeSettingsService();
  await service.init();
  // init() 会在 200ms 后触发一次后台连通性检测；先让它跑完（此刻 remoteNodes 仍为空），
  // 避免后台 ping 混进后面的请求计数。
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return service;
}

/// 把一个节点塞进服务内存列表（不走 addRemoteNode，避免其自带的连通性探测副作用）
NodeEndpoint mountNode(
  NodeSettingsService service, {
  required String apiBaseUrl,
  String? lanApiBaseUrl,
  String authCode = '',
  String id = 'node-a',
  String name = '测试节点',
}) {
  final node = NodeEndpoint(
    id: id,
    name: name,
    apiBaseUrl: apiBaseUrl,
    lanApiBaseUrl: lanApiBaseUrl,
    authCode: authCode,
  );
  service.remoteNodes.add(node);
  return node;
}

/// 取指定 action 的第一个请求（忽略后台 ping 探测噪声）
FakeNodeRequest requestFor(FakeNodeServer server, String action) =>
    server.requests.firstWhere((r) => r.action == action);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TestWidgetsFlutterBinding 默认会装上拦截所有 HttpClient 的 mock（一切请求都回 400），
  // 这里把它摘掉，让 Dio 走真实环回 socket 打本机假节点。
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late FakeNodeServer server;

  setUp(() async {
    server = await FakeNodeServer.start();
  });

  tearDown(() async {
    await server.dispose();
  });

  // ── 正常调用链路 ────────────────────────────────────────────────────────

  group('callNodeAction 正常链路', () {
    test('success:true 时原样返回 data，请求体是 {action, params} JSON', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply.successData(<dynamic>[
            <String, dynamic>{'id': 'n1', 'title': '第一本'},
            <String, dynamic>{'id': 'n2', 'title': '第二本'},
          ]);

      final response = await service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_novels',
        params: <String, dynamic>{'keyword': '第一'},
      );

      final data = response['data'];
      expect(data, isA<List<dynamic>>());
      expect((data as List<dynamic>).length, 2);
      expect(Map<String, dynamic>.from(data.first as Map), <String, dynamic>{
        'id': 'n1',
        'title': '第一本',
      });
      expect(response['success'], isTrue);

      final recorded = requestFor(server, 'list_novels');
      expect(recorded.method, 'POST');
      expect(recorded.path, _kCallPath);
      expect(recorded.header('content-type'), contains('application/json'));
      expect(recorded.params, <String, dynamic>{'keyword': '第一'});
      // 成功调用会把节点标记为在线
      expect(service.nodeConnectivity['node-a'], isTrue);
      expect(service.nodeConnectivityError['node-a'], isEmpty);
    });

    test('success:false 时抛出含节点 error 文案的异常，且不熔断', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) =>
          req.action == 'list_novels' ? FakeNodeReply.businessError('集合不存在') : FakeNodeReply.successData(<String, dynamic>{});

      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('集合不存在')),
        ),
      );
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivity['node-a'], isFalse);
      expect(service.nodeConnectivityError['node-a'], contains('集合不存在'));
    });

    test('fetchNodeNovels 复用同一条链路并把 data 转成 List<Map>', () async {
      final service = await createService();
      final node = mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply.successData(<dynamic>[
            <String, dynamic>{'id': 'n1'},
          ]);

      final novels = await service.fetchNodeNovels(node);
      expect(novels, <Map<String, dynamic>>[
        <String, dynamic>{'id': 'n1'}
      ]);
      expect(requestFor(server, 'list_novels'), isNotNull);
    });
  });

  // ── 熔断 ─────────────────────────────────────────────────────────────────

  group('节点熔断', () {
    test('探测全部失败 → 熔断位为真，后续 callNodeAction 直接抛"已熔断"', () async {
      final service = await createService();
      final deadPort = await freeLoopbackPort();
      mountNode(service, apiBaseUrl: 'http://127.0.0.1:$deadPort');
      await service.checkNodeConnectivity('node-a');

      expect(service.isNodeCircuitBreaked('node-a'), isTrue);
      expect(service.nodeConnectivity['node-a'], isFalse);
      expect(service.nodeConnectivityError['node-a'], '节点不可达');
      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('节点已熔断')),
        ),
      );
    });

    test('resetNodeCircuitBreaker 后指向可用节点即可恢复', () async {
      final service = await createService();
      final deadPort = await freeLoopbackPort();
      mountNode(service, apiBaseUrl: 'http://127.0.0.1:$deadPort');
      await service.checkNodeConnectivity('node-a');
      expect(service.isNodeCircuitBreaked('node-a'), isTrue);

      service.resetNodeCircuitBreaker('node-a');
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);

      // 把地址改到活节点：熔断位是按 id 记录的，改地址不影响它
      service.remoteNodes[0] = service.remoteNodes[0].copyWith(apiBaseUrl: server.baseUrl);
      final response = await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');
      expect(response['success'], isTrue);
      expect(requestFor(server, 'list_novels'), isNotNull);
    });

    test('callNodeAction 连接失败会经快速探测后置熔断位', () async {
      final service = await createService();
      final deadPort = await freeLoopbackPort();
      mountNode(service, apiBaseUrl: 'http://127.0.0.1:$deadPort');

      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(isA<DioException>()),
      );
      expect(service.isNodeCircuitBreaked('node-a'), isTrue);
      expect(service.nodeConnectivityError['node-a'], contains('熔断'));

      // 熔断后不再发出 HTTP 请求
      final before = server.requests.length;
      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(isA<StateError>()),
      );
      expect(server.requests.length, before);
    });

    test('熔断+活节点：真实请求会自己把熔断解掉', () async {
      final service = await createService();
      final deadPort = await freeLoopbackPort();
      mountNode(service, apiBaseUrl: 'http://127.0.0.1:$deadPort');
      await service.checkNodeConnectivity('node-a');
      expect(service.isNodeCircuitBreaked('node-a'), isTrue);

      // 只把地址改回活节点，不手动 reset：下一次业务请求的复探应当场解除熔断
      service.remoteNodes[0] = service.remoteNodes[0].copyWith(apiBaseUrl: server.baseUrl);
      server.responder = (req) => req.action == 'ping'
          ? FakeNodeReply.successData(<String, dynamic>{'pong': true})
          : FakeNodeReply.successData(<dynamic>[
              <String, dynamic>{'id': 'n1'}
            ]);

      final response = await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');
      expect(response['success'], isTrue);
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivity['node-a'], isTrue);
      expect(requestFor(server, 'list_novels'), isNotNull);
    });

    test('401 不熔断，错误文案为授权码错误', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl, authCode: 'WRONG-CODE');
      server.responder = (req) => FakeNodeReply.unauthorized();

      await service.checkNodeConnectivity('node-a');
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivity['node-a'], isFalse);
      expect(service.nodeConnectivityError['node-a'], '授权码错误，请核对节点授权码');

      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(
          isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 401),
        ),
      );
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivityError['node-a'], '授权码错误，请核对节点授权码');
    });
  });

  // ── 并发打满时的背压（节点回 503） ────────────────────────────────────────

  group('节点并发满（HTTP 503）', () {
    /// 每次都回 503 的节点：模拟连接数打满
    void replyBusyAlways() {
      server.responder = (req) => FakeNodeReply(
        statusCode: HttpStatus.serviceUnavailable,
        json: <String, dynamic>{'success': false, 'error': 'node busy'},
      );
    }

    test('业务调用先 503 后成功：重试吃掉背压，用户侧不报错', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => server.requestCount(path: _kCallPath) <= 2
          ? FakeNodeReply(
              statusCode: HttpStatus.serviceUnavailable,
              json: <String, dynamic>{'success': false, 'error': 'node busy'},
            )
          : FakeNodeReply.successData(<String, dynamic>{'ok': true});

      final response = await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');

      expect(response['data'], <String, dynamic>{'ok': true});
      // 1 次首发 + 2 次重试
      expect(server.requestCount(path: _kCallPath), 3);
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
    });

    test('重试用尽仍 503：抛出但不熔断（节点是在线的）', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      replyBusyAlways();

      await expectLater(
        service.callNodeAction(nodeId: 'node-a', action: 'list_novels'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            HttpStatus.serviceUnavailable,
          ),
        ),
      );
      expect(server.requestCount(path: _kCallPath), 3);
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
    });

    test('连通性探测拿到 503 判为在线', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      replyBusyAlways();

      await service.checkNodeConnectivity('node-a');

      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivity['node-a'], isTrue);
      expect(service.nodeConnectivityError['node-a'], isEmpty);
    });
  });

  // ── 并发去重 ──────────────────────────────────────────────────────────────

  group('并发调用去重', () {
    test('同 nodeId+action+params 并发两次只发一个请求', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => req.action == 'list_media_collections'
          ? FakeNodeReply(json: <String, dynamic>{'success': true, 'data': <dynamic>[]},
              delay: const Duration(milliseconds: 300))
          : FakeNodeReply.successData(<dynamic>[]);

      final first = service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_media_collections',
        params: <String, dynamic>{'folder_id': 'f1'},
      );
      final second = service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_media_collections',
        params: <String, dynamic>{'folder_id': 'f1'},
      );
      final results = await Future.wait(<Future<Map<String, dynamic>>>[first, second]);

      expect(results[0], same(results[1]));
      expect(server.requestCount(path: _kCallPath, action: 'list_media_collections'), 1);
    });

    test('参数不同不去重，各发一个请求', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply(
        json: <String, dynamic>{'success': true, 'data': <dynamic>[]},
        delay: const Duration(milliseconds: 150),
      );

      await Future.wait(<Future<Map<String, dynamic>>>[
        service.callNodeAction(
            nodeId: 'node-a', action: 'list_media_collections', params: <String, dynamic>{'k': 1}),
        service.callNodeAction(
            nodeId: 'node-a', action: 'list_media_collections', params: <String, dynamic>{'k': 2}),
      ]);

      expect(server.requestCount(path: _kCallPath, action: 'list_media_collections'), 2);
    });

    test('失败后去重 key 被清理，可以重新发起', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      var shouldFail = true;
      server.responder = (req) {
        if (req.action != 'scan_media_folders') {
          return FakeNodeReply.successData(<dynamic>[]);
        }
        return shouldFail
            ? FakeNodeReply.businessError('扫描失败')
            : FakeNodeReply.successData(<dynamic>[
                <String, dynamic>{'id': 'c1'}
              ]);
      };

      final failing = service.callNodeAction(nodeId: 'node-a', action: 'scan_media_folders');
      final duplicated = service.callNodeAction(nodeId: 'node-a', action: 'scan_media_folders');
      await expectLater(failing, throwsA(isA<Exception>()));
      await expectLater(duplicated, throwsA(isA<Exception>()));
      expect(server.requestCount(path: _kCallPath, action: 'scan_media_folders'), 1);

      shouldFail = false;
      final retried = await service.callNodeAction(nodeId: 'node-a', action: 'scan_media_folders');
      expect(retried['data'], isA<List<dynamic>>());
      expect(server.requestCount(path: _kCallPath, action: 'scan_media_folders'), 2);
    });
  });

  // ── 授权头 ────────────────────────────────────────────────────────────────

  group('X-SW-Auth 授权头', () {
    test('配置 authCode 后节点收到 sha256(授权码) 十六进制摘要', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl, authCode: 'ABCD-1234-EFGH');

      await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');

      final digest = requestFor(server, 'list_novels').header('x-sw-auth');
      // 与 Rust node_server::auth_code_hash（sha2::Sha256 + trim + 小写 hex）对齐
      expect(digest, sha256.convert(utf8.encode('ABCD-1234-EFGH')).toString());
      expect(digest, NodeSettingsService.authCodeDigest('ABCD-1234-EFGH'));
    });

    test('授权码前后空白被裁剪后仍与节点侧一致', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl, authCode: '  ABCD-1234  ');

      await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');

      expect(
        requestFor(server, 'list_novels').header('x-sw-auth'),
        sha256.convert(utf8.encode('ABCD-1234')).toString(),
      );
    });

    test('未配置 authCode 时不发该头', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);

      await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');

      expect(requestFor(server, 'list_novels').header('x-sw-auth'), isNull);
    });

    test('buildNodeMediaUrl 对带授权码的节点把摘要放进 sw_auth 查询参数', () {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();
      final node = NodeEndpoint(
        id: 'node-a',
        name: '测试节点',
        apiBaseUrl: 'http://127.0.0.1:17888',
        authCode: 'ABCD-1234',
      );
      service.remoteNodes.add(node);

      final url = service.buildNodeMediaUrl(nodeId: 'node-a', filePath: '/media/a.jpg');
      final uri = Uri.parse(url);
      expect(uri.path, '/node/media');
      expect(uri.queryParameters['path'], '/media/a.jpg');
      expect(uri.queryParameters['sw_auth'], sha256.convert(utf8.encode('ABCD-1234')).toString());
    });
  });

  // ── params 清洗 ───────────────────────────────────────────────────────────

  group('_sanitizeJsonMap 参数清洗', () {
    test('BigInt/DateTime/Uint8List/嵌套 Map/List 均转成 JSON 安全形态', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);

      await service.callNodeAction(
        nodeId: 'node-a',
        action: 'import_media_folder',
        params: <String, dynamic>{
          'big': BigInt.parse('12345678901234567890'),
          'when': DateTime.utc(2026, 1, 2, 3, 4, 5),
          'bytes': Uint8List.fromList(<int>[1, 2, 3]),
          'nested': <Object?, Object?>{
            'inner_big': BigInt.zero,
            'list': <dynamic>[DateTime.utc(2020), 'text', 7, true, null],
            1: '数字键会被转成字符串',
          },
          'plain_num': 3.5,
          'missing': null,
        },
      );

      final params = requestFor(server, 'import_media_folder').params;
      expect(params['big'], '12345678901234567890');
      expect(params['when'], '2026-01-02T03:04:05.000Z');
      expect(params['bytes'], base64Encode(<int>[1, 2, 3]));
      final nested = Map<String, dynamic>.from(params['nested'] as Map);
      expect(nested['inner_big'], '0');
      expect(nested['1'], '数字键会被转成字符串');
      final list = nested['list'] as List<dynamic>;
      expect(list[0], '2020-01-01T00:00:00.000Z');
      expect(list.sublist(1), <dynamic>['text', 7, true, null]);
      expect(params['plain_num'], 3.5);
      // null 保留为 JSON null（_sanitizeJsonValue 对 null 直接返回 null）
      expect(params.containsKey('missing'), isTrue);
      expect(params['missing'], isNull);
    });

    test('未知类型退化为 toString()', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);

      await service.callNodeAction(
        nodeId: 'node-a',
        action: 'update_novel_info',
        params: <String, dynamic>{'duration': const Duration(seconds: 5)},
      );

      expect(requestFor(server, 'update_novel_info').params['duration'], '0:00:05.000000');
    });

    test('清洗后的参数参与去重 key（同值不同实例也算同一 key）', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply(
        json: <String, dynamic>{'success': true, 'data': <dynamic>[]},
        delay: const Duration(milliseconds: 200),
      );

      final a = service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_smart_folders',
        params: <String, dynamic>{'id': BigInt.from(42)},
      );
      final b = service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_smart_folders',
        params: <String, dynamic>{'id': BigInt.parse('42')},
      );
      await Future.wait(<Future<Map<String, dynamic>>>[a, b]);

      expect(server.requestCount(path: _kCallPath, action: 'list_smart_folders'), 1);
    });
  });

  // ── 流量统计（_recordAppTraffic） ────────────────────────────────────────

  group('调用后的流量统计', () {
    test('成功调用会把收发字节写进 appTxKbps/appRxKbps', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);

      expect(service.appTxKbps.value, 0);
      await service.callNodeAction(
        nodeId: 'node-a',
        action: 'list_novels',
        params: <String, dynamic>{'keyword': 'x' * 200},
      );

      expect(service.appTxKbps.value, greaterThan(0));
      expect(service.appRxKbps.value, greaterThan(0));
      // 空闲 1.5s 后归零
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      service.syncTrafficDisplayNow();
      expect(service.appTxKbps.value, 0);
      expect(service.appRxKbps.value, 0);
    });
  });

  // ── 兜底：不存在的节点 ───────────────────────────────────────────────────

  test('未配置的 nodeId 直接抛 StateError，不发请求', () async {
    final service = await createService();
    await expectLater(
      service.callNodeAction(nodeId: 'node-missing', action: 'list_novels'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('节点不存在'))),
    );
    expect(server.requestCount(path: _kCallPath), 0);
  });
}
