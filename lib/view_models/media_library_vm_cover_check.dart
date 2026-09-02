part of 'media_library_viewmodel.dart';

/// 集合/文件夹/条目丢失状态检查。
///
/// 所有公开方法保持同步签名（被 build 期间直接调用）：
/// - 缓存命中 → 直接返回缓存值
/// - 缓存未命中 → 返回默认值 false 并触发异步刷新，
///   刷新完成后通过 _asyncCoverVersion 触发 UI 重建。
/// 预热由 _prewarmCollectionCaches / _prewarmItemLostCache 负责，
/// 首屏 build 前已填充缓存，避免运行期 cache miss 频繁触发异步刷新。
extension CoverCheckExt on MediaLibraryViewModel {
  static const _cacheDurationMs = 5 * 60 * 1000;

  static bool _isExpired(String key, Map<String, int> timestamps) {
    final ts = timestamps[key];
    if (ts == null) return true;
    return DateTime.now().millisecondsSinceEpoch - ts > _cacheDurationMs;
  }

  /// 同步读取集合封面丢失状态。缓存未命中返回 false 并异步刷新。
  bool checkCollectionLost(media_api.MediaCollection collection) {
    if (isRemoteCollection(collection.id)) return false;
    if (_lostCollections.containsKey(collection.id) &&
        !_isExpired(collection.id, _checkTimestamps)) {
      return _lostCollections[collection.id]!;
    }
    // 缓存未命中：默认未丢失，后台异步刷新
    _refreshCollectionLostCache(collection);
    return false;
  }

  /// 异步刷新单个集合的封面丢失状态，写入缓存后触发 UI 重建。
  Future<void> _refreshCollectionLostCache(media_api.MediaCollection collection) async {
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      _lostCollections[collection.id] = false;
      _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    try {
      final results = await media_api.checkPathsExist(paths: [coverPath]);
      _lostCollections[collection.id] = !results.first;
      _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
      _asyncCoverVersion.value++;
    } catch (e) {
      _logger.error('[CoverCheck] 刷新集合丢失状态失败: ${collection.id} err=$e');
    }
  }

  /// 深度检查集合内所有文件是否丢失（仅在 fileCheckDepth == deep 时调用）。
  /// 同步返回缓存值，未命中返回 false 并异步刷新。
  bool deepCheckCollectionAllLost(media_api.MediaCollection collection) {
    if (_lostCollections.containsKey(collection.id) &&
        !_isExpired(collection.id, _checkTimestamps)) {
      return _lostCollections[collection.id]!;
    }
    _refreshDeepCollectionLostCache(collection);
    return false;
  }

  /// 异步深度刷新：批量检查集合内全部文件路径是否存在。
  Future<void> _refreshDeepCollectionLostCache(
    media_api.MediaCollection collection,
  ) async {
    try {
      final items = await media_api.getMediaCollectionItems(collectionId: collection.id);
      if (items.isEmpty) {
        _lostCollections[collection.id] = true;
        _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
        _asyncCoverVersion.value++;
        return;
      }
      final paths = items.map((i) => i.filePath).toList();
      final results = await media_api.checkPathsExist(paths: paths);
      final allLost = results.every((exists) => !exists);
      _lostCollections[collection.id] = allLost;
      _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
      _asyncCoverVersion.value++;
    } catch (e) {
      _logger.error('[CoverCheck] 深度检查集合丢失状态失败: ${collection.id} err=$e');
    }
  }

  /// 同步读取文件夹丢失状态。缓存未命中返回 false 并异步刷新。
  bool checkFolderLost(media_api.MediaFolder folder) {
    if (isRemoteFolder(folder.id)) return false;
    final cacheKey = 'folder:${folder.id}';
    if (_lostFolders.containsKey(folder.id) && !_isExpired(cacheKey, _checkTimestamps)) {
      return _lostFolders[folder.id]!;
    }
    _refreshFolderLostCache(folder);
    return false;
  }

  /// 异步刷新文件夹丢失状态：遍历直接子集合的封面/全量文件状态。
  Future<void> _refreshFolderLostCache(media_api.MediaFolder folder) async {
    final cacheKey = 'folder:${folder.id}';
    final deep = mediaPrefs.fileCheckDepth.value == FileCheckDepth.deep;
    final directCollections = mergedCollections
        .where((c) => c.folderId == folder.id)
        .toList(growable: false);
    if (directCollections.isEmpty) {
      _lostFolders[folder.id] = false;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    try {
      for (final col in directCollections) {
        // 先尝试同步缓存命中
        if (!checkCollectionLost(col)) {
          _lostFolders[folder.id] = false;
          _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
          return;
        }
        if (deep) {
          // 深度检查：未命中时触发异步，但此处同步流程只能取当前缓存值
          if (!deepCheckCollectionAllLost(col)) {
            _lostFolders[folder.id] = false;
            _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
            return;
          }
        }
      }
      _lostFolders[folder.id] = true;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      _asyncCoverVersion.value++;
    } catch (e) {
      _logger.error('[CoverCheck] 刷新文件夹丢失状态失败: ${folder.id} err=$e');
    }
  }

  /// 同步读取智能文件夹丢失状态。缓存未命中返回 false 并异步刷新。
  bool checkSmartFolderLost(SmartFolder sf) {
    if (isRemoteSmartFolder(sf.id)) return false;
    final cacheKey = 'sf:${sf.id}';
    if (_lostSmartFolders.containsKey(sf.id) && !_isExpired(cacheKey, _checkTimestamps)) {
      return _lostSmartFolders[sf.id]!;
    }
    _refreshSmartFolderLostCache(sf);
    return false;
  }

  /// 异步刷新智能文件夹丢失状态：遍历匹配集合的封面/全量文件状态。
  Future<void> _refreshSmartFolderLostCache(SmartFolder sf) async {
    final cacheKey = 'sf:${sf.id}';
    final deep = mediaPrefs.fileCheckDepth.value == FileCheckDepth.deep;
    final filtered = mergedCollections
        .where((c) => collectionMatchesSmartFolder(sf, c))
        .toList(growable: false);
    if (filtered.isEmpty) {
      _lostSmartFolders[sf.id] = false;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    try {
      for (final col in filtered) {
        if (!checkCollectionLost(col)) {
          _lostSmartFolders[sf.id] = false;
          _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
          return;
        }
        if (deep) {
          if (!deepCheckCollectionAllLost(col)) {
            _lostSmartFolders[sf.id] = false;
            _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
            return;
          }
        }
      }
      _lostSmartFolders[sf.id] = true;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      _asyncCoverVersion.value++;
    } catch (e) {
      _logger.error('[CoverCheck] 刷新智能文件夹丢失状态失败: ${sf.id} err=$e');
    }
  }

  /// 同步读取条目丢失状态。缓存未命中返回 false 并异步刷新。
  /// 缓存由 _prewarmItemLostCache 预热，首屏 build 期间应命中缓存。
  bool checkItemLost(media_api.MediaItem item) {
    final cacheKey = 'item:${item.id}:${item.filePath}';
    if (_lostItems.containsKey(cacheKey) && !_isExpired(cacheKey, _itemCheckTimestamps)) {
      return _lostItems[cacheKey]!;
    }
    _refreshItemLostCache(item);
    return false;
  }

  /// 异步刷新单个条目丢失状态。
  Future<void> _refreshItemLostCache(media_api.MediaItem item) async {
    final cacheKey = 'item:${item.id}:${item.filePath}';
    try {
      final results = await media_api.checkPathsExist(paths: [item.filePath]);
      _lostItems[cacheKey] = !results.first;
      _itemCheckTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      _asyncCoverVersion.value++;
    } catch (e) {
      _logger.error('[CoverCheck] 刷新条目丢失状态失败: ${item.id} err=$e');
    }
  }

  /// 清空所有丢失状态缓存（loadCollections / clearCoverCheckCache 调用）。
  void clearCoverCheckCache() {
    _lostCollections.clear();
    _lostFolders.clear();
    _lostSmartFolders.clear();
    _lostItems.clear();
    _checkTimestamps.clear();
    _itemCheckTimestamps.clear();
  }
}
