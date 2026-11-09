part of 'media_library_viewmodel.dart';

/// 数据刷新：全量/节流刷新、加载文件夹/集合、缓存预热、现存资源统计。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryRefreshExt on MediaLibraryViewModel {
  /// 读缓存版「磁盘上仍然存在」的资源体积与条数。
  ///
  /// 只查 Rust 侧聚合小表（毫秒级）；数据过期时 Rust 自己起后台线程补全量
  /// stat，完成后再由这里的 [liveStatsFollowUpDelay] 跟进拉一次。
  /// 旧实现每次进页面都同步跑全库逐文件 stat（网络卷上 38 万次往返），
  /// 页面打开卡分钟级就是它。
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
          final stats = await media_api.getCachedCollectionLiveStats();
          // 记录值口径无条件刷新：它是集合卡在 live 结果到达前的兜底显示
          for (final stat in stats) {
            _collectionSizes[stat.collectionId] = stat.recordedSize;
          }
          _collectionLiveStats
            ..clear()
            ..addEntries(
              stats
                  .where((stat) => stat.liveSize != null && stat.liveCount != null)
                  .map(
                    (stat) => MapEntry(
                      stat.collectionId,
                      (size: stat.liveSize!, count: stat.liveCount!),
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
    // 还有集合没有 live 结论 → 说明 Rust 后台全量 stat 要么在跑要么还没排上，
    // 到点再拉一次小表；全部就绪就不用再排了。
    if (_hasCollectionsAwaitingLiveStats) _scheduleLiveStatsFollowUp();
  }

  /// Rust 后台重扫完成后的跟进窗口：到时再拉一次缓存（只多一次小表读）。
  static const liveStatsFollowUpDelay = Duration(minutes: 3);

  /// 跟进拉取的最大次数：Rust 后台全量 stat 在网络卷上可能要几分钟，
  /// 窗口太短会错过；但也不能无限跟，超过次数就等下次进页面。
  static const liveStatsFollowUpMaxRounds = 3;

  /// 已跟进的轮次（每次进页面 loadCollections 重置）。
  /// 计数本体声明在主 VM 文件里（extension 不能声明实例字段）。
  void _scheduleLiveStatsFollowUp() {
    _liveStatsFollowUpTimer?.cancel();
    _liveStatsFollowUpTimer = Timer(liveStatsFollowUpDelay, () {
      _liveStatsFollowUpTimer = null;
      if (isClosed) return;
      if (_liveStatsFollowUpRounds >= liveStatsFollowUpMaxRounds) return;
      _liveStatsFollowUpRounds++;
      unawaited(refreshCollectionLiveStats());
    });
  }

  /// 是否还有本地集合在等 live 结论（远程集合的文件在节点侧，本机 stat 不到）。
  bool get _hasCollectionsAwaitingLiveStats {
    for (final collection in collections) {
      if (isRemoteCollection(collection.id)) continue;
      if (collection.itemCount == BigInt.zero) continue;
      if (!_collectionLiveStats.containsKey(collection.id)) return true;
    }
    return false;
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
      // 派生缓存里的集合路径按 id 生效：集合被删/重扫后旧快照可能过期。
      // 这里不整体清空（否则每层浏览都要重拉一遍路径），只丢掉已不存在的集合。
      final liveIds = rawCollections.map((c) => c.id).toSet();
      _collectionItemPaths.removeWhere((id, _) => !liveIds.contains(id));
      _prewarmCollectionCaches(rawCollections);
      // 现存资源统计要逐文件 stat，全库扫有实打实的开销，所以不挂在首屏链路上；
      // 删除资源/集合后也会走到这里，父级文件夹的体积因此自动跟着重算。
      // 走进页面就重置跟进轮次：本层可能还有一批新集合要等 live 结论。
      _liveStatsFollowUpRounds = 0;
      unawaited(refreshCollectionLiveStats());
      if (currentCollectionId.value != null && currentCollection == null) {
        exitCollection();
      }
    } catch (error) {
      _logger.error('[媒体库] loadCollections 异常: $error');
      showSnack('错误', '加载媒体集合失败: $error');
    }
  }

  /// 预热集合相关缓存。
  ///
  /// **不再**调 `getAllCollectionStats`：那要冷加载整张 media_items 表（51 万文件
  /// 实测 1.3s，磁盘忙时 13.5s）并把几十万条路径跨 FFI 全量塞给 Dart，而路径
  /// 只有文件名智能文件夹/深度搜索/悬停预览用得到——改成按需
  /// [ensureCollectionItemPaths]。体积/条数走聚合小表，见 [refreshCollectionLiveStats]。
  Future<void> _prewarmCollectionCaches(
    List<media_api.MediaCollection> cols,
  ) {
    if (cols.isEmpty) return Future<void>.value();
    // 逐资源所在卷的 stat：外置卷闲置后首次 stat 实测要 4.0s（唤醒开销），
    // 挂在首屏 await 链上等于让整个网格等磁盘醒来。`checkCollectionLost` 缓存未命中
    // 时按「未丢失」出图、落地后再重建，所以这趟放后台跑，结果到达时再通知 UI。
    unawaited(_prewarmCollectionCoverLoss(cols));
    return Future<void>.value();
  }

  /// 按需取本地集合的文件路径快照（优先内存，其次 Rust 聚合行，最后条目表）。
  ///
  /// 结果写入 [_collectionItemPaths] 并推进 [_itemPathsEpoch]；文件名模式的
  /// 智能文件夹匹配与深度搜索读的就是这份缓存。
  Future<List<String>> ensureCollectionItemPaths(String collectionId) async {
    final cached = _collectionItemPaths[collectionId];
    if (cached != null) return cached;
    // 同集合并发去重：网格卡片会在同一帧里连问几次
    final inFlight = _localItemPathsLoading[collectionId];
    if (inFlight != null) return inFlight;
    final future = () async {
      try {
        final paths = await media_api.getCollectionFilePaths(
          collectionId: collectionId,
        );
        _collectionItemPaths[collectionId] = paths;
        _itemPathsEpoch++;
        // 路径到货会让文件名匹配/悬停源换结果，丢弃它们的派生缓存
        _hoverSourcesCache.remove(collectionId);
        _sfMatchCache.clear();
        _invalidateVisible();
        return paths;
      } catch (e) {
        _logger.error('[媒体库] 读取集合路径失败: $collectionId err=$e');
        // 失败也落空列表：避免每次重建都重发同一个失败请求
        _collectionItemPaths[collectionId] = const <String>[];
        return const <String>[];
      } finally {
        _localItemPathsLoading.remove(collectionId);
      }
    }();
    _localItemPathsLoading[collectionId] = future;
    return future;
  }

  /// 后台请求某集合路径（build 期间用；不阻塞、不等待）。
  void requestCollectionItemPaths(String collectionId) {
    if (_collectionItemPaths.containsKey(collectionId)) return;
    if (_localItemPathsLoading.containsKey(collectionId)) return;
    unawaited(ensureCollectionItemPaths(collectionId));
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

  /// 按需读取集合的文件路径列表（同步读缓存，未就绪返回空）。
  /// 未命中时调用 [ensureCollectionItemPaths] / [requestCollectionItemPaths] 填充。
  List<String> _getCollectionItemPaths(String collectionId) {
    return _collectionItemPaths[collectionId] ?? const [];
  }

  /// 批量预热当前集合内所有条目的丢失状态缓存。
  /// 在 loadCurrentCollectionItems 中调用，避免 build 期间每张卡片单独调 FFI 阻塞 UI。
  /// [snapshot] 为该次加载的条目快照：await 期间列表可能已被其它集合替换。
  Future<void> _prewarmItemLostCache(List<media_api.MediaItem> snapshot) async {
    if (snapshot.isEmpty) return;
    final paths = snapshot.map((i) => i.filePath).toList();
    if (paths.isEmpty) return;
    try {
      final exists = await media_api.checkPathsExist(paths: paths);
      if (exists.length != snapshot.length) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < snapshot.length; i++) {
        final item = snapshot[i];
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
