import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/initialize/ffmpeg.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/video_thumb_queue.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

part 'media_library_vm_remote.dart';
part 'media_library_vm_smart_folders.dart';
part 'media_library_vm_collections.dart';

enum MediaItemSortOrder {
  nameAsc,
  nameDesc,
  sizeDesc,
  sizeAsc,
  timeDesc,
  timeAsc;

  String get label => switch (this) {
    nameAsc => '文件名 A→Z',
    nameDesc => '文件名 Z→A',
    sizeDesc => '大小 大到小',
    sizeAsc => '大小 小到大',
    timeDesc => '修改时间 新到旧',
    timeAsc => '修改时间 旧到新',
  };
}

enum CollectionSortOrder {
  combinedSort,
  dateUpdated,
  nameAsc,
  nameDesc,
  countDesc,
  countAsc,
  sizeDesc,
  sizeAsc;

  String get label => switch (this) {
    combinedSort => '综合排序',
    dateUpdated => '最近更新',
    nameAsc => '名称 A→Z',
    nameDesc => '名称 Z→A',
    countDesc => '项目数 多到少',
    countAsc => '项目数 少到多',
    sizeDesc => '大小 大到小',
    sizeAsc => '大小 小到大',
  };
}

class MediaLibraryViewModel extends BaseViewModel {
  static const String _remoteCollectionPrefix = 'remote-media:';
  static const String _remoteFolderPrefix = 'remote-media-folder:';
  static const String _smartFolderPrefix = 'smart-folder:';

  /// 远程节点智能文件夹 ID 前缀，格式：smart-folder:remote:[nodeId]:[原始sfId]
  static const String _remoteSmartFolderPrefix = 'smart-folder:remote:';
  static const String _smartFoldersPrefsKey = 'media_library_smart_folders'; // kept for migration
  static const String _smartFolderFileName = 'smart_folders_data.json';
  static const String _collectionOrderPrefsKeyPrefix = 'media_col_order_';
  static const String _favoritesPrefsKey = 'media_library_favorites';

  final NodeSettingsService nodeSettingsService = getIt<NodeSettingsService>();
  final MediaPrefsService mediaPrefs = getIt<MediaPrefsService>();
  final Loggers _logger = Loggers(name: '媒体库');

  final folders = <media_api.MediaFolder>[].obs;
  final remoteFolders = <media_api.MediaFolder>[].obs;
  final collections = <media_api.MediaCollection>[].obs;
  final remoteCollections = <media_api.MediaCollection>[].obs;
  final currentItems = <media_api.MediaItem>[].obs;
  final selectedIds = <String>{}.obs;
  final isSelecting = false.obs;
  final isScanning = false.obs;
  final scanStatusText = ''.obs;
  final isLoadingItems = false.obs;

  /// 远程集合加载进度（0.0~1.0），null 表示未开始或无进度信息可用。
  final itemLoadProgress = Rxn<double>();

  /// 远程节点数据是否正在后台异步加载中。
  final isLoadingRemote = false.obs;
  final currentFolderId = RxnString();
  final currentCollectionId = RxnString();
  final savedScrollOffset = 0.0.obs;

  /// Emits a non-null value whenever the screen should jump its scroll controller
  /// to the given offset. The screen resets this to null after consuming it.
  final scrollRestoreTarget = Rxn<double>();

  /// 最后预览的资源 ID（从 Viewer 返回后高亮展示并滚动到该位置）。
  final lastViewedItemId = RxnString();

  /// Per-browse-level scroll offset memory: key = folderId (null = root)
  final _browseScrollOffsets = <String?, double>{};

  /// Saves the browse scroll offset when entering a collection so it can be
  /// restored when exiting, independent of collection scroll changes.
  double _savedBrowseScrollOffset = 0.0;

  final smartFolders = <SmartFolder>[].obs;

  /// 各远程节点的智能文件夹列表，key = nodeId，value = 重命名 ID 后的 SmartFolder 列表。
  final _remoteSmartFolders = <String, List<SmartFolder>>{}.obs;

  /// 增量版本触发重新排序后的响应式重建。
  final collectionOrderVersion = 0.obs;
  final _collectionOrders = <String, List<String>>{};

  /// 收藏的集合 ID 集合。
  final favoriteCollectionIds = <String>{}.obs;

  /// 是否仅显示收藏集合（仅在浏览层生效）。
  final showFavoritesOnly = false.obs;

  /// 是否启用瀑布流布局（详情页网格布局）。
  final useMasonryGrid = true.obs;

  /// 是否显示媒体 tile 上的叠加层（类型标签 + 标题栏）。
  final showMediaOverlay = true.obs;

  /// collectionId → 该集合内所有 MediaItem.fileSize 的总和（懒计算）。
  final _collectionSizes = <String, BigInt>{};

  /// collectionId → 该集合内所有媒体文件路径列表（供智能文件夹文件名匹配使用，懒加载）。
  final _collectionItemPaths = <String, List<String>>{};

  /// 视频封面异步生成版本计数器（读取即注册响应式依赖）。
  final _asyncCoverVersion = 0.obs;

  /// collectionId → 缩略图路径（仅含成功生成的条目）。
  final _collectionVideoThumbnails = <String, String>{};

  /// 用于集合封面生成的串行队列（并发=2，防止 CPU 爆满）。
  final _coverQueue = VideoThumbQueue(concurrency: 2);

  /// 用于 scrub 帧提取的串行队列（并发=2）。
  final _scrubQueue = VideoThumbQueue(concurrency: 2);

  /// 当前文件夹对应的封面任务 key 列表（退出文件夹时取消）。
  final _currentFolderCoverKeys = <String>{};

  /// videoPath → scrub 帧路径列表的异步缓存（仅含非空结果）。
  final _videoFrameCache = <String, Future<List<String>>>{};

  /// videoPath → 已完成的帧结果（同步可读，供 getCollectionVideoFrameAtFraction 使用）。
  final _videoFrameResults = <String, List<String>>{};

  /// filePath → 音频封面缩略图路径的异步缓存。
  final _audioCoverCache = <String, Future<String?>>{};

  final remoteCollectionNodeId = <String, String>{}.obs;
  final remoteCollectionNodeName = <String, String>{}.obs;
  final remoteCollectionRawId = <String, String>{}.obs;
  final remoteFolderNodeId = <String, String>{}.obs;
  final remoteFolderNodeName = <String, String>{}.obs;
  final remoteFolderRawId = <String, String>{}.obs;

  /// 集合内资源列表的排序方式。
  final itemSortOrder = MediaItemSortOrder.nameAsc.obs;

  /// 浏览视图中集合列表的排序方式。
  final collectionSortOrder = CollectionSortOrder.dateUpdated.obs;

  Worker? _nodeMutationWorker;
  Future<void>? _refreshAllFuture;

  /// 集合文件夹自动扫描定时器（每 30 秒后台轮询）。
  Timer? _folderWatchTimer;

  /// 缩略图生成后触发缓存清理的防抖定时器（1 分钟后执行）。
  Timer? _trimCacheTimer;

  /// 上次扫描时各集合的 item 数量快照，用于判断是否有新增。
  final _collectionItemCountSnapshot = <String, int>{};

  @override
  Future<void> onInitAsync() async {
    _logger.info('[媒体库] onInitAsync: isInitialized=$isInitialized');
    // 初始化媒体偏好设置，并将并发量同步到队列
    await mediaPrefs.init();
    _coverQueue.concurrency = mediaPrefs.concurrency.value;
    _scrubQueue.concurrency = mediaPrefs.concurrency.value;
    // 监听并发量变化，动态更新队列并发限制
    ever(mediaPrefs.concurrency, (v) {
      _coverQueue.concurrency = v;
      _scrubQueue.concurrency = v;
    });

    // 缩略图生成完成后，防抖 1 分钟触发一次缓存大小检查
    void scheduleTrimCache() {
      _trimCacheTimer?.cancel();
      _trimCacheTimer = Timer(const Duration(minutes: 1), () {
        mediaPrefs.trimCacheToLimit();
      });
    }

    _coverQueue.onTaskComplete = scheduleTrimCache;
    _scrubQueue.onTaskComplete = scheduleTrimCache;

    // 无论是否已初始化都重建 worker（onClose 后 worker 会被置 null）
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) async {
      await refreshAll();
    });
    if (isInitialized) {
      // 永久 ViewModel 再次进入页面时：刷新数据 + 重新加载智能文件夹（磁盘上的数据描和内存始终保持同步）
      _logger.info('[媒体库] onInitAsync: 已初始化，重新加载智能文件夹 + 执行数据刷新');
      await _loadSmartFolders();
      await refreshAll();
      return;
    }
    await super.onInitAsync();
    // nodeSettingsService 在 main() 中已 await 初始化，此处为兜底
    if (!nodeSettingsService.isInitialized) {
      _logger.info('[媒体库] onInitAsync: nodeSettingsService 尚未初始化，等待...');
      await nodeSettingsService.init();
    }
    await _loadSmartFolders();
    await _loadCollectionOrders();
    await _loadFavorites();
    _logger.info('[媒体库] onInitAsync: 开始 refreshAll');
    await refreshAll();
    _logger.info(
      '[媒体库] onInitAsync: refreshAll 完成，collections=${collections.length}，folders=${folders.length}',
    );
    // 启动集合文件夹自动扫描定时器（每 30 秒轮询）
    _folderWatchTimer?.cancel();
    _folderWatchTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollCollectionFolders(),
    );
  }

  @override
  void onClose() {
    _nodeMutationWorker?.dispose();
    _nodeMutationWorker = null;
    _folderWatchTimer?.cancel();
    _folderWatchTimer = null;
    _trimCacheTimer?.cancel();
    _trimCacheTimer = null;
    super.onClose();
  }

  List<media_api.MediaFolder> get mergedFolders {
    final items = <media_api.MediaFolder>[...folders, ...remoteFolders];
    items.sort((left, right) {
      final orderCompare = left.order.compareTo(right.order);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return items;
  }

  List<media_api.MediaCollection> get mergedCollections {
    final items = <media_api.MediaCollection>[...collections, ...remoteCollections];
    items.sort((left, right) {
      final cmp = right.updatedAt.compareTo(left.updatedAt);
      if (cmp != 0) {
        return cmp;
      }
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return items;
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

  bool isSmartFolder(String id) => id.startsWith(_smartFolderPrefix);

  /// 是否是远程节点的智能文件夹（ID 格式：smart-folder:remote:[nodeId]:[rawId]）。
  bool isRemoteSmartFolder(String id) => id.startsWith(_remoteSmartFolderPrefix);

  /// 从远程智能文件夹 ID 中提取 nodeId。
  String? remoteSmartFolderNodeId(String id) {
    if (!isRemoteSmartFolder(id)) return null;
    // smart-folder:remote:<nodeId>:<rawId>
    final suffix = id.substring(_remoteSmartFolderPrefix.length);
    final colon = suffix.indexOf(':');
    return colon == -1 ? suffix : suffix.substring(0, colon);
  }

  /// 本地 + 所有远程节点的智能文件夹合并列表（响应式，依赖 _remoteSmartFolders 的变化）。
  List<SmartFolder> get mergedSmartFolders {
    // 读取 length 以向 GetX 注册响应式依赖，避免访问受保护的 .value
    _remoteSmartFolders.length;
    return [...smartFolders, for (final list in _remoteSmartFolders.values) ...list];
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
    if (fid != null && isSmartFolder(fid)) return null;
    return fid;
  }

  media_api.MediaCollection? get currentCollection {
    final collectionId = currentCollectionId.value;
    if (collectionId == null) {
      return null;
    }
    return mergedCollections.firstWhereOrNull((collection) => collection.id == collectionId);
  }

  String get currentCollectionTitle => currentCollection?.title ?? '';

  String get currentBrowseTitle => currentSmartFolder?.name ?? currentFolder?.name ?? '媒体库';

  List<media_api.MediaFolder> get currentFolderTrail {
    // Smart folders are always root-level virtual folders – no breadcrumb sub-trail needed
    if (currentSmartFolder != null) return [];
    final trail = <media_api.MediaFolder>[];
    var cursor = currentFolder;
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
    return mergedFolders.where((folder) => folder.parentId == folderId).toList(growable: false);
  }

  /// 判断集合是否匹配智能文件夹。
  /// - 远程集合 或 远程智能文件夹：忽略文件夹范围过滤，仅对标题和路径做正则匹配。
  /// - 本地集合 + 本地智能文件夹：执行完整的 matchesCollection 逻辑。
  bool collectionMatchesSmartFolder(SmartFolder sf, media_api.MediaCollection c) {
    final regexOnly = isRemoteCollection(c.id) || isRemoteSmartFolder(sf.id);
    if (regexOnly) {
      // 远程场景：跳过文件夹范围检查，仅对标题和路径做正则匹配
      if (sf.regexPattern.isEmpty) return true;
      try {
        final re = RegExp(sf.regexPattern, caseSensitive: false, unicode: true);
        return re.hasMatch(c.title) || re.hasMatch(c.folderPath);
      } catch (_) {
        return true;
      }
    }
    // 本地集合 + 本地智能文件夹：完整匹配（包含文件夹范围 + 文件名模式）
    if (!sf.matchesCollection(c)) return false;
    if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
      final paths = _collectionItemPaths[c.id] ?? const [];
      return sf.matchesFileNames(paths);
    }
    return true;
  }

  List<media_api.MediaCollection> get currentCollections {
    final folderId = currentFolderId.value;
    // Read version to register as reactive dependency so Obx rebuilds on reorder
    collectionOrderVersion.value;
    // Read sort order to register reactive dependency
    collectionSortOrder.value;
    // Read favorites to register dependency
    final favOnly = showFavoritesOnly.value;
    final favIds = favoriteCollectionIds.toSet();
    // Smart folder: 按智能文件夹规则过滤集合（远程集合忽略文件夹范围）
    if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      if (sf == null) return [];
      var filtered = mergedCollections
          .where((c) => collectionMatchesSmartFolder(sf, c))
          .toList(growable: true);
      if (favOnly) filtered = filtered.where((c) => favIds.contains(c.id)).toList();
      return _applySortOrder(filtered, folderId);
    }
    var filtered = mergedCollections
        .where((collection) => collection.folderId == folderId)
        .toList(growable: true);
    if (favOnly) filtered = filtered.where((c) => favIds.contains(c.id)).toList();
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
        _logger.info(
          '_applySortOrder: combinedSort orderKey=$orderKey applying ${customOrder.length}-item custom order',
        );
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
        _logger.info(
          '_applySortOrder: combinedSort orderKey=$orderKey NO custom order, using createdAt',
        );
      }
      return result;
    }
    if (sort != CollectionSortOrder.dateUpdated) {
      final result = [...list];
      switch (sort) {
        case CollectionSortOrder.nameAsc:
          result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        case CollectionSortOrder.nameDesc:
          result.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
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
    _logger.info('_applySortOrder: dateUpdated orderKey=$orderKey sorted by updatedAt desc');
    return result;
  }

  List<MediaLibraryItem> get visibleItems {
    // Smart folders (local + remote) are only shown at root level (currentFolderId == null)
    final sfItems = (currentFolderId.value == null)
        ? mergedSmartFolders.map(MediaLibrarySmartFolderItem.new).toList()
        : <MediaLibrarySmartFolderItem>[];
    return <MediaLibraryItem>[
      ...currentChildFolders.map(MediaLibraryFolderItem.new),
      ...sfItems,
      ...currentCollections.map(MediaLibraryCollectionItem.new),
    ];
  }

  bool get isInDetail => currentCollectionId.value != null;

  /// \u5f53\u524d\u96c6\u5408\u5185\u8d44\u6e90\u6309 [itemSortOrder] \u6392\u5e8f\u540e\u7684\u5217\u8868\uff08\u54cd\u5e94\u5f0f\uff09\u3002
  List<media_api.MediaItem> get sortedCurrentItems {
    // \u8bfb\u53d6 itemSortOrder.value \u4ee5\u6ce8\u518c\u54cd\u5e94\u5f0f\u4f9d\u8d56
    final order = itemSortOrder.value;
    final items = [...currentItems];
    switch (order) {
      case MediaItemSortOrder.nameAsc:
        items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case MediaItemSortOrder.nameDesc:
        items.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case MediaItemSortOrder.sizeDesc:
        items.sort((a, b) => b.fileSize.compareTo(a.fileSize));
      case MediaItemSortOrder.sizeAsc:
        items.sort((a, b) => a.fileSize.compareTo(b.fileSize));
      case MediaItemSortOrder.timeDesc:
        items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      case MediaItemSortOrder.timeAsc:
        items.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
    }
    return items;
  }

  /// \u5728\u8d44\u6e90\u7ba1\u7406\u5668\u4e2d\u663e\u793a\u8be5\u6587\u4ef6\u6240\u5728\u6587\u4ef6\u5939\u3002
  Future<void> openItemInFolder(media_api.MediaItem item) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', item.filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', item.filePath]);
      } else {
        await Process.run('xdg-open', [File(item.filePath).parent.path]);
      }
    } catch (e) {
      showSnack('\u9519\u8bef', '\u6253\u5f00\u6587\u4ef6\u5939\u5931\u8d25: $e');
    }
  }

  /// \u5220\u9664\u7269\u7406\u6587\u4ef6\u5e76\u91cd\u65b0\u626b\u63cf\u5f53\u524d\u96c6\u5408\u6e05\u9664 DB \u4e2d\u7684\u65e7\u8bb0\u5f55\u3002
  Future<void> deleteItemFile(media_api.MediaItem item) async {
    final collection = currentCollection;
    try {
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();
    } catch (e) {
      showSnack('\u9519\u8bef', '\u5220\u9664\u6587\u4ef6\u5931\u8d25: $e');
      return;
    }
    // \u91cd\u65b0\u5bfc\u5165\u96c6\u5408\u6587\u4ef6\u5939\u4ee5\u4e0e DB \u540c\u6b65
    if (collection != null && !isRemoteCollection(collection.id)) {
      try {
        await media_api.importMediaFolder(folderPath: collection.folderPath);
        await loadCollections();
      } catch (_) {}
    }
    await loadCurrentCollectionItems();
    showSnack('\u6210\u529f', '\u6587\u4ef6\u5df2\u5220\u9664');
  }

  /// 删除远程节点上的媒体文件（保留集合记录，仅删除节点本地磁盘上的物理文件）。
  Future<void> deleteRemoteItemLocalFile(media_api.MediaItem item) async {
    final collectionId = currentCollectionId.value ?? item.collectionId;
    final nodeId = getRemoteNodeId(collectionId);
    final rawCollectionId = getRemoteRawCollectionId(collectionId);
    if (nodeId == null || rawCollectionId == null) {
      showSnack('错误', '找不到对应的远程节点信息');
      return;
    }
    try {
      await nodeSettingsService.callNodeAction(
        nodeId: nodeId,
        action: 'delete_media_item_local_file',
        params: {'item_id': item.id, 'collection_id': rawCollectionId},
      );
      await loadCurrentCollectionItems();
      showSnack('成功', '节点本地文件已删除');
    } catch (e) {
      showSnack('错误', '删除节点文件失败: $e');
    }
  }

  bool isRemoteCollection(String collectionId) => remoteCollectionNodeId.containsKey(collectionId);

  bool isRemoteFolder(String folderId) => remoteFolderNodeId.containsKey(folderId);

  String? getRemoteNodeId(String collectionId) => remoteCollectionNodeId[collectionId];

  String? getRemoteNodeName(String collectionId) => remoteCollectionNodeName[collectionId];

  String? getRemoteRawCollectionId(String collectionId) => remoteCollectionRawId[collectionId];

  String? getRemoteFolderNodeId(String folderId) => remoteFolderNodeId[folderId];

  String? getRemoteFolderNodeName(String folderId) => remoteFolderNodeName[folderId];

  String? getRemoteRawFolderId(String folderId) => remoteFolderRawId[folderId];

  /// [isCover] = true 时使用「远程封面清晰度」（列表缩略图），false 时用「远程图片清晰度」（预览全图）。
  String? buildMediaSource(media_api.MediaItem item, {String? collectionId, bool isCover = false}) {
    final targetCollectionId = collectionId ?? currentCollectionId.value;
    if (targetCollectionId == null) {
      return item.filePath;
    }
    if (!isRemoteCollection(targetCollectionId)) {
      return item.filePath;
    }
    final nodeId = getRemoteNodeId(targetCollectionId);
    if (nodeId == null) {
      return null;
    }
    if (isCover) {
      final width = mediaPrefs.remoteCoverWidth.value;
      return nodeSettingsService.buildNodeMediaUrl(
        nodeId: nodeId,
        filePath: item.filePath,
        thumbnailWidth: width > 0 ? width : null,
        isCover: true,
      );
    }
    final width = mediaPrefs.remoteImageWidth.value;
    return nodeSettingsService.buildNodeMediaUrl(
      nodeId: nodeId,
      filePath: item.filePath,
      thumbnailWidth: width > 0 ? width : null,
    );
  }

  String? buildCollectionCoverSource(media_api.MediaCollection collection) {
    // 读取异步封面版本，在 Obx 上下文中注册响应式依赖
    _asyncCoverVersion.value;
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    if (isRemoteCollection(collection.id)) {
      // 远程集合：视频/音频封面路径均通过节点 URL 返回（服务端 ensureCoverThumbnail 提取帧/封面）
      final nodeId = getRemoteNodeId(collection.id);
      if (nodeId == null) return null;
      // 应用远程封面清晰度设置，节省上行带宽；isCover=true 使服务端用对应保护策略
      final width = mediaPrefs.remoteCoverWidth.value;
      return nodeSettingsService.buildNodeMediaUrl(
        nodeId: nodeId,
        filePath: coverPath,
        thumbnailWidth: width > 0 ? width : null,
        isCover: true,
      );
    }
    // 本地视频封面 — 异步生成缩略图
    if (_isVideoPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!_coverQueue.contains(collection.id)) {
        _generateCollectionVideoThumbnailAsync(collection.id, coverPath);
      }
      return null;
    }
    // 本地音频封面 — 异步提取嵌入专辑封面
    if (_isAudioPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!_coverQueue.contains(collection.id)) {
        _generateCollectionAudioCoverAsync(collection.id, coverPath);
      }
      return null;
    }
    return coverPath;
  }

  static const _kVideoExtensions = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'flv',
    'm4v',
    'wmv',
    '3gp',
    'ts',
    'm2ts',
    'mts',
  };

  static bool _isVideoPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _kVideoExtensions.contains(ext);
  }

  static const _kAudioExtensions = {
    'mp3',
    'flac',
    'aac',
    'm4a',
    'ogg',
    'opus',
    'wav',
    'wma',
    'ape',
    'aiff',
    'alac',
  };

  static bool _isAudioPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _kAudioExtensions.contains(ext);
  }

  void _generateCollectionVideoThumbnailAsync(String collectionId, String videoPath) {
    _logger.info('[VideoThumb] 入队封面: collectionId=$collectionId');
    _currentFolderCoverKeys.add(collectionId);
    _coverQueue.enqueue(collectionId, () async {
      _currentFolderCoverKeys.remove(collectionId);
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) {
          _logger.info('[VideoThumb] 帧为空，不缓存: collectionId=$collectionId');
          return;
        }
        final thumb = frames[frames.length ~/ 2];
        _logger.info('[VideoThumb] 封面生成成功: collectionId=$collectionId');
        _collectionVideoThumbnails[collectionId] = thumb;
        _asyncCoverVersion.value++;
      } catch (e) {
        _logger.error('[VideoThumb] 封面生成失败: collectionId=$collectionId err=$e');
      }
    });
  }

  void _generateCollectionAudioCoverAsync(String collectionId, String audioPath) {
    _logger.info('[AudioCover] 入队集合封面: collectionId=$collectionId');
    _currentFolderCoverKeys.add(collectionId);
    _coverQueue.enqueue(collectionId, () async {
      _currentFolderCoverKeys.remove(collectionId);
      try {
        final coverPath = await getAudioCoverSource(audioPath);
        if (coverPath == null || coverPath.isEmpty) {
          _logger.info('[AudioCover] 无嵌入封面: collectionId=$collectionId');
          return;
        }
        _logger.info('[AudioCover] 封面提取成功: collectionId=$collectionId');
        _collectionVideoThumbnails[collectionId] = coverPath;
        _asyncCoverVersion.value++;
      } catch (e) {
        _logger.error('[AudioCover] 封面提取失败: collectionId=$collectionId err=$e');
      }
    });
  }

  String? buildFolderCoverSource(media_api.MediaFolder folder) {
    // 注册响应式依赖：集合排序变更时同步更新文件夹封面
    collectionOrderVersion.value;
    final collection = _findFirstCollectionForFolder(folder.id);
    if (collection == null) {
      return null;
    }
    return buildCollectionCoverSource(collection);
  }

  String? buildSmartFolderCoverSource(SmartFolder sf) {
    // 订阅排序版本：集合拖拽重排后封面随之更新
    collectionOrderVersion.value;
    // 过滤后应用自定义排序（与 currentCollections 一致），保证封面反映用户拖拽位置
    final filtered = mergedCollections
        .where((c) => collectionMatchesSmartFolder(sf, c))
        .toList(growable: false);
    final sorted = _applySortOrder(List.of(filtered), sf.id);
    if (sorted.isEmpty) return null;
    return buildCollectionCoverSource(sorted.first);
  }

  /// 返回最多 [_kHoverScrubFrames] 个均匀采样的封面路径，用于集合卡片悬停预览。
  /// - 图片：直接返回文件路径
  /// - 视频：若已有缩略图则返回缩略图路径，否则返回 null 占位（稍后异步触发生成）
  /// - 远程集合：返回空
  static const int _kHoverScrubFrames = 20;
  final _hoverSourcesCache = <String, List<String?>>{};

  /// collectionId → 集合内按均匀采样的视频路径列表（用于实时取帧）。
  final _hoverVideoPathsCache = <String, List<String>>{};

  List<String?> buildCollectionHoverSources(media_api.MediaCollection collection) {
    if (isRemoteCollection(collection.id)) return const [];
    final cached = _hoverSourcesCache[collection.id];
    if (cached != null) return cached;
    try {
      final items = media_api.getMediaCollectionItems(collectionId: collection.id);
      if (items.isEmpty) return _hoverSourcesCache[collection.id] = const [];
      final n = items.length;
      final count = n.clamp(1, _kHoverScrubFrames);
      final result = <String?>[];
      final videoPaths = <String>[];
      for (int i = 0; i < count; i++) {
        final idx = ((i / (count - 1).clamp(1, count - 1)) * (n - 1)).round().clamp(0, n - 1);
        final p = items[idx].filePath;
        if (_isVideoPath(p)) {
          // 视频：使用已有缩略图或 null 占位；后台触发生成
          final thumb = _collectionVideoThumbnails[collection.id];
          result.add(thumb);
          videoPaths.add(p);
          final hoverKey = 'hover:${collection.id}:$i';
          if (thumb == null && !_coverQueue.contains(hoverKey)) {
            _generateHoverVideoThumbnailAsync(collection.id, p, i, count);
          }
        } else {
          result.add(p);
        }
      }
      if (videoPaths.isNotEmpty) _hoverVideoPathsCache[collection.id] = videoPaths;
      _hoverSourcesCache[collection.id] = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// 后台为集合 hover 预览中的指定视频帧生成缩略图，完成后触发 UI 刷新。
  void _generateHoverVideoThumbnailAsync(
    String collectionId,
    String videoPath,
    int slotIdx,
    int totalSlots,
  ) {
    final hoverKey = 'hover:$collectionId:$slotIdx';
    _coverQueue.enqueue(hoverKey, () async {
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) return;
        final frameIdx = totalSlots == 1
            ? 0
            : ((slotIdx / (totalSlots - 1)) * (frames.length - 1)).round().clamp(
                0,
                frames.length - 1,
              );
        final thumb = frames[frameIdx];
        final sources = _hoverSourcesCache[collectionId];
        if (sources != null && slotIdx < sources.length) {
          sources[slotIdx] = thumb;
        }
        _asyncCoverVersion.value++;
      } catch (e) {
        _logger.error('[VideoThumb] hover 封面生成失败: collectionId=$collectionId slotIdx=$slotIdx err=$e');
      }
    });
  }

  /// 实时取帧：根据鼠标在卡片上的水平比例 [fraction]∈[0,1]，
  /// 利用该集合内视频的 scrub 帧缓存按比例返回路径。
  /// 若缓存未就绪返回 null（调用方显示 coverSource 即可）。
  String? getCollectionVideoFrameAtFraction(String collectionId, double fraction) {
    final videoPaths = _hoverVideoPathsCache[collectionId];
    if (videoPaths == null || videoPaths.isEmpty) return null;
    final slotFraction = fraction.clamp(0.0, 1.0);
    final slotIdx = videoPaths.length == 1
        ? 0
        : (slotFraction * (videoPaths.length - 1)).round().clamp(0, videoPaths.length - 1);
    final videoPath = videoPaths[slotIdx];
    final frames = _videoFrameResults[videoPath];
    if (frames == null || frames.isEmpty) return null;
    final frameIdx = frames.length == 1
        ? 0
        : (slotFraction * (frames.length - 1)).round().clamp(0, frames.length - 1);
    return frames[frameIdx];
  }

  /// 将集合内视频的 scrub 帧任务提到 [_scrubQueue] 队首（高优先级预取）。
  /// 供卡片 hover 3s 后触发实时预览使用。
  void prefetchCollectionVideoFrames(String collectionId) {
    final videoPaths = _hoverVideoPathsCache[collectionId];
    if (videoPaths == null) return;
    for (final vp in videoPaths) {
      _enqueueOrPrioritizeScrub(vp, prioritize: true);
    }
  }

  /// 内部：将 [videoPath] 的 scrub 帧抽取任务入队（[prioritize]=true 则插队首）。
  /// 结果写入 [_videoFrameCache]。
  void _enqueueOrPrioritizeScrub(String videoPath, {bool prioritize = false}) {
    if (_videoFrameCache.containsKey(videoPath)) {
      if (prioritize) _scrubQueue.prioritize(videoPath, () async {});
      return;
    }
    final completer = Completer<List<String>>();
    _videoFrameCache[videoPath] = completer.future;

    Future<void> work() async {
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) {
          _videoFrameCache.remove(videoPath);
          _videoFrameResults.remove(videoPath);
          completer.complete(const []);
        } else {
          _videoFrameResults[videoPath] = frames;
          completer.complete(frames);
          _asyncCoverVersion.value++;
        }
      } catch (e) {
        _videoFrameCache.remove(videoPath);
        _videoFrameResults.remove(videoPath);
        completer.complete(const []);
        _logger.error('[VideoThumb] scrub 帧失败: $videoPath err=$e');
      }
    }

    if (prioritize) {
      _scrubQueue.prioritize(videoPath, work);
    } else {
      _scrubQueue.enqueue(videoPath, work);
    }
  }

  int collectionCountInFolder(String folderId) {
    return mergedCollections.where((collection) => collection.folderId == folderId).length;
  }

  List<media_api.MediaFolder> getAvailableFoldersForCollection(String collectionId) {
    if (isRemoteCollection(collectionId)) {
      final nodeId = getRemoteNodeId(collectionId);
      if (nodeId == null) {
        return const <media_api.MediaFolder>[];
      }
      final items = remoteFolders
          .where((folder) => remoteFolderNodeId[folder.id] == nodeId)
          .toList(growable: false);
      items.sort((left, right) => left.name.toLowerCase().compareTo(right.name.toLowerCase()));
      return items;
    }
    final items = folders.toList(growable: false);
    items.sort((left, right) => left.name.toLowerCase().compareTo(right.name.toLowerCase()));
    return items;
  }

  Future<void> refreshAll() async {
    final inFlight = _refreshAllFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _refreshAllInternal();
    _refreshAllFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshAllFuture, future)) {
        _refreshAllFuture = null;
      }
    }
  }

  Future<void> _refreshAllInternal() async {
    // Phase 1: 立即加载本地数据，使 UI 快速可用
    await loadFolders();
    await loadCollections();
    await loadCurrentCollectionItems();
    // Phase 2: 后台异步加载远程节点数据，不阻塞 UI
    _refreshRemoteBackground();
  }

  void _refreshRemoteBackground() {
    if (isLoadingRemote.value) return; // 已有后台任务在跑
    isLoadingRemote.value = true;
    refreshRemoteLibrary()
        .catchError((Object e) {
          _logger.error('[媒体库] 远程刷新失败: $e');
        })
        .whenComplete(() {
          isLoadingRemote.value = false;
        });
  }

  /// 后台轮询：检查本地集合文件夹是否有新增/删除的文件，有则静默增量更新。
  Future<void> _pollCollectionFolders() async {
    // 只处理本地集合，跳过远程
    final localCols = collections.toList(growable: false);
    _logger.info('_pollCollectionFolders: 开始轮询 ${localCols.length} 个本地集合');
    bool anyChanged = false;
    for (final col in localCols) {
      try {
        final prev = _collectionItemCountSnapshot[col.id] ?? col.itemCount;
        final dir = Directory(col.folderPath);
        if (!dir.existsSync()) {
          _logger.info('_pollCollectionFolders: 目录不存在，跳过: ${col.folderPath}');
          continue;
        }
        final exts = {
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'heic',
          'heif',
          'avif',
          'mp4',
          'mov',
          'avi',
          'mkv',
          'webm',
          'flv',
          'm4v',
          'wmv',
          'ts',
        };
        int count = 0;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            final ext = e.path.split('.').last.toLowerCase();
            if (exts.contains(ext)) count++;
          }
        }
        _collectionItemCountSnapshot[col.id] = count;
        _logger.info('_pollCollectionFolders: 集合[${col.title}] prev=$prev now=$count');
        if (count != prev) {
          _logger.info('_pollCollectionFolders: 检测到变化，触发增量扫描: ${col.title}');
          await media_api.importMediaFolder(folderPath: col.folderPath);
          anyChanged = true;
        }
      } catch (e) {
        _logger.info('_pollCollectionFolders: 集合 ${col.id} 检查异常: $e');
      }
    }
    if (anyChanged) {
      _logger.info('_pollCollectionFolders: 有变化，刷新集合列表');
      await loadCollections();
      if (currentCollectionId.value != null && !isRemoteCollection(currentCollectionId.value!)) {
        await loadCurrentCollectionItems();
      }
    }
  }

  Future<void> loadFolders() async {
    try {
      final raw = media_api.getAllMediaFolders();
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
      final rawCollections = media_api.getAllMediaCollections();
      _logger.info('[媒体库] loadCollections: 加载到 ${rawCollections.length} 个集合');
      collections.assignAll(rawCollections);
      _hoverSourcesCache.clear(); // 集合更新时清空封面缓存
      // 集合大小异步计算，避免阻塞 assignAll 后的 UI 渲染
      _computeCollectionSizesAsync(rawCollections);
      if (currentCollectionId.value != null && currentCollection == null) {
        exitCollection();
      }
    } catch (error) {
      _logger.error('[媒体库] loadCollections 异常: $error');
      showSnack('错误', '加载媒体集合失败: $error');
    }
  }

  void _computeCollectionSizesAsync(List<media_api.MediaCollection> cols) {
    Future.microtask(() {
      try {
        // 批量一次 FFI 获取所有本地集合大小与文件路径
        final statsList = media_api.getAllCollectionStats();
        for (final s in statsList) {
          _collectionSizes[s.collectionId] = s.totalSize;
          _collectionItemPaths[s.collectionId] = s.filePaths;
        }
      } catch (e) {
        _logger.error('[媒体库] _computeCollectionSizesAsync 批量统计失败，降级逐条查询: $e');
        // 降级：逐条查询（兜底）
        for (final col in cols) {
          if (!_collectionSizes.containsKey(col.id) || !_collectionItemPaths.containsKey(col.id)) {
            try {
              final items = media_api.getMediaCollectionItems(collectionId: col.id);
              _collectionSizes[col.id] = items.fold(BigInt.zero, (s, i) => s + i.fileSize);
              _collectionItemPaths[col.id] = items.map((i) => i.filePath).toList();
            } catch (_) {}
          }
        }
      }
    });
  }

  BigInt getCollectionTotalSize(String id) => _collectionSizes[id] ?? BigInt.zero;

  /// 返回指定集合内所有媒体文件路径（可能为空列表，异步缓存未就绪时）。
  List<String> collectionItemPaths(String id) => _collectionItemPaths[id] ?? const [];

  bool isFavorite(String id) => favoriteCollectionIds.contains(id);

  Future<void> toggleFavorite(String id) async {
    if (favoriteCollectionIds.contains(id)) {
      favoriteCollectionIds.remove(id);
    } else {
      favoriteCollectionIds.add(id);
    }
    await _saveFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_favoritesPrefsKey);
      if (json != null && json.isNotEmpty) {
        final list = (jsonDecode(json) as List<dynamic>).cast<String>();
        favoriteCollectionIds.assignAll(list.toSet());
      }
    } catch (e) {
      _logger.error('加载收藏列表失败: $e');
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesPrefsKey, jsonEncode(favoriteCollectionIds.toList()));
    } catch (e) {
      _logger.error('保存收藏列表失败: $e');
    }
  }

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
        final payloads = await nodeSettingsService.fetchNodeMediaCollectionItems(
          nodeId: nodeId,
          collectionId: rawId,
          onReceiveProgress: (count, total) {
            if (total > 0) itemLoadProgress.value = count / total;
          },
        );
        currentItems.assignAll(payloads.map((payload) => _buildRemoteItem(payload, collectionId)));
      } else {
        currentItems.assignAll(media_api.getMediaCollectionItems(collectionId: collectionId));
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
      _logger.info('[Scroll] enterCollection: no previousOffset, set savedScrollOffset=0');
    }

    await loadCurrentCollectionItems();
    _logger.info('[Scroll] enterCollection END: savedScrollOffset=${savedScrollOffset.value}');
  }

  void exitCollection() {
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
    exitSelection();
    _logger.info('[Scroll] exitCollection END');
  }

  void enterFolder(String folderId) {
    // 取消上一个文件夹中还未执行的封面任务
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    // Snapshot scroll position for the current browse level before navigating into folder
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    currentFolderId.value = folderId;
    // Debug: show what custom order (if any) will be applied for this folder
    final orderKey = folderId;
    final savedOrder = _collectionOrders[orderKey];
    _logger.info(
      'enterFolder: folderId=$folderId, savedOrder=${savedOrder == null ? "NONE" : savedOrder.join(",")}',
    );
    exitCollection();
    exitSelection();
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
    final parentId = currentFolder?.parentId;
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = parentId;
    exitCollection();
    exitSelection();
  }

  /// Navigate directly to the root browse level, restoring its saved scroll position.
  void exitToRoot() {
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = null;
    exitCollection();
    exitSelection();
  }

  void enterSelection(String firstId) {
    isSelecting.value = true;
    selectedIds.add(firstId);
  }

  void exitSelection() {
    isSelecting.value = false;
    selectedIds.clear();
  }

  void toggleSelection(String id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
      if (selectedIds.isEmpty) {
        exitSelection();
      }
      return;
    }
    selectedIds.add(id);
    if (selectedIds.isNotEmpty) {
      isSelecting.value = true;
    }
  }

  void toggleSelectAll() {
    final items = visibleItems;
    if (selectedIds.length == items.length) {
      selectedIds.clear();
      isSelecting.value = false;
      return;
    }
    selectedIds.assignAll(items.map((item) => item.id).toSet());
    isSelecting.value = items.isNotEmpty;
  }

  /// 返回视频的悬停悔放帧列表（异步缓存，重复调用直接返回）。
  /// 优先使用内置 ffmpeg 模块，其次系统 ffmpeg，否则返回空列表（可重试）。
  Future<List<String>> getVideoScrubFrames(String videoPath) async {
    // 若有缓存且非空则直接返回
    final cached = _videoFrameCache[videoPath];
    if (cached != null) {
      final result = await cached;
      if (result.isNotEmpty) return result;
      // 空结果（ffmpeg 当时失败）——移除缓存以便重试
      _videoFrameCache.remove(videoPath);
    }
    // 通过队列排队（普通优先级），结果写入 _videoFrameCache
    _enqueueOrPrioritizeScrub(videoPath);
    return await (_videoFrameCache[videoPath] ?? Future.value(const []));
  }

  /// 异步获取音频文件的封面缩略图路径（提取嵌入的专辑封面）。
  /// 结果缓存在 [_audioCoverCache] 中，相同路径只执行一次。
  Future<String?> getAudioCoverSource(String filePath) {
    return _audioCoverCache.putIfAbsent(filePath, () => _doGetAudioCover(filePath));
  }

  Future<String?> _doGetAudioCover(String filePath) async {
    final ffmpegExe = await RustFFmpeg.resolvePath();
    if (ffmpegExe == null) return null;
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      final dir = Directory('${appDir.path}${sep}SlimeWorks${sep}library${sep}media${sep}covers');
      await dir.create(recursive: true);
      // 稳定 key：路径哈希 + 固定宽度
      final key = filePath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
      final outPath = '${dir.path}${sep}audio_${key}_w300.jpg';
      final outFile = File(outPath);
      if (outFile.existsSync() && outFile.lengthSync() > 0) return outPath;
      // 调用 ffmpeg 提取嵌入封面（最常见格式：mp3/flac/m4a 的 0:v:0 流）
      await Process.run(ffmpegExe, [
        '-i',
        filePath,
        '-map',
        '0:v:0',
        '-vf',
        'scale=300:-1',
        '-frames:v',
        '1',
        '-q:v',
        '3',
        '-y',
        outPath,
      ]);
      return (outFile.existsSync() && outFile.lengthSync() > 0) ? outPath : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _doGetScrubFrames(String videoPath) async {
    _logger.info('[VideoThumb] _doGetScrubFrames: 解析 ffmpeg 路径...');
    final ffmpegExe = await RustFFmpeg.resolvePath();
    if (ffmpegExe == null) {
      _logger.info('[VideoThumb] _doGetScrubFrames: ffmpeg 不可用，返回空');
      return const <String>[];
    }
    _logger.info('[VideoThumb] _doGetScrubFrames: ffmpegExe=$ffmpegExe, 提取帧中...');
    return _doExtractScrubFrames(videoPath, ffmpegExe);
  }

  Future<List<String>> _doExtractScrubFrames(String videoPath, String ffmpegExe) async {
    final key = videoPath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    late Directory frameDir;
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      frameDir = Directory(
        '${appDir.path}${sep}library${sep}media${sep}thumbnails${sep}scrub$sep$key',
      );
      await frameDir.create(recursive: true);
      _logger.info('[VideoThumb] 帧目录: ${frameDir.path}');
    } catch (e) {
      _logger.error('[VideoThumb] 帧目录创建失败: $e');
      return const <String>[];
    }

    // ── 用 ffprobe 探测真实时长 ─────────────────────────────────────────
    double? probedDuration;
    try {
      final ffprobeExe = await RustFFmpeg.resolveProbe();
      if (ffprobeExe != null) {
        _logger.info('[VideoThumb] ffprobe: $ffprobeExe');
        final probe = await Process.run(ffprobeExe, [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          videoPath,
        ]);
        final parsed = double.tryParse((probe.stdout as String).trim());
        if (parsed != null && parsed > 0) {
          probedDuration = parsed;
          _logger.info('[VideoThumb] ffprobe 时长: ${probedDuration}s');
        } else {
          _logger.info(
            '[VideoThumb] ffprobe 返回无效时长 stdout="${probe.stdout}" stderr="${(probe.stderr as String).substring(0, (probe.stderr as String).length.clamp(0, 120))}"',
          );
        }
      } else {
        _logger.info('[VideoThumb] ffprobe 不可用，跳过时长探测');
      }
    } catch (e) {
      _logger.error('[VideoThumb] ffprobe 异常: $e');
    }

    // 若 ffprobe 失败则只取前几秒以防 seek 越界（短视频 EINVAL）
    final qualityLevel = mediaPrefs.currentLevel;
    final int frameCount;
    final double duration;
    if (probedDuration != null) {
      frameCount = qualityLevel.frameCount;
      duration = probedDuration;
    } else {
      frameCount = qualityLevel.frameCountFallback;
      duration = 4.0; // 保守值：只在前 4 秒内提取
      _logger.info('[VideoThumb] ffprobe 失败，降级为 $frameCount 帧 / ${duration}s');
    }

    final sep = Platform.pathSeparator;
    final paths = <String>[];
    int consecutiveFails = 0;
    for (int i = 0; i < frameCount; i++) {
      final outFile = File('${frameDir.path}${sep}frame_${i.toString().padLeft(2, '0')}.jpg');
      // 已存在且非空则直接复用
      if (outFile.existsSync() && outFile.lengthSync() > 0) {
        paths.add(outFile.path);
        consecutiveFails = 0;
        continue;
      }
      // 分布于 [0, duration*0.9]，避免最后一帧恰好越界
      final double t = frameCount == 1 ? 0.0 : (duration * 0.9 * i / (frameCount - 1));
      final int secs = t.toInt();
      final String seek =
          '${(secs ~/ 3600).toString().padLeft(2, '0')}'
          ':${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}'
          ':${(secs % 60).toString().padLeft(2, '0')}';
      try {
        // -ss 放在 -i 之前：输入快速定位（避免慢解码导致的 EINVAL）
        final result = await Process.run(ffmpegExe, [
          '-ss',
          seek,
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-vf',
          'scale=${qualityLevel.scaleWidth}:-2',
          '-q:v',
          '${qualityLevel.qv}',
          '-y',
          outFile.path,
        ]);
        if (result.exitCode == 0 && outFile.existsSync() && outFile.lengthSync() > 0) {
          paths.add(outFile.path);
          consecutiveFails = 0;
        } else {
          // 删除可能残留的空文件
          try {
            if (outFile.existsSync()) outFile.deleteSync();
          } catch (_) {}
          _logger.error('[VideoThumb] ffmpeg 帧$i 失败: exitCode=${result.exitCode} seek=$seek');
          consecutiveFails++;
          if (consecutiveFails >= 3) {
            _logger.info('[VideoThumb] 连续 3 帧失败，提前终止');
            break;
          }
        }
      } catch (e) {
        _logger.error('[VideoThumb] ffmpeg 帧$i 异常: $e');
        consecutiveFails++;
      }
    }
    _logger.info('[VideoThumb] 提取完成: ${paths.length}/$frameCount 帧成功');
    return paths;
  }

  List<NodeEndpoint> get enabledRemoteNodes => nodeSettingsService.enabledRemoteNodes;

  void showSnack(String title, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('$title：$message'), behavior: SnackBarBehavior.floating),
        );
    });
  }

  media_api.MediaCollection? _findFirstCollectionForFolder(
    String folderId, {
    Set<String>? visited,
  }) {
    final seen = visited ?? <String>{};
    if (!seen.add(folderId)) {
      return null;
    }

    // 使用 _applySortOrder 应用自定义排序，保证文件夹封面与用户拖拽顺序一致
    final directCollections = mergedCollections
        .where((collection) => collection.folderId == folderId)
        .toList(growable: false);
    final ordered = _applySortOrder(List.of(directCollections), folderId);
    if (ordered.isNotEmpty) {
      return ordered.first;
    }

    final children = mergedFolders.where((folder) => folder.parentId == folderId);
    for (final child in children) {
      final collection = _findFirstCollectionForFolder(child.id, visited: seen);
      if (collection != null) {
        return collection;
      }
    }
    return null;
  }

  String _buildRemoteCollectionId(String nodeId, String rawId) {
    return '$_remoteCollectionPrefix$nodeId:$rawId';
  }

  String _buildRemoteFolderId(String nodeId, String rawId) {
    return '$_remoteFolderPrefix$nodeId:$rawId';
  }

  String? _resolveRemoteTargetFolderId(String nodeId) {
    final folderId = effectiveFolderId;
    if (folderId == null || !isRemoteFolder(folderId)) {
      return null;
    }
    if (getRemoteFolderNodeId(folderId) != nodeId) {
      return null;
    }
    return getRemoteRawFolderId(folderId);
  }

  int _parseIntLike(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return int.tryParse(normalized) ?? num.tryParse(normalized)?.toInt() ?? 0;
  }

  int? _parseNullableIntLike(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'null') {
      return null;
    }
    return _parseIntLike(value);
  }

  BigInt _parseBigIntLike(Object? value) {
    if (value == null) {
      return BigInt.zero;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is num) {
      return BigInt.from(value.toInt());
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.tryParse(normalized) ?? BigInt.from(num.tryParse(normalized)?.toInt() ?? 0);
  }

  String? _stringOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'null') {
      return null;
    }
    return normalized;
  }
}
