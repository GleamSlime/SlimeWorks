import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

import 'helpers/fake_node_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 假节点跑在环回端口上，得绕开 flutter test 默认给 HttpClient 装的 mock
  // （它一律回 400），参照 power_aliyun_prefs_test 的做法。
  setUpAll(() => HttpOverrides.global = null);

  // 客户端摘要必须与 Rust node_server 的 auth_code_hash 完全一致，否则永远 401。
  group('NodeSettingsService 授权码摘要', () {
    test('匹配 sha256 标准向量', () {
      expect(
        NodeSettingsService.authCodeDigest('test'),
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      );
    });

    test('忽略授权码前后空白（与 Rust 侧 trim 行为一致）', () {
      expect(
        NodeSettingsService.authCodeDigest('  ABCD-1234  '),
        NodeSettingsService.authCodeDigest('ABCD-1234'),
      );
    });

    // 电力统计/阿里云/Sentry 三个功能服务的节点请求统一从这里取 Dio。
    // 它们原先各自 new 裸 Dio，没有这个头——节点一设授权码，连"这台节点支持
    // 不支持本功能"的探测都吃 401，端侧就是一句「该节点不支持此功能」。
    test('createNodeDio 出的 Dio 给配了授权码的节点补上 X-SW-Auth', () async {
      final server = await FakeNodeServer.start();
      addTearDown(server.dispose);

      const String authCode = 'ABCD-1234';
      final service = NodeSettingsService();
      service.remoteNodes.add(
        NodeEndpoint(
          id: 'n1',
          name: '假节点',
          apiBaseUrl: server.baseUrl,
          authCode: authCode,
        ),
      );

      final dio = service.createNodeDio(
        BaseOptions(connectTimeout: const Duration(seconds: 3)),
      );
      await dio.get<Map<String, dynamic>>('${server.baseUrl}/node/call');

      expect(
        server.lastRequest.headers['x-sw-auth'],
        NodeSettingsService.authCodeDigest(authCode),
      );
    });

    test('节点没配授权码时不带头（保持旧部署的免鉴权行为）', () async {
      final server = await FakeNodeServer.start();
      addTearDown(server.dispose);

      final service = NodeSettingsService();
      service.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '假节点', apiBaseUrl: server.baseUrl),
      );

      final dio = service.createNodeDio(
        BaseOptions(connectTimeout: const Duration(seconds: 3)),
      );
      await dio.get<Map<String, dynamic>>('${server.baseUrl}/node/call');

      expect(server.lastRequest.headers.containsKey('x-sw-auth'), isFalse);
    });
  });
}
