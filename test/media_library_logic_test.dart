// 媒体库 ViewModel 可测逻辑切片单测。
//
// 设计约束（不触发 FFI / 不依赖 GetIt 全链路初始化 / 不需要 RustLib.init）：
// - MediaLibraryViewModel 的字段初始化会 `getIt<NodeSettingsService>()` 与
//   `getIt<MediaPrefsService>()`，二者构造函数均为纯内存操作（真正的 IO 在
//   init() 内），所以测试里直接注册真实轻量实例即可，不走 getItInit()。
// - NodeSettingsService 用测试子类覆写 4 个 fetchNode* 网络方法返回桩数据，
//   buildNodeMediaUrl / enabledRemoteNodes 等纯逻辑仍用真实实现。
// - 任何会触达 media_api（FRB）的调用都被 VM 自身的 try/catch 吞掉，
//   个别用例专门验证"FFI 不可用时错误被兜住"。
import 'package:dio/dio.dart' show ProgressCallback;
import 'package:flutter_test/flutter_test.dart';
// assignAll 等 Rx 集合扩展由 get 包提供（VM 内部同样依赖该扩展）
// ignore: depend_on_referenced_packages
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/natural_compare.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 桩节点服务：网络取数走内存桩，URL 拼接等纯逻辑保留真实实现。
class _StubNodeSettingsService extends NodeSettingsService {
  List<Map<String, dynamic>> mediaFoldersPayload = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> mediaCollectionsPayload = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> smartFoldersPayload = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> collectionItemsPayload = <Map<String, dynamic>>[];
  ProgressCallback? lastProgressCallback;

  @override
  Future<List<Map<String, dynamic>>> fetchNodeMediaFolders(
    NodeEndpoint node,
  ) async {
    return mediaFoldersPayload;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNodeMediaCollections(
    NodeEndpoint node,
  ) async {
    return mediaCollectionsPayload;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNodeSmartFolders(
    NodeEndpoint node,
  ) async {
    return smartFoldersPayload;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNodeMediaCollectionItems({
    required String nodeId,
    required String collectionId,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastProgressCallback = onReceiveProgress;
    return collectionItemsPayload;
  }
}

// ── 数据构造辅助 ─────────────────────────────────────────────────────────────

media_api.MediaCollection col(
  String id, {
  String? title,
  String? folderId,
  String folderPath = '/lib',
  String? coverPath,
  BigInt? itemCount,
  int createdAt = 0,
  int updatedAt = 0,
}) {
  return media_api.MediaCollection(
    id: id,
    title: title ?? id,
    folderPath: folderPath,
    folderId: folderId,
    coverPath: coverPath,
    itemCount: itemCount ?? BigInt.one,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

media_api.MediaFolder folder(
  String id, {
  String? name,
  String? parentId,
  int order = 0,
}) {
  return media_api.MediaFolder(
    id: id,
    name: name ?? id,
    createdAt: 0,
    order: order,
    parentId: parentId,
  );
}

media_api.MediaItem item(
  String id, {
  String? title,
  String filePath = '/lib/f.jpg',
  media_api.MediaKind kind = media_api.MediaKind.image,
  String collectionId = 'c1',
  int size = 0,
  int modifiedAt = 0,
}) {
  return media_api.MediaItem(
    id: id,
    collectionId: collectionId,
    title: title ?? id,
    filePath: filePath,
    kind: kind,
    fileSize: BigInt.from(size),
    modifiedAt: modifiedAt,
    order: 0,
  );
}

SmartFolder sf(
  String id, {
  String? name,
  String pattern = '',
  List<String> keywords = const [],
  List<String> targetFolderIds = const [],
  SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
}) {
  return SmartFolder(
    id: id,
    name: name ?? id,
    regexPattern: pattern,
    keywords: keywords,
    regexTarget: regexTarget,
    targetFolderIds: targetFolderIds,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubNodeSettingsService nodeService;
  late MediaPrefsService prefs;
  late MediaLibraryViewModel vm;

  setUp(() async {
    await getIt.reset();
    nodeService = _StubNodeSettingsService();
    prefs = MediaPrefsService();
    getIt
      ..registerSingleton<NodeSettingsService>(nodeService)
      ..registerSingleton<MediaPrefsService>(prefs);
    vm = MediaLibraryViewModel();
  });

  tearDown(() async {
    await getIt.reset();
  });

  /// 挂载一个测试节点并刷新远程库（走桩数据，不发真实 HTTP）。
  Future<void> mountNodeAndRefresh({
    List<Map<String, dynamic>> folders = const [],
    List<Map<String, dynamic>> collections = const [],
    List<Map<String, dynamic>> smartFolders = const [],
  }) async {
    nodeService
      ..mediaFoldersPayload = folders
      ..mediaCollectionsPayload = collections
      ..smartFoldersPayload = smartFolders;
    nodeService.remoteNodes.add(
      const NodeEndpoint(id: 'node-a', name: '节点A', apiBaseUrl: 'http://127.0.0.1:17888'),
    );
    await vm.refreshRemoteLibrary();
  }

  // ── naturalCompare 自然序比较器 ────────────────────────────────────────────

  group('naturalCompare 自然序', () {
    test('数字段按数值而非字典序比较', () {
      expect(naturalCompare('A2', 'A10'), lessThan(0));
      expect(naturalCompare('A10', 'A100'), lessThan(0));
      expect(naturalCompare('XXX(101)', 'XXX(9)'), greaterThan(0));
    });

    test('前导零剥离后按数值比较', () {
      expect(naturalCompare('file007', 'file7'), 0);
      expect(naturalCompare('file08', 'file9'), lessThan(0));
    });

    test('字母忽略大小写', () {
      expect(naturalCompare('ABC', 'abc'), 0);
      expect(naturalCompare('ABC', 'abd'), lessThan(0));
    });

    test('前缀相同时较短者在前，完全相同返回 0', () {
      expect(naturalCompare('abc', 'abcd'), lessThan(0));
      expect(naturalCompare('same', 'same'), 0);
    });

    test('数字与字母相邻时按码元序', () {
      // '1'(0x31) < 'a'(0x61)：数字段起始时数字在前
      expect(naturalCompare('1a', 'a1'), lessThan(0));
    });
  });

  // ── mergedFolders / mergedCollections 排序与缓存 ──────────────────────────

  group('mergedFolders', () {
    test('先按 order 再按小写名称排序，合并本地与远程', () {
      vm.folders.assignAll([
        folder('f-b', name: 'b', order: 1),
        folder('f-Z', name: 'Z', order: 0),
        folder('f-a', name: 'a', order: 0),
      ]);
      vm.remoteFolders.assignAll([folder('f-c', name: 'c', order: 0)]);
      expect(
        vm.mergedFolders.map((f) => f.id).toList(),
        ['f-a', 'f-c', 'f-Z', 'f-b'],
      );
    });
  });

  group('mergedCollections', () {
    test('按 updatedAt 降序，同 updatedAt 按小写标题升序', () {
      final c1 = col('c1', title: 'Bee', updatedAt: 100);
      final c2 = col('c2', title: 'apple', updatedAt: 100);
      final c3 = col('c3', title: 'Old', updatedAt: 50);
      vm.collections.assignAll([c1, c2, c3]);
      expect(vm.mergedCollections.map((c) => c.id).toList(), [
        'c2',
        'c1',
        'c3',
      ]);
    });

    test('输入实例不变时命中排序缓存（返回同一列表实例）', () {
      vm.collections.assignAll([col('c1'), col('c2')]);
      final first = vm.mergedCollections;
      final second = vm.mergedCollections;
      expect(identical(first, second), isTrue);
    });

    test('集合列表变更后缓存失效并重算；结果为不可修改列表', () {
      vm.collections.assignAll([col('c1', updatedAt: 1)]);
      final first = vm.mergedCollections;
      expect(() => first.add(col('x')), throwsUnsupportedError);
      vm.collections.assignAll([col('c1', updatedAt: 1), col('c2', updatedAt: 2)]);
      final second = vm.mergedCollections;
      expect(identical(first, second), isFalse);
      expect(second.map((c) => c.id).toList(), ['c2', 'c1']);
    });
  });

  // ── 同名集合分组 ───────────────────────────────────────────────────────────

  group('同名集合分组', () {
    test('isDupGroup / dupGroupTitle 前缀解析', () {
      expect(vm.isDupGroup('dup-group:相册'), isTrue);
      expect(vm.isDupGroup('remote-media:node-a:c1'), isFalse);
      expect(vm.dupGroupTitle('dup-group:相册'), '相册');
      expect(vm.dupGroupTitle('folder-1'), isNull);
    });

    test('isInDupGroup / currentDupGroupTitle 跟随 currentFolderId', () {
      vm.currentFolderId.value = 'dup-group:相册';
      expect(vm.isInDupGroup, isTrue);
      expect(vm.currentDupGroupTitle, '相册');
      vm.currentFolderId.value = 'f1';
      expect(vm.isInDupGroup, isFalse);
      expect(vm.currentDupGroupTitle, isNull);
    });

    test('visibleItems 将同名集合折叠为分组文件夹并登记父目录', () {
      vm.collections.assignAll([
        col('a', title: '同人', folderId: null),
        col('b', title: '独一', folderId: null),
        col('c', title: '同人', folderId: null),
      ]);
      final items = vm.visibleItems;
      // 首个出现位置保留：第 1 项为分组虚拟文件夹，第 2 项为独立集合
      expect(items[0], isA<MediaLibraryFolderItem>());
      expect(items[0].id, 'dup-group:同人');
      expect(items[1], isA<MediaLibraryCollectionItem>());
      expect(items[1].id, 'b');
      // 分组父目录登记后，dupGroupCollections 能取回两个同名集合
      expect(vm.dupGroupCollections('dup-group:同人').map((c) => c.id).toSet(), {
        'a',
        'c',
      });
    });

    test('进入分组后不再嵌套分组，直接平铺集合', () {
      vm.collections.assignAll([
        col('a', title: '同人', folderId: null),
        col('c', title: '同人', folderId: null),
      ]);
      vm.visibleItems; // 登记分组父目录
      vm.currentFolderId.value = 'dup-group:同人';
      final items = vm.visibleItems;
      expect(items.every((i) => i is MediaLibraryCollectionItem), isTrue);
      expect(items.map((i) => i.id).toSet(), {'a', 'c'});
    });

    test('collectionCountInFolder：分组按分组成员数，普通文件夹按 folderId 计数', () {
      vm.collections.assignAll([
        col('a', title: '同人', folderId: null),
        col('c', title: '同人', folderId: null),
        col('d', title: '其他', folderId: null),
      ]);
      vm.visibleItems;
      expect(vm.collectionCountInFolder('dup-group:同人'), 2);
      expect(vm.collectionCountInFolder('f-none'), 0);
    });
  });

  // ── 智能文件夹 ID 解析与导航上下文 ────────────────────────────────────────

  group('智能文件夹 ID 与导航', () {
    test('isSmartFolder / isRemoteSmartFolder / remoteSmartFolderNodeId', () {
      expect(vm.isSmartFolder('smart-folder:x'), isTrue);
      expect(vm.isSmartFolder('folder-1'), isFalse);
      expect(vm.isRemoteSmartFolder('smart-folder:remote:n1:sf1'), isTrue);
      expect(vm.isRemoteSmartFolder('smart-folder:local1'), isFalse);
      // nodeId 为 UUID 不含冒号，rawId 可以含冒号
      expect(
        vm.remoteSmartFolderNodeId('smart-folder:remote:n1:smart-folder:xyz'),
        'n1',
      );
      expect(vm.remoteSmartFolderNodeId('smart-folder:remote:n2'), 'n2');
      expect(vm.remoteSmartFolderNodeId('smart-folder:local'), isNull);
    });

    test('effectiveFolderId：智能文件夹单目标取目标，多/零目标取根', () {
      final one = sf('smart-folder:s1', targetFolderIds: const ['f1']);
      final many = sf('smart-folder:s2', targetFolderIds: const ['f1', 'f2']);
      vm.smartFolders.assignAll([one, many]);

      vm.currentFolderId.value = 'f1';
      expect(vm.effectiveFolderId, 'f1');

      vm.currentFolderId.value = 'smart-folder:s1';
      expect(vm.effectiveFolderId, 'f1');

      vm.currentFolderId.value = 'smart-folder:s2';
      expect(vm.effectiveFolderId, isNull);

      vm.currentFolderId.value = null;
      expect(vm.effectiveFolderId, isNull);
    });

    test('currentBrowseTitle 优先级：智能文件夹 > 同名分组 > 文件夹 > 媒体库', () {
      vm.smartFolders.assignAll([sf('smart-folder:s1', name: '精选')]);
      vm.currentFolderId.value = 'smart-folder:s1';
      expect(vm.currentBrowseTitle, '精选');

      vm.currentFolderId.value = 'dup-group:同人';
      expect(vm.currentBrowseTitle, '同人');

      vm.currentFolderId.value = null;
      expect(vm.currentBrowseTitle, '媒体库');
    });

    test('currentFolderTrail 自根到当前；父子环不死循环', () {
      vm.folders.assignAll([
        folder('a'),
        folder('b', parentId: 'a'),
        folder('c', parentId: 'b'),
      ]);
      vm.currentFolderId.value = 'c';
      expect(vm.currentFolderTrail.map((f) => f.id).toList(), ['a', 'b', 'c']);
      vm.currentFolderId.value = null;
      expect(vm.currentFolderTrail, isEmpty);

      // 构造父子环 a↔b：visited 集合应保证终止
      vm.folders.assignAll([folder('a', parentId: 'b'), folder('b', parentId: 'a')]);
      vm.currentFolderId.value = 'b';
      expect(vm.currentFolderTrail.map((f) => f.id).toList(), ['a', 'b']);
    });

    test('currentChildFolders 仅返回直接子文件夹', () {
      vm.folders.assignAll([
        folder('a'),
        folder('b', parentId: 'a'),
        folder('c', parentId: 'b'),
      ]);
      vm.currentFolderId.value = 'a';
      expect(vm.currentChildFolders.map((f) => f.id).toList(), ['b']);
    });

    test('exitFolder：智能文件夹回根；同名分组回登记父目录；普通文件夹回父级', () {
      vm.smartFolders.assignAll([sf('smart-folder:s1')]);
      vm.currentFolderId.value = 'smart-folder:s1';
      vm.exitFolder();
      expect(vm.currentFolderId.value, isNull);

      // 普通文件夹：先建立 a→b 导航，再退出 b 回 a
      vm.folders.assignAll([folder('a'), folder('b', parentId: 'a')]);
      vm.enterFolder('b');
      expect(vm.currentFolderId.value, 'b');
      vm.exitFolder();
      expect(vm.currentFolderId.value, 'a');
    });
  });

  // ── currentCollections：过滤 + 收藏 + 排序 ────────────────────────────────

  group('currentCollections 排序与过滤', () {
    test('按当前文件夹过滤；根目录只含 folderId==null 的集合', () {
      vm.collections.assignAll([
        col('r1', folderId: null),
        col('f1a', folderId: 'f1'),
        col('f1b', folderId: 'f1'),
      ]);
      vm.currentFolderId.value = 'f1';
      expect(vm.currentCollections.map((c) => c.id).toSet(), {'f1a', 'f1b'});
      vm.currentFolderId.value = null;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['r1']);
    });

    test('showFavoritesOnly 仅保留收藏集合', () {
      vm.collections.assignAll([
        col('a', folderId: null, updatedAt: 2),
        col('b', folderId: null, updatedAt: 1),
      ]);
      vm.currentFolderId.value = null;
      vm.favoriteCollectionIds.assignAll({'b'});
      vm.showFavoritesOnly.value = true;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['b']);
      vm.showFavoritesOnly.value = false;
      expect(vm.currentCollections.length, 2);
    });

    test('nameAsc 使用自然序（A2 在 A10 前）', () {
      vm.collections.assignAll([
        col('x', title: 'A10', folderId: null),
        col('y', title: 'A2', folderId: null),
      ]);
      vm.collectionSortOrder.value = CollectionSortOrder.nameAsc;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['y', 'x']);
      vm.collectionSortOrder.value = CollectionSortOrder.nameDesc;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['x', 'y']);
    });

    test('countAsc/countDesc 按 itemCount 排序', () {
      vm.collections.assignAll([
        col('small', folderId: null, itemCount: BigInt.from(2)),
        col('big', folderId: null, itemCount: BigInt.from(100)),
      ]);
      vm.collectionSortOrder.value = CollectionSortOrder.countDesc;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['big', 'small']);
      vm.collectionSortOrder.value = CollectionSortOrder.countAsc;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['small', 'big']);
    });

    test('combinedSort 无拖拽顺序时按 createdAt 升序', () {
      vm.collections.assignAll([
        col('late', folderId: null, createdAt: 200, updatedAt: 999),
        col('early', folderId: null, createdAt: 100, updatedAt: 1),
      ]);
      vm.collectionSortOrder.value = CollectionSortOrder.combinedSort;
      expect(vm.currentCollections.map((c) => c.id).toList(), ['early', 'late']);
    });

    test('不存在的智能文件夹 ID 返回空列表', () {
      vm.currentFolderId.value = 'smart-folder:ghost';
      expect(vm.currentCollections, isEmpty);
    });
  });

  // ── sortedCurrentItems：条目排序 + 搜索过滤 ───────────────────────────────

  group('sortedCurrentItems', () {
    setUp(() {
      vm.currentItems.assignAll([
        item('p10', title: 'page10', size: 10, modifiedAt: 100),
        item('p2', title: 'page2', size: 20, modifiedAt: 300),
        item('p1', title: 'page1', size: 30, modifiedAt: 200),
      ]);
    });

    test('nameAsc/nameDesc 走自然序', () {
      vm.itemSortOrder.value = MediaItemSortOrder.nameAsc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p1',
        'p2',
        'p10',
      ]);
      vm.itemSortOrder.value = MediaItemSortOrder.nameDesc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p10',
        'p2',
        'p1',
      ]);
    });

    test('sizeAsc/sizeDesc 与 timeAsc/timeDesc 数值排序', () {
      vm.itemSortOrder.value = MediaItemSortOrder.sizeAsc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p10',
        'p2',
        'p1',
      ]);
      vm.itemSortOrder.value = MediaItemSortOrder.sizeDesc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p1',
        'p2',
        'p10',
      ]);
      vm.itemSortOrder.value = MediaItemSortOrder.timeAsc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p10',
        'p1',
        'p2',
      ]);
      vm.itemSortOrder.value = MediaItemSortOrder.timeDesc;
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), [
        'p2',
        'p1',
        'p10',
      ]);
    });

    test('searchQuery 非空时按标题（忽略大小写）过滤', () {
      vm.searchQuery.value = 'PAGE2';
      expect(vm.sortedCurrentItems.map((i) => i.id).toList(), ['p2']);
      vm.searchQuery.value = '';
      expect(vm.sortedCurrentItems.length, 3);
    });
  });

  // ── 深度搜索 / 相似查找（visibleItems 分流） ──────────────────────────────

  group('深度搜索 searchQuery', () {
    test('匹配后代文件夹名与集合标题', () {
      vm.folders.assignAll([
        folder('f1', name: 'HolidayPics'),
        folder('f2', name: 'Other', parentId: 'f1'),
      ]);
      vm.collections.assignAll([
        col('c1', title: 'Christmas Eve', folderId: null),
        col('c2', title: '日常', folderId: 'f2'),
      ]);
      vm.currentFolderId.value = null;

      vm.searchQuery.value = 'holiday';
      final byFolder = vm.visibleItems;
      expect(byFolder.map((i) => i.id).toList(), ['f1']);

      vm.searchQuery.value = 'christmas';
      expect(vm.visibleItems.map((i) => i.id).toList(), ['c1']);

      // 子孙文件夹内的集合也在搜索范围内
      vm.searchQuery.value = '日常';
      expect(vm.visibleItems.map((i) => i.id).toList(), ['c2']);
      vm.searchQuery.value = '';
    });

    test('远程集合按资源文件名匹配（路径缓存异步补齐，Windows 分隔符兼容）', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': '无中文标题集', 'folder_path': '/node/rc1'},
        ],
      );
      nodeService.collectionItemsPayload = [
        {'id': 'i1', 'file_path': 'C:\\pics\\Holiday2.jpg'},
      ];
      vm.currentFolderId.value = null;
      vm.searchQuery.value = 'holiday2';

      // 第一轮：路径未加载，文件名命中不了
      final round1 = vm.visibleItems;
      expect(round1.where((i) => i.id == 'remote-media:node-a:rc1'), isEmpty);

      // 桩 fetch 立即完成后 _searchVersion 自增，重读即可命中
      await Future<void>.delayed(Duration.zero);
      final round2 = vm.visibleItems;
      expect(
        round2.where((i) => i.id == 'remote-media:node-a:rc1').length,
        1,
      );
    });
  });

  group('相似查找 similarSearchQuery', () {
    test('亲和度分层：全名 > 中文分词 > 逐字（≥2 共同汉字）', () {
      vm.collections.assignAll([
        col('t1', title: '我们的夏日 旅行', folderId: null),
        col('t2', title: '夏日时光', folderId: null),
        col('t3', title: '日行千里', folderId: null),
        col('t0', title: '完全无关', folderId: null),
      ]);
      vm.similarSearchQuery.value = '夏日 旅行';
      expect(vm.visibleItems.map((i) => i.id).toList(), ['t1', 't2', 't3']);
    });

    test('英文查询仅命中全名包含（无分词/逐字层）', () {
      vm.collections.assignAll([
        col('e1', title: 'Photo Album', folderId: null),
        col('e2', title: 'Pica Cho', folderId: null),
      ]);
      vm.similarSearchQuery.value = 'photo';
      expect(vm.visibleItems.map((i) => i.id).toList(), ['e1']);
    });

    test('startSimilarSearch 与 searchQuery 互斥', () {
      vm.searchQuery.value = 'abc';
      vm.startSimilarSearch(col('x', title: '夏日 旅行'));
      expect(vm.searchQuery.value, isEmpty);
      expect(vm.isSearchActive.value, isFalse);
      expect(vm.similarSearchQuery.value, '夏日 旅行');
      vm.clearSimilarSearch();
      expect(vm.similarSearchQuery.value, isEmpty);
    });
  });

  // ── collectionMatchesSmartFolder / 匹配缓存 ───────────────────────────────

  group('智能文件夹匹配', () {
    test('本地匹配：文件夹范围 + 标题/路径正则（大小写不敏感）', () {
      final localSf = sf('smart-folder:s1', pattern: 'ALBUM', targetFolderIds: ['f1']);
      final inScope = col('a', title: 'My Album 1', folderId: 'f1');
      final inScopeNoMatch = col('b', title: 'Sketches', folderId: 'f1');
      final outOfScope = col('c', title: 'My Album 2', folderId: 'f2');
      vm.collections.assignAll([inScope, inScopeNoMatch, outOfScope]);
      vm.currentFolderId.value = 'smart-folder:s1';
      vm.smartFolders.assignAll([localSf]);

      expect(vm.collectionMatchesSmartFolder(localSf, inScope), isTrue);
      expect(vm.collectionMatchesSmartFolder(localSf, inScopeNoMatch), isFalse);
      expect(vm.collectionMatchesSmartFolder(localSf, outOfScope), isFalse);
      expect(vm.currentCollections.map((c) => c.id).toList(), ['a']);
      expect(vm.currentSmartFolder?.id, 'smart-folder:s1');
    });

    test('远程集合走 regexOnly：忽略文件夹范围，仅标题/路径正则', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'Remote Album', 'folder_path': '/data/remote_album'},
        ],
      );
      final localSf = sf('smart-folder:s1', pattern: 'album', targetFolderIds: ['f1']);
      final remoteCol = vm.mergedCollections.first;
      // folderId 不在 targetFolderIds 内，但远程集合跳过范围检查
      expect(vm.collectionMatchesSmartFolder(localSf, remoteCol), isTrue);
      // 路径命中也算（标题 'Remote Album' 已命中，这里用只匹配路径的模式）
      final pathOnly = sf('smart-folder:s2', pattern: 'remote_album');
      expect(vm.collectionMatchesSmartFolder(pathOnly, remoteCol), isTrue);
    });

    test('远程智能文件夹 regexOnly：坏正则/空模式一律放行', () {
      vm.collections.assignAll([col('a', title: '任意', folderId: 'f9')]);
      final badRegexSf = sf('smart-folder:remote:node-a:sf1', pattern: '[unclosed');
      final emptySf = sf('smart-folder:remote:node-a:sf2');
      expect(vm.collectionMatchesSmartFolder(badRegexSf, vm.collections.first), isTrue);
      expect(vm.collectionMatchesSmartFolder(emptySf, vm.collections.first), isTrue);
    });

    test('文件名模式：本地路径缓存为空时不匹配（匹配延迟到预热后）', () {
      // _collectionItemPaths 为私有懒加载缓存，测试环境未经 FFI 预热必为空，
      // 因此文件名模式的本地匹配只能得到 false —— 锁定"未预热不误报"的行为。
      final fileSf = sf('smart-folder:s1', pattern: 'holiday', regexTarget: SmartFolderRegexTarget.fileName);
      vm.collections.assignAll([col('a', title: 'Holiday', folderId: null)]);
      expect(vm.collectionMatchesSmartFolder(fileSf, vm.collections.first), isFalse);
    });

    test('collectionsMatchingSmartFolder 缓存行为与失效窗口', () {
      final localSf = sf('smart-folder:s1', pattern: 'x');
      vm.collections.assignAll([col('a', title: 'x1', folderId: null)]);
      final first = vm.collectionsMatchingSmartFolder(localSf);
      final second = vm.collectionsMatchingSmartFolder(localSf);
      final third = vm.collectionsMatchingSmartFolder(localSf);
      // 首次调用读取的 generation 是"重算前快照"，条目记录旧代数；
      // 第二次调用未命中并重算，第三次起命中缓存返回同一实例。
      expect(identical(first, second), isFalse);
      expect(identical(second, third), isTrue);
      expect(third.map((c) => c.id).toList(), ['a']);
      expect(() => third.add(col('zzz')), throwsUnsupportedError);

      // 源变化后 mergedCollections 被重算（代数 +1，UI 总会经它读取），
      // 匹配缓存随之失效并重算
      vm.collections.assignAll([
        col('a', title: 'x1', folderId: null),
        col('b', title: 'x2', folderId: null),
      ]);
      expect(vm.mergedCollections.length, 2); // 触发 mergedCollections 重算
      final updated = vm.collectionsMatchingSmartFolder(localSf);
      expect(identical(updated, second), isFalse);
      expect(updated.map((c) => c.id).toSet(), {'a', 'b'});
    });

    test('已确认行为：mergedCollections 未被重算前，匹配缓存按旧代数快照命中', () {
      // 缓存条目记录的是"读取时刻的 generation 快照"。若集合变更后
      // 没有任何调用方重读 mergedCollections，匹配结果会停留在旧列表。
      // 真实 UI 每帧都会读 mergedCollections，因此不可达；此用例锁定边界语义。
      final localSf = sf('smart-folder:s1', pattern: 'x');
      vm.collections.assignAll([col('a', title: 'x1', folderId: null)]);
      vm.collectionsMatchingSmartFolder(localSf);
      final cached = vm.collectionsMatchingSmartFolder(localSf);
      vm.collections.assignAll([col('a', title: 'x1', folderId: null), col('b', title: 'x2', folderId: null)]);
      final stale = vm.collectionsMatchingSmartFolder(localSf);
      expect(identical(stale, cached), isTrue);
      expect(stale.map((c) => c.id).toList(), ['a']);
    });
  });

  // ── buildMediaSource / 封面来源分流 ───────────────────────────────────────

  group('buildMediaSource', () {
    test('无集合上下文与本地集合直接返回 filePath', () {
      final it = item('i1', filePath: '/lib/a.jpg');
      expect(vm.buildMediaSource(it), '/lib/a.jpg');
      expect(vm.buildMediaSource(it, collectionId: 'local-c'), '/lib/a.jpg');
    });

    test('本地图片缩略图管线：暂停期间不入队，直接回原图', () {
      vm.thumbGenerationPaused.value = true;
      final it = item('i1', filePath: '/lib/a.jpg');
      expect(vm.buildMediaSource(it, isCover: true), '/lib/a.jpg');
    });

    test('远程封面：width 取 effectiveRemoteCoverWidth，带 mode=cover', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'R', 'folder_path': '/node/rc1'},
        ],
      );
      final it = item('i1', filePath: '/node/rc1/a.jpg', collectionId: 'remote-media:node-a:rc1');
      final url = vm.buildMediaSource(
        it,
        collectionId: 'remote-media:node-a:rc1',
        isCover: true,
      )!;
      final uri = Uri.parse(url);
      expect(uri.path, '/node/media');
      expect(uri.queryParameters['path'], '/node/rc1/a.jpg');
      expect(uri.queryParameters['width'], '240'); // 默认 remoteCoverWidth
      expect(uri.queryParameters['mode'], 'cover');
    });

    test('远程预览图：width 取 remoteImageWidth，0 表示原图（不带 width 参数）', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'R', 'folder_path': '/node/rc1'},
        ],
      );
      final it = item('i1', filePath: '/node/rc1/a.jpg');
      final original = Uri.parse(
        vm.buildMediaSource(it, collectionId: 'remote-media:node-a:rc1')!,
      );
      expect(original.queryParameters.containsKey('width'), isFalse);
      expect(original.queryParameters.containsKey('mode'), isFalse);

      prefs.remoteImageWidth.value = 1080;
      final scaled = Uri.parse(
        vm.buildMediaSource(it, collectionId: 'remote-media:node-a:rc1')!,
      );
      expect(scaled.queryParameters['width'], '1080');
    });

    test('远程映射存在但节点已移除：buildNodeMediaUrl 抛 StateError', () {
      vm.remoteCollectionNodeId['remote-media:node-z:c9'] = 'node-z';
      expect(
        () => vm.buildMediaSource(item('i1'), collectionId: 'remote-media:node-z:c9'),
        throwsStateError,
      );
    });

    test('buildRemoteOriginalMediaSource：本地/非图片返回 null，图片回无缩放 URL', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'R', 'folder_path': '/node/rc1'},
        ],
      );
      final cid = 'remote-media:node-a:rc1';
      expect(
        vm.buildRemoteOriginalMediaSource(item('i1'), collectionId: 'local'),
        isNull,
      );
      expect(
        vm.buildRemoteOriginalMediaSource(
          item('i1', kind: media_api.MediaKind.video),
          collectionId: cid,
        ),
        isNull,
      );
      final url = vm.buildRemoteOriginalMediaSource(
        item('i1', filePath: '/node/rc1/a.jpg', collectionId: cid),
        collectionId: cid,
      )!;
      final uri = Uri.parse(url);
      expect(uri.queryParameters['width'], isNull);
      expect(uri.queryParameters['mode'], isNull);
    });
  });

  group('buildCollectionCoverSource', () {
    test('空封面返回 null；本地图片封面原样返回', () {
      expect(vm.buildCollectionCoverSource(col('a', coverPath: null)), isNull);
      expect(vm.buildCollectionCoverSource(col('a', coverPath: '')), isNull);
      expect(
        vm.buildCollectionCoverSource(col('a', coverPath: '/lib/cover.jpg')),
        '/lib/cover.jpg',
      );
    });

    test('本地视频/音频封面：暂停期间不入队，返回 null 占位', () {
      vm.thumbGenerationPaused.value = true;
      expect(
        vm.buildCollectionCoverSource(col('a', coverPath: '/lib/movie.mkv')),
        isNull,
      );
      expect(
        vm.buildCollectionCoverSource(col('b', coverPath: '/lib/song.flac')),
        isNull,
      );
    });

    test('远程集合封面 URL 带 mode=cover 与缩放宽度', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'R', 'folder_path': '/node/rc1', 'cover_path': '/node/rc1/c.mp4'},
        ],
      );
      final remoteCol = vm.mergedCollections.first;
      final url = vm.buildCollectionCoverSource(remoteCol)!;
      final uri = Uri.parse(url);
      expect(uri.queryParameters['mode'], 'cover');
      expect(uri.queryParameters['width'], '240');
    });
  });

  // ── 远程数据刷新：payload → 数据类转换 ────────────────────────────────────

  group('refreshRemoteLibrary 数据转换', () {
    test('文件夹：合成 ID / 空 id 跳过 / 缺名兜底 / parent_id 映射', () async {
      await mountNodeAndRefresh(
        folders: [
          {'id': 'p1', 'name': '父夹', 'order': 3, 'created_at': '111'},
          {'id': 'c1', 'name': '子夹', 'parent_id': 'p1'},
          {'id': '', 'name': '无效'},
          {'id': 'x1', 'created_at': 5},
        ],
      );
      final ids = vm.remoteFolders.map((f) => f.id).toList();
      expect(ids, [
        'remote-media-folder:node-a:p1',
        'remote-media-folder:node-a:c1',
        'remote-media-folder:node-a:x1',
      ]);
      final parented = vm.remoteFolders.firstWhere((f) => f.id.endsWith(':c1'));
      expect(parented.parentId, 'remote-media-folder:node-a:p1');
      final unnamed = vm.remoteFolders.firstWhere((f) => f.id.endsWith(':x1'));
      expect(unnamed.name, '未命名文件夹');
      expect(vm.remoteFolderNodeId['remote-media-folder:node-a:p1'], 'node-a');
      expect(vm.remoteFolderRawId['remote-media-folder:node-a:p1'], 'p1');
    });

    test('集合：folder_id 映射 / total_size 入集合大小缓存 / item_count BigInt', () async {
      await mountNodeAndRefresh(
        folders: [
          {'id': 'p1', 'name': '父夹'},
        ],
        collections: [
          {
            'id': 'rc1',
            'title': '远程集',
            'folder_path': '/node/rc1',
            'folder_id': 'p1',
            'item_count': '12345678901234567890',
            'total_size': '999',
          },
        ],
      );
      final c = vm.remoteCollections.single;
      expect(c.id, 'remote-media:node-a:rc1');
      expect(c.folderId, 'remote-media-folder:node-a:p1');
      expect(c.itemCount, BigInt.parse('12345678901234567890'));
      expect(vm.getCollectionTotalSize(c.id), BigInt.from(999));
      expect(vm.getCollectionTotalSize('unknown-id'), BigInt.zero);
      expect(vm.isRemoteCollection(c.id), isTrue);
      expect(vm.getRemoteNodeName(c.id), '节点A');
    });

    test('远程智能文件夹：ID 重命名 + targetFolderIds 清空 + 合并可见', () async {
      await mountNodeAndRefresh(
        smartFolders: [
          {
            'id': 'sf-raw',
            'name': '节点精选',
            'regexPattern': 'x',
            'targetFolderIds': ['local-f1'],
          },
        ],
      );
      final remoteSfId = 'smart-folder:remote:node-a:sf-raw';
      expect(vm.isRemoteSmartFolder(remoteSfId), isTrue);
      expect(vm.getSmartFolder(remoteSfId)?.targetFolderIds, isEmpty);
      expect(vm.mergedSmartFolders.map((s) => s.id).toList(), [remoteSfId]);
    });
  });

  group('loadCurrentCollectionItems（远程桩数据 → MediaItem 转换）', () {
    test('字段解析：kind 兜底 image / 大数 fileSize / 可空 width / 缺字段默认', () async {
      await mountNodeAndRefresh(
        collections: [
          {'id': 'rc1', 'title': 'R', 'folder_path': '/node/rc1'},
        ],
      );
      nodeService.collectionItemsPayload = [
        {
          'id': 'i1',
          'title': '视频',
          'file_path': '/node/rc1/v.mp4',
          'kind': 'VIDEO',
          'file_size': '18446744073709551616',
          'modified_at': '42',
          'width': 1920,
        },
        {
          'id': 'i2',
          'file_path': '/node/rc1/a.mp3',
          'kind': 'audio',
          'width': 'null',
          'duration_ms': 12000,
        },
        {'id': 'i3', 'file_path': '/x.png', 'kind': 'doc'},
      ];
      vm.currentCollectionId.value = 'remote-media:node-a:rc1';
      await vm.loadCurrentCollectionItems();

      final items = vm.currentItems;
      expect(items.length, 3);
      final first = items[0];
      expect(first.kind, media_api.MediaKind.video);
      expect(first.collectionId, 'remote-media:node-a:rc1');
      expect(first.fileSize, BigInt.parse('18446744073709551616'));
      expect(first.modifiedAt, 42);
      expect(first.width, 1920);
      // 缺 title → '未命名媒体'，缺 order → 0
      final second = items[1];
      expect(second.title, '未命名媒体');
      expect(second.kind, media_api.MediaKind.audio);
      expect(second.width, isNull); // 字符串 'null' 视为空
      expect(second.durationMs, BigInt.from(12000));
      // 未知 kind 兜底为 image，缺 fileSize/modifiedAt → 0
      final third = items[2];
      expect(third.kind, media_api.MediaKind.image);
      expect(third.fileSize, BigInt.zero);
      expect(third.modifiedAt, 0);
    });

    test('本地集合触发 FFI 失败时错误被吞、列表清空', () async {
      vm.collections.assignAll([col('lc', folderId: null)]);
      vm.currentCollectionId.value = 'lc';
      await vm.loadCurrentCollectionItems();
      expect(vm.currentItems, isEmpty);
      expect(vm.isLoadingItems.value, isFalse);
    });
  });

  // ── 选择操作 ───────────────────────────────────────────────────────────────

  group('选择与批量选中', () {
    test('enterSelection / toggleSelection / exitSelection 状态机', () {
      vm.enterSelection('a');
      expect(vm.isSelecting.value, isTrue);
      expect(vm.selectedIds, {'a'});
      vm.toggleSelection('b');
      expect(vm.selectedIds, {'a', 'b'});
      vm.toggleSelection('a');
      expect(vm.selectedIds, {'b'});
      vm.toggleSelection('b');
      expect(vm.selectedIds, isEmpty);
      expect(vm.isSelecting.value, isFalse); // 清空后自动退出选择
    });

    test('toggleSelectAll 以 visibleItems 为全集，两次调用为全选/清空', () {
      vm.folders.assignAll([folder('f1', parentId: null)]);
      vm.collections.assignAll([col('c1', folderId: null)]);
      vm.toggleSelectAll();
      expect(vm.selectedIds, {'f1', 'c1'});
      expect(vm.isSelecting.value, isTrue);
      vm.toggleSelectAll();
      expect(vm.selectedIds, isEmpty);
      expect(vm.isSelecting.value, isFalse);
    });

    test('selectUnfavoritedCollections 只选未收藏集合', () {
      vm.collections.assignAll([
        col('a', folderId: null, updatedAt: 2),
        col('b', folderId: null, updatedAt: 1),
      ]);
      vm.currentFolderId.value = null;
      vm.favoriteCollectionIds.assignAll({'a'});
      vm.selectUnfavoritedCollections();
      expect(vm.selectedIds, {'b'});
      expect(vm.isSelecting.value, isTrue);
    });
  });

  // ── 收藏 / 悬停 / 可用文件夹 ──────────────────────────────────────────────

  group('收藏与辅助查询', () {
    test('toggleFavorite 增删收藏（保存走 FFI 失败时静默吞掉）', () async {
      await vm.toggleFavorite('c1');
      expect(vm.isFavorite('c1'), isTrue);
      await vm.toggleFavorite('c1');
      expect(vm.isFavorite('c1'), isFalse);
    });

    test('hoveredLocalCollection：未悬停/不存在/远程均返回 null', () {
      vm.collections.assignAll([col('a', folderId: null)]);
      expect(vm.hoveredLocalCollection(), isNull);
      vm.hoveredCollectionId.value = 'ghost';
      expect(vm.hoveredLocalCollection(), isNull);
      vm.hoveredCollectionId.value = 'a';
      expect(vm.hoveredLocalCollection()?.id, 'a');
      vm.remoteCollectionNodeId['a'] = 'node-a';
      expect(vm.hoveredLocalCollection(), isNull);
    });

    test('getAvailableFoldersForCollection：本地按名称（忽略大小写）排序', () {
      vm.folders.assignAll([
        folder('f-B', name: 'beta'),
        folder('f-A', name: 'Alpha'),
        folder('f-c', name: 'c'),
      ]);
      expect(
        vm.getAvailableFoldersForCollection('any').map((f) => f.id).toList(),
        ['f-A', 'f-B', 'f-c'],
      );
    });

    test('远程集合的可用文件夹 = 同节点远程文件夹排序', () async {
      await mountNodeAndRefresh(
        folders: [
          {'id': 'n1b', 'name': 'b'},
          {'id': 'n1a', 'name': 'A'},
        ],
        collections: [
          {'id': 'x', 'title': 'R', 'folder_path': '/node/x'},
        ],
      );
      vm.remoteFolders.add(folder('f-other', name: 'z'));
      vm.remoteFolderNodeId['f-other'] = 'node-b';
      final result = vm.getAvailableFoldersForCollection('remote-media:node-a:x');
      expect(result.map((f) => f.name).toList(), ['A', 'b']);
    });
  });

  // ── 丢失检查（cover_check）可测切片 ───────────────────────────────────────

  group('cover_check 分流', () {
    test('远程集合/远程文件夹直接短路返回 false，不查缓存不刷新', () async {
      vm.remoteCollectionNodeId['rc'] = 'node-a';
      vm.remoteFolderNodeId['rf'] = 'node-a';
      expect(vm.checkCollectionLost(col('rc', coverPath: '/nope/x.jpg')), isFalse);
      expect(vm.checkFolderLost(folder('rf')), isFalse);
      expect(vm.checkSmartFolderLost(sf('smart-folder:remote:node-a:1')), isFalse);
    });

    test('本地集合无封面路径视为未丢失；缓存命中窗口内不再刷新', () async {
      final noCover = col('c1', coverPath: null);
      expect(vm.checkCollectionLost(noCover), isFalse);
      await Future<void>.delayed(Duration.zero); // 让异步刷新写入缓存
      // 第二次命中"已缓存 + 未过期"分支，仍返回 false 且无副作用
      expect(vm.checkCollectionLost(noCover), isFalse);
    });

    test('clearCoverCheckCache 可安全调用', () {
      vm.checkItemLost(item('i1'));
      vm.clearCoverCheckCache();
      expect(vm.checkItemLost(item('i1')), isFalse);
    });
  });

  // ── 排序枚举 label ─────────────────────────────────────────────────────────

  group('排序枚举', () {
    test('MediaItemSortOrder / CollectionSortOrder 每个成员都有非空中文 label', () {
      for (final o in MediaItemSortOrder.values) {
        expect(o.label, isNotEmpty);
      }
      for (final o in CollectionSortOrder.values) {
        expect(o.label, isNotEmpty);
      }
      expect(MediaItemSortOrder.nameAsc.label, '文件名 A→Z');
      expect(CollectionSortOrder.combinedSort.label, '综合排序');
    });
  });
}
