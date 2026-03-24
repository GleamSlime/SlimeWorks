part of 'novel_library_viewmodel.dart';

/// 多选批量操作、拖拽排序、内容搜索
extension NovelLibraryActions on NovelLibraryViewModel {
  // ─────────────────────────────────────────
  // 多选批量操作
  // ─────────────────────────────────────────

  /// 删除所有已选项目（书籍直接删除，文件夹只删除文件夹本身，书籍移至根目录）
  Future<void> deleteSelected() async {
    final ids = selectedIds.toList();
    final folderIds = ids.where((id) => folders.any((f) => f.id == id)).toList();
    final novelIds = ids.where((id) => novels.any((n) => n.id == id) || isRemoteNovel(id)).toList();

    for (final fid in folderIds) {
      rust_api.deleteFolder(folderId: fid);
    }
    for (final nid in novelIds) {
      await deleteNovel(nid);
    }

    exitSelection();
    await loadData();
    await refreshRemoteNovels();
    showSnack('成功', '已删除 ${ids.length} 个项目');
  }

  /// 批量收藏/取消收藏已选中的书籍
  Future<void> favoriteSelected() async {
    final novelIds = selectedIds
        .where((id) => novels.any((n) => n.id == id) || isRemoteNovel(id))
        .toList();
    if (novelIds.isEmpty) return;
    try {
      final allFavorited = novelIds.every((id) {
        final local = novels.firstWhereOrNull((n) => n.id == id);
        if (local != null) return local.isFavorite;
        final remote = remoteNovels.firstWhereOrNull((n) => n.id == id);
        return remote?.isFavorite ?? false;
      });
      for (final id in novelIds) {
        await toggleFavorite(id);
      }
      exitSelection();
      await loadNovels();
      await refreshRemoteNovels();
      showSnack('成功', allFavorited ? '已取消收藏' : '已添加到收藏');
    } catch (e) {
      showSnack('错误', '收藏操作失败: $e');
    }
  }

  /// 批量移动已选中书籍到指定文件夹（folderId 为 null 则移回根目录）
  Future<void> moveSelectedToFolder(String? folderId) async {
    final novelIds = selectedIds.where((id) => novels.any((n) => n.id == id)).toList();
    if (novelIds.isEmpty) return;
    try {
      for (final id in novelIds) {
        rust_api.moveNovelToFolder(novelId: id, folderId: folderId);
      }
      exitSelection();
      await loadNovels();
      showSnack('成功', '已移动 ${novelIds.length} 本书籍');
    } catch (e) {
      showSnack('错误', '移动书籍失败: $e');
    }
  }

  // ─────────────────────────────────────────
  // 拖拽排序
  // ─────────────────────────────────────────

  /// 将 [oldIndex] 的 item 移动到 [newIndex]（同类型之间才生效）
  Future<void> reorderItems(int oldIndex, int newIndex) async {
    final items = filteredItems;
    logger.log('reorderItems start: $oldIndex -> $newIndex, items=${items.length}', name: '书库');
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex >= items.length) return;

    final moved = items[oldIndex];
    final target = items[newIndex];

    if (moved is LibraryFolderItem && target is LibraryFolderItem) {
      final folderList = items.whereType<LibraryFolderItem>().map((f) => f.folder).toList();
      final from = folderList.indexWhere((f) => f.id == moved.id);
      final to = folderList.indexWhere((f) => f.id == target.id);
      logger.log('reorderFolders from $from to $to', name: '书库');
      if (from == -1 || to == -1) return;
      final item = folderList.removeAt(from);
      folderList.insert(to, item);
      rust_api.batchUpdateFolderOrders(folderIds: folderList.map((f) => f.id).toList());
      await loadFolders();
    } else if (moved is LibraryBookItem && target is LibraryBookItem) {
      final bookList = items.whereType<LibraryBookItem>().map((b) => b.metadata).toList();
      final from = bookList.indexWhere((b) => b.id == moved.id);
      final to = bookList.indexWhere((b) => b.id == target.id);
      logger.log(
        'reorderBooks index from $from to $to (moved=${moved.id} target=${target.id})',
        name: '书库',
      );
      if (from == -1 || to == -1) return;
      final item = bookList.removeAt(from);
      bookList.insert(to, item);
      final orderedIds = bookList.map((b) => b.id).toList();
      // capture old orders before applying local update
      final oldOrderMap = {for (final n in novels) n.id: n.customOrder};
      _applyBookOrderLocally(orderedIds);
      // 拖拽排序后,切换到customOrder排序模式
      sortField.value = 'customOrder';
      logger.log(
        'scheduling async persist of changed novel orders for ${orderedIds.length} novels',
        name: '书库',
      );
      Future<void>(() async {
        logger.log('persist changed orders started', name: '书库');
        await _persistNovelOrdersChanged(oldOrderMap, orderedIds);
        logger.log('persist changed orders finished', name: '书库');
      });
    }
    // 跨类型拖拽忽略
  }

  /// 根据 item id 进行重排 —— 将 movedId 插入到 targetId 的前面（前置语义）
  Future<void> reorderItemsById(String movedId, String targetId) async {
    final items = filteredItems;
    logger.log(
      'reorderItemsById start: moved=$movedId target=$targetId, items=${items.length}',
      name: '书库',
    );
    final movedIdx = items.indexWhere((i) => i.id == movedId);
    final targetIdx = items.indexWhere((i) => i.id == targetId);
    if (movedIdx == -1 || targetIdx == -1 || movedIdx == targetIdx) return;

    if (items[movedIdx] is LibraryBookItem && items[targetIdx] is LibraryBookItem) {
      final bookList = items.whereType<LibraryBookItem>().map((b) => b.metadata).toList();
      final from = bookList.indexWhere((b) => b.id == movedId);
      final to = bookList.indexWhere((b) => b.id == targetId);
      logger.log(
        'reorderBooksById from $from to $to (moved=$movedId target=$targetId)',
        name: '书库',
      );
      if (from == -1 || to == -1 || from == to) return;
      final movedItem = bookList.removeAt(from);
      // 用 indexWhere 找到 removeAt 后 target 的实际位置，再插入其前。
      // 避免手动计算 to-1 / to 导致的向前拖拽语义错误。
      final insertAt = bookList.indexWhere((b) => b.id == targetId);
      bookList.insert(insertAt == -1 ? bookList.length : insertAt, movedItem);
      final orderedIds = bookList.map((b) => b.id).toList();
      final oldOrderMap = {for (final n in novels) n.id: n.customOrder};
      _applyBookOrderLocally(orderedIds);
      // 拖拽排序后,切换到customOrder排序模式
      sortField.value = 'customOrder';
      logger.log(
        'scheduling async persist of changed novel orders for ${orderedIds.length} novels (byId)',
        name: '书库',
      );
      Future<void>(() async {
        logger.log('persist changed orders (byId) started', name: '书库');
        await _persistNovelOrdersChanged(oldOrderMap, orderedIds);
        logger.log('persist changed orders (byId) finished', name: '书库');
      });
    } else if (items[movedIdx] is LibraryFolderItem && items[targetIdx] is LibraryFolderItem) {
      final folderList = items.whereType<LibraryFolderItem>().map((f) => f.folder).toList();
      final from = folderList.indexWhere((f) => f.id == movedId);
      final to = folderList.indexWhere((f) => f.id == targetId);
      if (from == -1 || to == -1 || from == to) return;
      final movedItem = folderList.removeAt(from);
      final insertAt = folderList.indexWhere((f) => f.id == targetId);
      folderList.insert(insertAt == -1 ? folderList.length : insertAt, movedItem);
      rust_api.batchUpdateFolderOrders(folderIds: folderList.map((f) => f.id).toList());
      await loadFolders();
    }
  }

  void _applyBookOrderLocally(List<String> orderedIds) {
    final orderMap = <String, int>{for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i};
    logger.log('Applying local book order for ${orderedIds.length} ids', name: '书库');

    final updated = novels.map((novel) {
      final order = orderMap[novel.id];
      if (order == null) return novel;

      return NovelMetadata(
        id: novel.id,
        title: novel.title,
        author: novel.author,
        filePath: novel.filePath,
        format: novel.format,
        fileSize: novel.fileSize,
        modifiedAt: novel.modifiedAt,
        isFavorite: novel.isFavorite,
        tags: novel.tags,
        addedAt: novel.addedAt,
        progress: novel.progress,
        lastReadAt: novel.lastReadAt,
        coverPath: novel.coverPath,
        folderId: novel.folderId,
        customOrder: order,
        notes: novel.notes,
      );
    }).toList();

    novels.assignAll(updated);
    logger.log('Local book order applied, novels updated count=${novels.length}', name: '书库');
  }

  /// Persist only changed novel orders by calling `updateNovelOrder` per item.
  /// This avoids a single large blocking native call and yields to the event loop
  /// between batches so the UI remains responsive.
  Future<void> _persistNovelOrdersChanged(
    Map<String, int?> oldOrderMap,
    List<String> orderedIds,
  ) async {
    final changed = <MapEntry<String, int>>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final newOrder = i;
      final old = oldOrderMap[id];
      if (old == null || old != newOrder) changed.add(MapEntry(id, newOrder));
    }

    logger.log('persist changed count=${changed.length}', name: '书库');
    if (changed.isEmpty) return;

    try {
      // update in small batches to give UI time to process events
      const batchSize = 50;
      for (int i = 0; i < changed.length; i += batchSize) {
        final end = (i + batchSize) < changed.length ? (i + batchSize) : changed.length;
        final batch = changed.sublist(i, end);
        for (final entry in batch) {
          try {
            rust_api.updateNovelOrder(novelId: entry.key, order: entry.value);
          } catch (err) {
            logger.log('updateNovelOrder failed for ${entry.key}: $err', name: '书库');
          }
        }
        // yield to event loop
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } catch (e) {
      logger.log('persistNovelOrdersChanged error: $e', name: '书库');
    }
  }

  // ─────────────────────────────────────────
  // 内容搜索
  // ─────────────────────────────────────────

  Future<void> searchInContent(String keyword) async {
    if (keyword.isEmpty) {
      contentSearchResults.clear();
      return;
    }

    try {
      searchCancelled = false;
      isSearching.value = true;
      isCancelling.value = false;
      searchProgress.value = 0.0;
      searchCompleted.value = 0;
      searchTotal.value = novels.length;
      contentSearchResults.clear();

      final allResults = <NovelMetadata>[];

      final batches = await searchInAllNovelsBatched(keyword: keyword, batchSize: BigInt.from(5));

      for (final batch in batches) {
        if (searchCancelled) {
          showSnack('搜索', '已取消搜索');
          break;
        }

        allResults.addAll(batch.results.map((r) => r.novel));

        final completed = batch.completed.toInt();
        final total = batch.total.toInt();
        searchCompleted.value = completed;
        searchTotal.value = total;
        searchProgress.value = total > 0 ? completed / total : 0.0;

        contentSearchResults.value = allResults.toList();
      }

      for (final node in nodeSettingsService.enabledRemoteNodes) {
        try {
          final results = await nodeSettingsService.searchNodeNovels(node, keyword);
          for (final payload in results) {
            final rawId = (payload['id'] ?? '').toString();
            if (rawId.isEmpty) continue;
            final syntheticId = 'remote:${node.id}:$rawId';
            final existed = allResults.any((n) => n.id == syntheticId);
            if (existed) continue;
            allResults.add(_buildRemoteNovelModel(payload, syntheticId));
            remoteNovelNodeId[syntheticId] = node.id;
            remoteNovelNodeName[syntheticId] = node.name;
            remoteNovelRawId[syntheticId] = rawId;
          }
        } catch (_) {}
      }

      contentSearchResults.value = allResults.toList();

      if (!searchCancelled) {
        if (allResults.isEmpty) {
          showSnack('搜索结果', '没有找到包含"$keyword"的书籍');
        } else {
          showSnack('搜索结果', '找到 ${allResults.length} 本包含关键词的书籍');
        }
      }
    } catch (e) {
      showSnack('错误', '搜索失败: $e');
    } finally {
      isSearching.value = false;
      searchProgress.value = 0.0;
    }
  }

  Future<void> cancelSearch() async {
    if (isCancelling.value) return;
    isCancelling.value = true;
    searchCancelled = true;
    try {
      rust_api.cancelSearch();
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      if (kDebugMode) print('取消搜索失败: $e');
    } finally {
      isCancelling.value = false;
    }
  }
}
