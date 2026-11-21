// 移动端 / 桌面端的「本机」节点语义回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 用户报的两个症状（都是这次修的）
// ═══════════════════════════════════════════════════════════════════════════
// 1. **移动端切到「本机」→ 书库/媒体库一个都读不到**
//    移动端没有本机数据源（Rust 侧数据目录在 iOS/Android 上没有可用落点，
//    业务代码里也明确写着「移动端没有本机媒体库」）。但侧栏节点选择器仍然
//    无条件列出「本机」，用户选中后 `activeNodeId` 变成空串：
//    `isRemoteMode` 变 false → 本机 FFI 读出来是空 → 页面全空、也不报错。
//
// 2. **移动端切到另一个远程节点后，还是能读到「本机」的媒体库**
//    更准确地说是：切到「本机」时 `dataRemoteNodes` 会退化成
//    `enabledRemoteNodes`（全部启用节点），媒体库把这些节点全拼进列表。
//    桌面端这是设计如此（用户确认保留聚合），移动端没有这个语义。
//
// 修法（用户已确认方向）：
//   · 移动端**隐藏**「本机」选项，`selectActiveNode('')` 也直接拒绝；
//   · 移动端 `_validateActiveNode` 在 activeNodeId 为空/节点失效时，
//     自动落到第一个启用节点，别让用户停在空白页；
//   · 桌面端**保留**「本机 = 本机 + 全部启用节点」的聚合行为不变。
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

/// 造一个只有内存节点、不做网络探测的服务实例。
Future<NodeSettingsService> makeService({
  required bool mobile,
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'node_local_enabled': false,
    ...prefs,
  });
  final svc = NodeSettingsService()..mobilePlatformProbe = () => mobile;
  await svc.init();
  return svc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('移动端（没有本机数据源）', () {
    test('不允许切到「本机」：selectActiveNode("") 被拒绝', () async {
      final svc = await makeService(mobile: true);
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '节点A', apiBaseUrl: 'http://127.0.0.1:1'),
      );
      await svc.selectActiveNode('n1');
      expect(svc.isRemoteMode, isTrue);

      await svc.selectActiveNode('');

      expect(
        svc.activeNodeId.value,
        'n1',
        reason: '移动端选「本机」必须无效，否则所有数据页会变成全空',
      );
      expect(svc.isRemoteMode, isTrue);
    });

    test('activeNodeId 为空时自动落到第一个启用节点', () async {
      // 模拟「旧版本把本机存进了 activeNodeId」的升级场景
      final svc = await makeService(mobile: true);
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '节点A', apiBaseUrl: 'http://127.0.0.1:1'),
      );
      expect(svc.activeNodeId.value, isEmpty);

      // 任何一次配置变化都会走 _validateActiveNode
      await svc.updateRemoteNode(svc.getNodeById('n1')!);

      expect(
        svc.activeNodeId.value,
        'n1',
        reason: '移动端停在「本机」= 全空界面，必须自动落到一个节点',
      );
    });

    test('当前节点被禁用时落到另一个启用节点，而不是回本机', () async {
      final svc = await makeService(mobile: true);
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '节点A', apiBaseUrl: 'http://127.0.0.1:1'),
      );
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n2', name: '节点B', apiBaseUrl: 'http://127.0.0.1:2'),
      );
      await svc.selectActiveNode('n1');

      await svc.updateRemoteNode(
        svc.getNodeById('n1')!.copyWith(enabled: false),
      );

      expect(svc.isRemoteMode, isTrue, reason: '移动端不该回落到本机');
      expect(svc.activeNodeId.value, 'n2');
    });
  });

  group('桌面端（保留本机聚合语义）', () {
    test('允许切到「本机」，且本机模式聚合全部启用节点', () async {
      final svc = await makeService(mobile: false);
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '节点A', apiBaseUrl: 'http://127.0.0.1:1'),
      );
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n2', name: '节点B', apiBaseUrl: 'http://127.0.0.1:2'),
      );
      await svc.selectActiveNode('n1');
      await svc.selectActiveNode('');

      expect(svc.isRemoteMode, isFalse, reason: '桌面端必须仍能切回本机');
      expect(
        svc.dataRemoteNodes.map((n) => n.id).toList(),
        <String>['n1', 'n2'],
        reason: '桌面端本机模式保留「本机 + 全部启用节点」的聚合（用户已确认）',
      );
    });

    test('远程模式只取当前节点', () async {
      final svc = await makeService(mobile: false);
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n1', name: '节点A', apiBaseUrl: 'http://127.0.0.1:1'),
      );
      svc.remoteNodes.add(
        NodeEndpoint(id: 'n2', name: '节点B', apiBaseUrl: 'http://127.0.0.1:2'),
      );
      await svc.selectActiveNode('n2');

      expect(svc.dataRemoteNodes.map((n) => n.id).toList(), <String>['n2']);
    });
  });
}
