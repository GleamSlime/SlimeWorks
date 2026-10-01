part of 'media_library_viewmodel.dart';

/// 数据刷新：全量/节流刷新、加载文件夹/集合、缓存预热、现存资源统计。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryRefreshExt on MediaLibraryViewModel {
  /// 刷新「磁盘上仍然存在」的资源体积与条数（Rust 侧并发逐文件 stat）。
  ///
  /// 全库扫描有真实开销，所以不挂在首屏链路上：每次 loadCollections 之后补一轮，
  /// 期间再来请求就标记脏，本轮跑完补一次，保证删除动作最终会反映到父级汇总上。
  Future<void> refreshCollectionLiveStats() async {
    if (_liveStatsInFlight) {
      _liveStatsDirty = true;
      return;
    }
    _liveStatsInFlight = true;
    try {
      do {
        _liveStatsDirty = false;
        try {
          final stats = await media_api.getAllCollectionLiveStats();
          _collectionLiveStats
            ..clear()
            ..addEntries(
              stats.map(
                (stat) => MapEntry(
                  stat.collectionId,
                  (size: stat.liveSize, count: stat.liveCount.toInt()),
                ),
              ),
            );
          liveStatsVersion.value++;
        } catch (error) {
          _logger.error('[媒体库] 现存资源统计失败: $error');
        }
      } while (_liveStatsDirty);
    } finally {
      _liveStatsInFlight = false;
    }
  }

  List<media_api.MediaFolder> getAvailableFoldersForCollection(
    String collectionId,
  ) {
    if (isRemoteCollection(collectionId)) {
      final nodeId = getRemoteNodeId(collectionId);
      if (nodeId == null) {
        return const <media_api.MediaFolder>[];
      }
      final items = remoteFolders
          .where((folder) => remoteFolderNodeId[folder.id] == nodeId)
          .toList(growable: false);
      items.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      return items;
    }
    final items = folders.toList(growable: false);
    items.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return items;
  }

  /// 强制全量刷新（手动刷新按钮 / 节点变更 tick / 首次初始化）：远程部分不做节流。
  Future<void> refreshAll() => _refreshAll(throttleRemote: false);

  /// 进页面专用刷新：本地 FFI（快）始终执行；远程节点刷新带 60s 节流，
  /// 频繁进出页面不再反复打节点接口。
  Future<void> refreshAllOnEnter() => _refreshAll(throttleRemote: true);

  Future<void> _refreshAll({required bool throttleRemote}) async {
    final inFlight = _refreshAllFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _refreshAllInternal(throttleRemote: throttleRemote);
    _refreshAllFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshAllFuture, future)) {
        _refreshAllFuture = null;
      }
    }
  }

  Future<void> _refreshAllInternal({required bool throttleRemote}) async {
    // Phase 1: 立即加载本地数据，使 UI 快速可用
    final trace = TimingTrace('媒体库 refreshAll');
    await _loadSmartFolders();
    trace.lap('智能文件夹');
    await loadFolders();
    trace.lap('本地文件夹');
    await loadCollections();
    trace.lap('本地集合');
    await loadCurrentCollectionItems();
    trace.end(note: '本地数据完成，转入远程');
    // Phase 2: 后台异步加载远程节点数据，不阻塞 UI
    _refreshRemoteBackground(throttled: throttleRemote);
  }

  void _refreshRemoteBackground({bool throttled = false}) {
    if (isLoadingRemote.value) return; // 已有后台任务在跑
    if (throttled) {
      final last = _lastRemoteRefreshAt;
      if (last != null &&
          DateTime.now().difference(last) <
              MediaLibraryViewModel._kRemoteRefreshThrottle) {
        // 60s 内刚刷新过远程：跳过本次，避免频繁进出页面反复打节点接口
        return;
      }
    }
    isLoadingRemote.value = true;
    final trace = TimingTrace('远程媒体库后台刷新');
    // 离线/熔断节点的复活探测挂在这里：只有进页面和点刷新才付这一次，没有后台定时轮询。
    // 顺序不能反 —— 熔断位还挂着时 fetchNodeMediaMetadata 直接抛，远程那一栏就是空的。
    nodeSettingsService
        .recheckOfflineNodes()
        .then((_) => refreshRemoteLibrary())
        .catchError((Object e) {
          _logger.error('[媒体库] 远程刷新失败: $e');
        })
        .whenComplete(() {
          trace.end();
          _lastRemoteRefreshAt = DateTime.now();
          isLoadingRemote.value = false;
        });
  }

  Future<void> loadFolders() async {
    try {
      final raw = await media_api.getAllMediaFolders();
      _logger.info('[媒体库] loadFolders: 加载到 ${raw.length} 个文件夹');
      folders.assignAll(raw);
      // 仅当不在智能文件夹中时才自动退出：智能文件夹不在 mergedFolders 里，不应被误清除
      if (currentFolderId.value != null &&
          currentFolder == null &&
          !isSmartFolder(currentFolderId.value!)) {
        currentFolderId.value = null;
      }
    } catch (error) {
      _logger.error('[媒体库] loadFolders 异常: $error');
      showSnack('错误', '加载媒体文件夹失败: $error');
    }
  }

  Future<void> loadCollections() async {
    try {
      final rawCollections = await media_api.getAllMediaCollections();
      _logger.info('[媒体库] loadCollections: 加载到 ${rawCollections.length} 个集合');
      collections.assignAll(rawCollections);
      _hoverSourcesCache.clear();
      clearCoverCheckCache();
      // 预热阶段：批量填充 _collectionSizes / _collectionItemPaths / _lostCollections
      // 一次 await 三组缓存，避免 build 期间每张卡片单独调 FFI 阻塞 UI
      await _prewarmCollectionCaches(rawCollections);
      // 现存资源统计要逐文件 stat，全库扫有实打实的开销，所以不挂在首屏链路上；
      // 删除资源/集合后也会走到这里，父级文件夹的体积因此自动跟着重算。
      unawaited(refreshCollectionLiveStats());
      if (currentCollectionId.value != null && currentCollection == null) {
        exitCollection();
      }
    } catch (error) {
      _logger.error('[媒体库] loadCollections 异常: $error');
      showSnack('错误', '加载媒体集合失败: $error');
    }
  }

  /// 批量预热集合相关缓存：sizes / item paths / 封面存在性
  /// 在 loadCollections 中调用，避免 build 期间每张卡片单独调 FFI 阻塞 UI
  Future<void> _prewarmCollectionCaches(
    List<media_api.MediaCollection> cols,
  ) async {
    if (cols.isEmpty) return;
    // Phase 1: 一次 FFI 调用获取所有集合的 size + file_paths
    try {
      final statsList = await media_api.getAllCollectionStats();
      for (final s in statsList) {
        _collectionSizes[s.collectionId] = s.totalSize;
        _collectionItemPaths[s.collectionId] = s.filePaths;
      }
      // 文件路径是文件名模式匹配的唯一输入，写入后必须让智能文件夹缓存失效
      _itemPathsEpoch++;
      // _itemPathsEpoch 为非 Rx 计数：浏览层派生缓存在此手动失效
      _invalidateVisible();
    } catch (e) {
      _logger.error('[媒体库] _prewarmCollectionCaches stats 失败: $e');
    }
    // Phase 2 是逐资源所在卷的 stat：外置卷闲置后首次 stat 实测要 4.0s（唤醒开销），
    // 挂在首屏 await 链上等于让整个网格等磁盘醒来。`checkCollectionLost` 缓存未命中
    // 时按「未丢失」出图、落地后再重建，所以这趟放后台跑，结果到达时再通知 UI。
    unawaited(_prewarmCollectionCoverLoss(cols));
  }

  /// 批量检查本地集合的封面路径存在性，填充 _lostCollections（由预热后台调用）。
  Future<void> _prewarmCollectionCoverLoss(
    List<media_api.MediaCollection> cols,
  ) async {
    try {
      final coverPaths = <String>[];
      final coverOwners = <String>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final c in cols) {
        if (isRemoteCollection(c.id)) continue;
        final p = c.coverPath;
        if (p == null || p.isEmpty) {
          _lostCollections[c.id] = false;
          _checkTimestamps[c.id] = now;
          continue;
        }
        coverPaths.add(p);
        coverOwners.add(c.id);
      }
      if (coverPaths.isEmpty) return;
      final exists = await media_api.checkPathsExist(paths: coverPaths);
      for (int i = 0; i < coverOwners.length; i++) {
        _lostCollections[coverOwners[i]] = !exists[i];
        _checkTimestamps[coverOwners[i]] = now;
      }
      // 首屏已按「未丢失」出图，这里结论落地要让卡片重算一次
      _notifyCoverChanged();
    } catch (e) {
      _logger.error('[媒体库] _prewarmCollectionCaches 封面存在性失败: $e');
    }
  }

  /// 按需读取集合的文件路径列表（从预热缓存中读取，不调 FFI）
  /// 缓存由 loadCollections 中的 _prewarmCollectionCaches 预热；
  /// 新集合未预热时返回空列表，等下一次 loadCollections 时填充。
  List<String> _getCollectionItemPaths(String collectionId) {
    return _collectionItemPaths[collectionId] ?? const [];
  }

  /// 批量预热当前集合内所有条目的丢失状态缓存。
  /// 在 loadCurrentCollectionItems 中调用，避免 build 期间每张卡片单独调 FFI 阻塞 UI。
  Future<void> _prewarmItemLostCache() async {
    if (currentItems.isEmpty) return;
    final paths = currentItems.map((i) => i.filePath).toList();
    if (paths.isEmpty) return;
    try {
      final exists = await media_api.checkPathsExist(paths: paths);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < currentItems.length; i++) {
        final item = currentItems[i];
        final cacheKey = 'item:${item.id}:${item.filePath}';
        _lostItems[cacheKey] = !exists[i];
        _itemCheckTimestamps[cacheKey] = now;
      }
    } catch (e) {
      _logger.error('[媒体库] _prewarmItemLostCache 失败: $e');
    }
  }

  BigInt getCollectionTotalSize(String id) =>
      _collectionSizes[id] ?? BigInt.zero;

  /// 返回指定集合内所有媒体文件路径（可能为空列表，异步缓存未就绪时）。
  List<String> collectionItemPaths(String id) => _getCollectionItemPaths(id);
}
