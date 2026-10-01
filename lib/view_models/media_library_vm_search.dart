part of 'media_library_viewmodel.dart';

/// 库内搜索与相似查找：查询词驱动、深度搜索、远程条目路径预热。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibrarySearchExt on MediaLibraryViewModel {
  /// 以指定集合名称为查询词，在当前层级 + 全部子孙文件夹内做相似查找。
  /// 命中的集合并入浏览网格并按亲和度层级排序（全名称 > 分词 > 逐字匹配）。
  void startSimilarSearch(media_api.MediaCollection source) {
    // 与普通搜索框互斥，避免两套筛选叠加
    searchQuery.value = '';
    isSearchActive.value = false;
    similarSearchQuery.value = source.title;
  }

  /// 清除相似查找筛选，恢复浏览网格。
  void clearSimilarSearch() {
    similarSearchQuery.value = '';
  }

  /// 相似查找：在当前层级 + 全部子孙文件夹内，按名称亲和度层级匹配集合。
  /// 亲和度排序：tier1 全名称 > tier2 分词 > tier3 逐字匹配，同层级内保持原始顺序。
  /// 注意：tier2 分词、tier3 逐字匹配仅针对中文字符进行（忽略数字、特殊符号与英文）。
  List<MediaLibraryItem> _similarSearchItems(String query) {
    final folderId = currentFolderId.value;
    final allFolders = mergedFolders;
    // 范围内文件夹 ID 集合（含当前层级自身），BFS 收集全部后代
    final scopeFolderIds = <String?>{folderId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in allFolders) {
        if (scopeFolderIds.contains(f.parentId) &&
            !scopeFolderIds.contains(f.id)) {
          scopeFolderIds.add(f.id);
          changed = true;
        }
      }
    }

    final queryLower = query.toLowerCase();
    // 中文连续片段（≥2字），供 tier2 分词匹配，忽略其中的数字、符号与英文
    final zhRunReg = RegExp('[\\u4e00-\\u9fff]+');
    final queryZhRuns = zhRunReg
        .allMatches(queryLower)
        .map((m) => m.group(0)!)
        .where((s) => s.length >= 2)
        .toList(growable: false);
    // 查询词中出现的唯一中文字符集合，供 tier3 逐字匹配
    final queryZhChars =
        queryLower.runes.where(MediaLibraryViewModel._isCjkChar).toSet();

    // 记录每个命中的集合及其最高亲和度层级
    final hits = <({media_api.MediaCollection collection, int tier})>[];
    for (final c in mergedCollections) {
      if (!scopeFolderIds.contains(c.folderId)) continue;
      final tLow = c.title.toLowerCase();
      int? tier;
      if (tLow.contains(queryLower)) {
        tier = 1;
      } else {
        // 标题中的中文连续片段（≥2字）与唯一中文字符集合
        final titleZhRuns = zhRunReg
            .allMatches(tLow)
            .map((m) => m.group(0)!)
            .where((s) => s.length >= 2)
            .toList(growable: false);
        final titleZhChars =
            tLow.runes.where(MediaLibraryViewModel._isCjkChar).toSet();
        // 分词匹配：查询词任一中文片段是标题某中文片段的子串
        if (queryZhRuns.any((q) => titleZhRuns.any((t) => t.contains(q)))) {
          tier = 2;
        } else {
          // 逐字匹配：查询词与标题的唯一中文字符交集个数
          final shared = queryZhChars.intersection(titleZhChars);
          if (shared.length >= 2) tier = 3;
        }
      }
      if (tier != null) hits.add((collection: c, tier: tier));
    }

    // 按层级升序稳定排序（同层级保持原始顺序）
    final sorted = List.of(hits)..sort((a, b) => a.tier.compareTo(b.tier));
    return sorted
        .map((h) => MediaLibraryCollectionItem(h.collection))
        .toList(growable: false);
  }

  /// 从当前层级开始的深度搜索：文件夹名 → 集合名 → 集合内资源文件名。
  /// 结果以当前层级的展示形式（文件夹卡片 + 集合卡片）返回。
  List<MediaLibraryItem> _deepSearchItems(String query) {
    // 注册响应式依赖：远程条目路径异步加载完成后触发重建
    _searchVersion.value;
    final folderId = currentFolderId.value;
    final allFolders = mergedFolders;

    // 范围内文件夹 ID 集合（含当前层级自身），BFS 收集全部后代
    final scopeFolderIds = <String?>{folderId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in allFolders) {
        if (scopeFolderIds.contains(f.parentId) &&
            !scopeFolderIds.contains(f.id)) {
          scopeFolderIds.add(f.id);
          changed = true;
        }
      }
    }

    // 文件夹名匹配（当前层级下的后代文件夹）
    final matchedFolders = allFolders
        .where(
          (f) =>
              f.id != folderId &&
              scopeFolderIds.contains(f.id) &&
              f.name.toLowerCase().contains(query),
        )
        .toList(growable: false);

    // 范围内集合：普通文件夹取后代范围；智能文件夹/同名分组内直接取其集合列表
    final List<media_api.MediaCollection> scopedCollections;
    if (folderId != null && (isSmartFolder(folderId) || isDupGroup(folderId))) {
      scopedCollections = currentCollections;
    } else {
      scopedCollections = mergedCollections
          .where((c) => scopeFolderIds.contains(c.folderId))
          .toList(growable: false);
    }

    // 集合名匹配 + 资源文件名匹配（命中文件名的集合也作为结果展示）
    final matchedCollectionIds = <String>{};
    final matchedCollections = <media_api.MediaCollection>[];
    for (final c in scopedCollections) {
      final titleHit = c.title.toLowerCase().contains(query);
      var itemHit = false;
      if (!titleHit) {
        if (isRemoteCollection(c.id)) {
          // 远程集合：异步加载条目路径，本轮先跳过，加载完成后自动重建
          _requestRemoteItemPaths(c.id);
          final paths = _remoteCollectionItemPaths[c.id];
          itemHit =
              paths != null &&
              paths.any((p) =>
                  MediaLibraryViewModel._pathBasename(p)
                      .toLowerCase()
                      .contains(query));
        } else {
          itemHit = _getCollectionItemPaths(
            c.id,
          ).any((p) =>
              MediaLibraryViewModel._pathBasename(p)
                  .toLowerCase()
                  .contains(query));
        }
      }
      if ((titleHit || itemHit) && matchedCollectionIds.add(c.id)) {
        matchedCollections.add(c);
      }
    }

    return <MediaLibraryItem>[
      ...matchedFolders.map(MediaLibraryFolderItem.new),
      ...matchedCollections.map(MediaLibraryCollectionItem.new),
    ];
  }

  /// 异步加载远程集合的条目路径（深度搜索匹配资源文件名用）。
  void _requestRemoteItemPaths(String collectionId) {
    if (_remoteCollectionItemPaths.containsKey(collectionId) ||
        _remoteItemPathsLoading.contains(collectionId)) {
      return;
    }
    final nodeId = getRemoteNodeId(collectionId);
    final rawId = getRemoteRawCollectionId(collectionId);
    if (nodeId == null || rawId == null) return;
    _remoteItemPathsLoading.add(collectionId);
    final trace = TimingTrace('深度搜索预热远程条目', scope: collectionId);
    nodeSettingsService
        .fetchNodeMediaCollectionItems(nodeId: nodeId, collectionId: rawId)
        .then((payloads) {
          trace.end(note: '条目=${payloads.length}');
          _remoteCollectionItemPaths[collectionId] = payloads
              .map((p) => (p['file_path'] ?? '').toString())
              .toList();
          _searchVersion.value++;
        })
        .catchError((_) {})
        .whenComplete(() => _remoteItemPathsLoading.remove(collectionId));
  }
}
