import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/node/headless_node_launcher.dart';

void main() {
  group('HeadlessNodeLauncher.buildArguments', () {
    test('带上端口、名称与授权码', () {
      final args = HeadlessNodeLauncher.buildArguments(
        port: 17888,
        name: '客厅 NAS',
        authCode: 'ABCD-1234',
      );

      expect(args, containsAllInOrder(['--host', '0.0.0.0']));
      expect(args, containsAllInOrder(['--port', '17888']));
      expect(args, containsAllInOrder(['--name', '客厅 NAS']));
      expect(args, containsAllInOrder(['--auth', 'ABCD-1234']));
      // 未指定目录时不传，让子进程继承客户端环境，数据目录天然一致
      expect(args, isNot(contains('--data-dir')));
      expect(args, isNot(contains('--log-dir')));
    });

    test('授权码为空时不生成 --auth，避免节点误开启校验', () {
      final args = HeadlessNodeLauncher.buildArguments(
        port: 17888,
        name: '   ',
        authCode: '  ',
      );

      expect(args, isNot(contains('--auth')));
      // 名称空白回落默认名，不能给节点传空名
      expect(args, containsAllInOrder(['--name', '本机节点']));
    });

    test('指定目录时追加对应参数', () {
      final args = HeadlessNodeLauncher.buildArguments(
        port: 18000,
        name: 'NAS',
        authCode: 'CODE',
        dataDir: '/mnt/slime',
        logDir: '/mnt/slime/logs',
      );

      expect(args, containsAllInOrder(['--data-dir', '/mnt/slime']));
      expect(args, containsAllInOrder(['--log-dir', '/mnt/slime/logs']));
    });
  });
}
