part of 'novel_library_viewmodel.dart';

/// 多选批量操作、拖拽排序、内容搜索
extension NovelLibraryActions on NovelLibraryViewModel {
  // ─────────────────────────────────────────
  // 多选批量操作
  // ─────────────────────────────────────────

  /// 删除所有已选项目（书籍直接删除，文件夹只删除文件夹本身，书籍移至根目录）
  ///
  /// ★ 远程夹必须发到节点：合成 id 灌进本机 FFI 要么报错要么什么都没删，而旧实现
  /// 无论成败最后都统一提示「已删除 N 个项目」—— 批量删远程夹时用户看到的假成功。
  /// 现在按远程/本机分流，并逐项收集失败原因，有失败就明确告诉用户失败了几项。
  Future<void> deleteSelected() async {
    final ids = selectedIds.toList();
    final folderIds = ids.where((id) => folders.any((f) => f.id == id)).toList();
    final remoteFolderIds = ids.where((id) => isRemoteFolderId(id)).toList();
    final novelIds = ids.where((id) => novels.any((n) => n.id == id) || isRemoteNovel(id)).toList();

    // 逐项收集失败：单项失败不该让整批中断，但也不能把失败算成成功
    final failures = <String>[];
    for (final fid in [...folderIds, ...remoteFolderIds]) {
      try {
        if (isRemoteFolderId(fid)) {
          final nodeId = getRemoteFolderNodeId(fid);
          final rawId = getRemoteFolderRawId(fid);
          if (nodeId == null || rawId == null) {
            throw StateError('远程节点映射不存在');
          }
          await nodeSettingsService.deleteNodeNovelFolder(nodeId: nodeId, folderId: rawId);
        } else {
          rust_api.deleteFolder(folderId: fid);
        }
      } catch (e) {
        failures.add('$fid: $e');
      }
    }
    for (final nid in novelIds) {
      try {
        await deleteNovel(nid);
        // deleteNovel 自身吞异常并只弹提示，这里回查数据是否真的没了
        // （远程书删除失败时列表不会被刷新掉）
        if (isRemoteNovel(nid) && remoteNovels.any((n) => n.id == nid)) {
          failures.add('$nid: 删除未生效');
        }
      } catch (e) {
        failures.add('$nid: $e');
      }
    }

    exitSelection();
    await loadData();
    await refreshRemoteNovels();
    if (failures.isEmpty) {
      showSnack('成功', '已删除 ${ids.length} 个项目');
    } else {
      // 让用户看见失败：不吞成「已删除 N 个项目」
      showSnack(
        '部分失败',
        '成功 ${ids.length - failures.length} 项，失败 ${failures.length} 项：${failures.first}',
      );
    }
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
  ///
  /// 远程书（含选中远程夹作为目标）一律经节点：合成 id 灌进本机 FFI 是静默失败。
  /// 走 `moveNovelToFolder`（它已按 isRemoteNovel 分流），目标夹是远程时先剥成 rawId。
  Future<void> moveSelectedToFolder(String? folderId) async {
    final novelIds = selectedIds
        .where((id) => novels.any((n) => n.id == id) || isRemoteNovel(id))
        .toList();
    if (novelIds.isEmpty) return;

    // 目标夹：远程夹要先换算成节点侧 rawId（合成 id 传给节点是无效 id）
    String? targetFolderId = folderId;
    if (folderId != null && isRemoteFolderId(folderId)) {
      final rawId = getRemoteFolderRawId(folderId);
      if (rawId == null) {
        showSnack('错误', '移动书籍失败: 无效的远程文件夹 ID');
        return;
      }
      targetFolderId = rawId;
    }

    final failures = <String>[];
    for (final id in novelIds) {
      try {
        // ★ 必须写 this.：本文件顶部无前缀 import 了 novel_api_seam，
        //   它的顶层 moveNovelToFolder 会遮蔽 VM 上的同名 extension 方法。
        await this.moveNovelToFolder(id, targetFolderId);
        // moveNovelToFolder 内部吞异常只弹提示，这里回查数据确认这次移动真的生效
        final remote = remoteNovels.firstWhereOrNull((n) => n.id == id);
        if (remote != null && remote.folderId != targetFolderId) {
          failures.add('$id: 移动未生效');
        }
      } catch (e) {
        failures.add('$id: $e');
      }
    }
    exitSelection();
    await loadNovels();
    await refreshRemoteNovels();
    if (failures.isEmpty) {
      showSnack('成功', '已移动 ${novelIds.length} 本书籍');
    } else {
      showSnack('部分失败', '成功 ${novelIds.length - failures.length} 本，失败 ${failures.length} 本');
    }
  }

  // ─────────────────────────────────────────
  // 拖拽排序
  // ─────────────────────────────────────────

  /// 将 [oldIndex] 的 item 移动到 [newIndex]（同类型之间才生效）
  Future<void> reorderItems(int oldIndex, int newIndex) async {
    final items = filteredItems;
    _logger.log('reorderItems start: $oldIndex -> $newIndex, items=${items.length}', name: '书库');
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex >= items.length) return;

    final moved = items[oldIndex];
    final target = items[newIndex];

    if (moved is LibraryFolderItem && target is LibraryFolderItem) {
      final folderList = items.whereType<LibraryFolderItem>().map((f) => f.folder).toList();
      final from = folderList.indexWhere((f) => f.id == moved.id);
      final to = folderList.indexWhere((f) => f.id == target.id);
      _logger.log('reorderFolders from $from to $to', name: '书库');
      if (from == -1 || to == -1) return;
      final item = folderList.removeAt(from);
      folderList.insert(to, item);
      await _persistFolderOrder(folderList.map((f) => f.id).toList());
    } else if (moved is LibraryBookItem && target is LibraryBookItem) {
      final bookList = items.whereType<LibraryBookItem>().map((b) => b.metadata).toList();
      final from = bookList.indexWhere((b) => b.id == moved.id);
      final to = bookList.indexWhere((b) => b.id == target.id);
      _logger.log(
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
      _logger.log(
        'scheduling async persist of changed novel orders for ${orderedIds.length} novels',
        name: '书库',
      );
      Future<void>(() async {
        _logger.log('persist changed orders started', name: '书库');
        await _persistNovelOrdersChanged(oldOrderMap, orderedIds);
        _logger.log('persist changed orders finished', name: '书库');
      });
    }
    // 跨类型拖拽忽略
  }

  /// 根据 item id 进行重排 —— 将 movedId 插入到 targetId 的前面（前置语义）
  Future<void> reorderItemsById(String movedId, String targetId) async {
    final items = filteredItems;
    _logger.log(
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
      _logger.log(
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
      _logger.log(
        'scheduling async persist of changed novel orders for ${orderedIds.length} novels (byId)',
        name: '书库',
      );
      Future<void>(() async {
        _logger.log('persist changed orders (byId) started', name: '书库');
        await _persistNovelOrdersChanged(oldOrderMap, orderedIds);
        _logger.log('persist changed orders (byId) finished', name: '书库');
      });
    } else if (items[movedIdx] is LibraryFolderItem && items[targetIdx] is LibraryFolderItem) {
      final folderList = items.whereType<LibraryFolderItem>().map((f) => f.folder).toList();
      final from = folderList.indexWhere((f) => f.id == movedId);
      final to = folderList.indexWhere((f) => f.id == targetId);
      if (from == -1 || to == -1 || from == to) return;
      final movedItem = folderList.removeAt(from);
      final insertAt = folderList.indexWhere((f) => f.id == targetId);
      folderList.insert(insertAt == -1 ? folderList.length : insertAt, movedItem);
      await _persistFolderOrder(folderList.map((f) => f.id).toList());
      await loadFolders();
    }
  }

  /// 持久化文件夹拖拽排序：远程夹必须发到节点，本机夹走 FFI。
  ///
  /// ★ 合成 id `remote-folder:<nodeId>:<rawId>` 灌进本机 FFI 是静默失败，
  ///   而旧实现拖完照样 `loadFolders()` 重拉本机表 —— 顺序看着「没保存」。
  ///   同一列表里混有本地夹与远程夹时，按各自的归属分别提交（顺序值互不相干）。
  Future<void> _persistFolderOrder(List<String> orderedIds) async {
    final localIds = <String>[];
    // nodeId → 该节点上按新顺序排好的 rawId 列表
    final remoteByNode = <String, List<String>>{};
    for (final id in orderedIds) {
      if (!isRemoteFolderId(id)) {
        localIds.add(id);
        continue;
      }
      final nodeId = getRemoteFolderNodeId(id);
      final rawId = getRemoteFolderRawId(id);
      if (nodeId == null || rawId == null) continue;
      (remoteByNode[nodeId] ??= <String>[]).add(rawId);
    }
    if (localIds.isNotEmpty) {
      rust_api.batchUpdateFolderOrders(folderIds: localIds);
    }
    for (final entry in remoteByNode.entries) {
      try {
        await nodeSettingsService.reorderNodeNovelFolders(
          nodeId: entry.key,
          folderIds: entry.value,
        );
      } catch (e) {
        showSnack('错误', '保存远程文件夹排序失败: $e');
      }
    }
    if (remoteByNode.isNotEmpty) {
      await refreshRemoteNovels();
    }
  }

  void _applyBookOrderLocally(List<String> orderedIds) {
    final orderMap = <String, int>{for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i};
    _logger.log('Applying local book order for ${orderedIds.length} ids', name: '书库');

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
    _logger.log('Local book order applied, novels updated count=${novels.length}', name: '书库');
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

    _logger.log('persist changed count=${changed.length}', name: '书库');
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
            _logger.log('updateNovelOrder failed for ${entry.key}: $err', name: '书库');
          }
        }
        // yield to event loop
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } catch (e) {
      _logger.log('persistNovelOrdersChanged error: $e', name: '书库');
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

      // 远程模式下本机书库不参与搜索，只问当前节点
      final localBatches = nodeSettingsService.isRemoteMode
          ? const <SearchBatchResult>[]
          : await searchInAllNovelsBatched(keyword: keyword, batchSize: BigInt.from(5));

      for (final batch in localBatches) {
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

      for (final node in nodeSettingsService.dataRemoteNodes) {
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
      if (kDebugMode) _logger.error('[书库] 取消搜索失败: $e');
    } finally {
      isCancelling.value = false;
    }
  }
}
