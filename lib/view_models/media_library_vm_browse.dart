part of 'media_library_viewmodel.dart';

/// 浏览层派生数据：同名分组、合并数据源、排序、可见列表、文件夹汇总。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryBrowseExt on MediaLibraryViewModel {
  // ── 同名集合分组 ──────────────────────────────────────────────────────────

  /// 是否为同名集合分组虚拟文件夹。
  bool isDupGroup(String id) => id.startsWith(MediaLibraryViewModel.dupGroupPrefix);

  /// 从分组 ID 中提取集合标题。
  String? dupGroupTitle(String id) => isDupGroup(id)
      ? id.substring(MediaLibraryViewModel.dupGroupPrefix.length)
      : null;

  /// 当前是否处于同名集合分组内。
  bool get isInDupGroup {
    final fid = currentFolderId.value;
    return fid != null && isDupGroup(fid);
  }

  /// 当前同名分组标题（不在分组内时为 null）。
  String? get currentDupGroupTitle {
    final fid = currentFolderId.value;
    return fid == null ? null : dupGroupTitle(fid);
  }

  /// 返回指定同名分组包含的集合列表（标题相同且属于同一父文件夹）。
  List<media_api.MediaCollection> dupGroupCollections(String groupId) {
    final title = dupGroupTitle(groupId);
    final parent = _dupGroupParents[groupId];
    return mergedCollections
        .where((c) => c.title == title && c.folderId == parent)
        .toList(growable: false);
  }

  /// 同名分组内集合卡的展示名（父级目录名），非分组内或无父级可显示时为 null。
  String? dupGroupDisplayTitle(String collectionId) =>
      _dupGroupDisplayTitles[collectionId];

  /// 算出同名分组内每个集合的展示名。
  ///
  /// 分组里各集合的目录末段都是同一个标题（xxx/1/哈哈哈、xxx/2/哈哈哈），能区分来源的
  /// 只有它上面的祖先目录，所以取「组内不撞名的最短祖先路径」：正常情况下就是父目录名
  /// 1、2、3；a/1/哈哈哈 与 b/1/哈哈哈 这种父级也同名的，自动升级成 a/1、b/1。
  Map<String, String> _buildDupGroupDisplayTitles(
    String groupTitle,
    List<media_api.MediaCollection> members,
  ) {
    final ancestors = <String, List<String>>{
      for (final c in members) c.id: _ancestorSegments(c.folderPath),
    };
    // 取该集合最内层 depth 级祖先拼成的标签；祖先不够深（或这一级仍是同名标题）时为空串
    String labelAt(String id, int depth) {
      final segs = ancestors[id]!;
      if (depth > segs.length) return '';
      final label = segs.sublist(segs.length - depth).join('/');
      return label == groupTitle ? '' : label;
    }

    final out = <String, String>{};
    for (final c in members) {
      final maxDepth = ancestors[c.id]!.length;
      var depth = 1;
      while (depth <= maxDepth) {
        final own = labelAt(c.id, depth);
        final clashes = members.any(
          (o) => o.id != c.id && labelAt(o.id, depth) == own,
        );
        if (own.isNotEmpty && !clashes) {
          out[c.id] = own;
          break;
        }
        depth++;
      }
      // 根目录下直接放的集合（无祖先段）没有可区分的父级，交回 UI 用集合标题显示
    }
    return out;
  }

  /// 集合目录路径中可用来区分来源的祖先段：去掉末段（集合自身目录），兼容两种分隔符。
  List<String> _ancestorSegments(String folderPath) {
    final segs = folderPath
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segs.length <= 1) return const [];
    return segs.sublist(0, segs.length - 1);
  }

  // ── 合并数据源 ────────────────────────────────────────────────────────────

  List<media_api.MediaFolder> get mergedFolders {
    // 排序键一次算好，避免比较器里反复 toLowerCase 生成临时字符串
    final keyed = [
      for (final item in <media_api.MediaFolder>[...folders, ...remoteFolders])
        (item, item.name.toLowerCase()),
    ];
    keyed.sort((left, right) {
      final orderCompare = left.$1.order.compareTo(right.$1.order);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return left.$2.compareTo(right.$2);
    });
    return keyed.map((e) => e.$1).toList();
  }

  /// mergedCollections 排序结果缓存。
  ///
  /// 原实现每次读取都重新拷贝+全量排序，而它被集合卡封面、文件夹封面、
  /// 智能文件夹匹配、丢失检查等 build 路径反复调用，是每帧重建的主要 CPU 开销。
  List<media_api.MediaCollection> get mergedCollections {
    final local = collections;
    final remote = remoteCollections;
    final src = _mergedCollectionsSrc;
    final out = _mergedCollectionsOut;
    if (src != null &&
        out != null &&
        src.length == local.length + remote.length &&
        _sameCollectionSource(src, local, remote)) {
      return out;
    }
    final all = <media_api.MediaCollection>[...local, ...remote];
    // 排序键一次算好，避免比较器里反复 toLowerCase 生成临时字符串
    final keyed = [
      for (final item in all) (item, item.title.toLowerCase()),
    ];
    keyed.sort((left, right) {
      final cmp = right.$1.updatedAt.compareTo(left.$1.updatedAt);
      if (cmp != 0) {
        return cmp;
      }
      return left.$2.compareTo(right.$2);
    });
    final result = List<media_api.MediaCollection>.unmodifiable(
      keyed.map((e) => e.$1).toList(growable: false),
    );
    _mergedCollectionsSrc = all;
    _mergedCollectionsOut = result;
    _mergedCollectionsGeneration++;
    return result;
  }

  /// 逐项比对快照与当前「本地 + 远程」拼接结果是否为同一批实例。
  bool _sameCollectionSource(
    List<media_api.MediaCollection> src,
    List<media_api.MediaCollection> local,
    List<media_api.MediaCollection> remote,
  ) {
    var i = 0;
    for (final c in local) {
      if (!identical(src[i++], c)) return false;
    }
    for (final c in remote) {
      if (!identical(src[i++], c)) return false;
    }
    return true;
  }

  media_api.MediaFolder? get currentFolder {
    final folderId = currentFolderId.value;
    if (folderId == null) {
      return null;
    }
    return mergedFolders.firstWhereOrNull((folder) => folder.id == folderId);
  }

  SmartFolder? get currentSmartFolder {
    final folderId = currentFolderId.value;
    if (folderId == null || !isSmartFolder(folderId)) return null;
    return getSmartFolder(folderId);
  }

  bool isSmartFolder(String id) =>
      id.startsWith(MediaLibraryViewModel._smartFolderPrefix);

  /// 是否是远程节点的智能文件夹（ID 格式：smart-folder:remote:[nodeId]:[rawId]）。
  bool isRemoteSmartFolder(String id) =>
      id.startsWith(MediaLibraryViewModel._remoteSmartFolderPrefix);

  /// 从远程智能文件夹 ID 中提取 nodeId。
  String? remoteSmartFolderNodeId(String id) {
    if (!isRemoteSmartFolder(id)) return null;
    // smart-folder:remote:<nodeId>:<rawId>
    final suffix =
        id.substring(MediaLibraryViewModel._remoteSmartFolderPrefix.length);
    final colon = suffix.indexOf(':');
    return colon == -1 ? suffix : suffix.substring(0, colon);
  }

  /// 本地 + 所有远程节点的智能文件夹合并列表（响应式，依赖 _remoteSmartFolders 的变化）。
  List<SmartFolder> get mergedSmartFolders {
    // 读取 length 以向 GetX 注册响应式依赖，避免访问受保护的 .value
    _remoteSmartFolders.length;
    return [
      ...smartFolders,
      for (final list in _remoteSmartFolders.values) ...list,
    ];
  }

  SmartFolder? getSmartFolder(String id) =>
      mergedSmartFolders.firstWhereOrNull((sf) => sf.id == id);

  /// The "real" folder context for operations (create sub-folder, scan, import).
  /// • When navigated into a smart folder with a single [targetFolderIds], that real folder
  ///   is the effective context.
  /// • When in a smart folder with multiple or no targets, returns null (root).
  /// • Otherwise returns the current regular folder ID (may be null).
  String? get effectiveFolderId {
    final sf = currentSmartFolder;
    if (sf != null) {
      return sf.targetFolderIds.length == 1 ? sf.targetFolderIds.first : null;
    }
    final fid = currentFolderId.value;
    // 同名集合分组是虚拟文件夹：操作上下文为其登记的父文件夹（可能为 null = 根目录）
    if (fid != null && isDupGroup(fid)) return _dupGroupParents[fid];
    if (fid != null && isSmartFolder(fid)) return null;
    return fid;
  }

  media_api.MediaCollection? get currentCollection {
    final collectionId = currentCollectionId.value;
    if (collectionId == null) {
      return null;
    }
    return mergedCollections.firstWhereOrNull(
      (collection) => collection.id == collectionId,
    );
  }

  String get currentCollectionTitle => currentCollection?.title ?? '';

  String get currentBrowseTitle =>
      currentSmartFolder?.name ??
      currentDupGroupTitle ??
      currentFolder?.name ??
      '媒体库';

  List<media_api.MediaFolder> get currentFolderTrail {
    // Smart folders are always root-level virtual folders – no breadcrumb sub-trail needed
    if (currentSmartFolder != null) return [];
    // 同名集合分组：面包屑展示其登记的父文件夹路径（分组标题段由 UI 层额外拼接）
    final fid = currentFolderId.value;
    if (fid != null && isDupGroup(fid)) {
      return _folderTrailFrom(_dupGroupParents[fid]);
    }
    return _folderTrailFrom(fid);
  }

  /// 从指定文件夹 ID 回溯构建面包屑路径（自根到该文件夹）。
  List<media_api.MediaFolder> _folderTrailFrom(String? folderId) {
    final trail = <media_api.MediaFolder>[];
    var cursor = folderId == null
        ? null
        : mergedFolders.firstWhereOrNull((folder) => folder.id == folderId);
    final visited = <String>{};
    while (cursor != null && visited.add(cursor.id)) {
      trail.insert(0, cursor);
      final parentId = cursor.parentId;
      cursor = parentId == null
          ? null
          : mergedFolders.firstWhereOrNull((folder) => folder.id == parentId);
    }
    return trail;
  }

  List<media_api.MediaFolder> get currentChildFolders {
    // Smart folders have no sub-folders
    if (currentSmartFolder != null) return [];
    final folderId = currentFolderId.value;
    return mergedFolders
        .where((folder) => folder.parentId == folderId)
        .toList(growable: false);
  }

  /// 判断集合是否匹配智能文件夹。
  /// - 远程集合 或 远程智能文件夹：忽略文件夹范围过滤，仅对标题和路径做正则匹配。
  /// - 本地集合 + 本地智能文件夹：执行完整的 matchesCollection 逻辑。
  bool collectionMatchesSmartFolder(
    SmartFolder sf,
    media_api.MediaCollection c,
  ) {
    final regexOnly = isRemoteCollection(c.id) || isRemoteSmartFolder(sf.id);
    if (regexOnly) {
      // 远程场景：跳过文件夹范围检查，仅对标题和路径做正则匹配
      // 使用 effectivePattern（合并 keywords + regexPattern）而非单独的 regexPattern
      final pattern = sf.effectivePattern;
      if (pattern.isEmpty) return true;
      try {
        final re = RegExp(pattern, caseSensitive: false, unicode: true);
        return re.hasMatch(c.title) || re.hasMatch(c.folderPath);
      } catch (_) {
        return true;
      }
    }
    // 本地集合 + 本地智能文件夹：完整匹配（包含文件夹范围 + 文件名模式）
    final matchResult = sf.matchesCollection(c);
    if (!matchResult) {
      _logger.info(
        '[collectionMatchesSmartFolder] 本地集合"${c.title}"不匹配sf"${sf.name}": folderId=${c.folderId}, targetFolderIds=${sf.targetFolderIds}, regexTarget=${sf.regexTarget}',
      );
    }
    if (!matchResult) return false;
    if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
      final paths = _getCollectionItemPaths(c.id);
      final fileMatch = sf.matchesFileNames(paths);
      if (!fileMatch) {
        _logger.info(
          '[collectionMatchesSmartFolder] 文件名模式不匹配: collection="${c.title}", pathsCount=${paths.length}',
        );
      }
      return fileMatch;
    }
    return true;
  }

  /// 智能文件夹匹配的集合列表（带缓存）。
  ///
  /// 卡片 build 期间每张智能文件夹卡都会独立全量扫一遍 mergedCollections，
  /// 且封面与 matchCount 各扫一次；此处合并成一份可复用结果并按输入代数失效。
  /// SmartFolder 未重写 ==，故 `entry.sf == sf` 即实例同一，定义必然一致。
  List<media_api.MediaCollection> collectionsMatchingSmartFolder(
    SmartFolder sf,
  ) {
    final generation = _mergedCollectionsGeneration;
    final pathsEpoch = _itemPathsEpoch;
    final hit = _sfMatchCache[sf.id];
    if (hit != null &&
        hit.sf == sf &&
        hit.generation == generation &&
        hit.pathsEpoch == pathsEpoch) {
      return hit.collections;
    }
    final matched = List<media_api.MediaCollection>.unmodifiable(
      mergedCollections.where((c) => collectionMatchesSmartFolder(sf, c)),
    );
    _sfMatchCache[sf.id] = _SmartFolderMatch(
      sf: sf,
      generation: generation,
      pathsEpoch: pathsEpoch,
      collections: matched,
    );
    return matched;
  }

  List<media_api.MediaCollection> get currentCollections {
    // 注意：此 getter 在每次 visibleItems / 网格 Obx 重建时都会被读取。不要在里头做同步
    // 日志或重活——媒体量大时（数千集合）会在 UI 线程上刷屏式写日志，放大卡顿与主线程阻塞。
    // 派生缓存：网格的 Obx 只订阅 visibleVersion，缓存命中时这里直接返回上一轮结果，
    // 不再重跑过滤+排序；缓存由 _invalidateVisible() 统一失效（输入变化 ever 监听）。
    final cached = _currentCollectionsOut;
    if (cached != null) return cached;
    final result = _computeCurrentCollections();
    _currentCollectionsOut = result;
    return result;
  }

  List<media_api.MediaCollection> _computeCurrentCollections() {
    final folderId = currentFolderId.value;
    // Read version to register as reactive dependency so Obx rebuilds on reorder
    collectionOrderVersion.value;
    // Read sort order to register reactive dependency
    collectionSortOrder.value;
    // Read favorites to register dependency
    final favOnly = showFavoritesOnly.value;
    final favIds = favoriteCollectionIds.toSet();
    // 同名集合分组：直接返回该分组登记的集合列表（标题相同且父文件夹一致）
    if (folderId != null && isDupGroup(folderId)) {
      final grouped = dupGroupCollections(folderId);
      final filtered = favOnly
          ? grouped.where((c) => favIds.contains(c.id)).toList(growable: true)
          : grouped.toList(growable: true);
      return _applySortOrder(filtered, folderId);
    }
    // Smart folder: 按智能文件夹规则过滤集合（远程集合忽略文件夹范围）
    if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      if (sf == null) {
        _logger.error(
          '[currentCollections] 智能文件夹不存在: folderId=$folderId, mergedSmartFolderIds=${mergedSmartFolders.map((s) => s.id).toList()}',
        );
        return [];
      }
      var filtered = List.of(collectionsMatchingSmartFolder(sf));
      if (favOnly) {
        filtered = filtered.where((c) => favIds.contains(c.id)).toList();
      }
      return _applySortOrder(filtered, folderId);
    }
    var filtered = mergedCollections
        .where((collection) => collection.folderId == folderId)
        .toList(growable: true);
    if (favOnly) {
      filtered = filtered.where((c) => favIds.contains(c.id)).toList();
    }
    return _applySortOrder(filtered, folderId ?? 'root');
  }

  List<media_api.MediaCollection> _applySortOrder(
    List<media_api.MediaCollection> list,
    String orderKey,
  ) {
    final sort = collectionSortOrder.value;
    if (sort == CollectionSortOrder.combinedSort) {
      // 先按创建时间升序排列（文件创建顺序）作为基准
      final result = [...list];
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      // 再叠加拖拽自定义排序：保留拖拽指定的相对位置，未设定的按创建时间顺序填入
      final customOrder = _collectionOrders[orderKey];
      if (customOrder != null && customOrder.isNotEmpty) {
        // _logger.info(
        //   '_applySortOrder: combinedSort orderKey=$orderKey applying ${customOrder.length}-item custom order',
        // );
        result.sort((a, b) {
          final ai = customOrder.indexOf(a.id);
          final bi = customOrder.indexOf(b.id);
          // 两者都有自定义位置：按拖拽顺序
          if (ai != -1 && bi != -1) return ai.compareTo(bi);
          // 只有 a 有自定义位置：a 前置
          if (ai != -1) return -1;
          // 只有 b 有自定义位置：b 前置
          if (bi != -1) return 1;
          // 两者均无自定义位置：保持创建时间顺序（已 stable 排好）
          return 0;
        });
      } else {
        // _logger.info(
        //   '_applySortOrder: combinedSort orderKey=$orderKey NO custom order, using createdAt',
        // );
      }
      return result;
    }
    if (sort != CollectionSortOrder.dateUpdated) {
      final result = [...list];
      switch (sort) {
        case CollectionSortOrder.nameAsc:
          result.sort((a, b) => naturalCompare(a.title, b.title));
        case CollectionSortOrder.nameDesc:
          result.sort((a, b) => naturalCompare(b.title, a.title));
        case CollectionSortOrder.countDesc:
          result.sort((a, b) => b.itemCount.compareTo(a.itemCount));
        case CollectionSortOrder.countAsc:
          result.sort((a, b) => a.itemCount.compareTo(b.itemCount));
        case CollectionSortOrder.sizeDesc:
          result.sort(
            (a, b) => (_collectionSizes[b.id] ?? BigInt.zero).compareTo(
              _collectionSizes[a.id] ?? BigInt.zero,
            ),
          );
        case CollectionSortOrder.sizeAsc:
          result.sort(
            (a, b) => (_collectionSizes[a.id] ?? BigInt.zero).compareTo(
              _collectionSizes[b.id] ?? BigInt.zero,
            ),
          );
        case CollectionSortOrder.dateUpdated:
          break;
        case CollectionSortOrder.combinedSort:
          break;
      }
      return result;
    }
    // dateUpdated：按 updatedAt 降序排列，不应用拖拽顺序
    final result = [...list];
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // _logger.d('_applySortOrder: dateUpdated orderKey=$orderKey sorted by updatedAt desc');
    return result;
  }

  List<MediaLibraryItem> get visibleItems {
    // 派生缓存：网格 Obx 只订阅 visibleVersion，命中时不重跑过滤/排序/同名分组。
    // 缓存由 _invalidateVisible() 在任一派生输入变化时统一失效（见 onInitAsync 的 ever 注册）。
    final cached = _visibleItemsOut;
    if (cached != null) return cached;
    final result = _computeVisibleItems();
    _visibleItemsOut = result;
    return result;
  }

  List<MediaLibraryItem> _computeVisibleItems() {
    // 同名分组展示名每轮重算：非分组视图一律清空，避免陈旧映射串到别的层级
    _dupGroupDisplayTitles = const {};
    // 相似查找激活时：按名称亲和度层级筛选当前层级 + 子孙文件夹内的集合
    final similar = similarSearchQuery.value.trim();
    if (similar.isNotEmpty) {
      return _similarSearchItems(similar);
    }
    // 搜索激活时：深度搜索当前层级并仅展示匹配项（用防抖后的生效词，输入途中不重跑）
    final query = appliedSearchQuery.value.trim().toLowerCase();
    if (query.isNotEmpty) {
      return _deepSearchItems(query);
    }
    // Smart folders (local + remote) are only shown at root level (currentFolderId == null)
    final folderId = currentFolderId.value;
    final sfItems = (folderId == null)
        ? mergedSmartFolders.map(MediaLibrarySmartFolderItem.new).toList()
        : <MediaLibrarySmartFolderItem>[];
    final collections = currentCollections;
    // 同名集合分组：分组内部不再嵌套分组，直接平铺显示集合卡片；
    // 智能文件夹内集合来自跨目录匹配，也不做同名聚合。
    if (folderId != null && (isDupGroup(folderId) || isSmartFolder(folderId))) {
      final groupTitle = dupGroupTitle(folderId);
      if (groupTitle != null) {
        _dupGroupDisplayTitles = _buildDupGroupDisplayTitles(
          groupTitle,
          collections,
        );
      }
      return <MediaLibraryItem>[
        ...currentChildFolders.map(MediaLibraryFolderItem.new),
        ...sfItems,
        ...collections.map(MediaLibraryCollectionItem.new),
      ];
    }
    // 按标题聚合同名集合：≥2 个同名集合折叠为虚拟分组文件夹；
    // 首次出现位置保留顺序，其余重复项从平铺列表中移除。
    final titleCounts = <String, int>{};
    for (final c in collections) {
      titleCounts[c.title] = (titleCounts[c.title] ?? 0) + 1;
    }
    final emittedGroupTitles = <String>{};
    final collectionItems = <MediaLibraryItem>[];
    for (final c in collections) {
      if ((titleCounts[c.title] ?? 0) >= 2) {
        if (!emittedGroupTitles.add(c.title)) continue;
        final groupId = '${MediaLibraryViewModel.dupGroupPrefix}${c.title}';
        // 登记分组所属父文件夹，供进入分组后按标题+父目录筛选集合
        _dupGroupParents[groupId] = folderId;
        collectionItems.add(
          MediaLibraryFolderItem(
            media_api.MediaFolder(
              id: groupId,
              name: c.title,
              createdAt: 0,
              order: 0,
              parentId: folderId,
            ),
          ),
        );
      } else {
        collectionItems.add(MediaLibraryCollectionItem(c));
      }
    }
    return <MediaLibraryItem>[
      ...currentChildFolders.map(MediaLibraryFolderItem.new),
      ...sfItems,
      ...collectionItems,
    ];
  }

  bool get isInDetail => currentCollectionId.value != null;

  int collectionCountInFolder(String folderId) {
    // 同名集合分组：统计分组内集合数量而非真实文件夹下的集合
    if (isDupGroup(folderId)) {
      return dupGroupCollections(folderId).length;
    }
    return mergedCollections
        .where((collection) => collection.folderId == folderId)
        .length;
  }

  /// 集合「磁盘上仍然存在」的体积与条数（排除失效资源）。
  ///
  /// 远程集合的文件在节点侧，本机 stat 不到，直接用节点上报值；
  /// 本地集合在全库 stat 落地前退回库里记录值，避免首屏闪 0。
  ({BigInt size, int count}) collectionResources(
    media_api.MediaCollection collection,
  ) {
    // 读取即注册依赖：stat 落地后集合卡也要跟着换数
    liveStatsVersion.value;
    if (!isRemoteCollection(collection.id)) {
      final live = _collectionLiveStats[collection.id];
      if (live != null) return live;
    }
    return (
      size: getCollectionTotalSize(collection.id),
      count: collection.itemCount.toInt(),
    );
  }

  /// 文件夹卡片的展示汇总。
  ///
  /// [MediaFolderSummary.childCards] 只数直接子级（点开这个文件夹能看到的卡片），
  /// resources/size 递归整棵子树，且只计仍然存在的资源。
  MediaFolderSummary folderSummary(String folderId) {
    // 读取即注册依赖：全库 stat 落地后卡片重建
    liveStatsVersion.value;
    if (isDupGroup(folderId)) {
      // 同名集合分组是虚拟文件夹：成员集合即其全部子级，分组内不再二次聚合
      final members = dupGroupCollections(folderId);
      var resources = 0;
      var size = BigInt.zero;
      for (final collection in members) {
        final stat = collectionResources(collection);
        resources += stat.count;
        size += stat.size;
      }
      return MediaFolderSummary(
        childCards: members.length,
        resources: resources,
        size: size,
      );
    }
    return _folderSummaries()[folderId] ?? MediaFolderSummary.empty;
  }

  /// 智能文件夹命中集合的体积与条数汇总。
  ({BigInt size, int count}) smartFolderResources(SmartFolder sf) {
    liveStatsVersion.value;
    var size = BigInt.zero;
    var count = 0;
    for (final collection in collectionsMatchingSmartFolder(sf)) {
      final stat = collectionResources(collection);
      size += stat.size;
      count += stat.count;
    }
    return (size: size, count: count);
  }

  /// 一次性算出所有文件夹的汇总，卡片同步读缓存。
  ///
  /// 后序遍历：父级的递归量 = 本层集合 + 各子文件夹已经算好的递归量，整棵树只走一遍。
  Map<String, MediaFolderSummary> _folderSummaries() {
    // 先读 mergedCollections：集合变化只有经过它重算才会推进代数，
    // 放在缓存判定之后再读就永远慢一拍，新增的集合会算不进汇总。
    final collections = mergedCollections;
    final local = folders;
    final remote = remoteFolders;
    final out = _folderSummaryOut;
    if (out != null &&
        _folderSummaryGeneration == _mergedCollectionsGeneration &&
        _folderSummaryLiveEpoch == liveStatsVersion.value &&
        _sameFolderSource(local, remote)) {
      return out;
    }
    final computed = _computeFolderSummaries(collections);
    _folderSummarySrc = <media_api.MediaFolder>[...local, ...remote];
    _folderSummaryOut = computed;
    _folderSummaryGeneration = _mergedCollectionsGeneration;
    _folderSummaryLiveEpoch = liveStatsVersion.value;
    return computed;
  }

  /// 文件夹结构快照是否仍是同一批实例（字段全 final，实例不变即内容不变）。
  bool _sameFolderSource(
    List<media_api.MediaFolder> local,
    List<media_api.MediaFolder> remote,
  ) {
    final src = _folderSummarySrc;
    if (src == null || src.length != local.length + remote.length) {
      return false;
    }
    var i = 0;
    for (final folder in local) {
      if (!identical(src[i++], folder)) return false;
    }
    for (final folder in remote) {
      if (!identical(src[i++], folder)) return false;
    }
    return true;
  }

  Map<String, MediaFolderSummary> _computeFolderSummaries(
    List<media_api.MediaCollection> collections,
  ) {
    final childrenByParent = <String, List<media_api.MediaFolder>>{};
    for (final folder in mergedFolders) {
      final parentId = folder.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(folder);
      }
    }
    final collectionsByFolder = <String, List<media_api.MediaCollection>>{};
    for (final collection in collections) {
      final parentId = collection.folderId;
      if (parentId != null) {
        collectionsByFolder.putIfAbsent(parentId, () => []).add(collection);
      }
    }

    final summaries = <String, MediaFolderSummary>{};
    MediaFolderSummary walk(
      media_api.MediaFolder folder,
      Set<String> visiting,
    ) {
      final cached = summaries[folder.id];
      if (cached != null) return cached;
      // 远程节点的父子数据可能带环，走不出的按空汇总返回
      if (!visiting.add(folder.id)) return MediaFolderSummary.empty;
      final direct = collectionsByFolder[folder.id] ?? const [];
      final children = childrenByParent[folder.id] ?? const [];
      var resources = 0;
      var size = BigInt.zero;
      for (final collection in direct) {
        final stat = collectionResources(collection);
        resources += stat.count;
        size += stat.size;
      }
      // 同名集合在本层折叠成一张分组卡，所以集合贡献的卡片数按去重标题计
      var childCards = children.length + direct.map((c) => c.title).toSet().length;
      for (final child in children) {
        final sub = walk(child, visiting);
        resources += sub.resources;
        size += sub.size;
      }
      visiting.remove(folder.id);
      final summary = MediaFolderSummary(
        childCards: childCards,
        resources: resources,
        size: size,
      );
      summaries[folder.id] = summary;
      return summary;
    }

    for (final folder in mergedFolders) {
      walk(folder, <String>{});
    }
    return summaries;
  }
}
