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
    // 搜索词只筛集合卡片，进内容就该看全量：先收起来，退出时再恢复
    _stashBrowseSearchForDetail(atLevel: currentFolderId.value);
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

  /// 退出集合内容回到浏览层。[restoreBrowseSearch] = false 供 [enterFolder] 用：
  /// 那里正在换层，搜索词该按层级判定决定收起还是恢复，而不是无条件翻出来。
  void exitCollection({bool restoreBrowseSearch = true}) {
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
    // 回到浏览层：若正是收起搜索词的那一层，把结果原样还回来
    if (restoreBrowseSearch) _restoreBrowseSearchForLevel(currentFolderId.value);
    exitSelection();
    _logger.info('[Scroll] exitCollection END');
  }

  void enterFolder(String folderId) {
    // 取消上一个文件夹中还未执行的封面任务
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    // Snapshot scroll position for the current browse level before navigating into folder
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    final fromLevel = currentFolderId.value;
    // 记下从哪一层进来的：返回时要退的是这一层，而不是目标文件夹的物理父级
    _folderBackLevels.add(fromLevel);
    currentFolderId.value = folderId;
    // Debug: show what custom order (if any) will be applied for this folder
    final orderKey = folderId;
    final savedOrder = _collectionOrders[orderKey];
    _logger.info(
      'enterFolder: folderId=$folderId, savedOrder=${savedOrder == null ? "NONE" : savedOrder.join(",")}',
    );
    exitCollection(restoreBrowseSearch: false);
    exitSelection();
    // 搜索词属于录入它的那一层：面包屑跳回该层就把结果翻出来，
    // 其余情况（下钻进子层）收起它——不然按名字命中而点进来的文件夹，
    // 会因为子项不含该词而显示成一片空白。
    if (!_restoreBrowseSearchForLevel(folderId)) {
      _stashBrowseSearchForDetail(atLevel: fromLevel);
    }
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
    final back = _takeBackLevel();
    // 同名集合分组：返回其登记的父文件夹（null = 根目录）
    final fid = currentFolderId.value;
    if (fid != null && isDupGroup(fid)) {
      final parent = back.hasLevel ? back.level : _dupGroupParents[fid];
      _browseScrollOffsets.remove(fid);
      currentFolderId.value = parent;
      exitCollection();
      exitSelection();
      return;
    }
    // 优先退回来时的层级：深度搜索的结果是从整棵子树扁平捞上来的，
    // 物理父级（父子链）往往不是用户打开结果时所在的那一层。
    final parentId = back.hasLevel ? back.level : currentFolder?.parentId;
    _browseScrollOffsets.remove(fid);
    currentFolderId.value = parentId;
    exitCollection();
    exitSelection();
  }

  /// 弹出「来时的层级」。栈空时 `hasLevel` 为 false，调用方退回父子链。
  ///
  /// 途中丢掉两类无效记录：已经身处的那一层（记录它等于原地不动，会把返回按键
  /// 变成一次空操作）和已被删掉的层级——删文件夹时 [currentFolderId] 会被直接
  /// 改到别处，栈里就可能留下指向不存在层级的陈旧记录。
  ({bool hasLevel, String? level}) _takeBackLevel() {
    while (_folderBackLevels.isNotEmpty) {
      final candidate = _folderBackLevels.removeLast();
      if (candidate == currentFolderId.value) continue;
      if (candidate != null && !mergedFolders.any((f) => f.id == candidate)) {
        continue;
      }
      return (hasLevel: true, level: candidate);
    }
    return (hasLevel: false, level: null);
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
    // 面包屑/根目录按钮是「跳到某层」而不是逐级返回，来路到这里就作废了：
    // 留着它们，下一次返回会莫名其妙把用户拽回早已离开的分支。
    _folderBackLevels.clear();
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = null;
    exitCollection();
    exitSelection();
  }
}
