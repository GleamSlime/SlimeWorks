import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/node/node_models.dart';

void main() {
  // ── NodeEndpoint ──────────────────────────────────────────────────────────

  group('NodeEndpoint', () {
    test('构造函数正确赋值', () {
      const endpoint = NodeEndpoint(
        id: 'node-001',
        name: '客厅节点',
        apiBaseUrl: 'http://192.168.1.100:17888',
        enabled: true,
        supportsMove: false,
        supportsCoverUpdate: true,
      );
      expect(endpoint.id, 'node-001');
      expect(endpoint.name, '客厅节点');
      expect(endpoint.apiBaseUrl, 'http://192.168.1.100:17888');
      expect(endpoint.enabled, isTrue);
      expect(endpoint.supportsMove, isFalse);
      expect(endpoint.supportsCoverUpdate, isTrue);
    });

    test('默认值合理', () {
      const endpoint = NodeEndpoint(
        id: 'node-002',
        name: '默认节点',
        apiBaseUrl: 'http://localhost:17888',
      );
      expect(endpoint.enabled, isTrue);
      expect(endpoint.supportsMove, isTrue);
      expect(endpoint.supportsCoverUpdate, isTrue);
    });

    test('toJson/fromJson 往返一致', () {
      const endpoint = NodeEndpoint(
        id: 'node-003',
        name: '书房节点',
        apiBaseUrl: 'http://192.168.1.50:17888',
        enabled: false,
        supportsMove: true,
        supportsCoverUpdate: false,
      );
      final json = endpoint.toJson();
      final restored = NodeEndpoint.fromJson(json);

      expect(restored.id, endpoint.id);
      expect(restored.name, endpoint.name);
      expect(restored.apiBaseUrl, endpoint.apiBaseUrl);
      expect(restored.enabled, endpoint.enabled);
      expect(restored.supportsMove, endpoint.supportsMove);
      expect(restored.supportsCoverUpdate, endpoint.supportsCoverUpdate);
    });

    test('fromJson 可处理缺省字段', () {
      final json = <String, dynamic>{
        'id': 'node-min',
        'name': '最简节点',
      };
      final endpoint = NodeEndpoint.fromJson(json);
      expect(endpoint.apiBaseUrl, '');
      expect(endpoint.enabled, isTrue);
      expect(endpoint.supportsMove, isTrue);
      expect(endpoint.supportsCoverUpdate, isTrue);
    });

    test('fromJson 对非 bool 类型降级处理', () {
      final json = <String, dynamic>{
        'id': 'node-str',
        'name': '字符串布尔',
        'apiBaseUrl': 'http://test',
        'enabled': 'true',
        'supportsMove': 1,
        'supportsCoverUpdate': 'yes',
      };
      final endpoint = NodeEndpoint.fromJson(json);
      expect(endpoint.enabled, isTrue);
      expect(endpoint.supportsMove, isTrue);
      expect(endpoint.supportsCoverUpdate, isTrue);
    });

    test('fromJson 对 null 值降级为默认值', () {
      final json = <String, dynamic>{
        'id': 'node-null',
        'name': '空值节点',
        'apiBaseUrl': 'http://test',
        'enabled': null,
        'supportsMove': null,
        'supportsCoverUpdate': null,
      };
      final endpoint = NodeEndpoint.fromJson(json);
      expect(endpoint.enabled, isTrue);
      expect(endpoint.supportsMove, isTrue);
      expect(endpoint.supportsCoverUpdate, isTrue);
    });

    test('copyWith 不传参数时返回等值副本', () {
      const endpoint = NodeEndpoint(
        id: 'node-004',
        name: '副本测试',
        apiBaseUrl: 'http://test',
      );
      final copy = endpoint.copyWith();
      expect(copy.id, endpoint.id);
      expect(copy.name, endpoint.name);
      expect(copy.apiBaseUrl, endpoint.apiBaseUrl);
      expect(copy.enabled, endpoint.enabled);
      expect(copy.supportsMove, endpoint.supportsMove);
      expect(copy.supportsCoverUpdate, endpoint.supportsCoverUpdate);
    });

    test('copyWith 替换指定字段', () {
      const endpoint = NodeEndpoint(
        id: 'node-005',
        name: '原始',
        apiBaseUrl: 'http://original',
        enabled: true,
      );
      final updated = endpoint.copyWith(name: '更新', enabled: false);
      expect(updated.id, endpoint.id);
      expect(updated.name, '更新');
      expect(updated.enabled, isFalse);
      expect(updated.apiBaseUrl, endpoint.apiBaseUrl);
    });

    test('toJson 输出所有字段', () {
      const endpoint = NodeEndpoint(
        id: 'node-006',
        name: '完整',
        apiBaseUrl: 'http://full',
        enabled: false,
        supportsMove: false,
        supportsCoverUpdate: false,
      );
      final json = endpoint.toJson();
      expect(json.containsKey('id'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('apiBaseUrl'), isTrue);
      expect(json.containsKey('enabled'), isTrue);
      expect(json.containsKey('supportsMove'), isTrue);
      expect(json.containsKey('supportsCoverUpdate'), isTrue);
    });
  });
}