// 书库 ViewModel 可测逻辑切片单测。
//
// 设计约束（不触发 FFI / 不写真实用户文件 / 不需要 RustLib.init）：
// - NovelLibraryViewModel 构造仅依赖 getIt<NodeSettingsService>()，
//   其构造函数为纯内存操作，测试里注册桩子类覆写 fetchNodeNovels 返回
//   内存 payload，enabledRemoteNodes 等纯逻辑保留真实实现。
// - refreshRemoteNovels / _buildRemoteNovelModel / _parseChapterCount 等
//   私有环节全部经 refreshRemoteNovels 公开入口触达。
// - 关键词规则的"有效新增/删除"路径会写真实 $HOME/slimeworks 文件，
//   测试环境无法重定向 HOME，因此只覆盖"提前返回、不落盘"的守卫分支。
// - 任何触达 novel_reader FRB 的调用均被 VM 自身 try/catch 吞掉，
//   个别用例专门锁定"FFI 不可用时不误打标"的行为。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// assignAll 等 Rx 集合扩展由 get 包提供（VM 内部同样依赖该扩展）
// ignore: depend_on_referenced_packages
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

/// 桩节点服务：远程书架取数走内存桩，节点列表/启用过滤保留真实实现。
class _StubNodeSettingsService extends NodeSettingsService {
  List<Map<String, dynamic>> novelsPayload = <Map<String, dynamic>>[];
  bool throwOnFetch = false;

  @override
  Future<List<Map<String, dynamic>>> fetchNodeNovels(NodeEndpoint node) async {
    if (throwOnFetch) throw Exception('节点离线');
    return novelsPayload;
  }
}

// ── 数据构造辅助 ─────────────────────────────────────────────────────────────

NovelMetadata novel(
  String id, {
  String? title,
  String? folderId,
  int addedAt = 0,
  int fileSize = 0,
  bool isFavorite = false,
  List<String> tags = const [],
  int? customOrder,
  String? coverPath,
  NovelFormat format = NovelFormat.txt,
}) {
  return NovelMetadata(
    id: id,
    title: title ?? id,
    filePath: '/lib/$id.txt',
    format: format,
    fileSize: BigInt.from(fileSize),
    modifiedAt: 0,
    addedAt: addedAt,
    progress: 0,
    coverPath: coverPath,
    folderId: folderId,
    customOrder: customOrder,
    isFavorite: isFavorite,
    tags: tags,
  );
}

NovelFolder dir(
  String id, {
  String? name,
  String? parentId,
  int order = 0,
  int createdAt = 0,
}) {
  return NovelFolder(
    id: id,
    name: name ?? id,
    createdAt: createdAt,
    order: order,
    parentId: parentId,
  );
}

Map<String, dynamic> payload(
  String id, {
  Object? folderId,
  Object? folderName,
  Object? folderTitle,
  Object? chapterCount,
  String chapterCountKey = 'chapter_count',
  String title = '远程书',
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    if (folderId != null) 'folder_id': folderId,
    if (folderName != null) 'folder_name': folderName,
    if (folderTitle != null) 'folder_title': folderTitle,
    if (chapterCount != null) chapterCountKey: chapterCount,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubNodeSettingsService nodeService;
  late NovelLibraryViewModel vm;
  late Directory tmpDir;

  setUp(() async {
    await getIt.reset();
    nodeService = _StubNodeSettingsService();
    getIt.registerSingleton<NodeSettingsService>(nodeService);
    vm = NovelLibraryViewModel();
  });

  tearDown(() async {
    await getIt.reset();
  });

  setUpAll(() {
    tmpDir = Directory.systemTemp.createTempSync('novel_library_logic_test');
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  /// 挂载一个测试节点并用桩 payload 刷新远程书架（不发真实 HTTP）。
  Future<void> mountNodeAndRefresh({
    List<Map<String, dynamic>> novels = const [],
    bool throwOnFetch = false,
  }) async {
    nodeService
      ..novelsPayload = novels
      ..throwOnFetch = throwOnFetch;
    nodeService.remoteNodes.add(
      const NodeEndpoint(id: 'node-a', name: '节点A', apiBaseUrl: 'http://127.0.0.1:17888'),
    );
    await vm.refreshRemoteNovels();
  }

  // ── 远程 ID 解析 ───────────────────────────────────────────────────────────

  group('远程 ID 解析', () {
    test('isRemoteNovel / getNovelNodeName / getRemoteNodeId / getRemoteRawNovelId', () async {
      // rawId 自带冒号：合成 ID 再嵌套冒号时映射表仍取原始值
      await mountNodeAndRefresh(novels: [payload('abc:def'), payload('plain')]);
      const withColon = 'remote:node-a:abc:def';
      const plain = 'remote:node-a:plain';
      expect(vm.isRemoteNovel(withColon), isTrue);
      expect(vm.isRemoteNovel(plain), isTrue);
      expect(vm.isRemoteNovel('local-1'), isFalse);
      expect(vm.getRemoteNodeId(withColon), 'node-a');
      expect(vm.getNovelNodeName(withColon), '节点A');
      expect(vm.getRemoteRawNovelId(withColon), 'abc:def');
      expect(vm.getRemoteRawNovelId(plain), 'plain');
      expect(vm.getNovelNodeName('ghost'), isNull);
      expect(vm.getRemoteNodeId('ghost'), isNull);
      expect(vm.getRemoteRawNovelId('ghost'), isNull);
    });

    test('isRemoteFolderId 前缀判定', () {
      expect(vm.isRemoteFolderId('remote-folder:node-a:f1'), isTrue);
      expect(vm.isRemoteFolderId('folder-1'), isFalse);
      expect(vm.isRemoteFolderId('remote-folder:'), isTrue); // 仅前缀也算远程形态
    });

    test('远程目录分组：常规合成 ID 因解析段标偏移而恒为空（缺陷证据）', () async {
      // _parseRemoteFolderSyntheticId 取 parts[2] 当 nodeId，但合成 ID
      // 'remote-folder:<nodeId>:<folderId>' 的 nodeId 在 parts[1]，且段数判定为 <4：
      // 常规远程目录（folder 段不含冒号）解析直接判无效 → 落本地分支 → 0 本；
      // 带冒号的深层 folderId 则 nodeId 错位也取不到书。
      // 本用例锁定现状，修复实现时此用例应随之失败提醒更新。
      await mountNodeAndRefresh(
        novels: [
          payload('n1', folderId: 'sub:deep'),
          payload('n2', folderId: 'sub:deep'),
          payload('n3', folderId: 'other'),
        ],
      );
      expect(vm.getFolderNovelCount('remote-folder:node-a:sub:deep'), 0);
      expect(vm.getFolderNovelCount('remote-folder:node-a:other'), 0);
      expect(vm.getFolderNovelCount('remote-folder:node-b:sub:deep'), 0);
    });

    test('解析分支即便命中节点段，目录尾段也与原始 folderId 错位（分组恒空）', () async {
      // 令 folder_id 以 '<nodeId>:' 开头：合成卡片 ID
      // 'remote-folder:node-a:node-a:f1' 解析出 nodeId='node-a'（段标恰好碰对），
      // 但目录段被截成 'f1'，与书籍原始 folderId 'node-a:f1' 不再相等 → 0 本。
      // 结论：_parseRemoteFolderSyntheticId 段标偏移使远程分组分支不可能命中，
      // 远程目录卡片点开后书籍列表恒为空 —— 锁定现状作缺陷证据。
      await mountNodeAndRefresh(novels: [payload('n1', folderId: 'node-a:f1')]);
      expect(vm.getFolderNovelCount('remote-folder:node-a:node-a:f1'), 0);
      // 本地书籍同样不受该分支影响
      vm.novels.assignAll([novel('l1', folderId: 'node-a:f1')]);
      expect(vm.getFolderNovelCount('remote-folder:node-a:node-a:f1'), 0);
    });

    test('无法解析的远程目录 ID（缺目录段）落到本地分组分支返回 0', () async {
      await mountNodeAndRefresh(novels: [payload('n1', folderId: 'f1')]);
      // 'remote-folder:node-a' 只有 3 段，_parseRemoteFolderSyntheticId 判无效，
      // 于是按本地分支查 novels.folderId == 'remote-folder:node-a' → 0 本
      expect(vm.getFolderNovelCount('remote-folder:node-a'), 0);
    });

    test('currentFolderName：本地按 folders 查名，远程按显示名映射，未知为空串', () async {
      await mountNodeAndRefresh(
        novels: [payload('n1', folderId: 'f1', folderName: '有声书目录')],
      );
      vm.folders.assignAll([dir('f-local', name: '本地夹')]);

      vm.currentFolderId.value = 'f-local';
      expect(vm.currentFolderName, '本地夹');
      vm.currentFolderId.value = 'remote-folder:node-a:f1';
      expect(vm.currentFolderName, '有声书目录');
      // 前缀是远程但映射不存在 → 空串（不回退查本地表）
      vm.currentFolderId.value = 'remote-folder:node-a:ghost';
      expect(vm.currentFolderName, '');
      vm.currentFolderId.value = null;
      expect(vm.currentFolderName, '');
    });
  });

  // ── refreshRemoteNovels：payload → NovelMetadata 转换 ─────────────────────

  group('refreshRemoteNovels 数据转换', () {
    test('字段映射：format 兜底 / 大数与坏数 / 封面 dataURI / tags 去空白 / 严格 isFavorite', () async {
      await mountNodeAndRefresh(
        novels: [
          {
            'id': 'r1',
            'title': '全字段书',
            'author': '某作者',
            'format': 'EPUB',
            'file_size': '18446744073709551616',
            'modified_at': '42',
            'added_at': '7',
            'last_read_at': '99',
            'progress': 0.35,
            'tags': [' 汉 ', '', '   ', '科幻'],
            'folder_id': 'f1',
            'cover_base64': 'AAAB',
            'cover_ext': 'webp',
            'custom_order': 5,
            'is_favorite': true,
            'notes': '备注',
            'file_path': '/node/r1.epub',
          },
          {
            'id': 'r2',
            'format': 'pdf', // 未知格式 → txt
            'file_size': 'abc', // BigInt 解析失败 → 0
            'progress': '50%', // 非 num → 0
            'custom_order': '5', // 非 int → null
            'is_favorite': 1, // 严格 ==true 判定 → false
            'folder_id': '', // 空串 → null 归根
            'cover_path': '/node/r2.png', // 无 base64 时回退 cover_path
          },
          {'id': ''}, // 空 id → 跳过
        ],
      );

      expect(vm.remoteNovels.length, 2);
      final full = vm.remoteNovels.firstWhere((n) => n.id == 'remote:node-a:r1');
      expect(full.format, NovelFormat.epub);
      expect(full.fileSize, BigInt.parse('18446744073709551616'));
      expect(full.modifiedAt, 42);
      expect(full.addedAt, 7);
      expect(full.lastReadAt, 99);
      expect(full.progress, 0.35);
      expect(full.tags, [' 汉 ', '科幻']); // 只按 trim 非空过滤，不裁剪首尾空格
      expect(full.folderId, 'f1');
      expect(full.coverPath, 'data:image/webp;base64,AAAB');
      expect(full.customOrder, 5);
      expect(full.isFavorite, isTrue);
      expect(full.author, '某作者');
      expect(full.notes, '备注');

      final minimal = vm.remoteNovels.firstWhere((n) => n.id == 'remote:node-a:r2');
      expect(minimal.format, NovelFormat.txt);
      expect(minimal.fileSize, BigInt.zero);
      expect(minimal.title, '未命名书籍'); // 缺 title 兜底
      expect(minimal.progress, 0);
      expect(minimal.customOrder, isNull);
      expect(minimal.isFavorite, isFalse);
      expect(minimal.folderId, isNull);
      expect(minimal.coverPath, '/node/r2.png');
      expect(minimal.lastReadAt, isNull);
      expect(minimal.tags, isEmpty);
    });

    test('节点拉取抛错被吞，远程列表清空', () async {
      await mountNodeAndRefresh(novels: [payload('r1')]);
      expect(vm.remoteNovels.length, 1);
      await mountNodeAndRefresh(throwOnFetch: true);
      expect(vm.remoteNovels, isEmpty);
      expect(vm.remoteNovelNodeId, isEmpty);
      expect(vm.remoteFolderDisplayNames, isEmpty);
    });

    test('目录显示名：folder_name 优先，folder_title 次之，均缺回退"远程目录"', () async {
      await mountNodeAndRefresh(
        novels: [
          payload('a', folderId: 'f-a', folderName: '甲目录'),
          payload('b', folderId: 'f-b', folderTitle: '乙标题'),
          payload('c', folderId: 'f-c'),
        ],
      );
      expect(vm.remoteFolderDisplayNames['remote-folder:node-a:f-a'], '甲目录');
      expect(vm.remoteFolderDisplayNames['remote-folder:node-a:f-b'], '乙标题');
      expect(vm.remoteFolderDisplayNames['remote-folder:node-a:f-c'], '远程目录');
    });

    test('_parseChapterCount 经 refresh 触达：多候选键 / int / num / 字符串 / 坏值', () async {
      await mountNodeAndRefresh(
        novels: [
          payload('c1', chapterCount: 12),
          payload('c2', chapterCount: '34', chapterCountKey: 'chapters_count'),
          payload('c3', chapterCount: 5.7, chapterCountKey: 'chapterCount'),
          payload('c4', chapterCount: 'bad', chapterCountKey: 'chaptersCount'),
          payload('c5', chapterCount: 3, chapterCountKey: 'chapter_total'),
        ],
      );
      expect(vm.getNovelChapterCount('remote:node-a:c1'), 12);
      expect(vm.getNovelChapterCount('remote:node-a:c2'), 34);
      expect(vm.getNovelChapterCount('remote:node-a:c3'), 5); // num → toInt 截断
      expect(vm.getNovelChapterCount('remote:node-a:c4'), isNull); // 坏值不登记
      expect(vm.getNovelChapterCount('remote:node-a:c5'), 3);
      expect(vm.getNovelChapterCount('ghost'), isNull);
    });

    test('重刷后旧远程条目章节数被清理，本地章节数保留', () async {
      vm.chapterCountMap.addAll({'local-novel': 7});
      await mountNodeAndRefresh(
        novels: [payload('a', chapterCount: 1), payload('b', chapterCount: 2)],
      );
      expect(vm.chapterCountMap['remote:node-a:b'], 2);
      // 第二次刷新只剩 a：b 的映射消失，其章节数应随之清理
      await mountNodeAndRefresh(novels: [payload('a', chapterCount: 9)]);
      expect(vm.chapterCountMap.containsKey('remote:node-a:b'), isFalse);
      expect(vm.chapterCountMap['remote:node-a:a'], 9);
      expect(vm.chapterCountMap['local-novel'], 7); // 非远程来源不清理
    });
  });

  // ── filteredItems：根目录结构与搜索分流 ───────────────────────────────────

  group('filteredItems 根目录', () {
    test('本地文件夹按 order 升序、同 order 按 createdAt 降序，书籍排最后', () {
      vm.folders.assignAll([
        dir('f1', order: 1, createdAt: 100),
        dir('f2', order: 0, createdAt: 50),
        dir('f3', order: 0, createdAt: 90),
      ]);
      vm.novels.assignAll([novel('b1', folderId: null)]);
      final items = vm.filteredItems;
      expect(items.map((i) => i.id).toList(), ['f3', 'f2', 'f1', 'b1']);
      expect(items[0], isA<LibraryFolderItem>());
      expect(items.last, isA<LibraryBookItem>());
    });

    test('远程目录卡片按名称小写排序，位于本地夹后、书籍前，同目录去重', () async {
      vm.folders.assignAll([dir('lf', name: '本地')]);
      await mountNodeAndRefresh(
        novels: [
          payload('n1', folderId: 'zz', folderName: 'zeta'),
          payload('n2', folderId: 'zz', folderName: 'zeta'), // 同目录只出一张卡
          payload('n3', folderId: 'aa', folderName: 'Alpha'),
          payload('n4'), // 无目录 → 根书籍
        ],
      );
      final items = vm.filteredItems;
      expect(items.map((i) => i.id).toList(), [
        'lf',
        'remote-folder:node-a:aa',
        'remote-folder:node-a:zz',
        'remote:node-a:n4',
      ]);
    });

    test('选中过滤标签时隐藏所有文件夹卡片', () {
      vm.folders.assignAll([dir('lf')]);
      vm.novels.assignAll([novel('b1', folderId: null, tags: ['汉'])]);
      vm.selectedFilterTags.assignAll(['汉']);
      final items = vm.filteredItems;
      expect(items.every((i) => i is LibraryBookItem), isTrue);
      expect(items.map((i) => i.id).toList(), ['b1']);
    });

    test('标题搜索忽略大小写并合并本地与远程；空关键词不触发搜索分支', () async {
      vm.novels.assignAll([novel('l1', title: 'Trigger Happy'), novel('l2', title: '无关')]);
      await mountNodeAndRefresh(
        novels: [payload('r1', title: 'MY trigger Book'), payload('r2', title: '别的')],
      );
      vm.searchQuery.value = 'TRIGGER';
      expect(vm.filteredItems.map((i) => i.id).toSet(), {'l1', 'remote:node-a:r1'});
      vm.searchQuery.value = '';
      expect(vm.filteredItems.length, greaterThanOrEqualTo(4));
    });

    test('searchByContent 走内容结果列表，并叠加 tag/收藏过滤', () {
      vm.contentSearchResults.assignAll([
        novel('c1', title: '任意', tags: ['汉'], isFavorite: true),
        novel('c2', title: '任意', tags: ['日']),
      ]);
      vm.searchQuery.value = '不存在的词'; // 内容模式下标题词不参与
      vm.searchByContent.value = true;
      expect(vm.filteredItems.map((i) => i.id).toSet(), {'c1', 'c2'});
      vm.selectedFilterTags.assignAll(['汉']);
      expect(vm.filteredItems.map((i) => i.id).toList(), ['c1']);
      vm.selectedFilterTags.clear();
      vm.showFavoritesOnly.value = true;
      expect(vm.filteredItems.map((i) => i.id).toList(), ['c1']);
    });

    test('文件夹内只列直属书籍（不含子夹书籍），子文件夹不进列表', () async {
      vm.folders.assignAll([dir('f1'), dir('f2', parentId: 'f1')]);
      vm.novels.assignAll([
        novel('in-f1', folderId: 'f1'),
        novel('in-f2', folderId: 'f2'),
        novel('root', folderId: null),
      ]);
      vm.enterFolder('f1');
      expect(vm.filteredItems.map((i) => i.id).toList(), ['in-f1']);
      expect(vm.currentFolderId.value, 'f1');
    });
  });

  // ── 排序（经 setSortOption 公开入口驱动 _sortBooks） ───────────────────────

  group('setSortOption 排序', () {
    setUp(() {
      vm.novels.assignAll([
        novel('early', addedAt: 10),
        novel('late', addedAt: 99),
        novel('mid', addedAt: 50, isFavorite: true),
      ]);
    });

    test('收藏书永远置顶，其余按 addedAt 升降序', () {
      vm.setSortOption('addedAt', true);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['mid', 'early', 'late']);
      vm.setSortOption('addedAt', false);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['mid', 'late', 'early']);
    });

    test('title 按小写比较；fileSize 按 BigInt 数值', () {
      vm.novels.assignAll([
        novel('a', title: 'Bee', fileSize: 10),
        novel('b', title: 'apple', fileSize: 2),
        novel('c', title: 'Cherry', fileSize: 100),
      ]);
      vm.setSortOption('title', true);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['b', 'a', 'c']);
      vm.setSortOption('fileSize', false);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['c', 'a', 'b']);
    });

    test('customOrder：null 视为 999999 垫底，同序按 addedAt 再整体翻转', () {
      vm.novels.assignAll([
        novel('o2', customOrder: 2, addedAt: 200),
        novel('oNone', addedAt: 1),
        novel('o1', customOrder: 1, addedAt: 300),
        novel('o2tie', customOrder: 2, addedAt: 100),
      ]);
      vm.setSortOption('customOrder', true);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['o1', 'o2tie', 'o2', 'oNone']);
    });

    test('未知排序字段回退 addedAt', () {
      vm.setSortOption('不存在的字段', true);
      expect(vm.filteredNovels.map((n) => n.id).toList(), ['mid', 'early', 'late']);
    });
  });

  // ── 分页 ───────────────────────────────────────────────────────────────────

  group('分页状态', () {
    test('120 本书：首屏 100，loadMore 增 50 并被总数截断，reset 回 100', () {
      vm.novels.assignAll(List.generate(120, (i) => novel('n$i')));
      expect(vm.displayedItemCount.value, 100);
      expect(vm.displayedItems.length, 100);
      expect(vm.canLoadMore, isTrue);

      vm.loadMoreItems();
      expect(vm.displayedItemCount.value, 120); // (100+50) clamp 到实际总数
      expect(vm.displayedItems.length, 120);
      expect(vm.canLoadMore, isFalse);

      vm.loadMoreItems(); // 无可加载时为空操作
      expect(vm.displayedItemCount.value, 120);

      vm.resetPagination();
      expect(vm.displayedItemCount.value, 100);
      expect(vm.canLoadMore, isTrue);
    });

    test('不足一页时 canLoadMore 为 false 且 loadMore 不动计数', () {
      vm.novels.assignAll([novel('only')]);
      expect(vm.canLoadMore, isFalse);
      vm.loadMoreItems();
      expect(vm.displayedItemCount.value, 100);
    });

    test('enterFolder / exitFolder 都会重置分页并退出选择态', () {
      vm.folders.assignAll([dir('f1')]);
      vm.novels.assignAll(List.generate(200, (i) => novel('n$i', folderId: i < 150 ? 'f1' : null)));
      vm.loadMoreItems();
      vm.enterSelection('n1');

      vm.enterFolder('f1');
      expect(vm.currentFolderId.value, 'f1');
      expect(vm.displayedItemCount.value, 100);
      expect(vm.isSelecting.value, isFalse);

      vm.enterSelection('n1');
      vm.exitFolder();
      expect(vm.currentFolderId.value, isNull);
      expect(vm.displayedItemCount.value, 100);
      expect(vm.isSelecting.value, isFalse);
    });
  });

  // ── 标签过滤 ───────────────────────────────────────────────────────────────

  group('标签', () {
    setUp(() {
      vm.novels.assignAll([
        novel('a', tags: ['汉', '科幻']),
        novel('b', tags: ['汉']),
        novel('c', tags: ['日漫']),
      ]);
      vm.remoteNovels.assignAll([novel('r', tags: ['汉'])]);
    });

    test('allTagCounts 合并本地与远程计数；allAvailableTags 按 codepoint 排序', () {
      expect(vm.allTagCounts['汉'], 3);
      expect(vm.allTagCounts['科幻'], 1);
      expect(vm.allAvailableTags, ['日漫', '汉', '科幻']);
    });

    test('filterBySingleTag：trim 后单选标签，清空搜索并重置分页', () {
      vm.searchQuery.value = 'abc';
      vm.searchByContent.value = true;
      vm.loadMoreItems(); // 不满一页也允许调用，观察 reset
      vm.filterBySingleTag('  汉  ');
      expect(vm.selectedFilterTags, ['汉']);
      expect(vm.searchQuery.value, '');
      expect(vm.searchByContent.value, isFalse);
      expect(vm.displayedItemCount.value, 100);
      expect(vm.filteredNovels.map((n) => n.id).toSet(), {'a', 'b', 'r'});
    });

    test('filterBySingleTag 空白关键词为无操作', () {
      vm.filterBySingleTag('   ');
      expect(vm.selectedFilterTags, isEmpty);
    });
  });

  // ── 选择状态机 ─────────────────────────────────────────────────────────────

  group('选择与全选', () {
    test('enterSelection / toggleSelection / exitSelection 演化', () {
      vm.enterSelection('a');
      expect(vm.isSelecting.value, isTrue);
      expect(vm.selectedIds, {'a'});
      vm.toggleSelection('b');
      expect(vm.selectedIds, {'a', 'b'});
      vm.toggleSelection('a');
      expect(vm.selectedIds, {'b'});
      vm.toggleSelection('b');
      expect(vm.selectedIds, isEmpty);
      expect(vm.isSelecting.value, isFalse); // 清空后自动退出
      vm.exitSelection();
      expect(vm.isSelecting.value, isFalse);
    });

    test('toggleSelectAll 以 filteredItems 为全集，二次调用清空', () {
      vm.folders.assignAll([dir('f1')]);
      vm.novels.assignAll([novel('b1'), novel('b2')]);
      vm.toggleSelectAll();
      expect(vm.selectedIds, {'f1', 'b1', 'b2'});
      vm.toggleSelectAll();
      expect(vm.selectedIds, isEmpty);
    });
  });

  // ── 文件夹封面（临时文件驱动 File.existsSync） ─────────────────────────────

  group('文件夹封面与直属书籍分组', () {
    late String okCover;
    late String okCover2;

    setUp(() {
      final f1 = File('${tmpDir.path}/cover1.png')..writeAsStringSync('x');
      final f2 = File('${tmpDir.path}/cover2.png')..writeAsStringSync('y');
      okCover = f1.path;
      okCover2 = f2.path;
    });

    test('getFolderCover 返回第一本封面文件真实存在的书；全缺返回 null', () {
      vm.novels.assignAll([
        novel('a', folderId: 'f1', coverPath: '${tmpDir.path}/ghost.png'), // 文件不存在
        novel('b', folderId: 'f1', coverPath: okCover),
        novel('c', folderId: 'f1'), // 无封面字段
        novel('d', folderId: 'f2', coverPath: okCover2), // 别的目录不算
      ]);
      expect(vm.getFolderCover('f1'), okCover);
      expect(vm.getFolderCover('empty-folder'), isNull);
    });

    test('getFolderCovers 保持书籍顺序、跳过缺失文件并按 maxCount 截断', () {
      vm.novels.assignAll([
        novel('a', folderId: 'f1', coverPath: okCover),
        novel('b', folderId: 'f1', coverPath: '${tmpDir.path}/ghost.png'),
        novel('c', folderId: 'f1', coverPath: ''), // 空串视为无封面
        novel('d', folderId: 'f1', coverPath: okCover2),
      ]);
      expect(vm.getFolderCovers('f1'), [okCover, okCover2]);
      expect(vm.getFolderCovers('f1', maxCount: 1), [okCover]);
    });
  });

  // ── 关键词规则（仅守卫分支；有效路径写真实 $HOME 文件，见文件头注释） ──────

  group('关键词规则守卫', () {
    test('addKeywordRule 空关键词与重复规则提前返回（不触发落盘）', () async {
      await vm.addKeywordRule('   ', '任意标签'); // 空关键词 → 早退
      expect(vm.keywordRules, isEmpty);

      vm.keywordRules.add({'keyword': '恋爱', 'tag': '日常'}); // 手工注入，绕开保存
      await vm.addKeywordRule('恋爱', '日常'); // 完全重复 → 早退
      expect(vm.keywordRules.length, 1);
    });

    test('removeKeywordRule 越界索引为无操作（不触发落盘）', () async {
      vm.keywordRules.add({'keyword': 'k', 'tag': 't'});
      await vm.removeKeywordRule(-1);
      await vm.removeKeywordRule(vm.keywordRules.length);
      expect(vm.keywordRules.length, 1);
    });

    test('applyKeywordRulesToNovel：书不存在或无规则时早退；FFI 不可用时不误打标', () async {
      // 无规则 → 早退
      await vm.applyKeywordRulesToNovel('n1', '/lib/n1.txt');
      // 书不存在 → 早退
      vm.keywordRules.add({'keyword': '触发词', 'tag': 'T'});
      await vm.applyKeywordRulesToNovel('ghost', '/lib/n1.txt');

      // 书存在：searchInNovel（FRB）在测试环境必抛，被逐条吞掉，
      // 匹配集合不增长 → 不会调用 updateNovelTags（其若被调用会未捕获地炸掉本用例）
      vm.novels.assignAll([novel('n1', tags: ['原标签'])]);
      await vm.applyKeywordRulesToNovel('n1', '/lib/n1.txt');
      expect(vm.novels.single.tags, ['原标签']);
    });
  });
}
