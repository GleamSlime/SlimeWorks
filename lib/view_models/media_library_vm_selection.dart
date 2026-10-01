part of 'media_library_viewmodel.dart';

/// 浏览层集合卡的派生数据快照。
///
/// 把卡片 build 要用的 VM 查询（封面派生、丢失检查、资源统计、节点名等）
/// 打包成纯数据：卡片 build 从「每卡逐个回查 VM 方法」变为「读一次快照」，
/// 与选择通知器（selectionOf）配合后，选择/数据变化只重建真正相关的卡片。
/// 缓存与 visibleItems 派生缓存同代失效（_invalidateVisible）。
class BrowseCardData {
  const BrowseCardData({
    required this.item,
    required this.coverSource,
    required this.isRemote,
    required this.isLost,
    required this.isFavorited,
    required this.nodeName,
    required this.resourceCount,
    required this.totalSize,
    required this.childCount,
    required this.matchCount,
  });

  final MediaLibraryItem item;

  /// 封面源（三类卡各自的封面派生结果）
  final String? coverSource;

  /// 是否远程节点的内容
  final bool isRemote;

  /// 封面/资源是否丢失
  final bool isLost;

  /// 是否已收藏（仅集合卡有意义）
  final bool isFavorited;

  /// 所属远程节点名（本地内容为 null）
  final String? nodeName;

  /// 仍然存在的资源条数（失效资源不计）
  final int resourceCount;

  /// 仍然存在的资源体积
  final BigInt totalSize;

  /// 文件夹卡的直接子级卡片数（其余卡为 0）
  final int childCount;

  /// 智能文件夹卡的命中集合数（其余卡为 0）
  final int matchCount;
}

/// 浏览层选择通知器与派生缓存失效。
///
/// 旧结构中每张卡各包一个 Obx（4000+ 集合 = 4000 路监听），
/// 任一 Rx 变化（选中、封面批次完成、存活统计落地）都会让全部卡片
/// 重查 visibleItems/封面/统计——这是每帧重建的主要放大器。
/// 本扩展把这条链收敛为：
/// - 数据层：网格唯一 Obx 只订阅 [MediaLibraryViewModel.visibleVersion]；
/// - 选择层：卡片 ListenableBuilder 只订阅自己的 [selectionOf] notifier，
///   diff 通知（syncSelectionTo）只重建真正变化的卡片。
extension BrowseSelectionExt on MediaLibraryViewModel {
  // ── 派生缓存失效 ────────────────────────────────────────────────────────

  /// 浏览层派生缓存统一失效入口：清三份缓存并推进 visibleVersion，
  /// 网格的唯一数据 Obx 随之重建一次（而非每输入各触发一次）。
  void _invalidateVisible() {
    _visibleItemsOut = null;
    _currentCollectionsOut = null;
    _browseCardCache.clear();
    visibleVersion.value++;
  }

  // ── 选择通知器 ──────────────────────────────────────────────────────────

  /// 取卡片级选中通知器：卡片用 ListenableBuilder 订阅它，选择变化时只重建自己。
  ///
  /// notifier 在取消选中后仍保留在表里（值为 false）：正在订阅的 ListenableBuilder
  /// 持有该实例，若从表中删除，下次再选中同一张卡会新建 notifier，
  /// 旧订阅者收不到 true 通知，选中描边会丢失。
  ValueListenable<bool> selectionOf(String id) {
    final existing = _selectionNotifiers[id];
    if (existing != null) return existing;
    return _selectionNotifiers[id] = ValueNotifier<bool>(
      selectedIds.contains(id),
    );
  }

  /// 选择写点收口：diff 新旧选中集合后只通知变化的 notifier，并同步 selectedIds。
  ///
  /// [selecting] 为 null 表示保持当前 isSelecting 状态（增量增删场景）。
  void syncSelectionTo(Set<String> next, {bool? selecting}) {
    // 先 diff 再写：只 notify 真正变化的卡片，避免全部卡片重查
    final removedIds = selectedIds.where((id) => !next.contains(id));
    final addedIds = next.where((id) => !selectedIds.contains(id));
    for (final id in removedIds) {
      final notifier = _selectionNotifiers[id];
      if (notifier != null && notifier.value) notifier.value = false;
    }
    for (final id in addedIds) {
      final notifier = _selectionNotifiers[id];
      if (notifier != null && !notifier.value) notifier.value = true;
    }
    selectedIds.assignAll(next);
    if (selecting != null) isSelecting.value = selecting;
  }

  /// 框选落点：命中集合直接赋选中并进入选择模式（空命中则退出）。
  void applyBoxSelection(Set<String> hitIds) {
    if (hitIds.isEmpty) {
      syncSelectionTo(const <String>{}, selecting: false);
      return;
    }
    syncSelectionTo(hitIds, selecting: true);
  }

  // ── 集合卡派生数据快照 ──────────────────────────────────────────────────

  /// 取集合卡的派生数据快照（懒打包 + 代数缓存）。
  ///
  /// 只对实际 build 的可见卡打包，全量派生发生在缓存失效后的首次网格重建；
  /// 同一代数内重复读同一张卡直接命中缓存。
  BrowseCardData browseCardData(MediaLibraryItem item) {
    final cached = _browseCardCache[item.id];
    if (cached != null) return cached;
    final data = _buildBrowseCardData(item);
    _browseCardCache[item.id] = data;
    return data;
  }

  BrowseCardData _buildBrowseCardData(MediaLibraryItem item) {
    if (item is MediaLibraryCollectionItem) {
      final collection = item.collection;
      final live = collectionResources(collection);
      final isRemote = isRemoteCollection(collection.id);
      return BrowseCardData(
        item: item,
        coverSource: buildCollectionCoverSource(collection),
        isRemote: isRemote,
        isLost: isRemote ? false : checkCollectionLost(collection),
        isFavorited: isFavorite(collection.id),
        nodeName: isRemote ? getRemoteNodeName(collection.id) : null,
        resourceCount: live.count,
        totalSize: live.size,
        childCount: 0,
        matchCount: 0,
      );
    }
    if (item is MediaLibraryFolderItem) {
      final folder = item.folder;
      final isRemote = isRemoteFolder(folder.id);
      final summary = folderSummary(folder.id);
      return BrowseCardData(
        item: item,
        coverSource: buildFolderCoverSource(folder),
        isRemote: isRemote,
        // 同名分组是虚拟文件夹：封面不存在丢失概念
        isLost: isDupGroup(folder.id) ? false : checkFolderLost(folder),
        isFavorited: false,
        nodeName: isRemote ? getRemoteFolderNodeName(folder.id) : null,
        resourceCount: summary.resources,
        totalSize: summary.size,
        childCount: summary.childCards,
        matchCount: 0,
      );
    }
    final sf = (item as MediaLibrarySmartFolderItem).smartFolder;
    final isRemote = isRemoteSmartFolder(sf.id);
    final sfResources = smartFolderResources(sf);
    final nodeId = remoteSmartFolderNodeId(sf.id);
    return BrowseCardData(
      item: item,
      coverSource: buildSmartFolderCoverSource(sf),
      isRemote: isRemote,
      isLost: checkSmartFolderLost(sf),
      isFavorited: false,
      nodeName: nodeId != null
          ? (nodeSettingsService.getNodeById(nodeId)?.name ?? nodeId)
          : null,
      resourceCount: sfResources.count,
      totalSize: sfResources.size,
      childCount: 0,
      matchCount: collectionsMatchingSmartFolder(sf).length,
    );
  }

  // ── 选择模式进出与批量选择 ────────────────────────────────────────────────

  void enterSelection(String firstId) {
    // 选择写点一律走 syncSelectionTo 收口：diff 通知卡片级 notifier，只重建真正变化的卡
    syncSelectionTo({firstId}, selecting: true);
  }

  void exitSelection() {
    syncSelectionTo(const <String>{}, selecting: false);
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      // 移除后为空则退出选择模式（保持旧语义）
      final next = {...selectedIds}..remove(id);
      if (next.isEmpty) {
        syncSelectionTo(next, selecting: false);
        return;
      }
      syncSelectionTo(next);
      return;
    }
    syncSelectionTo({...selectedIds, id}, selecting: true);
  }

  void toggleSelectAll() {
    final items = visibleItems;
    if (selectedIds.length == items.length) {
      syncSelectionTo(const <String>{}, selecting: false);
      return;
    }
    syncSelectionTo(
      items.map((item) => item.id).toSet(),
      selecting: items.isNotEmpty,
    );
  }

  /// 取消所有选择，并选中当前文件夹内全部未收藏的集合（批量操作入口）。
  /// 智能文件夹下按其过滤规则确定范围；无未收藏集合时保持选择模式且选中为空。
  void selectUnfavoritedCollections() {
    final folderId = currentFolderId.value;
    List<media_api.MediaCollection> scope;
    if (folderId != null && isDupGroup(folderId)) {
      scope = dupGroupCollections(folderId);
    } else if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      scope = sf == null
          ? <media_api.MediaCollection>[]
          : mergedCollections
                .where((c) => collectionMatchesSmartFolder(sf, c))
                .toList();
    } else {
      scope = mergedCollections.where((c) => c.folderId == folderId).toList();
    }
    final unfavoritedIds = scope
        .where((c) => !favoriteCollectionIds.contains(c.id))
        .map((c) => c.id)
        .toSet();
    _logger.info(
      'selectUnfavoritedCollections: folderId=$folderId, scope=${scope.length}, unfavorited=${unfavoritedIds.length}',
    );
    syncSelectionTo(unfavoritedIds, selecting: true);
  }
}
