import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/mock/seams/novel_api_seam.dart';
import 'package:slime_works/mock/seams/novel_api_seam.dart' as rust_api;

part 'novel_library_viewmodel_novel.dart';
part 'novel_library_viewmodel_actions.dart';
const Loggers _logger = Loggers(name: '书库');

/// 后台封面存在性检查的 isolate 入口（顶层函数）。
/// ★ 闭包必须只捕获可发送的参数：捕获 VM 实例（哪怕只在 catch 里用 _logger）
/// 会让 Isolate.run 报 object is unsendable。
Map<String, bool> _checkCoverFilesExist(Set<String> paths) {
  final map = <String, bool>{};
  for (final p in paths) {
    try {
      map[p] = File(p).existsSync();
    } catch (_) {
      map[p] = false;
    }
  }
  return map;
}


/// 书库 ViewModel
class NovelLibraryViewModel extends BaseViewModel {
  final NodeSettingsService nodeSettingsService = getIt<NodeSettingsService>();
  Worker? _nodeMutationWorker;

  /// mutation tick 整轮重拉的防抖窗口：一次导入/批量操作会连发多个 tick，
  /// 2s 内的变更合并成一次刷新，避免 N 个事件 × N 个节点的整轮重付。
  static const _remoteRefreshDebounce = Duration(seconds: 2);
  Timer? _remoteRefreshDebounceTimer;

  /// 远程书架刷新的代际号：并发刷新时旧一轮的结果不得覆盖新一轮。
  int _remoteRefreshGeneration = 0;

  /// 首屏后台远程刷新的在途句柄（不阻塞 onInitAsync，测试可显式等待）。
  Future<void>? _backgroundRemoteRefresh;

  // 书库 数据
  final novels = <NovelMetadata>[].obs;
  final remoteNovels = <NovelMetadata>[].obs;
  final isScanning = false.obs;
  final scanStatusText = ''.obs;
  final scanProgressText = ''.obs;
  final searchQuery = ''.obs;
  final searchByContent = false.obs;
  final isSearching = false.obs;
  final isCancelling = false.obs;
  final searchProgress = 0.0.obs;
  final searchTotal = 0.obs;
  final searchCompleted = 0.obs;
  final contentSearchResults = <NovelMetadata>[].obs;
  final isClearingNovels = false.obs;

  // 文件夹数据
  final folders = <NovelFolder>[].obs;

  /// 当前文件夹 ID，null = 根目录
  final currentFolderId = RxnString();

  /// 保存的滚动位置
  final savedScrollOffset = 0.0.obs;

  // 分页相关
  final displayedItemCount = 100.obs; // 当前显示的项目数量
  final itemsPerPage = 50; // 每次加载更多的数量

  // 选择相关
  final selectedIds = <String>{}.obs;
  final isSelecting = false.obs;

  // 搜索取消标志
  bool searchCancelled = false;

  // Tag 过滤
  final selectedFilterTags = <String>[].obs;

  // 收藏筛选
  final showFavoritesOnly = false.obs;

  // 关键词规则
  final keywordRules = <Map<String, String>>[].obs;
  final keywordApplyCompleted = 0.obs;
  final keywordApplyTotal = 0.obs;

  // 章节数量缓存（novelId -> chapterCount）
  final chapterCountMap = <String, int>{}.obs;

  // 远程节点映射
  final remoteNovelNodeId = <String, String>{}.obs;
  final remoteNovelNodeName = <String, String>{}.obs;
  final remoteNovelRawId = <String, String>{}.obs;
  final remoteFolderDisplayNames = <String, String>{}.obs;

  // 排序相关
  final sortField = 'addedAt'.obs; // 'addedAt', 'title', 'fileSize'
  final sortAscending = false.obs; // true=升序, false=降序

  /// 当前文件夹名称
  String get currentFolderName {
    final fid = currentFolderId.value;
    if (fid == null) return '';
    if (fid.startsWith('remote-folder:')) {
      return remoteFolderDisplayNames[fid] ?? '';
    }
    return folders.firstWhereOrNull((f) => f.id == fid)?.name ?? '';
  }

  /// 获取文件夹封面（返回该文件夹内第一本有封面的epub或txt书籍的封面路径）
  ///
  /// 纯读派生缓存：build 期间零 IO。存在性检查在后台批量完成后经
  /// coverCheckEpoch 通知刷新；缓存未命中时按「未证实丢失」先展示（占位闪一下可接受）。
  String? getFolderCover(String folderId) {
    final candidates = _folderCoverCandidates(folderId);
    for (final path in candidates) {
      if (_isCoverConfirmedMissing(path)) continue;
      return path;
    }
    return null;
  }

  /// 获取文件夹前6本书的封面列表（用于6宫格显示）
  ///
  /// 与 getFolderCover 同一口径：候选来自派生缓存，存在性只读后台检查结果。
  List<String> getFolderCovers(String folderId, {int maxCount = 6}) {
    final candidates = _folderCoverCandidates(folderId);
    final covers = <String>[];
    for (final path in candidates) {
      if (covers.length >= maxCount) break;
      if (_isCoverConfirmedMissing(path)) continue;
      covers.add(path);
    }
    return covers;
  }

  /// 获取文件夹直属书籍数量（不包含子文件夹）——O(1) 读派生缓存
  int getFolderNovelCount(String folderId) {
    _ensureFolderBooksCache();
    return _folderBooksCache[folderId]?.length ?? 0;
  }

  /// 文件夹封面候选（未做存在性过滤）：来自派生缓存的书籍列表，
  /// 保留书籍顺序、跳过空封面字段；data URI 与 http(s) URL 不做本地存在性检查。
  List<String> _folderCoverCandidates(String folderId) {
    _ensureFolderBooksCache();
    final books = _folderBooksCache[folderId] ?? const <NovelMetadata>[];
    final result = <String>[];
    for (final book in books) {
      final p = book.coverPath;
      if (p != null && p.isNotEmpty) result.add(p);
    }
    return result;
  }

  int? getNovelChapterCount(String novelId) {
    return chapterCountMap[novelId];
  }

  bool isRemoteNovel(String novelId) {
    return remoteNovelNodeId.containsKey(novelId);
  }

  String? getNovelNodeName(String novelId) {
    return remoteNovelNodeName[novelId];
  }

  String? getRemoteNodeId(String novelId) {
    return remoteNovelNodeId[novelId];
  }

  String? getRemoteRawNovelId(String novelId) {
    return remoteNovelRawId[novelId];
  }

  bool isRemoteFolderId(String folderId) {
    return folderId.startsWith('remote-folder:');
  }

  String _buildRemoteFolderSyntheticId(String nodeId, String folderId) {
    return 'remote-folder:$nodeId:$folderId';
  }

  List<NovelMetadata> _getBooksInFolder(String folderId) {
    _ensureFolderBooksCache();
    final cached = _folderBooksCache[folderId];
    // ★ 必须给副本：filteredItems 会对返回值原地 _sortBooks，
    // 直接交出缓存列表会把派生缓存的顺序也排掉（封面候选顺序随之漂移）
    if (cached != null) return List<NovelMetadata>.of(cached);
    // 未建索引的临时目录 ID（如刚创建尚未入库）按空处理；
    // 索引在 novels/remoteNovels 下一次变更时整体重建
    return <NovelMetadata>[];
  }

  // ── 文件夹→书籍 派生缓存（审计 #5） ────────────────────────────────────────
  // 原实现每张文件夹卡 build 期间做 O(全部书籍) 过滤 + 逐封面 existsSync，
  // SMB/外置卷上每次重建近百次网络 stat。改为：novels/remoteNovels/映射表变更
  // 时置脏，首次读取一次性重算全部分组；封面存在性由后台批量检查（见下）。

  /// 文件夹分组索引是否已失效（数据变更后待重算）
  bool _folderBooksCacheDirty = true;

  /// folderId（含 remote-folder: 合成 ID）→ 直属书籍列表
  Map<String, List<NovelMetadata>> _folderBooksCache = {};

  /// 缓存失效通知：Obx 里读它即可在数据/存在性变化后重建。
  /// ★ 只允许在 build/Obx 中读取；勿在 initState 里读 .value
  ///（GetX 4.7.3 会把父 Obx 注册成依赖导致整树反复重建）。
  final coverCheckEpoch = 0.obs;

  /// 数据源变更时挂失效标记（ever worker 回调，不主动 rebuild UI）。
  void _invalidateFolderDerivedCache() {
    _folderBooksCacheDirty = true;
  }

  /// 一次性重建 folderId → 书籍分组索引。
  void _ensureFolderBooksCache() {
    if (!_folderBooksCacheDirty) return;
    final map = <String, List<NovelMetadata>>{};
    for (final n in novels) {
      final fid = n.folderId;
      if (fid == null || fid.isEmpty) continue;
      (map[fid] ??= <NovelMetadata>[]).add(n);
    }
    for (final n in remoteNovels) {
      final nodeId = remoteNovelNodeId[n.id];
      final fid = n.folderId;
      if (nodeId == null || fid == null || fid.isEmpty) continue;
      // 合成格式 'remote-folder:<nodeId>:<folderId>'（与 _buildRemoteFolderSyntheticId 同口径）
      final syntheticId = _buildRemoteFolderSyntheticId(nodeId, fid);
      (map[syntheticId] ??= <NovelMetadata>[]).add(n);
    }
    _folderBooksCache = map;
    _folderBooksCacheDirty = false;
  }

  // ── 封面存在性后台检查（审计 #5） ──────────────────────────────────────────
  // existsSync 移出 build：数据变更时后台批量 stat 一轮，结果进缓存；
  // build 只读缓存，未命中按「未证实丢失」处理（先展示，丢失标记最迟下一轮出现）。

  /// 封面路径 → 是否存在（仅本地文件路径；data URI / URL 不参与）
  final Map<String, bool> _coverExistsCache = {};

  /// 后台批量检查的在途句柄（防重入）。
  /// ★ 必须用 completer.future 而不是 async 函数返回值：async 调用在首个 await
  /// 前同步执行，函数体内再置 _coverCheckInFlight 会覆盖掉外层 whenComplete 包装，
  /// 完成回调清掉的是旧引用，句柄永远不清空 → 后续调度全被「在途」挡掉。
  Future<void>? _coverCheckInFlight;

  /// 待检查的封面路径队列（数据变更时重置为全量）
  Set<String> _coverCheckPending = {};

  /// 是否为「已证实不存在」的本地封面。未检查过的路径返回 false（先展示）。
  bool _isCoverConfirmedMissing(String path) {
    if (path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return false;
    }
    return _coverExistsCache[path] == false;
  }

  /// 单本书封面是否已证实丢失（书卡丢失角标用；远程/未检查返回 false）。
  bool isNovelCoverLost(NovelMetadata meta) {
    if (isRemoteNovel(meta.id)) return false;
    final p = meta.coverPath;
    if (p == null || p.isEmpty) return false;
    _scheduleCoverExistenceCheck();
    return _isCoverConfirmedMissing(p);
  }

  /// 文件夹是否所有候选封面都已证实丢失（与旧 _isFolderLost 语义一致：
  /// 无封面候选不算丢失；远程虚拟夹不检查本地盘）。
  bool isFolderCoverLost(String folderId) {
    if (isRemoteFolderId(folderId)) return false;
    final candidates = _folderCoverCandidates(folderId);
    if (candidates.isEmpty) return false;
    _scheduleCoverExistenceCheck();
    return candidates.every(_isCoverConfirmedMissing);
  }

  /// 数据变更后安排一轮后台存在性检查（幂等：在途则并入下一轮）。
  void _scheduleCoverExistenceCheck() {
    // 收集当前全部本地封面路径（含远程回退的 cover_path 也一并跳过——
    // 远程书的封面存在性由节点负责，本地 stat 无意义）
    final paths = <String>{};
    for (final n in novels) {
      final p = n.coverPath;
      if (p == null || p.isEmpty) continue;
      if (p.startsWith('data:') || p.startsWith('http://') || p.startsWith('https://')) {
        continue;
      }
      paths.add(p);
    }
    _coverCheckPending = paths;
    if (_coverCheckInFlight != null) return;
    // 先挂句柄再启动：async 函数体在首个 await 前同步执行，
    // 若启动后再赋值，whenComplete 清句柄时会误清新一轮的引用
    final completer = Completer<void>();
    _coverCheckInFlight = completer.future;
    _runCoverExistenceCheck().whenComplete(() {
      _coverCheckInFlight = null;
      completer.complete();
    });
  }

  /// 后台批量 stat 的执行体（可被测试注入替换）。
  ///
  /// 默认实现用 Isolate.run 把同步 IO 挪出 UI isolate；flutter_test 的测试区
  /// 禁止 spawn isolate（会报 unsendable/_Future），测试里注入同步实现即可——
  /// 「检查不在 build 期执行、结果经缓存+epoch 通知」的语义不变。
  @visibleForTesting
  static Future<Map<String, bool>> Function(Set<String> paths) coverExistenceChecker =
      _defaultCoverExistenceChecker;

  static Future<Map<String, bool>> _defaultCoverExistenceChecker(Set<String> paths) {
    // 只传纯数据进 isolate：闭包捕获 VM 实例会报 unsendable
    return Isolate.run(() => _checkCoverFilesExist(paths));
  }

  /// 后台批量 stat：结果回来后合并进缓存并 bump coverCheckEpoch 通知卡片重建。
  Future<void> _runCoverExistenceCheck() async {
    // 让出当前帧：本函数可能由 build 期间的同步读触发，
    // 通知必须落在帧外，避免 Obx 重建期写 Rx 冲突
    await null;
    while (_coverCheckPending.isNotEmpty) {
      final batch = _coverCheckPending;
      _coverCheckPending = <String>{};
      Map<String, bool> results;
      try {
        results = await coverExistenceChecker(batch);
      } catch (e) {
        _logger.log('[CoverCheck] 后台存在性检查失败: $e', name: '书库');
        return;
      }
      var changed = false;
      results.forEach((p, exists) {
        if (_coverExistsCache[p] != exists) {
          _coverExistsCache[p] = exists;
          changed = true;
        }
      });
      if (changed && !isClosed) {
        coverCheckEpoch.value++;
      }
    }
  }

  /// 供测试等待后台检查完成（生产代码不需要）。
  Future<void> debugWaitCoverCheck() async {
    while (_coverCheckInFlight != null) {
      await _coverCheckInFlight;
    }
  }

  List<NovelFolder> _buildRemoteVirtualFolders() {
    final map = <String, NovelFolder>{};

    for (final novel in remoteNovels) {
      final nodeId = getRemoteNodeId(novel.id);
      final folderId = novel.folderId;
      if (nodeId == null || folderId == null || folderId.isEmpty) {
        continue;
      }
      final syntheticId = _buildRemoteFolderSyntheticId(nodeId, folderId);
      final name = remoteFolderDisplayNames[syntheticId] ?? '远程目录';
      map[syntheticId] = NovelFolder(
        id: syntheticId,
        name: name,
        createdAt: 0,
        order: 999999,
        parentId: null,
      );
    }

    final list = map.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _logger.log('[RemoteDebug] 构建远程目录卡片数: ${list.length}', name: '书库');
    return list;
  }

  /// 当前展示的 items（文件夹 + 书籍）
  List<LibraryItem> get filteredItems {
    final fid = currentFolderId.value;
    final query = searchQuery.value;
    final filterTags = selectedFilterTags.toSet();
    final favoritesOnly = showFavoritesOnly.value;

    if (query.isNotEmpty) {
      List<NovelMetadata> results;
      if (searchByContent.value) {
        results = contentSearchResults.toList();
      } else {
        final lq = query.toLowerCase();
        final merged = <NovelMetadata>[...novels, ...remoteNovels];
        results = merged.where((n) => n.title.toLowerCase().contains(lq)).toList();
      }
      if (filterTags.isNotEmpty) {
        results = results.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
      }
      if (favoritesOnly) {
        results = results.where((n) => n.isFavorite).toList();
      }
      return results.map<LibraryItem>((n) => LibraryBookItem(n)).toList();
    }

    if (fid != null) {
      var folderBooks = _getBooksInFolder(fid);
      if (filterTags.isNotEmpty) {
        folderBooks = folderBooks.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
      }
      if (favoritesOnly) {
        folderBooks = folderBooks.where((n) => n.isFavorite).toList();
      }
      _sortBooks(folderBooks);
      return folderBooks.map<LibraryItem>((n) => LibraryBookItem(n)).toList();
    }

    final sortedFolders = folders.toList()
      ..sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        if (cmp != 0) return cmp;
        return b.createdAt.compareTo(a.createdAt);
      });
    final remoteFolders = _buildRemoteVirtualFolders();

    var rootBooks = novels.where((n) => n.folderId == null).toList();
    rootBooks.addAll(remoteNovels.where((n) => n.folderId == null || n.folderId!.isEmpty));
    if (filterTags.isNotEmpty) {
      rootBooks = rootBooks.where((n) => n.tags.any((t) => filterTags.contains(t))).toList();
    }
    if (favoritesOnly) {
      rootBooks = rootBooks.where((n) => n.isFavorite).toList();
    }
    _sortBooks(rootBooks);

    return [
      if (filterTags.isEmpty) ...sortedFolders.map<LibraryItem>((f) => LibraryFolderItem(f)),
      if (filterTags.isEmpty) ...remoteFolders.map<LibraryItem>((f) => LibraryFolderItem(f)),
      ...rootBooks.map<LibraryItem>((n) => LibraryBookItem(n)),
    ];
  }

  /// 用于显示的项目（支持分页）
  List<LibraryItem> get displayedItems {
    final allItems = filteredItems;
    final maxCount = displayedItemCount.value;
    if (allItems.length <= maxCount) {
      return allItems;
    }
    return allItems.sublist(0, maxCount);
  }

  /// 是否可以加载更多
  bool get canLoadMore => filteredItems.length > displayedItemCount.value;

  /// 加载更多项目
  void loadMoreItems() {
    if (!canLoadMore) return;
    final allCount = filteredItems.length;
    final newCount = (displayedItemCount.value + itemsPerPage).clamp(0, allCount);
    displayedItemCount.value = newCount;
    _logger.info('加载更多：当前显示 $newCount / $allCount');
  }

  /// 重置分页（切换文件夹或筛选时调用）
  void resetPagination() {
    displayedItemCount.value = 100;
  }

  /// 所有书籍拥有的 tags
  List<String> get allAvailableTags {
    return allTagCounts.keys.toList()..sort();
  }

  void filterBySingleTag(String tag) {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      return;
    }
    selectedFilterTags.assignAll(<String>[normalized]);
    searchQuery.value = '';
    searchByContent.value = false;
    resetPagination();
  }

  /// 所有书籍标签计数（tag -> count）
  Map<String, int> get allTagCounts {
    final tagCountMap = <String, int>{};
    for (final n in [...novels, ...remoteNovels]) {
      for (final tag in n.tags) {
        tagCountMap[tag] = (tagCountMap[tag] ?? 0) + 1;
      }
    }
    return tagCountMap;
  }

  void _sortBooks(List<NovelMetadata> list) {
    list.sort((a, b) {
      // 1. 收藏的书籍优先
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;

      // 2. 在收藏分组内按用户选择的排序方式
      final field = sortField.value;
      final ascending = sortAscending.value;
      int cmp = 0;

      switch (field) {
        case 'addedAt':
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
        case 'title':
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'fileSize':
          cmp = a.fileSize.compareTo(b.fileSize);
          break;
        case 'customOrder':
          // 使用 customOrder 排序
          final aOrder = a.customOrder ?? 999999;
          final bOrder = b.customOrder ?? 999999;
          cmp = aOrder.compareTo(bOrder);
          if (cmp == 0) cmp = a.addedAt.compareTo(b.addedAt);
          break;
        default:
          // 回退到 addedAt
          cmp = a.addedAt.compareTo(b.addedAt);
      }

      return ascending ? cmp : -cmp;
    });
  }

  /// 设置排序选项
  void setSortOption(String field, bool ascending) {
    sortField.value = field;
    sortAscending.value = ascending;
    _logger.info('排序设置: $field ${ascending ? "升序" : "降序"}');
  }

  /// 过滤后的书籍列表
  List<NovelMetadata> get filteredNovels {
    final sortTest = TimeConsumptionTest()..start(log: false);
    final result = filteredItems.whereType<LibraryBookItem>().map((i) => i.metadata).toList();
    _logger.log('书库 ${result.length} 本，耗时 +${sortTest.end(log: false)}ms', name: '书库');
    return result;
  }

  /// 数据变更挂钩是否已安装（幂等）
  bool _dataHooksInstalled = false;

  /// 安装派生缓存失效 + 封面存在性检查的数据源挂钩。
  ///
  /// ★ 不能只放 onInitAsync：那是 BasePage 的页面级钩子，VM 被直接使用
  ///（Get.put / 测试）时不会执行，缓存将永远不失效。onStart 在两种路径下
  /// 都会被 GetX 生命周期调用，这里兜底安装；onInitAsync 再调一次是幂等 no-op。
  void _installDataHooks() {
    if (_dataHooksInstalled) return;
    _dataHooksInstalled = true;
    // 派生缓存失效挂数据源：novels/remoteNovels/节点映射任何变更都置脏，
    // 下一次读取一次性重算（worker 回调不在 build 期，无 Obx 依赖收集问题）
    ever<List<NovelMetadata>>(novels, (_) => _invalidateFolderDerivedCache());
    ever<List<NovelMetadata>>(remoteNovels, (_) => _invalidateFolderDerivedCache());
    ever<Map<String, String>>(remoteNovelNodeId, (_) => _invalidateFolderDerivedCache());
    // 本地书列表变更时安排一轮后台封面存在性检查（existsSync 不进 build）
    ever<List<NovelMetadata>>(novels, (_) => _scheduleCoverExistenceCheck());
  }

  @override
  void onInit() {
    super.onInit();
    _installDataHooks();
  }

  @override
  Future<void> onInitAsync() async {
    if (isInitialized) {
      return;
    }
    await super.onInitAsync();
    _installDataHooks();
    await nodeSettingsService.init();
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) {
      // 本地数据轻量重拉照旧；远程整轮重拉走 2s 防抖合并
      //（一次导入/批量操作会连发多个 tick，避免 N 事件 × N 节点整轮重付）
      unawaited(loadNovels());
      unawaited(loadFolders());
      _scheduleRemoteRefreshDebounced();
    });
    await Future.wait([loadData(), loadKeywordRules(), loadChapterCounts()]);
    // 审计 #3：远程刷新移出首屏 await——先显示本地书，远程到货再刷新。
    // 原先 N 节点串行 × 全量封面 base64 的传输直接压在进页面链路上。
    _backgroundRemoteRefresh = refreshRemoteNovels();
    unawaited(_backgroundRemoteRefresh);
  }

  /// mutation tick 的远程刷新防抖：窗口内多次触发只执行最后一次。
  void _scheduleRemoteRefreshDebounced() {
    _remoteRefreshDebounceTimer?.cancel();
    _remoteRefreshDebounceTimer = Timer(_remoteRefreshDebounce, () {
      if (isClosed) return;
      unawaited(refreshRemoteNovels());
    });
  }

  /// 供测试等待首屏后台远程刷新完成。
  Future<void> debugWaitRemoteRefresh() async {
    await _backgroundRemoteRefresh;
  }

  @override
  void onClose() {
    _nodeMutationWorker?.dispose();
    _nodeMutationWorker = null;
    _remoteRefreshDebounceTimer?.cancel();
    _remoteRefreshDebounceTimer = null;
    super.onClose();
  }

  Future<void> refreshRemoteNovels() async {
    // 代际号防过期覆盖：mutation 防抖刷新与用户操作后的显式刷新可能交叠，
    // 只有最新一轮的结果才允许写入 Rx
    final generation = ++_remoteRefreshGeneration;
    final allRemote = <NovelMetadata>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};
    final remoteFolderNames = <String, String>{};
    final remoteChapterCounts = <String, int>{};
    final previousRemoteIds = remoteNovelNodeId.keys.toSet();

    // 审计 #3：节点间由串行 for-await 改并发（失败熔断由 _callNode 内部负责）
    final nodes = nodeSettingsService.enabledRemoteNodes;
    await Future.wait(nodes.map((node) async {
      try {
        final payloads = await nodeSettingsService.fetchNodeNovels(node);
        _logger.log('[RemoteDebug] 节点 ${node.name} 返回书籍数: ${payloads.length}', name: '书库');
        for (final payload in payloads) {
          final remoteId = (payload['id'] ?? '').toString();
          if (remoteId.isEmpty) continue;

          final syntheticId = 'remote:${node.id}:$remoteId';
          final model = _buildRemoteNovelModel(payload, syntheticId, node);
          allRemote.add(model);
          nodeIdMap[syntheticId] = node.id;
          nodeNameMap[syntheticId] = node.name;
          rawIdMap[syntheticId] = remoteId;

          final folderIdRaw = payload['folder_id'];
          final folderId = folderIdRaw?.toString();
          if (folderId != null && folderId.isNotEmpty) {
            final syntheticFolderId = _buildRemoteFolderSyntheticId(node.id, folderId);
            final folderName =
                payload['folder_name']?.toString() ?? payload['folder_title']?.toString() ?? '远程目录';
            remoteFolderNames[syntheticFolderId] = folderName;
          }

          final chapterCount = _parseChapterCount(payload);
          if (chapterCount != null) {
            remoteChapterCounts[syntheticId] = chapterCount;
          }
        }
      } catch (e) {
        _logger.log('拉取远程节点书籍失败: ${node.name} -> $e', name: '书库');
      }
    }));

    if (generation != _remoteRefreshGeneration || isClosed) {
      // 已有更新一轮在跑/完成，本轮结果作废
      return;
    }

    remoteNovels.assignAll(allRemote);
    remoteNovelNodeId.assignAll(nodeIdMap);
    remoteNovelNodeName.assignAll(nodeNameMap);
    remoteNovelRawId.assignAll(rawIdMap);
    remoteFolderDisplayNames.assignAll(remoteFolderNames);
    _logger.log(
      '[RemoteDebug] 汇总: remoteNovels=${allRemote.length}, remoteFolders=${remoteFolderNames.length}',
      name: '书库',
    );

    chapterCountMap.removeWhere(
      (novelId, _) => previousRemoteIds.contains(novelId) && !nodeIdMap.containsKey(novelId),
    );
    chapterCountMap.addAll(remoteChapterCounts);
  }

  int? _parseChapterCount(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['chapter_count'],
      payload['chapters_count'],
      payload['chapterCount'],
      payload['chaptersCount'],
      payload['chapter_total'],
    ];

    for (final value in candidates) {
      if (value == null) {
        continue;
      }
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      final parsed = int.tryParse(value.toString());
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// 由节点 payload 组装远程书模型。
  ///
  /// 封面来源三级：
  /// 1. 旧节点仍回 cover_base64（不认识 with_cover=false）→ 保持 data URI（离线可显示）；
  /// 2. 新节点（with_cover=false 只回元数据）且书有封面 → 拼 GET /node/novel_cover
  ///    按需 URL，显示时 Image.network 流式取（首见闪占位可接受）；
  /// 3. 无节点上下文/无封面 → 回退 payload 的 cover_path（可能为 null，显示占位）。
  NovelMetadata _buildRemoteNovelModel(
    Map<String, dynamic> payload,
    String syntheticId, [
    NodeEndpoint? node,
  ]) {
    final formatRaw = (payload['format'] ?? 'txt').toString().toLowerCase();
    final format = formatRaw == 'epub' ? NovelFormat.epub : NovelFormat.txt;
    final fileSize = BigInt.tryParse((payload['file_size'] ?? '0').toString()) ?? BigInt.zero;
    final modifiedAt = int.tryParse((payload['modified_at'] ?? '0').toString()) ?? 0;
    final addedAt = int.tryParse((payload['added_at'] ?? '0').toString()) ?? 0;
    final lastReadAtRaw = payload['last_read_at'];
    final lastReadAt = lastReadAtRaw == null ? null : int.tryParse(lastReadAtRaw.toString());
    final tags = (payload['tags'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final folderIdRaw = payload['folder_id'];
    final folderId = (folderIdRaw == null || folderIdRaw.toString().isEmpty)
        ? null
        : folderIdRaw.toString();
    final coverBase64 = payload['cover_base64']?.toString();
    final coverExt = (payload['cover_ext'] ?? 'png').toString();
    final coverDataUri = (coverBase64 != null && coverBase64.isNotEmpty)
        ? 'data:image/$coverExt;base64,$coverBase64'
        : null;
    final rawCoverPath = payload['cover_path']?.toString();
    String? coverPath = coverDataUri;
    if (coverPath == null &&
        node != null &&
        rawCoverPath != null &&
        rawCoverPath.isNotEmpty) {
      final rawId = (payload['id'] ?? '').toString();
      try {
        // 封面被替换后节点按 id 覆盖写同名文件，URL 不变会命中客户端旧图缓存；
        // 把书籍 modified_at 拼成版本号，换封面后 URL 随之变化
        coverPath = nodeSettingsService.buildNodeNovelCoverUrl(
          nodeId: node.id,
          novelId: rawId,
          cacheBuster: modifiedAt,
        );
      } catch (_) {
        coverPath = null;
      }
    }
    // 旧口径回退：无法拼 URL 时保留节点侧路径（与改动前行为一致）
    coverPath ??= rawCoverPath;

    return NovelMetadata(
      id: syntheticId,
      title: (payload['title'] ?? '未命名书籍').toString(),
      author: payload['author']?.toString(),
      filePath: (payload['file_path'] ?? '').toString(),
      format: format,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      addedAt: addedAt,
      progress: (payload['progress'] is num) ? (payload['progress'] as num).toDouble() : 0,
      lastReadAt: lastReadAt,
      coverPath: coverPath,
      folderId: folderId,
      customOrder: payload['custom_order'] is int ? payload['custom_order'] as int : null,
      isFavorite: payload['is_favorite'] == true,
      tags: tags,
      notes: payload['notes']?.toString(),
    );
  }

  void showSnack(
    String title,
    String message, {
    SnackPosition? position,
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final context = navigatorKey.currentContext;
        if (context == null) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '$title：$message',
                style: colorText == null ? null : TextStyle(color: colorText),
              ),
              duration: duration ?? AppMotion.dwell,
              backgroundColor: backgroundColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
      } catch (_) {}
    });
  }

  Future<void> loadData() async {
    await Future.wait([loadNovels(), loadFolders()]);
  }

  Future<void> loadNovels() async {
    final t = TimeConsumptionTest()..start(log: false);
    try {
      novels.value = getAllNovels();
      _logger.log('加载书籍 ${novels.length} 本(+${t.end(log: false)}ms)', name: '书库');
    } catch (e) {
      showSnack('错误', '加载书籍列表失败: $e');
    }
  }

  Future<void> loadFolders() async {
    try {
      folders.value = getAllFolders();
    } catch (e) {
      showSnack('错误', '加载文件夹失败: $e');
    }
  }

  void enterSelection(String firstId) {
    isSelecting.value = true;
    selectedIds.add(firstId);
  }

  void exitSelection() {
    isSelecting.value = false;
    selectedIds.clear();
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
      if (selectedIds.isEmpty) exitSelection();
    } else {
      selectedIds.add(id);
    }
  }

  void toggleSelectAll() {
    final items = filteredItems;
    if (selectedIds.length == items.length) {
      selectedIds.clear();
    } else {
      selectedIds.assignAll(items.map((i) => i.id).toSet());
    }
  }
}
