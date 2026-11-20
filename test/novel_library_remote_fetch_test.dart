// 「远程节点获取不到书库」回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个测试锁的是什么
// ═══════════════════════════════════════════════════════════════════════════
// `NovelLibraryViewModel.onInitAsync()` 只由 `BasePage.onPageInit()` 调用。
// 而 `NovelLibraryPage` 原本是 **StatelessWidget**（不是 BasePage 子类），
// 于是 `onInitAsync()` **一次都没被触发过**：
//   · `refreshRemoteNovels()` 从不执行 → 远程模式书库**永远是空的**；
//   · 本机模式靠 `loadNovels()` 直接读 FFI，看起来正常，把问题盖住了。
// 用户视角：切到远程节点进书库 → 一本都没有，也不报错。
//
// 修法：页面改成 StatefulWidget，在 `initState` 里显式触发一次
// `onInitAsync()`（并 `unawaited(...).catchError` 把异常捞出来）。
//
// ★ 顺带记一个排查时踩的大坑：**`flutter_test` 会注入 HTTP mock，
//   把所有真实 HTTP 请求返回 400（body 为空）**。于是任何「用 flutter test
//   打真实节点」的验证都会以 400 失败，看起来像业务 bug。要测真实网络必须
//   `HttpOverrides.global = null`（本仓库的 ledger_service_test /
//   node_auth_code_test 也都这么做）。这个假象曾经让我误判了好几轮。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

/// 桩节点服务：只把「远程书列表」换成内存数据，其余逻辑保持真实。
class _StubNodeSettingsService extends NodeSettingsService {
  List<Map<String, dynamic>> novelsPayload = <Map<String, dynamic>>[];

  @override
  bool get isRemoteMode => true;

  @override
  List<NodeEndpoint> get dataRemoteNodes => const <NodeEndpoint>[
    NodeEndpoint(id: 'node-a', name: '桩节点', apiBaseUrl: 'http://127.0.0.1:1'),
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchNodeNovels(NodeEndpoint node) async =>
      novelsPayload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('远程模式下 VM 初始化后必须把节点上的书装进 remoteNovels', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final stub = _StubNodeSettingsService()
      ..novelsPayload = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'n1',
          'title': '远程书一',
          'file_path': '/node/books/1.txt',
          'format': 'txt',
          'progress': 0.0,
        },
        <String, dynamic>{
          'id': 'n2',
          'title': '远程书二',
          'file_path': '/node/books/2.txt',
          'format': 'txt',
          'progress': 0.3,
        },
      ];
    // 与生产路径一致：通过 getIt 注入桩服务，再用 Get.put 让 onInit 生效
    getIt.registerSingleton<NodeSettingsService>(stub);
    final vm = Get.put(NovelLibraryViewModel());

    await vm.onInitAsync();
    await vm.debugWaitRemoteRefresh();

    expect(
      vm.isInitialized,
      isTrue,
      reason: 'onInitAsync 必须真正跑完（页面没触发它正是原 bug）',
    );
    expect(
      vm.remoteNovels.length,
      2,
      reason: '远程模式下列表只能来自节点，必须把节点的书装进来',
    );
    expect(
      vm.remoteNovels.map((n) => n.title).toSet(),
      <String>{'远程书一', '远程书二'},
    );
    // 合并后的列表（页面真正渲染的那一份）也要有
    expect(
      vm.filteredItems.whereType<LibraryBookItem>().length,
      2,
      reason: 'filteredItems 是页面渲染源，必须包含这 2 本',
    );

    Get.delete<NovelLibraryViewModel>(force: true);
  });

  test('书籍库页面必须自己触发 VM 初始化（原 bug 的直接断言）', () async {
    // 原 bug：NovelLibraryPage 是 StatelessWidget，而 onInitAsync 只由
    // BasePage.onPageInit 调用 → 初始化从不发生 → 远程书库恒空。
    //
    // 这里不做 widget pump：本页依赖 ScreenChrome 的 provider，裸 pump 会因为
    // LateInitializationError('_data') 失败，那是测试夹具缺失、不是被测行为。
    // 改为直接检查源码契约：页面必须是 StatefulWidget，且 initState 里调了
    // onInitAsync。改动一旦退回 StatelessWidget / 删掉调用，这条立刻红。
    final src = File('lib/pages/novel_library/novel_library_page.dart')
        .readAsStringSync();
    expect(
      src.contains('class NovelLibraryPage extends StatefulWidget'),
      isTrue,
      reason: '页面必须是 StatefulWidget，否则 initState 里的初始化永远不会执行',
    );
    expect(
      src.contains('void initState()'),
      isTrue,
      reason: '需要在 initState 里触发 VM 初始化',
    );
    expect(
      src.contains('onInitAsync()'),
      isTrue,
      reason: '页面的 initState 必须调用 onInitAsync()（原 bug 就是漏了这一步）',
    );
  });
}
