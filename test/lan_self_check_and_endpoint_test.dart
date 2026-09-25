import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';

void main() {
  // ── LanTransferService.shouldRunEmptyDevicesSelfCheck 节流 ───────────────
  // 说明：该服务是普通类（非 GetxService），构造不触发 FFI/插件调用，可直接 new。
  // 私有字段 _lastEmptyDevicesSelfCheckAt 无法注入时间，>15s 的到期分支只能通过
  // 「新建实例」间接验证首次状态，无法在本测试内做时间旅行（如实说明）。

  group('shouldRunEmptyDevicesSelfCheck 节流', () {
    test('首次调用返回 true', () {
      final service = LanTransferService();
      expect(service.shouldRunEmptyDevicesSelfCheck(), isTrue);
    });

    test('首次调用后 15s 内再次调用返回 false', () {
      final service = LanTransferService();
      expect(service.shouldRunEmptyDevicesSelfCheck(), isTrue);
      // 立即再次调用：距上次记录远小于 15s
      expect(service.shouldRunEmptyDevicesSelfCheck(), isFalse);
      expect(service.shouldRunEmptyDevicesSelfCheck(), isFalse);
    });

    test('节流状态按实例独立：新实例首次调用仍为 true', () {
      final first = LanTransferService();
      expect(first.shouldRunEmptyDevicesSelfCheck(), isTrue);
      expect(first.shouldRunEmptyDevicesSelfCheck(), isFalse);

      final second = LanTransferService();
      expect(second.shouldRunEmptyDevicesSelfCheck(), isTrue);
    });
  });

  // ── NodeEndpoint.copyWith(clearLanApiBaseUrl) 与 effectiveApiBaseUrl ─────

  group('NodeEndpoint LAN 地址语义', () {
    const node = NodeEndpoint(
      id: 'n1',
      name: 'N',
      apiBaseUrl: 'http://wan.example:17888',
      lanApiBaseUrl: 'http://192.168.1.20:17888',
    );

    test('lanApiBaseUrl 非空时 effectiveApiBaseUrl 优先取 LAN', () {
      expect(node.effectiveApiBaseUrl, 'http://192.168.1.20:17888');
    });

    test('copyWith 默认保留 lanApiBaseUrl（未显式传入时不变）', () {
      final renamed = node.copyWith(name: '改名');
      expect(renamed.lanApiBaseUrl, 'http://192.168.1.20:17888');
      expect(renamed.name, '改名');
      // 传入新 LAN 地址是覆盖语义
      final replaced = node.copyWith(lanApiBaseUrl: 'http://10.0.0.9:17888');
      expect(replaced.lanApiBaseUrl, 'http://10.0.0.9:17888');
    });

    test('copyWith(clearLanApiBaseUrl: true) 清空 LAN，回落公网地址', () {
      final cleared = node.copyWith(clearLanApiBaseUrl: true);
      expect(cleared.lanApiBaseUrl, isNull);
      expect(cleared.effectiveApiBaseUrl, 'http://wan.example:17888');
      // 清除标志优先级高于同次传入的新值
      final clearWins = node.copyWith(
        lanApiBaseUrl: 'http://10.0.0.9:17888',
        clearLanApiBaseUrl: true,
      );
      expect(clearWins.lanApiBaseUrl, isNull);
    });

    test('lanApiBaseUrl 为空串时 effectiveApiBaseUrl 回落公网地址', () {
      const emptyLan = NodeEndpoint(
        id: 'n2',
        name: 'N2',
        apiBaseUrl: 'http://wan.example:17888',
        lanApiBaseUrl: '',
      );
      expect(emptyLan.effectiveApiBaseUrl, 'http://wan.example:17888');
    });

    test('fromJson 把空白/缺失 lanApiBaseUrl 归一为 null', () {
      final missing = NodeEndpoint.fromJson(<String, dynamic>{
        'id': 'n3',
        'name': 'N3',
        'apiBaseUrl': 'http://wan.example:17888',
      });
      expect(missing.lanApiBaseUrl, isNull);

      final blank = NodeEndpoint.fromJson(<String, dynamic>{
        'id': 'n4',
        'name': 'N4',
        'apiBaseUrl': 'http://wan.example:17888',
        'lanApiBaseUrl': '',
      });
      expect(blank.lanApiBaseUrl, isNull);
    });

    test('toJson 仅在 LAN 非空时输出 lanApiBaseUrl 字段', () {
      expect(node.toJson().containsKey('lanApiBaseUrl'), isTrue);
      final noLan = node.copyWith(clearLanApiBaseUrl: true);
      expect(noLan.toJson().containsKey('lanApiBaseUrl'), isFalse);
    });
  });
}
