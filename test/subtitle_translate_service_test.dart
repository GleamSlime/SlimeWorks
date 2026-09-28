import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/subtitle_translate_service.dart';

/// 用本地 HTTP 服务模拟 LibreTranslate，验证分批与译文对齐的真实链路
void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> receivedPayloads;

  setUp(() async {
    receivedPayloads = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      receivedPayloads.add(payload);
      final q = (payload['q'] as List).cast<String>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'translatedText': [for (int i = 0; i < q.length; i++) '译${q[i]}'],
        }));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('逐段翻译保持与字幕行一一对应', () async {
    final service = SubtitleTranslateService();
    final node = 'http://127.0.0.1:${server.port}';
    final serverConfig = TranslateServer(name: 'mock', url: node);
    service.setServers([serverConfig]);

    final texts = ['첫째', '둘째', '셋째'];
    final result = await service.translate(serverConfig, texts: texts, source: 'ko');

    expect(result.texts, ['译첫째', '译둘째', '译셋째']);
    expect(result.untranslatedCount, 0);
    expect(receivedPayloads.single['q'], texts);
    expect(receivedPayloads.single['source'], 'ko');
    expect(receivedPayloads.single['target'], 'zh');
  });

  test('超量字幕自动分批且仍然对齐', () async {
    final service = SubtitleTranslateService();
    final node = 'http://127.0.0.1:${server.port}';
    final serverConfig = TranslateServer(name: 'mock', url: '$node/');
    service.setServers([serverConfig]);

    // 每条 40 字符 × 100 条，远超单批 1500 字符上限
    final texts = [for (int i = 0; i < 100; i++) '$i' * 40];
    var done = 0;
    final result = await service.translate(
      serverConfig,
      texts: texts,
      source: 'auto',
      onProgress: (d, _) => done = d,
    );

    expect(result.texts.length, 100);
    expect(receivedPayloads.length, greaterThan(1));
    expect([
      for (final payload in receivedPayloads) ...(payload['q'] as List).cast<String>(),
    ], texts);
    for (int i = 0; i < texts.length; i++) {
      expect(result.texts[i], '译${texts[i]}');
    }
    expect(done, 100);
  });

  test('服务返回错误时保留原文并计数', () async {
    final failing = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    failing.listen((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'boom'}));
      await request.response.close();
    });

    final service = SubtitleTranslateService();
    final serverConfig = TranslateServer(
      name: 'mock',
      url: 'http://127.0.0.1:${failing.port}',
    );
    service.setServers([serverConfig]);

    final result = await service.translate(
      serverConfig,
      texts: ['a', 'b'],
      source: 'ko',
    );
    await failing.close(force: true);
    expect(result.texts, ['a', 'b']);
    expect(result.untranslatedCount, 2);
  });

  test('探测服务会发一条最小请求并带上 api_key', () async {
    final service = SubtitleTranslateService();
    final serverConfig = TranslateServer(
      name: 'mock',
      url: 'http://127.0.0.1:${server.port}',
      apiKey: 'secret',
    );
    service.setServers([serverConfig]);

    expect(await service.testServer(serverConfig), isTrue);
    expect(receivedPayloads.single['q'], ['hello']);
    expect(receivedPayloads.single['api_key'], 'secret');
  });
}
