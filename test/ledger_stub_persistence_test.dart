// LedgerStubStore 持久化回归。
//
// 背景：标签 / 模板 / 定时规则 / 附件 / 备份此前**只在内存里**
// （只有 `ledger_stub_enabled` 这一个开关进了 prefs），意味着本机模式下
// 用户加的标签、存的模板、定的定时规则**重启 App 全部丢失**，而且没有任何
// 提示。远程模式下更糟：这些模块还没有节点 action，静默写本机内存后照样
// 提示「成功」，属于假成功。
//
// 这个测试锁住两件事：
//   1. 写操作真的落盘（prefs 里有 `ledger_stub_data` 存档）；
//   2. 模拟进程重启（只清内存、不重新播种）后数据能从磁盘恢复。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自建标签写入后落盘，模拟重启仍可恢复', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LedgerStubStore.instance;
    await store.resetForTest();
    await store.init();

    final groups = await store.listTagGroups();
    expect(groups, isNotEmpty, reason: '播种后应有分组');
    final gid = groups.first.id;

    final createdId = await store.upsertTag(
      LedgerTag(id: 0, name: '持久化验证标签', groupId: gid),
    );
    expect(createdId, greaterThan(0));

    // 存档必须真的写进 prefs
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ledger_stub_data');
    expect(raw, isNotNull, reason: '写标签后必须有落盘存档');
    expect(raw, contains('持久化验证标签'));

    // 模拟重启：只清内存态（不播种），再 init —— 应从磁盘恢复。
    // 注意不能用 resetForTest()：它等于「丢弃内存 + 重新播种」，
    // 那是测试用例之间清零用的，不代表重启语义。
    store.debugClearMemoryForTest();
    await store.init();
    final tags = await store.listTags(groupId: 0);
    expect(
      tags.any((t) => t.name == '持久化验证标签'),
      isTrue,
      reason: '重启后自建标签必须还在（修复前它会丢）',
    );
    // ignore: avoid_print
    print('STUB_PERSIST_OK 标签数=${tags.length}');
  });
}
