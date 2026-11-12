// P3-8 回归：局域网传输不应存在两套设备轮询。
//
// 服务侧原本还有一个 3s 定时器在调 getDevices()，但**返回值从来没被任何人用过**
// （纯丢弃）；真正的设备列表轮询在 LanTransferViewModel（每 3s refreshDevices
// → getDevices 并写 UI）。两套并行 = 每个周期白跑一次 FFI + 一行日志。
//
// 这里用 RustLib.initMock 桩掉 FFI，统计 startService 之后一段时间内
// lanTransferGetDevices 的调用次数：应只来自显式调用（自检），不再有周期性调用。
import 'dart:async';
import 'dart:convert';

// connectivity_plus 的平台接口是它的传递依赖，测试里替换平台实现需要直接引用
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => '/tmp/sw_lan_test';
}

/// 固定返回「有网」，避开平台通道
class _FakeConnectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      <ConnectivityResult>[ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
}

class _MockLanApi implements RustLibApi {
  final List<String> calls = <String>[];

  int countOf(String method) => calls.where((c) => c == method).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = _symbolName(invocation.memberName);
    calls.add(name);
    switch (name) {
      case 'crateApiLanTransferLanTransferInit':
        return null;
      case 'crateApiLanTransferLanTransferStart':
        return Future<void>.value();
      case 'crateApiLanTransferLanTransferStop':
        return Future<void>.value();
      case 'crateApiLanTransferLanTransferGetDevices':
        return Future<List<String>>.value(<String>[]);
      case 'crateApiLanTransferLanTransferGetLocalDevice':
        return Future<String>.value(jsonEncode(<String, dynamic>{
          'device_id': 'self',
          'device_name': '本机',
          'device_type': 'desktop',
          'ip_address': '127.0.0.1',
          'port': 8889,
          'discovered_at': '2026-11-12T00:00:00Z',
          'is_online': true,
        }));
      case 'crateApiLanTransferLanTransferGetTrustedDevices':
        return Future<List<String>>.value(<String>[]);
    }
    throw StateError('mock 未配置该 FFI: $name');
  }
}

String _symbolName(Symbol symbol) {
  final text = symbol.toString();
  final match = RegExp(r'Symbol\("(.+?)"\)').firstMatch(text);
  return match?.group(1) ?? text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mock = _MockLanApi();
  late PathProviderPlatform previousPath;
  late ConnectivityPlatform previousConnectivity;

  setUpAll(() {
    RustLib.initMock(api: mock);
  });

  setUp(() {
    mock.calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    previousPath = PathProviderPlatform.instance;
    previousConnectivity = ConnectivityPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider();
    ConnectivityPlatform.instance = _FakeConnectivity();
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPath;
    ConnectivityPlatform.instance = previousConnectivity;
  });

  group('设备轮询只由 ViewModel 驱动（P3-8）', () {
    test('启动服务后 3.5 秒内没有来自服务侧的周期性 getDevices', () async {
      final service = LanTransferService();
      await service.startService();

      // 只有 runSelfCheck（start-service-success）会显式取一次设备列表
      final afterStart = mock.countOf('crateApiLanTransferLanTransferGetDevices');
      expect(afterStart, lessThanOrEqualTo(1),
          reason: '自检最多取一次；服务侧 3s 定时器已删除，不该再多');

      // 跨过一个完整的旧轮询周期（3s），旧实现这里会 +1
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      expect(
        mock.countOf('crateApiLanTransferLanTransferGetDevices'),
        afterStart,
        reason: '服务侧定时器已删除，跨周期后调用数不应增长',
      );

      await service.stopService();
    });

    test('stopService 之后也不再有后台轮询', () async {
      final service = LanTransferService();
      await service.startService();
      await service.stopService();

      final afterStop = mock.countOf('crateApiLanTransferLanTransferGetDevices');
      await Future<void>.delayed(const Duration(milliseconds: 3500));

      expect(mock.countOf('crateApiLanTransferLanTransferGetDevices'), afterStop);
    });

    test('VM 侧仍可显式取设备列表（保留的轮询路径可用）', () async {
      final service = LanTransferService();
      await service.startService();

      final before = mock.countOf('crateApiLanTransferLanTransferGetDevices');
      final devices = await service.getDevices();
      expect(devices, isEmpty);
      expect(mock.countOf('crateApiLanTransferLanTransferGetDevices'), before + 1);

      await service.stopService();
    });
  });
}
