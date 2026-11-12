// P2-17 回归：节点流量估算不再在主 isolate 做重活。
//
// 旧实现每次估算都要 sanitize 深拷贝整棵参数树 → jsonEncode → utf8.encode，
// 而且同一次调用里对响应体还估了两次。现在改成纯遍历的廉价口径：
// 字符串按 UTF-16 码元估算字节（ASCII 1:1、宽字符 ≈2.4），容器按项数开销累加，
// 不分配任何中间结构。这里锁定口径的关键性质（不是精确值）：
//  - 与真实 jsonEncode 字节数在同一量级（近似值本来就只给仪表盘看速度）
//  - 规模翻倍 → 估算翻倍（线性，可用来算速率）
//  - 不因 BigInt/DateTime/Uint8List 之类的特殊类型而抛错
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

/// 真实序列化后的字节数（作为对照基准）
int actualJsonBytes(Object? payload) => utf8.encode(jsonEncode(payload)).length;

Future<NodeSettingsService> newService() async {
  SharedPreferences.setMockInitialValues(<String, Object>{'node_local_enabled': false});
  final service = NodeSettingsService();
  await service.init();
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('估算口径（P2-17）', () {
    test('ASCII 键值对：估算与真实字节数同量级（0.5x~2x）', () async {
      final service = await newService();
      final payload = <String, dynamic>{
        'action': 'list_novels',
        'params': <String, dynamic>{'keyword': 'abc', 'page': 1, 'size': 20},
      };

      final estimated = service.estimatePayloadBytesForTest(payload);
      final actual = actualJsonBytes(payload);

      expect(estimated, greaterThan(actual * 0.5));
      expect(estimated, lessThan(actual * 2));
    });

    test('中文参数：估算不会低估到离谱（UTF-8 下汉字 3 字节）', () async {
      final service = await newService();
      final payload = <String, dynamic>{'keyword': '第一本小说的标题'};

      final estimated = service.estimatePayloadBytesForTest(payload);
      final actual = actualJsonBytes(payload);

      expect(estimated, greaterThan(actual * 0.6));
      expect(estimated, lessThan(actual * 2));
    });

    test('规模线性：条目翻 10 倍，估算也大致翻 10 倍', () async {
      final service = await newService();
      List<Map<String, dynamic>> items(int n) => List<Map<String, dynamic>>.generate(
            n,
            (i) => <String, dynamic>{'id': 'n$i', 'title': '标题$i'},
          );

      final small = service.estimatePayloadBytesForTest(items(10));
      final large = service.estimatePayloadBytesForTest(items(100));

      expect(large / small, greaterThan(8));
      expect(large / small, lessThan(12));
    });

    test('2MB 级 payload 估算远快于真实序列化（不做深拷贝/编码）', () async {
      final service = await newService();
      // 约 2MB：4 万个中文标题
      final payload = <String, dynamic>{
        'items': List<Map<String, dynamic>>.generate(
          40000,
          (i) => <String, dynamic>{'id': '$i', 'title': '这是第四万条测试标题的第$i条'},
        ),
      };

      // 先各跑一次预热（JIT）
      service.estimatePayloadBytesForTest(payload);
      actualJsonBytes(payload);

      final stopwatch = Stopwatch()..start();
      final estimated = service.estimatePayloadBytesForTest(payload);
      stopwatch.stop();
      final estimateMicros = stopwatch.elapsedMicroseconds;

      final encodeWatch = Stopwatch()..start();
      final actual = actualJsonBytes(payload);
      encodeWatch.stop();
      final encodeMicros = encodeWatch.elapsedMicroseconds;

      expect(estimated, greaterThan(0));
      expect(estimated, lessThan(actual * 2));
      // 估算应当明显快于 jsonEncode + utf8（不设硬性倍数，只要求不更慢）
      expect(estimateMicros, lessThan(encodeMicros),
          reason: '估算(${estimateMicros}us) 不该慢于真实编码(${encodeMicros}us)');
    });

    test('特殊类型不抛错（BigInt / DateTime / Uint8List / 嵌套）', () async {
      final service = await newService();
      final payload = <String, dynamic>{
        'big': BigInt.parse('12345678901234567890'),
        'when': DateTime.utc(2026, 1, 2, 3, 4, 5),
        'bytes': Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
        'nested': <String, dynamic>{
          'list': <dynamic>[1, 'two', true, null],
        },
      };

      expect(() => service.estimatePayloadBytesForTest(payload), returnsNormally);
      expect(service.estimatePayloadBytesForTest(payload), greaterThan(0));
    });

    test('空 payload / null 返回合理小值', () async {
      final service = await newService();
      expect(service.estimatePayloadBytesForTest(<String, dynamic>{}), 2);
      expect(service.estimatePayloadBytesForTest(null), 4);
    });
  });

  group('流量统计口径仍然可用（回归 node_call_integration 的断言面）', () {
    test('估算结果为正数，能被 _recordAppTraffic 用成速率', () async {
      final service = await newService();
      final bytes = service.estimatePayloadBytesForTest(
        <String, dynamic>{'keyword': 'x' * 200},
      );
      expect(bytes, greaterThan(200));
      expect(service.appTxKbps.value, 0);
    });
  });
}
