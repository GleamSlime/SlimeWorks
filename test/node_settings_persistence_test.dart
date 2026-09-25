import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

/// 说明：
/// - 测试全部通过 `new NodeSettingsService()` 直接构造，不经过 Get.put/onInit 全链路；
/// - 节点地址一律使用 127.0.0.1 的关闭端口（port 1），连通性探测会立刻被拒绝，
///   不会产生真实外网请求，也不会拖慢测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String closedBaseUrl = 'http://127.0.0.1:1';

  /// 构造一个已挂上远程节点列表的服务实例（不调用 init，避免 FFI/网络）。
  NodeSettingsService serviceWithNodes(List<NodeEndpoint> nodes) {
    final service = NodeSettingsService();
    service.remoteNodes.addAll(nodes);
    return service;
  }

  // ── buildNodeMediaUrl ─────────────────────────────────────────────────────

  group('buildNodeMediaUrl', () {
    NodeSettingsService makeService({String authCode = '', String? lanApiBaseUrl}) {
      // apiBaseUrl 带 /node/call 后缀：验证构建时会被 _normalizeBaseUrl 剥掉
      final node = NodeEndpoint(
        id: 'n1',
        name: '测试节点',
        apiBaseUrl: '$closedBaseUrl/node/call',
        lanApiBaseUrl: lanApiBaseUrl,
        authCode: authCode,
      );
      return serviceWithNodes([node]);
    }

    test('thumbnailWidth>0 时拼 width=，<=0 或 null 时不拼', () {
      final service = makeService();
      final withWidth = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg', thumbnailWidth: 240);
      final zeroWidth = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg', thumbnailWidth: 0);
      final nullWidth = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');

      expect(Uri.parse(withWidth).queryParameters['width'], '240');
      expect(zeroWidth.contains('width='), isFalse);
      expect(nullWidth.contains('width='), isFalse);
    });

    test('isCover=true 时拼 mode=cover，false 时不拼', () {
      final service = makeService();
      final cover = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg', isCover: true);
      final normal = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');

      expect(Uri.parse(cover).queryParameters['mode'], 'cover');
      expect(normal.contains('mode='), isFalse);
    });

    test('basePath 规整：补 http:// 由 _normalizeBaseUrl 完成，剥掉 /node/call 后缀', () {
      final service = serviceWithNodes([
        const NodeEndpoint(id: 'n1', name: 'N', apiBaseUrl: '127.0.0.1:1', authCode: ''),
      ]);
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');
      final uri = Uri.parse(url);
      expect(uri.scheme, 'http');
      expect(uri.host, '127.0.0.1');
      expect(uri.port, 1);
      expect(uri.path, '/node/media');
    });

    test('filePath 含中文/空格/& 时 percent-encode 且可无损解码', () {
      final service = makeService();
      const trickyPath = '/相册/家庭 照片&v2=1.jpg';
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: trickyPath);

      // 原始字符不应出现在 URL 中（已被 percent-encode）
      expect(url.contains('相册'), isFalse);
      expect(url.contains(' &'), isFalse);
      // 解码后应与原值完全一致
      expect(Uri.parse(url).queryParameters['path'], trickyPath);
    });

    test('授权码非空时 URL 带 sw_auth=sha256(码)（与 Rust 侧 hex 摘要约定一致）', () {
      final service = makeService(authCode: 'ABCD-1234');
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');

      // sha256("ABCD-1234") 的十六进制摘要（与 Rust auth_code_hash 独立计算的向量）
      expect(
        Uri.parse(url).queryParameters['sw_auth'],
        '01ce39a48e5f5e14ef4a9074f5dfce4eea6d27d766ce554f6a9f92cf078e936b',
      );
      // 摘要必须是 trim 后的明文摘要
      final servicePadded = makeService(authCode: '  ABCD-1234  ');
      expect(
        Uri.parse(servicePadded.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg'))
            .queryParameters['sw_auth'],
        '01ce39a48e5f5e14ef4a9074f5dfce4eea6d27d766ce554f6a9f92cf078e936b',
      );
    });

    test('中文授权码走 UTF-8 字节摘要', () {
      final service = makeService(authCode: '测试码-AB12');
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');
      expect(
        Uri.parse(url).queryParameters['sw_auth'],
        '7216bc7710e788cd39e77dc56357056137b95ba9d3e46025285ddf0dc550f22b',
      );
    });

    test('空授权码不带 sw_auth', () {
      final service = makeService();
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');
      expect(url.contains('sw_auth='), isFalse);
      expect(Uri.parse(url).queryParameters.containsKey('sw_auth'), isFalse);
    });

    test('LAN 地址优先参与构建与授权匹配', () {
      final service = serviceWithNodes([
        const NodeEndpoint(
          id: 'n1',
          name: 'N',
          apiBaseUrl: 'http://wan.example.invalid:1',
          authCode: '',
        ),
      ]);
      service.remoteNodes[0] = service.remoteNodes[0].copyWith(
        lanApiBaseUrl: 'http://127.0.0.1:1',
        authCode: 'ABCD-1234',
      );
      final url = service.buildNodeMediaUrl(nodeId: 'n1', filePath: '/a.jpg');
      final uri = Uri.parse(url);
      expect(uri.host, '127.0.0.1'); // effectiveApiBaseUrl 取 LAN
      expect(uri.queryParameters['sw_auth'], isNotNull); // LAN base 也参与授权匹配
    });

    test('未知 nodeId 抛 StateError', () {
      final service = makeService();
      expect(
        () => service.buildNodeMediaUrl(nodeId: 'missing', filePath: '/a.jpg'),
        throwsStateError,
      );
    });
  });

  // ── buildNodeUploadUrl ───────────────────────────────────────────────────

  group('buildNodeUploadUrl', () {
    test('规整后的 base + /node/upload，且不带查询参数', () {
      final service = serviceWithNodes([
        const NodeEndpoint(id: 'n1', name: 'N', apiBaseUrl: 'http://127.0.0.1:1/node/call', authCode: ''),
      ]);
      final url = service.buildNodeUploadUrl('n1');
      // '/node/call' 后缀应被剥离
      expect(url, '$closedBaseUrl/node/upload');
      expect(url.contains('?'), isFalse);
    });

    test('未知 nodeId 抛 StateError', () {
      final service = serviceWithNodes(const []);
      expect(() => service.buildNodeUploadUrl('missing'), throwsStateError);
    });
  });

  // ── authCodeForUrl：最长前缀匹配 / 禁用节点不授权 ────────────────────────

  group('authCodeForUrl', () {
    test('命中最长前缀节点', () {
      final service = serviceWithNodes([
        const NodeEndpoint(id: 'short', name: '短前缀', apiBaseUrl: closedBaseUrl, authCode: 'AAAA-1111'),
        const NodeEndpoint(
          id: 'long',
          name: '长前缀',
          apiBaseUrl: '$closedBaseUrl/proxy/sw',
          authCode: 'BBBB-2222',
        ),
      ]);

      expect(
        service.authCodeForUrl('$closedBaseUrl/proxy/sw/node/media?path=x'),
        'BBBB-2222',
      );
      expect(service.authCodeForUrl('$closedBaseUrl/other'), 'AAAA-1111');
      expect(service.authCodeForUrl('http://192.0.2.5/node/media'), isNull);
    });

    test('禁用节点即使前缀匹配也不授权', () {
      final service = serviceWithNodes([
        const NodeEndpoint(
          id: 'off',
          name: '停用节点',
          apiBaseUrl: closedBaseUrl,
          authCode: 'CCCC-3333',
          enabled: false,
        ),
      ]);
      expect(service.authCodeForUrl('$closedBaseUrl/node/media'), isNull);
    });

    test('授权码为空的节点不参与匹配', () {
      final service = serviceWithNodes([
        const NodeEndpoint(id: 'noauth', name: 'N', apiBaseUrl: closedBaseUrl, authCode: ''),
      ]);
      expect(service.authCodeForUrl('$closedBaseUrl/node/media'), isNull);
    });

    test('返回的是明文码而非摘要', () {
      final service = serviceWithNodes([
        const NodeEndpoint(id: 'n1', name: 'N', apiBaseUrl: closedBaseUrl, authCode: 'ABCD-1234'),
      ]);
      expect(service.authCodeForUrl('$closedBaseUrl/node/media'), 'ABCD-1234');
    });
  });

  // ── 远程节点 URL 规整（公开入口 addRemoteNode） ──────────────────────────

  group('addRemoteNode URL 规整', () {
    test('补 http:// 前缀、剥 /node/call、/health、尾部斜杠', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();

      await service.addRemoteNode(name: 'A', apiBaseUrl: '127.0.0.1:1');
      expect(service.remoteNodes.last.apiBaseUrl, closedBaseUrl);

      await service.addRemoteNode(name: 'B', apiBaseUrl: 'http://127.0.0.1:1/node/call');
      expect(service.remoteNodes.last.apiBaseUrl, closedBaseUrl);

      await service.addRemoteNode(name: 'C', apiBaseUrl: 'http://127.0.0.1:1/health');
      expect(service.remoteNodes.last.apiBaseUrl, closedBaseUrl);

      await service.addRemoteNode(name: 'D', apiBaseUrl: 'http://127.0.0.1:1/');
      expect(service.remoteNodes.last.apiBaseUrl, closedBaseUrl);

      // https 前缀应保留
      await service.addRemoteNode(name: 'E', apiBaseUrl: 'https://127.0.0.1:1');
      expect(service.remoteNodes.last.apiBaseUrl, 'https://127.0.0.1:1');
    });

    test('空名称回落为「未命名节点」，授权码两端空白被去除', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();
      await service.addRemoteNode(name: '   ', apiBaseUrl: '127.0.0.1:1', authCode: '  ABCD-1234  ');

      final node = service.remoteNodes.last;
      expect(node.name, '未命名节点');
      expect(node.authCode, 'ABCD-1234');
    });

    test('lanApiBaseUrl 同样被规整；纯空白视为 null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();
      await service.addRemoteNode(
        name: 'L1',
        apiBaseUrl: '127.0.0.1:1',
        lanApiBaseUrl: '127.0.0.1:2/node/call',
      );
      expect(service.remoteNodes.last.lanApiBaseUrl, 'http://127.0.0.1:2');
      // 注意：这里只断言规整结果；节点地址均为 127.0.0.1 关闭端口，探测秒失败不发真实请求

      await service.addRemoteNode(name: 'L2', apiBaseUrl: '127.0.0.1:1', lanApiBaseUrl: '   ');
      expect(service.remoteNodes.last.lanApiBaseUrl, isNull);
    });
  });

  // ── generateLocalAuthCode 格式 ───────────────────────────────────────────

  group('generateLocalAuthCode', () {
    test('格式为 4-4-4-4 分段的大写十六进制（共 16 位 hex）', () {
      final service = NodeSettingsService();
      final pattern = RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$');
      for (int i = 0; i < 20; i++) {
        expect(service.generateLocalAuthCode(), matches(pattern));
      }
    });

    test('多次生成基本不重复', () {
      final service = NodeSettingsService();
      final codes = List.generate(20, (_) => service.generateLocalAuthCode());
      expect(codes.toSet().length, codes.length);
    });
  });

  // ── _load 容错（经公开 init() 入口，localNodeEnabled=false 不触发 FFI） ──

  group('init()/_load 容错', () {
    test('正常 JSON：节点被加载且 URL 规整，授权码为空时自动生成并持久化', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_remote_nodes': jsonEncode([
          <String, dynamic>{
            'id': 'n1',
            'name': '客厅',
            'apiBaseUrl': '127.0.0.1:1/node/call',
            'enabled': false, // 禁用以避免 init 后台探测网络
          },
        ]),
      });

      final service = NodeSettingsService();
      await service.init();

      expect(service.remoteNodes.length, 1);
      expect(service.remoteNodes.single.apiBaseUrl, closedBaseUrl);
      expect(service.localNodeEnabled.value, isFalse);
      expect(service.localNodePort.value, 17888);

      // 授权码首次自动生成 + 写回 prefs
      final hexPattern = RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$');
      expect(service.localNodeAuthCode.value, matches(hexPattern));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('node_local_auth_code'), service.localNodeAuthCode.value);

      // 等待 init 内 200ms 延迟的连通性刷新落地（全部节点禁用 → 只写状态不发请求）
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(service.isInitialized, isTrue);
    });

    test('已有授权码时原样读回，不重新生成', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_local_auth_code': 'ABCD-1234',
      });
      final service = NodeSettingsService();
      await service.init();
      expect(service.localNodeAuthCode.value, 'ABCD-1234');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    test('损坏 JSON：remoteNodes 清空且不抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_remote_nodes': '{ this is not json !!!',
      });
      final service = NodeSettingsService();
      await service.init();
      expect(service.remoteNodes, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    test('JSON 不是列表：清空且不抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_remote_nodes': '{"a":1}',
      });
      final service = NodeSettingsService();
      await service.init();
      expect(service.remoteNodes, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    test('条目缺字段/非法：过滤无效项、保留有效项、缺省布尔字段按默认处理', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_remote_nodes': jsonEncode([
          <String, dynamic>{}, // 无 id 无 url → 过滤
          <String, dynamic>{'id': 'no-url', 'name': '缺地址'}, // apiBaseUrl 为空 → 过滤
          <String, dynamic>{'id': 'bad', 'apiBaseUrl': 'http://192.0.2.9:1', 'enabled': false}, // 显式禁用保留
          1, // 非 Map 条目 → 忽略
          <String, dynamic>{'id': 'ok', 'name': '正常', 'apiBaseUrl': 'http://127.0.0.1:1'}, // 缺 enabled → 默认 true
        ]),
      });

      final service = NodeSettingsService();
      await service.init();

      expect(service.remoteNodes.length, 2);
      expect(service.remoteNodes.map((n) => n.id), containsAll(['bad', 'ok']));
      expect(service.getNodeById('ok')!.enabled, isTrue);
      // 注意：'ok' 为启用节点，init 会调度一次连通性探测（指向 127.0.0.1:1 秒失败）。
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(service.remoteNodes.firstWhere((n) => n.id == 'ok').apiBaseUrl, 'http://127.0.0.1:1');
    });

    test('未设置 node_remote_nodes：清空列表', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();
      await service.init();
      expect(service.remoteNodes, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });

    test('init() 幂等：重复调用不重载新写入的 prefs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = NodeSettingsService();
      await service.init();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // init 之后再往 prefs 写节点，第二次 init 因已初始化直接返回
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('node_remote_nodes', '[{"id":"late","apiBaseUrl":"http://127.0.0.1:1"}]');
      await service.init();
      expect(service.remoteNodes, isEmpty);
    });
  });
}
