import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

void main() {
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
  });
}
