import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';

Future<void> respond(
  HttpRequest request,
  String model,
  List<Map<String, dynamic>> requests,
) async {
  final raw = await utf8.decoder.bind(request).join();
  request.response.headers.contentType = ContentType.json;
  if (request.uri.path == '/api/tags') {
    request.response.write(
      jsonEncode(<String, dynamic>{
        'models': <Map<String, dynamic>>[
          <String, dynamic>{'name': model},
        ],
      }),
    );
  } else {
    requests.add(jsonDecode(raw) as Map<String, dynamic>);
    request.response.write(
      jsonEncode(<String, dynamic>{
        'message': <String, dynamic>{
          'role': 'assistant',
          'content': '{"genres":["科幻"]}',
        },
      }),
    );
  }
  await request.response.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late HttpServer first;
  late HttpServer second;
  late List<Map<String, dynamic>> requests;

  setUp(() async {
    requests = <Map<String, dynamic>>[];
    first = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    first.listen((request) async {
      await respond(request, 'first-model', requests);
    });
    second.listen((request) async {
      await respond(request, 'second-model', requests);
    });
  });

  tearDown(() async {
    await first.close(force: true);
    await second.close(force: true);
  });

  String url(HttpServer server) => 'http://127.0.0.1:${server.port}';

  test('汇总所有服务器模型并固定模型所属服务器', () async {
    final service = OllamaService();
    service.setServers(<OllamaServer>[
      OllamaServer(url: url(first)),
      OllamaServer(url: url(second)),
    ]);

    final options = await service.getModelOptions();
    expect(options.map((option) => option.model.name), <String>[
      'first-model',
      'second-model',
    ]);
    expect(options[0].server.url, url(first));
    expect(options[1].server.url, url(second));
    expect(options[0].id, isNot(options[1].id));

    await service.generateStructured(
      model: options[1],
      systemPrompt: '只输出 JSON',
      userPrompt: '合成测试文本',
    );

    expect(requests, hasLength(1));
    expect(requests.single['model'], 'second-model');
    expect(requests.single['stream'], isFalse);
    expect(requests.single['format'], 'json');
    expect(requests.single['think'], isFalse);
    expect(requests.single['options']['num_ctx'], 4096);
    expect(requests.single['options']['num_predict'], 160);
  });

  test('一台服务器离线时仍返回另一台模型', () async {
    final offlineUrl = url(first);
    await first.close(force: true);
    final service = OllamaService();
    service.setServers(<OllamaServer>[
      OllamaServer(url: offlineUrl),
      OllamaServer(url: url(second)),
    ]);

    final options = await service.getModelOptions();

    expect(options, hasLength(1));
    expect(options.single.model.name, 'second-model');
  });
}
