part of 'media_library_viewmodel.dart';

/// 收藏集合：查询、切换、持久化加载与保存。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryFavoritesExt on MediaLibraryViewModel {
  bool isFavorite(String id) => favoriteCollectionIds.contains(id);

  /// 返回当前鼠标悬停的本地集合（供 Delete 快捷键直接删除文件夹）；
  /// 未悬停、悬停对象已不存在或为远程集合时返回 null。
  media_api.MediaCollection? hoveredLocalCollection() {
    final id = hoveredCollectionId.value;
    if (id == null) return null;
    for (final c in mergedCollections) {
      if (c.id == id) {
        return isRemoteCollection(id) ? null : c;
      }
    }
    return null;
  }

  Future<void> toggleFavorite(String id) async {
    if (favoriteCollectionIds.contains(id)) {
      favoriteCollectionIds.remove(id);
    } else {
      favoriteCollectionIds.add(id);
    }
    await _saveFavorites();
  }

  Future<void> _loadFavorites() async {
    // 数据库可能因独占锁等原因首次加载失败，失败后延迟重试一次
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final ids = await media_api.getFavoriteCollectionIds();
        favoriteCollectionIds.assignAll(ids.toSet());
        return;
      } catch (e) {
        _logger.error('加载收藏列表失败(第${attempt + 1}次): $e');
        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  Future<void> _saveFavorites() async {
    try {
      media_api.saveFavoriteCollectionIds(ids: favoriteCollectionIds.toList());
    } catch (e) {
      _logger.error('保存收藏列表失败: $e');
    }
  }
}
