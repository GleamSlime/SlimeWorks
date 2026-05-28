part of 'media_library_viewmodel.dart';

extension CoverCheckExt on MediaLibraryViewModel {
  static const _cacheDurationMs = 5 * 60 * 1000;

  static bool _isExpired(String key, Map<String, int> timestamps) {
    final ts = timestamps[key];
    if (ts == null) return true;
    return DateTime.now().millisecondsSinceEpoch - ts > _cacheDurationMs;
  }

  bool checkCollectionLost(media_api.MediaCollection collection) {
    if (isRemoteCollection(collection.id)) return false;
    if (_lostCollections.containsKey(collection.id) &&
        !_isExpired(collection.id, _checkTimestamps)) {
      return _lostCollections[collection.id]!;
    }
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      _lostCollections[collection.id] = false;
      _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
      return false;
    }
    final results = media_api.checkPathsExist(paths: [coverPath]);
    final lost = !results.first;
    _lostCollections[collection.id] = lost;
    _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
    return lost;
  }

  bool deepCheckCollectionAllLost(media_api.MediaCollection collection) {
    final items = media_api.getMediaCollectionItems(collectionId: collection.id);
    if (items.isEmpty) {
      _lostCollections[collection.id] = true;
      _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
      return true;
    }
    final paths = items.map((i) => i.filePath).toList();
    final results = media_api.checkPathsExist(paths: paths);
    final allLost = results.every((exists) => !exists);
    _lostCollections[collection.id] = allLost;
    _checkTimestamps[collection.id] = DateTime.now().millisecondsSinceEpoch;
    return allLost;
  }

  bool checkFolderLost(media_api.MediaFolder folder) {
    if (isRemoteFolder(folder.id)) return false;
    final cacheKey = 'folder:${folder.id}';
    if (_lostFolders.containsKey(folder.id) && !_isExpired(cacheKey, _checkTimestamps)) {
      return _lostFolders[folder.id]!;
    }
    final deep = mediaPrefs.fileCheckDepth.value == FileCheckDepth.deep;
    final directCollections = mergedCollections
        .where((c) => c.folderId == folder.id)
        .toList(growable: false);
    if (directCollections.isEmpty) {
      _lostFolders[folder.id] = false;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      return false;
    }
    for (final col in directCollections) {
      final coverLost = checkCollectionLost(col);
      if (!coverLost) {
        _lostFolders[folder.id] = false;
        _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
        return false;
      }
      if (deep) {
        final allLost = deepCheckCollectionAllLost(col);
        if (!allLost) {
          _lostFolders[folder.id] = false;
          _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
          return false;
        }
      }
    }
    _lostFolders[folder.id] = true;
    _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
    return true;
  }

  bool checkSmartFolderLost(SmartFolder sf) {
    if (isRemoteSmartFolder(sf.id)) return false;
    final cacheKey = 'sf:${sf.id}';
    if (_lostSmartFolders.containsKey(sf.id) && !_isExpired(cacheKey, _checkTimestamps)) {
      return _lostSmartFolders[sf.id]!;
    }
    final deep = mediaPrefs.fileCheckDepth.value == FileCheckDepth.deep;
    final filtered = mergedCollections
        .where((c) => collectionMatchesSmartFolder(sf, c))
        .toList(growable: false);
    if (filtered.isEmpty) {
      _lostSmartFolders[sf.id] = false;
      _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
      return false;
    }
    for (final col in filtered) {
      final coverLost = checkCollectionLost(col);
      if (!coverLost) {
        _lostSmartFolders[sf.id] = false;
        _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
        return false;
      }
      if (deep) {
        final allLost = deepCheckCollectionAllLost(col);
        if (!allLost) {
          _lostSmartFolders[sf.id] = false;
          _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
          return false;
        }
      }
    }
    _lostSmartFolders[sf.id] = true;
    _checkTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
    return true;
  }

  bool checkItemLost(media_api.MediaItem item) {
    final results = media_api.checkPathsExist(paths: [item.filePath]);
    return !results.first;
  }

  void clearCoverCheckCache() {
    _lostCollections.clear();
    _lostFolders.clear();
    _lostSmartFolders.clear();
    _checkTimestamps.clear();
  }
}
