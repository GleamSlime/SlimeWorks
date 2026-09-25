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
const String _kRemoteNodesKey = 'node_remote_nodes';
const String _kLocalEnabledKey = 'node_local_enabled';

const String _kArchivePath = '/node/upload/archive';
const String _kUploadPath = '/node/upload';
const String _kMediaPath = '/node/media';

/// 直接 new 服务 + init()（只挂授权拦截器与读 prefs），本机节点保持关闭以避开 Rust FFI。
Future<NodeSettingsService> createService({Map<String, Object> initialPrefs = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _kLocalEnabledKey: false,
    ...initialPrefs,
  });
  final service = NodeSettingsService();
  await service.init();
  // 让 init() 里 200ms 后的后台连通性检测先跑完，避免它的 ping 混进请求计数
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return service;
}

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

/// 让节点进入熔断态：把地址临时指向一个确定无人监听的端口做一次探测
Future<void> breakNode(NodeSettingsService service, String nodeId) async {
  final deadPort = await freeLoopbackPort();
  final index = nodeIdIndex(service, nodeId);
  service.remoteNodes[index] = service.remoteNodes[index]
      .copyWith(apiBaseUrl: 'http://127.0.0.1:$deadPort', clearLanApiBaseUrl: true);
  await service.checkNodeConnectivity(nodeId);
  expect(service.isNodeCircuitBreaked(nodeId), isTrue, reason: '前置条件：节点应已熔断');
}

int nodeIdIndex(NodeSettingsService service, String nodeId) =>
    service.remoteNodes.indexWhere((n) => n.id == nodeId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 摘掉 TestWidgetsFlutterBinding 的 HttpClient mock（否则所有请求都被拦成 400），
  // 让 Dio 真实访问本机环回端口上的假节点服务器。
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late FakeNodeServer server;
  late Directory tempDir;

  setUp(() async {
    server = await FakeNodeServer.start();
    tempDir = await Directory.systemTemp.createTemp('slime_node_upload_test_');
  });

  tearDown(() async {
    await server.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ── 归档上传 ──────────────────────────────────────────────────────────────

  group('uploadArchiveToNode', () {
    test('原始字节一致 + Content-Type/Content-Length + dest 参数解码正确', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      // 伪造的 zip 字节（节点侧只是 io::copy 落盘，这里关心的是字节保真）
      final zipBytes = Uint8List.fromList(<int>[
        0x50, 0x4B, 0x03, 0x04, // zip 本地文件头
        ...List<int>.generate(2048, (i) => (i * 7 + 3) & 0xFF),
      ]);
      final zipPath = '${tempDir.path}/归档 包.zip';
      await File(zipPath).writeAsBytes(zipBytes);

      final destDir = '/媒体库/测试 目录&分册';
      await service.uploadArchiveToNode(nodeId: 'node-a', zipPath: zipPath, destDir: destDir);

      final request = server.requests.firstWhere((r) => r.path == _kArchivePath);
      expect(request.method, 'POST');
      expect(request.bodyBytes, zipBytes);
      expect(request.bodyLength, zipBytes.length);
      expect(request.header('content-type'), contains('application/octet-stream'));
      expect(request.header('content-length'), '${zipBytes.length}');
      // dest 走 Uri.encodeComponent，服务端 queryParameters 自动解码
      expect(request.query['dest'], destDir);
      expect(service.nodeConnectivity['node-a'], isTrue);
    });

    test('success:false 抛出节点返回的 error 文案', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply.businessError('磁盘空间不足');
      final zipPath = '${tempDir.path}/a.zip';
      await File(zipPath).writeAsBytes(Uint8List.fromList(<int>[1, 2, 3, 4]));

      await expectLater(
        service.uploadArchiveToNode(nodeId: 'node-a', zipPath: zipPath, destDir: '/dest'),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('磁盘空间不足')),
        ),
      );
    });

    test('熔断且节点仍不可达时上传前即抛，reset 后恢复可上传', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      final zipPath = '${tempDir.path}/b.zip';
      await File(zipPath).writeAsBytes(Uint8List.fromList(<int>[9, 8, 7]));

      // 熔断（地址被临时改到无人监听端口），并保持不可达：复探也救不回来
      await breakNode(service, 'node-a');
      await expectLater(
        service.uploadArchiveToNode(nodeId: 'node-a', zipPath: zipPath, destDir: '/dest'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('节点已熔断')),
        ),
      );
      // 关键：复探只打 /node/call，归档端点一个请求都没收到
      expect(server.requestCount(path: _kArchivePath), 0);

      service.resetNodeCircuitBreaker('node-a');
      service.remoteNodes[nodeIdIndex(service, 'node-a')] =
          service.remoteNodes[nodeIdIndex(service, 'node-a')].copyWith(apiBaseUrl: server.baseUrl);
      await service.uploadArchiveToNode(nodeId: 'node-a', zipPath: zipPath, destDir: '/dest');
      expect(server.requestCount(path: _kArchivePath), 1);
      expect(server.lastRequest.bodyBytes, Uint8List.fromList(<int>[9, 8, 7]));
    });

    test('熔断位是缓存：节点恢复后上传自己就把熔断解除了', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      final zipPath = '${tempDir.path}/c.zip';
      await File(zipPath).writeAsBytes(Uint8List.fromList(<int>[1, 2, 3]));

      await breakNode(service, 'node-a');
      // 熔断位按 id 记录，与地址无关：把地址指回活节点即视为节点已恢复
      service.remoteNodes[nodeIdIndex(service, 'node-a')] =
          service.remoteNodes[nodeIdIndex(service, 'node-a')].copyWith(apiBaseUrl: server.baseUrl);

      // 不调 resetNodeCircuitBreaker：上传前的确认档复探应当场解除熔断
      await service.uploadArchiveToNode(nodeId: 'node-a', zipPath: zipPath, destDir: '/dest');

      expect(server.requestCount(path: _kArchivePath), 1);
      expect(service.isNodeCircuitBreaked('node-a'), isFalse);
      expect(service.nodeConnectivity['node-a'], isTrue);
      expect(service.nodeConnectivityError['node-a'], isEmpty);
    });
  });

  // ── 媒体上传（multipart） ────────────────────────────────────────────────

  group('uploadMediaToNode', () {
    test('multipart 上传：文件字节与字段都到达节点，返回 data 字段', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => req.path == _kUploadPath
          ? FakeNodeReply.successData(<String, dynamic>{
              'saved_path': '/node/uploads/a.png',
              'size': 6,
            })
          : FakeNodeReply.successData(<String, dynamic>{});
      final imagePath = '${tempDir.path}/a.png';
      final imageBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      await File(imagePath).writeAsBytes(imageBytes);

      final data = await service.uploadMediaToNode(
        nodeId: 'node-a',
        localPath: imagePath,
        collectionId: 'col-1',
      );

      expect(data['saved_path'], '/node/uploads/a.png');
      expect(data['size'], 6);

      final request = server.requests.firstWhere((r) => r.path == _kUploadPath);
      expect(request.method, 'POST');
      expect(request.header('content-type'), startsWith('multipart/form-data'));
      final bodyText = request.bodyText;
      expect(bodyText, contains('name="file"'));
      expect(bodyText, contains('filename="a.png"'));
      expect(bodyText, contains('name="collection_id"'));
      expect(bodyText, contains('col-1'));
      // 文件原始字节完整出现在 multipart body 中
      expect(_containsSequence(request.bodyBytes, imageBytes), isTrue);
    });

    test('success:false 抛出 error 文案', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply.businessError('目标集合只读');
      final path = '${tempDir.path}/c.txt';
      await File(path).writeAsString('hello');

      await expectLater(
        service.uploadMediaToNode(nodeId: 'node-a', localPath: path),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('目标集合只读')),
        ),
      );
    });

    test('熔断时上传前即抛', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      await breakNode(service, 'node-a');
      final path = '${tempDir.path}/d.txt';
      await File(path).writeAsString('hello');

      await expectLater(
        service.uploadMediaToNode(nodeId: 'node-a', localPath: path),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('节点已熔断')),
        ),
      );
      expect(server.requestCount(path: _kUploadPath), 0);
    });
  });

  // ── 文件下载 ──────────────────────────────────────────────────────────────

  group('downloadNodeFileTo', () {
    test('落盘内容与节点返回字节一致，URL 携带 sw_auth 摘要', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl, authCode: 'ABCD-1234');
      final payload = Uint8List.fromList(List<int>.generate(4096, (i) => (i * 13) & 0xFF));
      server.responder = (req) => req.path == _kMediaPath
          ? FakeNodeReply.fileBytes(payload)
          : FakeNodeReply.successData(<String, dynamic>{});
      final savePath = '${tempDir.path}/downloaded.bin';

      await service.downloadNodeFileTo(nodeId: 'node-a', filePath: '/media/a.jpg', savePath: savePath);

      expect(await File(savePath).length(), payload.length);
      expect(await File(savePath).readAsBytes(), payload);

      final request = server.requests.firstWhere((r) => r.path == _kMediaPath);
      expect(request.method, 'GET');
      expect(request.query['path'], '/media/a.jpg');
      // buildNodeMediaUrl 把摘要塞进查询参数（图片流拿不到请求头）
      expect(request.query['sw_auth'], sha256.convert(utf8.encode('ABCD-1234')).toString());
      // Dio 拦截器同时补了 X-SW-Auth
      expect(
        request.header('x-sw-auth'),
        NodeSettingsService.authCodeDigest('ABCD-1234'),
      );
    });

    test('未配置授权码时 URL 不带 sw_auth', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) =>
          req.path == _kMediaPath ? FakeNodeReply.fileBytes(<int>[1, 2, 3]) : FakeNodeReply.successData(<String, dynamic>{});
      final savePath = '${tempDir.path}/plain.bin';

      await service.downloadNodeFileTo(nodeId: 'node-a', filePath: '/media/b.jpg', savePath: savePath);

      final request = server.requests.firstWhere((r) => r.path == _kMediaPath);
      expect(request.query.containsKey('sw_auth'), isFalse);
      expect(await File(savePath).readAsBytes(), <int>[1, 2, 3]);
    });

    test('节点返回 404 时抛 DioException', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);
      server.responder = (req) => FakeNodeReply(
            statusCode: HttpStatus.notFound,
            json: <String, dynamic>{'success': false, 'error': '文件不存在'},
          );
      final savePath = '${tempDir.path}/missing.bin';

      await expectLater(
        service.downloadNodeFileTo(nodeId: 'node-a', filePath: '/media/x.jpg', savePath: savePath),
        throwsA(
          isA<DioException>().having((e) => e.response?.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  // ── 地址自动修正（_persistResolvedNodeBaseUrl） ─────────────────────────

  group('节点地址自动修正', () {
    test('经 LAN 地址调用成功后，apiBaseUrl 被改写并落 prefs', () async {
      final deadPort = await freeLoopbackPort();
      final wanBase = 'http://127.0.0.1:$deadPort';
      // 通过 prefs 预置节点，让 _load() 走真实加载链路（addRemoteNode 会自带探测副作用）
      SharedPreferences.setMockInitialValues(<String, Object>{
        _kLocalEnabledKey: false,
        _kRemoteNodesKey: jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'node-p',
            'name': '局域网节点',
            'apiBaseUrl': wanBase,
            'lanApiBaseUrl': server.baseUrl,
            'enabled': true,
          },
        ]),
      });

      final service = NodeSettingsService();
      await service.init();
      // 等 init 的后台探测跑完，再确认初始地址仍是 WAN 地址
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(service.getNodeById('node-p')!.apiBaseUrl, wanBase);
      expect(service.isNodeCircuitBreaked('node-p'), isFalse);

      final response = await service.callNodeAction(nodeId: 'node-p', action: 'list_novels');
      expect(response['success'], isTrue);

      // effectiveApiBaseUrl(LAN) 命中 → resolved 与 apiBaseUrl 不同 → 改写
      expect(service.getNodeById('node-p')!.apiBaseUrl, server.baseUrl);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRemoteNodesKey);
      expect(raw, isNotNull);
      expect(raw!, contains(server.baseUrl));
      expect(raw.contains(wanBase), isFalse);
    });

    test('resolved 与 apiBaseUrl 相同时不改写', () async {
      final service = await createService();
      mountNode(service, apiBaseUrl: server.baseUrl);

      await service.callNodeAction(nodeId: 'node-a', action: 'list_novels');

      expect(service.getNodeById('node-a')!.apiBaseUrl, server.baseUrl);
    });
  });
}

/// 在 [haystack] 中查找连续子序列 [needle]
bool _containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  outer:
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}
