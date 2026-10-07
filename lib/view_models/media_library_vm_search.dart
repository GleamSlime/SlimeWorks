part of 'media_library_viewmodel.dart';

/// 库内搜索与相似查找：查询词驱动、深度搜索、远程条目路径预热。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibrarySearchExt on MediaLibraryViewModel {
  /// 以指定集合名称为查询词，在当前层级 + 全部子孙文件夹内做相似查找。
  /// 命中的集合并入浏览网格并按亲和度层级排序（全名称 > 分词 > 逐字匹配）。
  void startSimilarSearch(media_api.MediaCollection source) {
    // 与普通搜索框互斥，避免两套筛选叠加
    clearSearch();
    isSearchActive.value = false;
    similarSearchQuery.value = source.title;
  }

  /// 清除相似查找筛选，恢复浏览网格。
  void clearSimilarSearch() {
    similarSearchQuery.value = '';
  }

  /// 搜索框输入防抖：停手 [_kSearchDebounce] 才把词交给 [appliedSearchQuery]。
  ///
  /// 空串例外要立刻生效——删完字就该看到原列表，不该再等一个窗口。
  void _scheduleSearchApply(String value) {
    _searchDebounceTimer?.cancel();
    if (value.isEmpty) {
      appliedSearchQuery.value = value;
      return;
    }
    _searchDebounceTimer = Timer(
      MediaLibraryViewModel._kSearchDebounce,
      () {
        // 只认这一次排上的定时器：更早的已被 cancel，不会有过期词覆盖
        appliedSearchQuery.value = searchQuery.value;
      },
    );
  }

  /// 立即应用当前搜索词：回车 = 用户明说「就搜这个」，不等防抖窗口。
  void applySearchQueryNow() {
    _searchDebounceTimer?.cancel();
    appliedSearchQuery.value = searchQuery.value;
  }

  /// 清除当前这一层的搜索词（搜索框的「清除」按钮）。
  ///
  /// 下钻层（集合内容 / 文件夹）里清除只丢掉本层筛选，不动收起的上一层搜索词——
  /// 那个词此刻在搜索框里是隐形的，回到它录入的那一层才该重新露面。
  void clearSearch() {
    _searchDebounceTimer?.cancel();
    searchQuery.value = '';
    appliedSearchQuery.value = '';
  }

  /// 离开某一浏览层去下钻（进集合 / 进文件夹）：把该层的搜索词收起来，
  /// 让下一层展示完整内容。[atLevel] 为收起时所在层级（null = 根目录）。
  void _stashBrowseSearchForDetail({required String? atLevel}) {
    final query = appliedSearchQuery.value;
    if (query.isEmpty) return;
    // 同一层重复下钻只留最新一份，避免栈里堆同一层级的多个词
    if (_stashedBrowseSearch.isNotEmpty &&
        _stashedBrowseSearch.last.$1 == atLevel) {
      _stashedBrowseSearch.last = (atLevel, query);
    } else {
      _stashedBrowseSearch.add((atLevel, query));
    }
    clearSearch();
  }

  /// 回到 [level] 这一层：若它正是收起搜索词的那一层，把词还给搜索框与筛选。
  /// 返回是否完成了恢复。
  bool _restoreBrowseSearchForLevel(String? level) {
    if (_stashedBrowseSearch.isEmpty) return false;
    final top = _stashedBrowseSearch.last;
    if (top.$1 != level) return false;
    _stashedBrowseSearch.removeLast();
    _searchDebounceTimer?.cancel();
    // 两个都要写：searchQuery 管搜索框回显，appliedSearchQuery 直接生效不等防抖
    searchQuery.value = top.$2;
    appliedSearchQuery.value = top.$2;
    return true;
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

    // 本轮攒下的远程条目路径需求一次性交给限速流水线（已在跑就不重复启动）
    _kickRemotePathPump();

    return <MediaLibraryItem>[
      ...matchedFolders.map(MediaLibraryFolderItem.new),
      ...matchedCollections.map(MediaLibraryCollectionItem.new),
    ];
  }

  /// 本轮深度搜索收集完远程需求后启动预热流水线（已在跑则交给它顺带消费）。
  void _kickRemotePathPump() {
    if (_remotePathQueue.isEmpty || _remotePathPumping) return;
    _remotePathPumping = true;
    unawaited(_pumpRemoteItemPaths());
  }

  /// 限速消费预热队列：每批 [_kRemotePathConcurrency] 个请求，
  /// 整批到货只推一次网格重算，而不是每个集合到货各算一遍。
  Future<void> _pumpRemoteItemPaths() async {
    try {
      while (_remotePathQueue.isNotEmpty) {
        // 用户已退出搜索（收起搜索词、进集合看内容）就别再打节点
        if (appliedSearchQuery.value.isEmpty) {
          _remotePathQueue.clear();
          break;
        }
        final batch = _remotePathQueue
            .take(MediaLibraryViewModel._kRemotePathConcurrency)
            .toList(growable: false);
        _remotePathQueue.removeAll(batch);
        _remoteItemPathsLoading.addAll(batch);
        final results = await Future.wait(batch.map(_fetchRemoteItemPaths));
        // 一批数据落地推一次重建（同窗口内的后续批次由 VM 合并），
        // 既不让结果干等到最后一批，也不让 600 个集合各触发一次全网格重算
        if (results.any((ok) => ok)) _notifySearchChanged();
      }
    } finally {
      _remotePathPumping = false;
    }
  }

  /// 拉取单个远程集合的条目路径：成功写缓存，失败记入负缓存不再重试。
  Future<bool> _fetchRemoteItemPaths(String collectionId) async {
    final nodeId = getRemoteNodeId(collectionId);
    final rawId = getRemoteRawCollectionId(collectionId);
    if (nodeId == null || rawId == null) return false;
    final trace = TimingTrace('深度搜索预热远程条目', scope: collectionId);
    try {
      final payloads = await nodeSettingsService
          .fetchNodeMediaCollectionItems(nodeId: nodeId, collectionId: rawId);
      trace.end(note: '条目=${payloads.length}');
      _remoteCollectionItemPaths[collectionId] = payloads
          .map((p) => (p['file_path'] ?? '').toString())
          .toList();
      return true;
    } catch (error) {
      trace.end(note: '失败($error)');
      _remoteItemPathsFailed.add(collectionId);
      return false;
    } finally {
      _remoteItemPathsLoading.remove(collectionId);
    }
  }

  /// 开启新一轮搜索：丢掉上一轮的失败名单与未发完的队列。
  /// 已成功的正缓存保留——条目路径与查询词无关，值得跨查询复用。
  void _resetRemotePathSession() {
    _remoteItemPathsFailed.clear();
    _remotePathQueue.clear();
  }

  /// 登记远程集合的条目路径预热需求（深度搜索匹配资源文件名用）。
  ///
  /// 只入队不直接发请求：一轮深度搜索会扫出几百个远程集合，齐发会把节点打到 503，
  /// 而响应零散回来又各触发一次全网格重算，就是「搜到结果后还在反复搜索」的来源。
  void _requestRemoteItemPaths(String collectionId) {
    if (_remoteCollectionItemPaths.containsKey(collectionId) ||
        _remoteItemPathsLoading.contains(collectionId) ||
        _remoteItemPathsFailed.contains(collectionId) ||
        _remotePathQueue.contains(collectionId)) {
      return;
    }
    final nodeId = getRemoteNodeId(collectionId);
    final rawId = getRemoteRawCollectionId(collectionId);
    if (nodeId == null || rawId == null) return;
    _remotePathQueue.add(collectionId);
  }
}
