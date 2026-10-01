part of 'media_library_viewmodel.dart';

/// 导航与加载：进入/退出集合、文件夹、根目录，加载集合条目，封面生成暂停/恢复。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryNavigationExt on MediaLibraryViewModel {
  Future<void> loadCurrentCollectionItems() async {
    final collectionId = currentCollectionId.value;
    if (collectionId == null) {
      currentItems.clear();
      return;
    }

    // isLoadingItems may already be true if coming from enterCollection; only set if not already
    if (!isLoadingItems.value) isLoadingItems.value = true;
    itemLoadProgress.value = null;
    try {
      if (isRemoteCollection(collectionId)) {
        final nodeId = getRemoteNodeId(collectionId);
        final rawId = getRemoteRawCollectionId(collectionId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程媒体集合映射不存在');
        }
        final itemsTrace = TimingTrace('拉取远程集合条目', scope: collectionId);
        final payloads = await nodeSettingsService
            .fetchNodeMediaCollectionItems(
              nodeId: nodeId,
              collectionId: rawId,
              onReceiveProgress: (count, total) {
                if (total > 0) itemLoadProgress.value = count / total;
              },
            );
        itemsTrace.end(note: '条目=${payloads.length}');
        currentItems.assignAll(
          payloads.map((payload) => _buildRemoteItem(payload, collectionId)),
        );
      } else {
        currentItems.assignAll(
          await media_api.getMediaCollectionItems(collectionId: collectionId),
        );
        // 预热 item 丢失状态：一次 FFI 批量检查，避免 build 期间每张卡片同步调 FFI 阻塞 UI
        await _prewarmItemLostCache();
      }
    } catch (error) {
      currentItems.clear();
      showSnack('错误', '加载集合内容失败: $error');
    } finally {
      isLoadingItems.value = false;
      itemLoadProgress.value = null;
    }
  }

  Future<void> enterCollection(String collectionId) async {
    _logger.info(
      '[Scroll] enterCollection START: collectionId=$collectionId, savedScrollOffset=${savedScrollOffset.value}, _savedBrowseScrollOffset=$_savedBrowseScrollOffset',
    );
    _savedBrowseScrollOffset = savedScrollOffset.value;
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    _logger.info(
      '[Scroll] enterCollection: saved browse offset to _savedBrowseScrollOffset=$_savedBrowseScrollOffset, _browseScrollOffsets[${currentFolderId.value}]=${_browseScrollOffsets[currentFolderId.value]}',
    );
    currentItems.clear();
    isLoadingItems.value = true;
    currentCollectionId.value = collectionId;
    exitSelection();

    final previousOffset = _browseScrollOffsets[collectionId];
    _logger.info(
      '[Scroll] enterCollection: previousOffset for collectionId=$collectionId is $previousOffset',
    );
    if (previousOffset != null) {
      savedScrollOffset.value = previousOffset;
      _logger.info(
        '[Scroll] enterCollection: restored savedScrollOffset to previousOffset=$previousOffset',
      );
    } else {
      savedScrollOffset.value = 0.0;
      _logger.info(
        '[Scroll] enterCollection: no previousOffset, set savedScrollOffset=0',
      );
    }

    await loadCurrentCollectionItems();
    _logger.info(
      '[Scroll] enterCollection END: savedScrollOffset=${savedScrollOffset.value}',
    );
  }

  void exitCollection() {
    final collectionId = currentCollectionId.value;
    _logger.info(
      '[Scroll] exitCollection START: collectionId=$collectionId, savedScrollOffset=${savedScrollOffset.value}, _savedBrowseScrollOffset=$_savedBrowseScrollOffset',
    );
    if (collectionId != null) {
      _browseScrollOffsets[collectionId] = savedScrollOffset.value;
      _logger.info(
        '[Scroll] exitCollection: saved collection offset to _browseScrollOffsets[$collectionId]=${savedScrollOffset.value}',
      );
    }
    final browseOffset = _savedBrowseScrollOffset;
    savedScrollOffset.value = browseOffset;
    scrollRestoreTarget.value = browseOffset;
    _logger.info(
      '[Scroll] exitCollection: restored browse offset: savedScrollOffset=$browseOffset, scrollRestoreTarget=$browseOffset',
    );
    currentCollectionId.value = null;
    currentItems.clear();
    exitSelection();
    _logger.info('[Scroll] exitCollection END');
  }

  void enterFolder(String folderId) {
    // 取消上一个文件夹中还未执行的封面任务
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    // Snapshot scroll position for the current browse level before navigating into folder
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    currentFolderId.value = folderId;
    // Debug: show what custom order (if any) will be applied for this folder
    final orderKey = folderId;
    final savedOrder = _collectionOrders[orderKey];
    _logger.info(
      'enterFolder: folderId=$folderId, savedOrder=${savedOrder == null ? "NONE" : savedOrder.join(",")}',
    );
    exitCollection();
    exitSelection();
  }

  void exitFolder() {
    // 取消当前文件夹中还未执行的封面任务
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    // Smart folders are always root-level – exit goes back to root
    if (currentSmartFolder != null) {
      exitToRoot();
      return;
    }
    // 同名集合分组：返回其登记的父文件夹（null = 根目录）
    final fid = currentFolderId.value;
    if (fid != null && isDupGroup(fid)) {
      final parent = _dupGroupParents[fid];
      _browseScrollOffsets.remove(fid);
      currentFolderId.value = parent;
      exitCollection();
      exitSelection();
      return;
    }
    final parentId = currentFolder?.parentId;
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = parentId;
    exitCollection();
    exitSelection();
  }

  /// 暂停封面生成：清空两个缩略图队列中未执行的任务，
  /// 并置暂停标志阻止 Obx 重建时的自动重新入队，直到调用 [resumeThumbGeneration]。
  void cancelThumbGeneration() {
    thumbGenerationPaused.value = true;
    _coverQueue.cancelAll();
    _scrubQueue.cancelAll();
    _currentFolderCoverKeys.clear();
    thumbProgress.value = null;
  }

  /// 恢复封面生成：解除暂停标志并触发重建，卡片会重新检查并自动入队缺失封面。
  void resumeThumbGeneration() {
    thumbGenerationPaused.value = false;
    _notifyCoverChanged();
  }

  /// Navigate directly to the root browse level, restoring its saved scroll position.
  void exitToRoot() {
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = null;
    exitCollection();
    exitSelection();
  }
}
