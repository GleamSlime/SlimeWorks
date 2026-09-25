// Ollama 服务层可测逻辑单测（OllamaService + OllamaSettingsService）。
//
// 可测性结论（先读码验证过）：
// - OllamaService 的 _dio 为私有且构造不注入，但服务器 URL 完全由用户配置，
//   因此用 dart:io 本机环回"假 Ollama 服务器"即可从公开入口驱动全部 HTTP 路径
//   （testServer/findAvailableServer/getModels/generate/translate/translateBatch），
//   含私有 _cleanupResponse 的清洗效果与私有 _updateServerInList 的列表回写。
// - translateBatch 的失败兜底（保留原文）可在无服务器/5xx 场景下观察。
// - OllamaSettingsService 走 SharedPreferences：用 setMockInitialValues 测
//   持久化往返、默认值写入与损坏数据容错；init() 会后台探测服务器，
//   故注入 _NoNetworkOllamaService 桩（覆写公开 testServer/findAvailableServer）
//   避免任何真实网络。模型层序列化已由 ollama_models_test.dart 覆盖，不重复。
// - 放弃项：_cleanupResponse 中 think 标签（）清洗不存在（代码只处理 <|...|> 系列特殊 token），按实际代码断言。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';

// ── 假 Ollama 服务器夹具 ─────────────────────────────────────────────────────

class _FixtureReply {
  const _FixtureReply(this.status, this.body, {this.contentType = 'application/json'});

  final int status;
  final String body;
  final String contentType;
}

class _FixtureRequest {
  _FixtureRequest(this.method, this.path, this.body, this.auth);

  final String method;
  final String path;
  final String body;
  final String? auth;
}

/// 本机环回端口上的可控假 Ollama：按 (method, path) 编排响应并记录请求。
class _FakeOllamaServer {
  _FakeOllamaServer._(this._server) {
    _sub = _server.listen((HttpRequest request) async {
      final String body = await utf8.decoder.bind(request).join();
      requests.add(
        _FixtureRequest(
          request.method,
          request.uri.path,
          body,
          request.headers.value(HttpHeaders.authorizationHeader),
        ),
      );
      final _FixtureReply reply = responder(request.method, request.uri.path);
      request.response.statusCode = reply.status;
      request.response.headers.set(HttpHeaders.contentTypeHeader, reply.contentType);
      // write(String) 默认按 Latin-1 编码，中文载荷会抛错，需手动 utf8 编码
      request.response.add(utf8.encode(reply.body));
      await request.response.close();
    });
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _sub;

  final List<_FixtureRequest> requests = <_FixtureRequest>[];

  _FixtureReply Function(String method, String path) responder =
      (String m, String p) => _FixtureReply(200, '{}');

  static Future<_FakeOllamaServer> start() async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _FakeOllamaServer._(server);
  }

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  List<_FixtureRequest> get chatRequests =>
      requests.where((_FixtureRequest r) => r.path == '/api/chat').toList(growable: false);

  Future<void> stop() async {
    await _sub.cancel();
    await _server.close(force: true);
  }
}

/// 取一个保证无人监听的环回端口（连接必然被拒）。
Future<int> _closedPort() async {
  final ServerSocket probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = probe.port;
  await probe.close();
  return port;
}

const TranslationLanguagePair _jaToZh = TranslationLanguagePair(
  from: '日文',
  to: '中文',
  displayName: '日文 → 中文',
);

// ── 无网络 OllamaService 桩（供 SettingsService 用例注入） ───────────────────

class _NoNetworkOllamaService extends OllamaService {
  int findCalls = 0;
  int testCalls = 0;
  int setServersCalls = 0;
  bool testResult = false;
  List<OllamaModel> modelsResult = const <OllamaModel>[];

  @override
  void setServers(List<OllamaServer> servers) {
    setServersCalls++;
    super.setServers(servers);
  }

  @override
  Future<bool> testServer(OllamaServer server) async {
    testCalls++;
    return testResult;
  }

  @override
  Future<OllamaServer?> findAvailableServer() async {
    findCalls++;
    return null;
  }

  @override
  Future<List<OllamaModel>> getModels() async => modelsResult;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 默认拦截真实 socket；本文件全部走本机环回（假服务器/必然拒绝端口）。
  HttpOverrides.global = null;

  const String keyServers = 'ollama_servers';
  const String keyDefaultModel = 'ollama_default_model';

  Future<String?> readPref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  // ═════════════════════════════════════════════════════════════════════════
  // OllamaService - 纯内存服务器列表管理
  // ═════════════════════════════════════════════════════════════════════════

  group('OllamaService - 服务器列表（内存）', () {
    test('servers getter 返回只读视图', () {
      final OllamaService service = OllamaService();
      service.addServer(OllamaServer(url: 'http://a'));
      expect(() => service.servers.add(OllamaServer(url: 'http://b')), throwsUnsupportedError);
      expect(service.servers, hasLength(1));
    });

    test('addServer/removeServer 基本增删', () {
      final OllamaService service = OllamaService();
      service.addServer(OllamaServer(url: 'http://a'));
      service.addServer(OllamaServer(url: 'http://b'));
      service.removeServer('http://a');
      expect(service.servers.map((OllamaServer s) => s.url), <String>['http://b']);

      service.removeServer('http://不存在');
      expect(service.servers, hasLength(1));
    });

    test('setServers 全量替换', () {
      final OllamaService service = OllamaService();
      service.addServer(OllamaServer(url: 'http://old'));
      service.setServers(<OllamaServer>[OllamaServer(url: 'http://n1'), OllamaServer(url: 'http://n2')]);
      expect(service.servers.map((OllamaServer s) => s.url), <String>['http://n1', 'http://n2']);
    });

    test('无任何服务器时 findAvailableServer 返回 null 且各入口抛异常', () async {
      final OllamaService service = OllamaService();
      expect(await service.findAvailableServer(), isNull);
      await expectLater(service.getModels(), throwsA(isA<Exception>()));
      await expectLater(
        service.generate(model: 'm', prompt: 'p'),
        throwsA(isA<Exception>()),
      );
      expect(service.servers, isEmpty); // 全程未发起任何网络
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // OllamaService - 经假 Ollama 服务器驱动的真实 HTTP 路径
  // ═════════════════════════════════════════════════════════════════════════

  group('OllamaService - testServer/findAvailableServer', () {
    late _FakeOllamaServer fixture;

    setUp(() async {
      fixture = await _FakeOllamaServer.start();
      addTearDown(fixture.stop);
    });

    test('200 → true，503 → false，连接被拒 → false（不抛异常）', () async {
      final OllamaService service = OllamaService();
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');
      expect(await service.testServer(OllamaServer(url: fixture.baseUrl)), isTrue);

      fixture.responder = (String m, String p) => const _FixtureReply(503, '');
      expect(await service.testServer(OllamaServer(url: fixture.baseUrl)), isFalse);

      final int dead = await _closedPort();
      expect(await service.testServer(OllamaServer(url: 'http://127.0.0.1:$dead')), isFalse);
    });

    test('配置 apiKey 时携带 Bearer 头，未配置则不带', () async {
      final OllamaService service = OllamaService();
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');

      await service.testServer(OllamaServer(url: fixture.baseUrl, apiKey: 'sk-1'));
      expect(fixture.requests.last.auth, 'Bearer sk-1');

      await service.testServer(OllamaServer(url: fixture.baseUrl));
      expect(fixture.requests.last.auth, isNull);
    });

    test('findAvailableServer 跳过死服务器命中活服务器，并回写列表状态', () async {
      final int dead = await _closedPort();
      final OllamaService service = OllamaService();
      service.setServers(<OllamaServer>[
        OllamaServer(url: 'http://127.0.0.1:$dead'),
        OllamaServer(url: fixture.baseUrl),
      ]);
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');

      final OllamaServer? found = await service.findAvailableServer();
      expect(found?.url, fixture.baseUrl);
      expect(service.currentServer?.url, fixture.baseUrl);
      // _updateServerInList 私有，但效果经公开 servers 可观察
      expect(service.servers[1].isAvailable, isTrue);
      expect(service.servers[1].lastChecked, isNotNull);
      expect(service.servers[0].isAvailable, isFalse);
    });

    test('优先复用当前可用服务器，不再轮询其余服务器', () async {
      final OllamaService service = OllamaService();
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');
      service.setServers(<OllamaServer>[
        OllamaServer(url: fixture.baseUrl),
        OllamaServer(url: fixture.baseUrl),
      ]);

      final OllamaServer? first = await service.findAvailableServer();
      expect(first, isNotNull);
      fixture.requests.clear();

      final OllamaServer? second = await service.findAvailableServer();
      expect(second?.url, first?.url);
      // 当前服务器探活成功即返回，仅 1 次请求（未轮询第二个）
      expect(fixture.requests, hasLength(1));
    });

    test('removeServer 删除当前服务器时清空 currentServer；setServers 也重置', () async {
      final OllamaService service = OllamaService();
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');
      service.addServer(OllamaServer(url: fixture.baseUrl));
      await service.findAvailableServer();
      expect(service.currentServer, isNotNull);

      service.removeServer(fixture.baseUrl);
      expect(service.currentServer, isNull);

      service.addServer(OllamaServer(url: fixture.baseUrl));
      await service.findAvailableServer();
      expect(service.currentServer, isNotNull);
      service.setServers(<OllamaServer>[]);
      expect(service.currentServer, isNull);
    });
  });

  group('OllamaService - getModels', () {
    late _FakeOllamaServer fixture;
    late OllamaService service;

    setUp(() async {
      fixture = await _FakeOllamaServer.start();
      addTearDown(fixture.stop);
      service = OllamaService();
      service.addServer(OllamaServer(url: fixture.baseUrl));
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{"models": []}');
      await service.findAvailableServer();
    });

    test('解析 models 列表（可选字段缺失兜底）', () async {
      fixture.responder = (String m, String p) => _FixtureReply(
        200,
        jsonEncode(<String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'name': 'qwen2.5', 'size': 4000000000},
            <String, dynamic>{'name': 'llama3'},
          ],
        }),
      );
      final List<OllamaModel> models = await service.getModels();
      expect(models.map((OllamaModel m) => m.name), <String>['qwen2.5', 'llama3']);
      expect(models.last.size, isNull);
    });

    test('响应缺 models 字段时返回空列表', () async {
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');
      expect(await service.getModels(), isEmpty);
    });

    test('HTTP 5xx 时抛 DioException 并清空 currentServer', () async {
      fixture.responder = (String m, String p) => const _FixtureReply(503, '');
      await expectLater(service.getModels(), throwsA(isA<DioException>()));
      expect(service.currentServer, isNull);
    });
  });

  group('OllamaService - generate/translate（含 _cleanupResponse 公开入口验证）', () {
    late _FakeOllamaServer fixture;
    late OllamaService service;

    setUp(() async {
      fixture = await _FakeOllamaServer.start();
      addTearDown(fixture.stop);
      service = OllamaService();
      service.addServer(OllamaServer(url: fixture.baseUrl));
      fixture.responder = (String m, String p) => const _FixtureReply(200, '{}');
    });

    test('非流式：请求体携带 system 指令/停止标记/推理参数，prompt 去首尾空白', () async {
      fixture.responder = (String m, String p) =>
          const _FixtureReply(200, '{"message": {"content": "ok"}, "done": true}');

      await service.translate(model: 'qwen', text: '  こんにちは  ', languagePair: _jaToZh);

      final _FixtureRequest chat = fixture.chatRequests.last;
      expect(chat.method, 'POST');
      final Map<String, dynamic> body = jsonDecode(chat.body) as Map<String, dynamic>;
      expect(body['model'], 'qwen');
      expect(body['stream'], isFalse);
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect(messages[0]['role'], 'system');
      expect(messages[1]['content'], 'こんにちは');
      expect((body['stop'] as List<dynamic>), contains('<|im_end|>'));
      expect((body['options'] as Map<String, dynamic>)['temperature'], 0);
    });

    test('非流式返回前执行清洗：去 <|...|> 特殊标记、压缩多空行、trim', () async {
      fixture.responder = (String m, String p) => _FixtureReply(
        200,
        jsonEncode(<String, dynamic>{
          'message': <String, dynamic>{
            'content': '  前半<|im_end|>\n\n\n\n后半<|endoftext|><|assistant|>\n',
          },
          'done': true,
        }),
      );

      final String out = await service.generate(model: 'm', prompt: 'p');
      expect(out, '前半\n\n后半');
    });

    test('流式：按行解析 NDJSON、兼容 data: 前缀、坏行跳过、累计回调与清洗', () async {
      final String ndjson = <String>[
        'data: ${jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': '部分一'}, 'done': false})}',
        jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': '部分二<|im_end|>'}, 'done': false}),
        '这不是JSON',
        jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': '部分三'}, 'done': true}),
        jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': '不应出现'}, 'done': false}),
      ].join('\n');
      fixture.responder = (String m, String p) =>
          _FixtureReply(200, ndjson, contentType: 'application/x-ndjson');

      final List<String> chunks = <String>[];
      final String out = await service.generate(
        model: 'm',
        prompt: 'p',
        onChunk: (String chunk) => chunks.add(chunk),
      );

      expect(chunks, <String>['部分一', '部分二<|im_end|>', '部分三']);
      // done=true 后 break：第四条内容不再出现；整体清洗去标记
      expect(out, '部分一部分二部分三');
      expect(out.contains('不应出现'), isFalse);
    });

    test('流式：[DONE] 哨兵行提前结束', () async {
      final String ndjson = <String>[
        jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': 'A'}, 'done': false}),
        '[DONE]',
        jsonEncode(<String, dynamic>{'message': <String, dynamic>{'content': 'B'}, 'done': false}),
      ].join('\n');
      fixture.responder = (String m, String p) =>
          _FixtureReply(200, ndjson, contentType: 'application/x-ndjson');

      final List<String> chunks = <String>[];
      await service.generate(model: 'm', prompt: 'p', onChunk: (String c) => chunks.add(c));
      expect(chunks, <String>['A']);
    });

    test('流式请求 stream=true；translate 与 generate 共享清洗', () async {
      fixture.responder = (String m, String p) => _FixtureReply(
        200,
        jsonEncode(<String, dynamic>{
          'message': <String, dynamic>{'content': '译文  '},
          'done': true,
        }),
      );
      final String out = await service.translate(
        model: 'm',
        text: 'テキスト',
        languagePair: _jaToZh,
        onChunk: (String _) {},
      );
      expect(out, '译文');
      expect(jsonDecode(fixture.chatRequests.last.body)['stream'], isTrue);
    });

    test('chat 5xx 时 generate 抛 DioException 并清空 currentServer', () async {
      fixture.responder = (String m, String p) => p.endsWith('/chat')
          ? const _FixtureReply(503, '')
          : const _FixtureReply(200, '{}');
      await service.findAvailableServer();
      await expectLater(service.generate(model: 'm', prompt: 'p'), throwsA(isA<DioException>()));
      expect(service.currentServer, isNull);
    });
  });

  group('OllamaService - translateBatch', () {
    late _FakeOllamaServer fixture;

    setUp(() async {
      fixture = await _FakeOllamaServer.start();
      addTearDown(fixture.stop);
    });

    test('空段跳过、成功段按序翻译并推进进度', () async {
      final OllamaService service = OllamaService();
      service.addServer(OllamaServer(url: fixture.baseUrl));
      fixture.responder = (String m, String p) {
        if (p.endsWith('/chat')) {
          final Map<String, dynamic> body = jsonDecode(
            fixture.chatRequests.last.body,
          ) as Map<String, dynamic>;
          final String src =
              ((body['messages'] as List<dynamic>).last as Map<String, dynamic>)['content']
                  as String;
          return _FixtureReply(
            200,
            jsonEncode(<String, dynamic>{
              'message': <String, dynamic>{'content': '[$src]'},
              'done': true,
            }),
          );
        }
        return const _FixtureReply(200, '{}');
      };

      final List<int> progress = <int>[];
      final List<String> results = await service.translateBatch(
        model: 'm',
        paragraphs: <String>['a', '   ', 'b'],
        languagePair: _jaToZh,
        onProgress: (int current, int total) => progress.add(current * 10 + total),
      );

      expect(results, <String>['[a]', '', '[b]']);
      // 空白段不回调进度；成功段回调 (1,3)、(3,3)
      expect(progress, <int>[13, 33]);
      expect(fixture.chatRequests, hasLength(2));
    });

    test('单段失败时保留原文且继续后续段落（不中断批次）', () async {
      final OllamaService service = OllamaService();
      service.addServer(OllamaServer(url: fixture.baseUrl));
      int chatCalls = 0;
      fixture.responder = (String m, String p) {
        if (p.endsWith('/chat')) {
          chatCalls++;
          if (chatCalls == 1) {
            return const _FixtureReply(503, '');
          }
          return _FixtureReply(
            200,
            jsonEncode(<String, dynamic>{
              'message': <String, dynamic>{'content': '第二段译文'},
              'done': true,
            }),
          );
        }
        return const _FixtureReply(200, '{}');
      };

      final List<String> results = await service.translateBatch(
        model: 'm',
        paragraphs: <String>['第一段', '第二段'],
        languagePair: _jaToZh,
      );
      expect(results, <String>['第一段', '第二段译文']);
    });

    test('无可用服务器时全部段落回退原文', () async {
      final OllamaService service = OllamaService();
      final List<String> results = await service.translateBatch(
        model: 'm',
        paragraphs: <String>['甲', '乙'],
        languagePair: _jaToZh,
      );
      expect(results, <String>['甲', '乙']);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // OllamaSettingsService（SharedPreferences 持久化 + 无网络桩注入）
  // ═════════════════════════════════════════════════════════════════════════

  group('OllamaSettingsService', () {
    late _NoNetworkOllamaService stub;
    late OllamaSettingsService settings;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      stub = _NoNetworkOllamaService();
      settings = OllamaSettingsService(stub);
    });

    List<dynamic> decodeServers(String? json) =>
        json == null ? <dynamic>[] : jsonDecode(json) as List<dynamic>;

    test('无历史数据时写入两台本地默认服务器并持久化', () async {
      await settings.init();

      expect(settings.servers.map((OllamaServer s) => s.url), <String>[
        'http://localhost:11434',
        'http://127.0.0.1:11434',
      ]);
      expect(settings.isInitialized.value, isTrue);
      expect(settings.defaultModel.value, '');

      final List<dynamic> persisted = decodeServers(await readPref(keyServers));
      expect(persisted, hasLength(2));
      expect(persisted.first['url'], 'http://localhost:11434');
      // 同步进 OllamaService
      expect(stub.servers.map((OllamaServer s) => s.url), contains('http://localhost:11434'));
    });

    test('读取已存服务器列表并注入 OllamaService', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        keyServers: jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'url': 'http://a:11434', 'apiKey': 'k', 'isAvailable': false},
          <String, dynamic>{'url': 'http://b:11434'},
        ]),
      });

      await settings.init();
      expect(settings.servers.map((OllamaServer s) => s.url), <String>['http://a:11434', 'http://b:11434']);
      expect(stub.servers, hasLength(2));
      expect(stub.findCalls, 1); // 有服务器 → 启动时后台探测一次
    });

    test('损坏 JSON：不抛异常、列表为空、默认服务器不补写', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{keyServers: '{{{坏数据'});

      await settings.init();
      expect(settings.servers, isEmpty);
      expect(settings.isInitialized.value, isTrue);
      expect(await readPref(keyServers), '{{{坏数据'); // 原样保留，未被覆盖
      expect(stub.findCalls, 0);
    });

    test('条目缺 url 字段：整次加载被 catch 兜住，不产生半截列表', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        keyServers: jsonEncode(<Map<String, dynamic>>[<String, dynamic>{'name': '没有url'}]),
      });

      await settings.init();
      expect(settings.servers, isEmpty);
      expect(settings.isInitialized.value, isTrue);
    });

    test('加载 defaultModel 值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        keyDefaultModel: 'qwen2.5:7b',
      });
      await settings.init();
      expect(settings.defaultModel.value, 'qwen2.5:7b');
    });

    test('init 幂等：二次调用不重复加载/探测', () async {
      await settings.init();
      final int findAfterFirst = stub.findCalls;
      final int setAfterFirst = stub.setServersCalls;

      await settings.init();
      expect(stub.findCalls, findAfterFirst);
      expect(stub.setServersCalls, setAfterFirst);
    });

    test('saveServers/saveDefaultModel 同时更新内存、服务与持久化', () async {
      await settings.init();

      await settings.saveServers(<OllamaServer>[OllamaServer(url: 'http://only:1')]);
      expect(settings.servers.map((OllamaServer s) => s.url), <String>['http://only:1']);
      expect(stub.servers.map((OllamaServer s) => s.url), <String>['http://only:1']);
      expect(decodeServers(await readPref(keyServers)).first['url'], 'http://only:1');

      await settings.saveDefaultModel('llama3');
      expect(settings.defaultModel.value, 'llama3');
      expect(await readPref(keyDefaultModel), 'llama3');
    });

    test('addServer/removeServer 持久化往返', () async {
      await settings.init();

      await settings.addServer(OllamaServer(url: 'http://new:9', apiKey: 'token'));
      expect(settings.servers, hasLength(3));
      expect(decodeServers(await readPref(keyServers)), hasLength(3));

      await settings.removeServer('http://new:9');
      expect(settings.servers, hasLength(2));
      expect(
        decodeServers(await readPref(keyServers)).map((dynamic e) => (e as Map)['url']),
        isNot(contains('http://new:9')),
      );
    });

    test('updateServer 用 oldUrl 原位替换；未知 oldUrl 不改动持久化', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        keyServers: jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'url': 'http://a'},
          <String, dynamic>{'url': 'http://b'},
          <String, dynamic>{'url': 'http://c'},
        ]),
      });
      await settings.init();

      await settings.updateServer('http://b', OllamaServer(url: 'http://b2', apiKey: 'k'));
      expect(settings.servers.map((OllamaServer s) => s.url), <String>['http://a', 'http://b2', 'http://c']);
      expect(stub.servers[1].apiKey, 'k');

      final String before = (await readPref(keyServers))!;
      await settings.updateServer('http://不存在', OllamaServer(url: 'http://d'));
      expect(await readPref(keyServers), before);
      expect(settings.servers, hasLength(3));
    });

    test('跨实例持久化往返：实例一保存 → 实例二读取一致', () async {
      await settings.init();
      await settings.saveServers(<OllamaServer>[
        OllamaServer(url: 'http://x:1', apiKey: 'a1', isAvailable: true),
      ]);

      final _NoNetworkOllamaService stub2 = _NoNetworkOllamaService();
      final OllamaSettingsService settings2 = OllamaSettingsService(stub2);
      await settings2.init();

      expect(settings2.servers.single.url, 'http://x:1');
      expect(settings2.servers.single.apiKey, 'a1');
      expect(settings2.servers.single.isAvailable, isTrue);
    });

    test('testServer/getModels/refreshServerStatus 全部委托 OllamaService', () async {
      stub.testResult = true;
      stub.modelsResult = <OllamaModel>[OllamaModel(name: 'm1')];

      expect(await settings.testServer(OllamaServer(url: 'http://a')), isTrue);
      expect(stub.testCalls, 1);
      expect((await settings.getModels()).single.name, 'm1');

      await settings.refreshServerStatus();
      expect(stub.findCalls, 1);
    });
  });
}
