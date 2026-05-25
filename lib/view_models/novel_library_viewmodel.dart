import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart' hide cancelSearch;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

part 'novel_library_viewmodel_novel.dart';
part 'novel_library_viewmodel_actions.dart';
const Loggers _logger = Loggers(name: '书库');


/// 书库 ViewModel
class NovelLibraryViewModel extends BaseViewModel {
  final NodeSettingsService nodeSettingsService = getIt<NodeSettingsService>();
  Worker? _nodeMutationWorker;

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
  String? getFolderCover(String folderId) {
    final folderBooks = _getBooksInFolder(folderId);
    // 优先查找有封面的书籍
    for (final book in folderBooks) {
      if (book.coverPath != null && book.coverPath!.isNotEmpty) {
        final coverFile = File(book.coverPath!);
        if (coverFile.existsSync()) {
          return book.coverPath;
        }
      }
    }
    return null;
  }

  /// 获取文件夹前6本书的封面列表（用于6宫格显示）
  List<String> getFolderCovers(String folderId, {int maxCount = 6}) {
    final folderBooks = _getBooksInFolder(folderId);
    final covers = <String>[];

    for (final book in folderBooks) {
      if (covers.length >= maxCount) break;
      if (book.coverPath != null && book.coverPath!.isNotEmpty) {
        final coverFile = File(book.coverPath!);
        if (coverFile.existsSync()) {
          covers.add(book.coverPath!);
        }
      }
    }
    return covers;
  }

  /// 获取文件夹直属书籍数量（不包含子文件夹）
  int getFolderNovelCount(String folderId) {
    return _getBooksInFolder(folderId).length;
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

  (String nodeId, String folderId)? _parseRemoteFolderSyntheticId(String syntheticId) {
    if (!isRemoteFolderId(syntheticId)) return null;
    final parts = syntheticId.split(':');
    if (parts.length < 4) return null;
    final nodeId = parts[2];
    final folderId = parts.sublist(3).join(':');
    return (nodeId, folderId);
  }

  List<NovelMetadata> _getBooksInFolder(String folderId) {
    final remoteParsed = _parseRemoteFolderSyntheticId(folderId);
    if (remoteParsed != null) {
      final books = remoteNovels.where((n) {
        final nodeId = getRemoteNodeId(n.id);
        return nodeId == remoteParsed.$1 && n.folderId == remoteParsed.$2;
      }).toList();
      _logger.log(
        '[RemoteDebug] 进入远程目录: folder=$folderId, node=${remoteParsed.$1}, rawFolder=${remoteParsed.$2}, books=${books.length}',
        name: '书库',
      );
      return books;
    }
    return novels.where((n) => n.folderId == folderId).toList();
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

  @override
  Future<void> onInitAsync() async {
    if (isInitialized) {
      return;
    }
    await super.onInitAsync();
    await nodeSettingsService.init();
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) async {
      await loadNovels();
      await loadFolders();
    });
    await Future.wait([loadData(), loadKeywordRules(), loadChapterCounts()]);
    await refreshRemoteNovels();
  }

  @override
  void onClose() {
    _nodeMutationWorker?.dispose();
    _nodeMutationWorker = null;
    super.onClose();
  }

  Future<void> refreshRemoteNovels() async {
    final allRemote = <NovelMetadata>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};
    final remoteFolderNames = <String, String>{};
    final remoteChapterCounts = <String, int>{};
    final previousRemoteIds = remoteNovelNodeId.keys.toSet();

    for (final node in nodeSettingsService.enabledRemoteNodes) {
      try {
        final payloads = await nodeSettingsService.fetchNodeNovels(node);
        _logger.log('[RemoteDebug] 节点 ${node.name} 返回书籍数: ${payloads.length}', name: '书库');
        for (final payload in payloads) {
          final remoteId = (payload['id'] ?? '').toString();
          if (remoteId.isEmpty) continue;

          final syntheticId = 'remote:${node.id}:$remoteId';
          final model = _buildRemoteNovelModel(payload, syntheticId);
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
            _logger.log(
              '[RemoteDebug] 映射远程目录: node=${node.name}, folderId=$folderId, name=$folderName, synthetic=$syntheticFolderId',
              name: '书库',
            );
          }

          final chapterCount = _parseChapterCount(payload);
          if (chapterCount != null) {
            remoteChapterCounts[syntheticId] = chapterCount;
          }
        }
      } catch (e) {
        _logger.log('拉取远程节点书籍失败: ${node.name} -> $e', name: '书库');
      }
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

  NovelMetadata _buildRemoteNovelModel(Map<String, dynamic> payload, String syntheticId) {
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
      coverPath: coverDataUri ?? payload['cover_path']?.toString(),
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
              duration: duration ?? const Duration(seconds: 2),
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
