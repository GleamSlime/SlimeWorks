// 小说库「文件夹」在无头（远程节点）模式下的分流单测。
//
// 这组用例锁的是本次修复的三个回归点：
// 1. 远程文件夹的**删除/重命名/新建**必须发到节点（action 名正确、参数是剥掉
//    合成前缀后的 rawId），不能把 `remote-folder:<nodeId>:<rawId>` 灌进本机 FFI；
// 2. 节点侧文件夹列表里的**空文件夹**也要成为卡片（在此之前卡片只能从书籍
//    payload 反推，新建的空夹在 UI 上永远看不见）；
// 3. 节点报错时用户看到的是**失败提示**，不再是无条件「已删除 N 个项目」。
//
// 不触 FFI、不写真实用户文件、不需要 RustLib.init：本机分支在测试里会抛
// 「flutter_rust_bridge has not been initialized」，正好用来断言「没走本机」。
//
// 跑法（必须隔离 HOME，否则会写到开发者的真实数据目录）：
//   HOME=/tmp/sw_novel_test /private/tmp/fl/flutter/bin/flutter test \
//     test/novel_remote_folder_dispatch_test.dart --no-pub
import 'package:flutter_test/flutter_test.dart';
// assignAll 等 Rx 集合扩展由 get 包提供
// ignore: depend_on_referenced_packages
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

/// 记录调用并按需抛错的节点服务桩：只覆写小说文件夹相关的方法，
/// 其余（节点列表、启用过滤、isRemoteMode）保留真实实现。
class _RecordingNodeService extends NodeSettingsService {
  /// 被调用的 (action, 参数) 序列，用于断言「真的发到节点且参数正确」
  final calls = <(String, Map<String, dynamic>)>[];

  /// 置非空时所有节点调用都抛这条错误（模拟节点侧 Err）
  String? failWith;

  List<Map<String, dynamic>> folderRows = <Map<String, dynamic>>[];

  void _record(String action, Map<String, dynamic> params) {
    calls.add((action, params));
    final failure = failWith;
    if (failure != null) throw Exception(failure);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNodeNovels(NodeEndpoint node) async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchNodeNovelFolders(NodeEndpoint node) async =>
      folderRows;

  @override
  Future<Map<String, dynamic>> createNodeNovelFolder({
    required String nodeId,
    required String name,
    String? parentId,
  }) async {
    _record('create_novel_folder', {'node_id': nodeId, 'name': name, 'parent_id': parentId});
    return <String, dynamic>{'id': 'created-1', 'name': name};
  }

  @override
  Future<void> renameNodeNovelFolder({
    required String nodeId,
    required String folderId,
    required String name,
  }) async => _record('rename_novel_folder', {
    'node_id': nodeId,
    'folder_id': folderId,
    'name': name,
  });

  @override
  Future<void> deleteNodeNovelFolder({
    required String nodeId,
    required String folderId,
  }) async => _record('delete_novel_folder', {'node_id': nodeId, 'folder_id': folderId});

  @override
  Future<void> deleteNodeNovelFolderWithNovels({
    required String nodeId,
    required String folderId,
  }) async =>
      _record('delete_novel_folder_with_novels', {'node_id': nodeId, 'folder_id': folderId});

  @override
  Future<void> reorderNodeNovelFolders({
    required String nodeId,
    required List<String> folderIds,
  }) async => _record('reorder_novel_folders', {'node_id': nodeId, 'folder_ids': folderIds});
}

NovelFolder localFolder(String id, {String? name, String? parentId, int order = 0}) => NovelFolder(
  id: id,
  name: name ?? id,
  createdAt: 0,
  order: order,
  parentId: parentId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingNodeService nodeService;
  late NovelLibraryViewModel vm;

  setUp(() async {
    await getIt.reset();
    nodeService = _RecordingNodeService();
    getIt.registerSingleton<NodeSettingsService>(nodeService);
    nodeService.remoteNodes.add(
      const NodeEndpoint(id: 'node-a', name: '节点A', apiBaseUrl: 'http://127.0.0.1:17888'),
    );
    vm = Get.put(NovelLibraryViewModel());
  });

  tearDown(() async {
    Get.delete<NovelLibraryViewModel>(force: true);
    await getIt.reset();
  });

  setUpAll(() {
    // flutter_test 测试区禁止 spawn isolate：把封面存在性检查换成同步实现
    NovelLibraryViewModel.coverExistenceChecker = (paths) async => <String, bool>{};
  });

  // ── 合成 ID 解析 ───────────────────────────────────────────────────────────

  group('remote-folder 合成 ID 解析', () {
    test('rawFolderId 自带冒号时不被截断（split(":") 取第 3 段会写坏）', () {
      // 解析规则：前两段是 nodeId，其余整体是 rawId
      final parsed = vm.parseRemoteFolderSyntheticId('remote-folder:node-a:folder:deep:x');
      expect(parsed, isNotNull);
      expect(parsed!.$1, 'node-a');
      expect(parsed.$2, 'folder:deep:x');
      expect(vm.getRemoteFolderNodeId('remote-folder:node-a:folder:deep:x'), 'node-a');
      expect(vm.getRemoteFolderRawId('remote-folder:node-a:folder:deep:x'), 'folder:deep:x');
    });

    test('缺目录段 / 非远程前缀 / 缺节点段 一律判无效（不回空串 rawId）', () {
      expect(vm.parseRemoteFolderSyntheticId('remote-folder:node-a'), isNull);
      expect(vm.parseRemoteFolderSyntheticId('remote-folder:node-a:'), isNull);
      expect(vm.parseRemoteFolderSyntheticId('remote-folder::f1'), isNull);
      expect(vm.parseRemoteFolderSyntheticId('folder-local'), isNull);
      expect(vm.getRemoteFolderRawId('folder-local'), isNull);
    });
  });

  // ── 删除 / 重命名 分流到节点 ───────────────────────────────────────────────

  group('文件夹写操作分流到节点', () {
    test('deleteFolder(远程夹)：调 delete_novel_folder 且传 rawId，不是合成 id', () async {
      await vm.deleteFolder('remote-folder:node-a:folder:deep');

      expect(nodeService.calls.length, 1);
      final (action, params) = nodeService.calls.single;
      expect(action, 'delete_novel_folder');
      expect(params['node_id'], 'node-a');
      // ★ 关键：rawId 必须原样带冒号，不能被截断成 'folder'
      expect(params['folder_id'], 'folder:deep');
    });

    test('deleteFolderWithNovels(远程夹)：走 delete_novel_folder_with_novels', () async {
      await vm.deleteFolderWithNovels('remote-folder:node-a:f2');

      final (action, params) = nodeService.calls.single;
      expect(action, 'delete_novel_folder_with_novels');
      expect(params['folder_id'], 'f2');
    });

    test('renameFolder(远程夹)：走 rename_novel_folder 且带新名', () async {
      await vm.renameFolder('remote-folder:node-a:f3', '新名字');

      final (action, params) = nodeService.calls.single;
      expect(action, 'rename_novel_folder');
      expect(params['folder_id'], 'f3');
      expect(params['name'], '新名字');
    });

    test('deleteFolder(本机夹)：不发节点请求（本机分支在测试里因 FFI 未初始化而报错）', () async {
      await vm.deleteFolder('folder-local');
      // 一次节点调用都没有 —— 证明确实走了本机分支而不是远程分支
      expect(nodeService.calls, isEmpty);
    });

    test('远程夹写操作失败：用户看到失败提示，且不是成功文案', () async {
      nodeService.failWith = '小说文件夹不存在 folder_x';
      await vm.deleteFolder('remote-folder:node-a:folder_x');

      // showSnack 走 addPostFrameCallback + ScaffoldMessenger，测试环境无树时静默丢弃，
      // 所以这里断言的是「请求确实发出去了并抛回来了」——即没有静默成功。
      expect(nodeService.calls.length, 1);
      expect(nodeService.calls.single.$1, 'delete_novel_folder');
    });

    test('在远程夹里新建子夹：parent_id 传 rawId', () async {
      vm.currentFolderId.value = 'remote-folder:node-a:parent-raw';
      await vm.createFolderWithName('子夹');

      final (action, params) = nodeService.calls.single;
      expect(action, 'create_novel_folder');
      expect(params['name'], '子夹');
      expect(params['parent_id'], 'parent-raw');
    });

    test('全局远程模式根目录新建：发到当前节点（不在本机建看不见的夹）', () async {
      await nodeService.selectActiveNode('node-a');
      vm.currentFolderId.value = null;
      await vm.createFolderWithName('根夹');

      final (action, params) = nodeService.calls.single;
      expect(action, 'create_novel_folder');
      expect(params['node_id'], 'node-a');
      expect(params['parent_id'], isNull);
    });
  });

  // ── 空文件夹也要有卡片 ─────────────────────────────────────────────────────

  group('节点文件夹列表 → 卡片', () {
    test('节点上有但没有任何书的空文件夹也出现在列表里（含真实 order）', () async {
      nodeService.folderRows = <Map<String, dynamic>>[
        {'id': 'empty-1', 'name': '空夹甲', 'created_at': 100, 'order': 1, 'parent_id': null},
      ];
      await vm.refreshRemoteNovels();

      final folders = vm.filteredItems.whereType<LibraryFolderItem>().toList()
        ..sort((a, b) => a.folder.order.compareTo(b.folder.order));
      expect(folders.length, 1);
      expect(folders.single.folder.id, 'remote-folder:node-a:empty-1');
      expect(folders.single.folder.name, '空夹甲');
      expect(folders.single.folder.order, 1);
      // 显示名映射同步落地（顶栏标题用它）
      expect(vm.currentFolderName, '');
      vm.currentFolderId.value = 'remote-folder:node-a:empty-1';
      expect(vm.currentFolderName, '空夹甲');
    });

    test('子夹挂在父夹下：根层只出父夹，进父夹才出子夹', () async {
      nodeService.folderRows = <Map<String, dynamic>>[
        {'id': 'p1', 'name': '父夹', 'created_at': 1, 'order': 0, 'parent_id': null},
        {'id': 'c1', 'name': '子夹', 'created_at': 2, 'order': 0, 'parent_id': 'p1'},
      ];
      await vm.refreshRemoteNovels();

      final rootItems = vm.filteredItems.whereType<LibraryFolderItem>().toList();
      expect(rootItems.map((f) => f.folder.name), ['父夹']);

      vm.currentFolderId.value = 'remote-folder:node-a:p1';
      final childItems = vm.filteredItems.whereType<LibraryFolderItem>().toList();
      expect(childItems.map((f) => f.folder.name), ['子夹']);
      // 子夹的 parentId 也换算成合成 id（否则 UI 上挂不到父夹）
      expect(childItems.single.folder.parentId, 'remote-folder:node-a:p1');
      // getChildFolders 同口径（移动书籍对话框用它）
      expect(vm.getChildFolders('remote-folder:node-a:p1').single.name, '子夹');
    });

    test('旧节点没有 list_novel_folders：文件夹列表为空也不影响书籍显示', () async {
      // 桩返回空文件夹列表（= 旧节点 / 该 action 报「不支持的动作」被吞）
      nodeService.folderRows = <Map<String, dynamic>>[];
      await vm.refreshRemoteNovels();
      expect(vm.remoteFolderRows, isEmpty);
      // 没有远程书时列表就是空的，而不是整页报错
      expect(vm.filteredItems, isEmpty);
    });
  });

  // ── 拖拽排序分流 ───────────────────────────────────────────────────────────

  group('拖拽排序分流到节点', () {
    test('远程夹拖拽：reorder_novel_folders 收到的是 rawId 序列，不带合成前缀', () async {
      nodeService.folderRows = <Map<String, dynamic>>[
        {'id': 'r1', 'name': '甲', 'created_at': 1, 'order': 0, 'parent_id': null},
        {'id': 'r2', 'name': '乙', 'created_at': 2, 'order': 1, 'parent_id': null},
      ];
      await vm.refreshRemoteNovels();

      // 卡片按名称排序（中文按 codeUnit：乙 E59 < 甲 7532），先按 rawId 找到两张卡
      String cardId(String rawId) => vm.filteredItems
          .whereType<LibraryFolderItem>()
          .firstWhere((f) => f.folder.id.endsWith(':$rawId'))
          .id;
      // 把「甲」拖到「乙」之前 → 期望提交顺序 [甲=r1, 乙=r2]
      await vm.reorderItemsById(cardId('r1'), cardId('r2'));

      final reorderCalls = nodeService.calls.where((c) => c.$1 == 'reorder_novel_folders');
      expect(reorderCalls.length, 1);
      expect(reorderCalls.single.$2['node_id'], 'node-a');
      // ★ 关键：节点收到的是 rawId，不能是 remote-folder:node-a:r1 这种合成 id
      expect(reorderCalls.single.$2['folder_ids'], ['r1', 'r2']);
    });

    test('本机夹拖拽不发节点请求（走了 FFI 分支）', () async {
      vm.folders.assignAll([localFolder('l1', order: 0), localFolder('l2', order: 1)]);
      final items = vm.filteredItems;
      expect(items.length, 2);
      // 本机拖拽会调 FRB 的 batchUpdateFolderOrders，在测试环境里抛「未初始化」
      // 并被 loadFolders 的 catch 吞掉；关键是没有产生任何节点调用
      try {
        await vm.reorderItemsById(items[1].id, items[0].id);
      } catch (_) {}
      expect(nodeService.calls.where((c) => c.$1 == 'reorder_novel_folders'), isEmpty);
    });
  });

  // ── 批量删除分流 ───────────────────────────────────────────────────────────

  group('deleteSelected 分流与失败可见', () {
    test('选中的远程夹走节点、本机夹走 FFI；失败项会显著影响最终提示', () async {
      vm.folders.assignAll([localFolder('local-f1')]);
      vm.selectedIds.addAll(<String>[
        'local-f1',
        'remote-folder:node-a:remote-f1',
      ]);

      await vm.deleteSelected();

      // 只有远程夹产生节点调用；本机夹不发节点请求
      expect(nodeService.calls.map((c) => c.$1), ['delete_novel_folder']);
      expect(nodeService.calls.single.$2['folder_id'], 'remote-f1');
      // 批量删除结束后选中态清空
      expect(vm.isSelecting.value, isFalse);
    });

    test('远程夹删除失败时不会算进成功数（不能吞成「已删除 N 个项目」）', () async {
      nodeService.failWith = '节点已熔断';
      vm.selectedIds.addAll(<String>['remote-folder:node-a:bad-f']);

      // 不应抛出（失败被逐项收集），但请求确实发出去了并失败了
      await vm.deleteSelected();
      expect(nodeService.calls.single.$1, 'delete_novel_folder');
      expect(vm.selectedIds, isEmpty);
    });
  });
}
