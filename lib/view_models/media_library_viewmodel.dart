import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
  dateUpdated,
  nameAsc,
  nameDesc,
  countDesc,
  countAsc,
  sizeDesc,
  sizeAsc;

  String get label => switch (this) {
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
  static const String _smartFoldersPrefsKey = 'media_library_smart_folders'; // kept for migration
  static const String _smartFolderFileName = 'smart_folders_data.json';
  static const String _collectionOrderPrefsKeyPrefix = 'media_col_order_';
  static const String _favoritesPrefsKey = 'media_library_favorites';

  final NodeSettingsService nodeSettingsService = getIt<NodeSettingsService>();
  final MediaPrefsService mediaPrefs = getIt<MediaPrefsService>();
  final Loggers logger = Loggers(name: '媒体库');

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
  final currentFolderId = RxnString();
  final currentCollectionId = RxnString();
  final savedScrollOffset = 0.0.obs;

  /// Emits a non-null value whenever the screen should jump its scroll controller
  /// to the given offset. The screen resets this to null after consuming it.
  final scrollRestoreTarget = Rxn<double>();

  /// Per-browse-level scroll offset memory: key = folderId (null = root)
  final _browseScrollOffsets = <String?, double>{};

  final smartFolders = <SmartFolder>[].obs;

  /// 增量版本触发重新排序后的响应式重建。
  final collectionOrderVersion = 0.obs;
  final _collectionOrders = <String, List<String>>{};

  /// 收藏的集合 ID 集合。
  final favoriteCollectionIds = <String>{}.obs;

  /// 是否仅显示收藏集合（仅在浏览层生效）。
  final showFavoritesOnly = false.obs;

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

  @override
  Future<void> onInitAsync() async {
    debugPrint('[MediaLibrary] onInitAsync: isInitialized=$isInitialized');
    // 初始化媒体偏好设置，并将并发量同步到队列
    await mediaPrefs.init();
    _coverQueue.concurrency = mediaPrefs.concurrency.value;
    _scrubQueue.concurrency = mediaPrefs.concurrency.value;
    // 监听并发量变化，动态更新队列并发限制
    ever(mediaPrefs.concurrency, (v) {
      _coverQueue.concurrency = v;
      _scrubQueue.concurrency = v;
    });

    // 无论是否已初始化都重建 worker（onClose 后 worker 会被置 null）
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) async {
      await refreshAll();
    });
    if (isInitialized) {
      // 永久 ViewModel 再次进入页面时：刷新数据 + 重新加载智能文件夹（磁盘上的数据描和内存始终保持同步）
      debugPrint('[MediaLibrary] onInitAsync: 已初始化，重新加载智能文件夹 + 执行数据刷新');
      await _loadSmartFolders();
      await refreshAll();
      return;
    }
    await super.onInitAsync();
    // nodeSettingsService 在 main() 中已 await 初始化，此处为兜底
    if (!nodeSettingsService.isInitialized) {
      debugPrint('[MediaLibrary] onInitAsync: nodeSettingsService 尚未初始化，等待...');
      await nodeSettingsService.init();
    }
    await _loadSmartFolders();
    await _loadCollectionOrders();
    await _loadFavorites();
    debugPrint('[MediaLibrary] onInitAsync: 开始 refreshAll');
    await refreshAll();
    debugPrint(
      '[MediaLibrary] onInitAsync: refreshAll 完成，collections=${collections.length}，folders=${folders.length}',
    );
  }

  @override
  void onClose() {
    _nodeMutationWorker?.dispose();
    _nodeMutationWorker = null;
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

  SmartFolder? getSmartFolder(String id) => smartFolders.firstWhereOrNull((sf) => sf.id == id);

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

  List<media_api.MediaCollection> get currentCollections {
    final folderId = currentFolderId.value;
    // Read version to register as reactive dependency so Obx rebuilds on reorder
    collectionOrderVersion.value;
    // Read sort order to register reactive dependency
    collectionSortOrder.value;
    // Read favorites to register dependency
    final favOnly = showFavoritesOnly.value;
    final favIds = favoriteCollectionIds.toSet();
    // Smart folder: 按智能文件夹规则过滤集合
    if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      if (sf == null) return [];
      var filtered = mergedCollections.where((c) {
        if (!sf.matchesCollection(c)) return false;
        // 文件名匹配模式：额外检查集合内文件名缓存
        if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
          final paths = _collectionItemPaths[c.id] ?? const [];
          return sf.matchesFileNames(paths);
        }
        return true;
      }).toList(growable: true);
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
            (a, b) => (_collectionSizes[b.id] ?? BigInt.zero)
                .compareTo(_collectionSizes[a.id] ?? BigInt.zero),
          );
        case CollectionSortOrder.sizeAsc:
          result.sort(
            (a, b) => (_collectionSizes[a.id] ?? BigInt.zero)
                .compareTo(_collectionSizes[b.id] ?? BigInt.zero),
          );
        case CollectionSortOrder.dateUpdated:
          break;
      }
      return result;
    }
    // Default: apply custom drag order
    final customOrder = _collectionOrders[orderKey];
    if (customOrder == null || customOrder.isEmpty) return list;
    list.sort((a, b) {
      final ai = customOrder.indexOf(a.id);
      final bi = customOrder.indexOf(b.id);
      if (ai == -1 && bi == -1) return 0;
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return list;
  }

  List<MediaLibraryItem> get visibleItems {
    // Smart folders are only shown at root level (currentFolderId == null)
    final sfItems = (currentFolderId.value == null)
        ? smartFolders.map(MediaLibrarySmartFolderItem.new).toList()
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

  bool isRemoteCollection(String collectionId) => remoteCollectionNodeId.containsKey(collectionId);

  bool isRemoteFolder(String folderId) => remoteFolderNodeId.containsKey(folderId);

  String? getRemoteNodeId(String collectionId) => remoteCollectionNodeId[collectionId];

  String? getRemoteNodeName(String collectionId) => remoteCollectionNodeName[collectionId];

  String? getRemoteRawCollectionId(String collectionId) => remoteCollectionRawId[collectionId];

  String? getRemoteFolderNodeId(String folderId) => remoteFolderNodeId[folderId];

  String? getRemoteFolderNodeName(String folderId) => remoteFolderNodeName[folderId];

  String? getRemoteRawFolderId(String folderId) => remoteFolderRawId[folderId];

  String? buildMediaSource(media_api.MediaItem item, {String? collectionId}) {
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
    return nodeSettingsService.buildNodeMediaUrl(nodeId: nodeId, filePath: item.filePath);
  }

  String? buildCollectionCoverSource(media_api.MediaCollection collection) {
    // 读取异步封面版本，在 Obx 上下文中注册响应式依赖
    _asyncCoverVersion.value;
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    if (isRemoteCollection(collection.id)) {
      if (_isVideoPath(coverPath)) return null; // 远程视频路径不尝试读取
      final nodeId = getRemoteNodeId(collection.id);
      if (nodeId == null) return null;
      return nodeSettingsService.buildNodeMediaUrl(nodeId: nodeId, filePath: coverPath);
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

  void _generateCollectionVideoThumbnailAsync(String collectionId, String videoPath) {
    debugPrint('[VideoThumb] 入队封面: collectionId=$collectionId');
    _currentFolderCoverKeys.add(collectionId);
    _coverQueue.enqueue(collectionId, () async {
      _currentFolderCoverKeys.remove(collectionId);
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) {
          debugPrint('[VideoThumb] 帧为空，不缓存: collectionId=$collectionId');
          return;
        }
        final thumb = frames[frames.length ~/ 2];
        debugPrint('[VideoThumb] ✅ 封面生成成功: collectionId=$collectionId');
        _collectionVideoThumbnails[collectionId] = thumb;
        _asyncCoverVersion.value++;
      } catch (e) {
        debugPrint('[VideoThumb] ❌ 封面生成失败: collectionId=$collectionId err=$e');
      }
    });
  }

  String? buildFolderCoverSource(media_api.MediaFolder folder) {
    final collection = _findFirstCollectionForFolder(folder.id);
    if (collection == null) {
      return null;
    }
    return buildCollectionCoverSource(collection);
  }

  String? buildSmartFolderCoverSource(SmartFolder sf) {
    final firstMatch = mergedCollections.firstWhereOrNull((c) {
      if (!sf.matchesCollection(c)) return false;
      if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
        final paths = _collectionItemPaths[c.id] ?? const [];
        return sf.matchesFileNames(paths);
      }
      return true;
    });
    if (firstMatch == null) return null;
    return buildCollectionCoverSource(firstMatch);
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
            : ((slotIdx / (totalSlots - 1)) * (frames.length - 1))
                .round()
                .clamp(0, frames.length - 1);
        final thumb = frames[frameIdx];
        final sources = _hoverSourcesCache[collectionId];
        if (sources != null && slotIdx < sources.length) {
          sources[slotIdx] = thumb;
        }
        _asyncCoverVersion.value++;
      } catch (e) {
        debugPrint('[VideoThumb] hover 封面生成失败: collectionId=$collectionId slotIdx=$slotIdx err=$e');
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
    final cachedFramesFuture = _videoFrameCache[videoPath];
    if (cachedFramesFuture == null) return null;
    // 同步读取：Future 已完成则直接取值
    String? result;
    cachedFramesFuture.then((frames) {
      if (frames.isNotEmpty) {
        final frameIdx = frames.length == 1
            ? 0
            : (slotFraction * (frames.length - 1)).round().clamp(0, frames.length - 1);
        result = frames[frameIdx];
      }
    });
    return result;
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
      // 已有缓存 future，仅尝试提升队内优先级（若仍在排队）
      if (prioritize) _scrubQueue.prioritize(videoPath, () async {});
      return;
    }
    final completer = Completer<List<String>>();
    _videoFrameCache[videoPath] = completer.future;

    Future<void> work() async {
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) {
          _videoFrameCache.remove(videoPath); // 失败不缓存，允许重试
          completer.complete(const []);
        } else {
          completer.complete(frames);
          _asyncCoverVersion.value++;
        }
      } catch (e) {
        _videoFrameCache.remove(videoPath);
        completer.complete(const []);
        debugPrint('[VideoThumb] scrub 帧失败: $videoPath err=$e');
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
    await loadFolders();
    await loadCollections();
    await refreshRemoteLibrary();
    await loadCurrentCollectionItems();
  }

  Future<void> loadFolders() async {
    try {
      final raw = media_api.getAllMediaFolders();
      debugPrint('[MediaLibrary] loadFolders: 加载到 ${raw.length} 个文件夹');
      folders.assignAll(raw);
      // 仅当不在智能文件夹中时才自动退出：智能文件夹不在 mergedFolders 里，不应被误清除
      if (currentFolderId.value != null &&
          currentFolder == null &&
          !isSmartFolder(currentFolderId.value!)) {
        currentFolderId.value = null;
      }
    } catch (error) {
      debugPrint('[MediaLibrary] loadFolders 异常: $error');
      showSnack('错误', '加载媒体文件夹失败: $error');
    }
  }

  Future<void> loadCollections() async {
    try {
      final rawCollections = media_api.getAllMediaCollections();
      debugPrint('[MediaLibrary] loadCollections: 加载到 ${rawCollections.length} 个集合');
      collections.assignAll(rawCollections);
      _hoverSourcesCache.clear(); // 集合更新时清空封面缓存
      // 集合大小异步计算，避免阻塞 assignAll 后的 UI 渲染
      _computeCollectionSizesAsync(rawCollections);
      if (currentCollectionId.value != null && currentCollection == null) {
        exitCollection();
      }
    } catch (error) {
      debugPrint('[MediaLibrary] loadCollections 异常: $error');
      showSnack('错误', '加载媒体集合失败: $error');
    }
  }

  void _computeCollectionSizesAsync(List<media_api.MediaCollection> cols) {
    Future.microtask(() {
      for (final col in cols) {
        if (!_collectionSizes.containsKey(col.id) || !_collectionItemPaths.containsKey(col.id)) {
          try {
            final items = media_api.getMediaCollectionItems(collectionId: col.id);
            _collectionSizes[col.id] = items.fold(BigInt.zero, (s, i) => s + i.fileSize);
            _collectionItemPaths[col.id] = items.map((i) => i.filePath).toList();
          } catch (_) {}
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
      logger.e('加载收藏列表失败: $e');
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_favoritesPrefsKey, jsonEncode(favoriteCollectionIds.toList()));
    } catch (e) {
      logger.e('保存收藏列表失败: $e');
    }
  }

  Future<void> refreshRemoteLibrary() async {
    await _refreshRemoteFolders();
    await _refreshRemoteCollections();
    if (currentFolderId.value != null && currentFolder == null) {
      currentFolderId.value = null;
    }
  }

  Future<void> refreshRemoteCollections() async {
    await refreshRemoteLibrary();
  }

  Future<void> _refreshRemoteFolders() async {
    final remote = <media_api.MediaFolder>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};

    for (final node in nodeSettingsService.enabledRemoteNodes) {
      try {
        final payloads = await nodeSettingsService.fetchNodeMediaFolders(node);
        for (final payload in payloads) {
          final rawId = (payload['id'] ?? '').toString();
          if (rawId.isEmpty) {
            continue;
          }
          final syntheticId = _buildRemoteFolderId(node.id, rawId);
          remote.add(_buildRemoteFolder(payload, syntheticId, node.id));
          nodeIdMap[syntheticId] = node.id;
          nodeNameMap[syntheticId] = node.name;
          rawIdMap[syntheticId] = rawId;
        }
      } catch (error) {
        logger.log('刷新远程媒体文件夹失败: ${node.name} -> $error', name: '媒体库');
      }
    }

    remoteFolders.assignAll(remote);
    remoteFolderNodeId.assignAll(nodeIdMap);
    remoteFolderNodeName.assignAll(nodeNameMap);
    remoteFolderRawId.assignAll(rawIdMap);
  }

  Future<void> _refreshRemoteCollections() async {
    final remote = <media_api.MediaCollection>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};

    for (final node in nodeSettingsService.enabledRemoteNodes) {
      try {
        final payloads = await nodeSettingsService.fetchNodeMediaCollections(node);
        for (final payload in payloads) {
          final rawId = (payload['id'] ?? '').toString();
          if (rawId.isEmpty) {
            continue;
          }
          final syntheticId = _buildRemoteCollectionId(node.id, rawId);
          remote.add(_buildRemoteCollection(payload, syntheticId, node.id));
          nodeIdMap[syntheticId] = node.id;
          nodeNameMap[syntheticId] = node.name;
          rawIdMap[syntheticId] = rawId;
        }
      } catch (error) {
        logger.log('刷新远程媒体集合失败: ${node.name} -> $error', name: '媒体库');
      }
    }

    remoteCollections.assignAll(remote);
    remoteCollectionNodeId.assignAll(nodeIdMap);
    remoteCollectionNodeName.assignAll(nodeNameMap);
    remoteCollectionRawId.assignAll(rawIdMap);
  }

  media_api.MediaFolder _buildRemoteFolder(
    Map<String, dynamic> payload,
    String syntheticId,
    String nodeId,
  ) {
    final parentRaw = _stringOrNull(payload['parent_id']);
    return media_api.MediaFolder(
      id: syntheticId,
      name: (payload['name'] ?? '未命名文件夹').toString(),
      createdAt: _parseIntLike(payload['created_at']),
      order: _parseIntLike(payload['order']),
      parentId: parentRaw == null ? null : _buildRemoteFolderId(nodeId, parentRaw),
    );
  }

  media_api.MediaCollection _buildRemoteCollection(
    Map<String, dynamic> payload,
    String syntheticId,
    String nodeId,
  ) {
    final folderRaw = _stringOrNull(payload['folder_id']);
    return media_api.MediaCollection(
      id: syntheticId,
      title: (payload['title'] ?? '未命名集合').toString(),
      folderPath: (payload['folder_path'] ?? '').toString(),
      folderId: folderRaw == null ? null : _buildRemoteFolderId(nodeId, folderRaw),
      coverPath: _stringOrNull(payload['cover_path']),
      itemCount: _parseBigIntLike(payload['item_count']),
      createdAt: _parseIntLike(payload['created_at']),
      updatedAt: _parseIntLike(payload['updated_at']),
    );
  }

  media_api.MediaItem _buildRemoteItem(Map<String, dynamic> payload, String collectionId) {
    final durationMsRaw = payload['duration_ms'];
    final kindRaw = (payload['kind'] ?? 'image').toString().toLowerCase();
    return media_api.MediaItem(
      id: (payload['id'] ?? '').toString(),
      collectionId: collectionId,
      title: (payload['title'] ?? '未命名媒体').toString(),
      filePath: (payload['file_path'] ?? '').toString(),
      kind: kindRaw == 'video' ? media_api.MediaKind.video : media_api.MediaKind.image,
      fileSize: _parseBigIntLike(payload['file_size']),
      modifiedAt: _parseIntLike(payload['modified_at']),
      width: _parseNullableIntLike(payload['width']),
      height: _parseNullableIntLike(payload['height']),
      durationMs: durationMsRaw == null ? null : _parseBigIntLike(durationMsRaw),
      order: _parseIntLike(payload['order']),
    );
  }

  Future<void> loadCurrentCollectionItems() async {
    final collectionId = currentCollectionId.value;
    if (collectionId == null) {
      currentItems.clear();
      return;
    }

    isLoadingItems.value = true;
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
    }
  }

  Future<void> enterCollection(String collectionId) async {
    // Snapshot scroll position for the current browse level before entering detail
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    currentCollectionId.value = collectionId;
    exitSelection();
    await loadCurrentCollectionItems();
  }

  void exitCollection() {
    currentCollectionId.value = null;
    currentItems.clear();
    exitSelection();
    // Restore the saved browse-level scroll offset
    final saved = _browseScrollOffsets[currentFolderId.value] ?? 0.0;
    scrollRestoreTarget.value = saved;
  }

  void enterFolder(String folderId) {
    // 取消上一个文件夹中还未执行的封面任务
    _coverQueue.cancelGroup(_currentFolderCoverKeys);
    _currentFolderCoverKeys.clear();
    // Snapshot scroll position for the current browse level before navigating into folder
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    currentFolderId.value = folderId;
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

  Future<List<String>> _doGetScrubFrames(String videoPath) async {
    debugPrint('[VideoThumb] _doGetScrubFrames: 解析 ffmpeg 路径...');
    final ffmpegExe = await RustFFmpeg.resolvePath();
    if (ffmpegExe == null) {
      debugPrint('[VideoThumb] _doGetScrubFrames: ffmpeg 不可用，返回空');
      return const <String>[];
    }
    debugPrint('[VideoThumb] _doGetScrubFrames: ffmpegExe=$ffmpegExe, 提取帧中...');
    return _doExtractScrubFrames(videoPath, ffmpegExe);
  }

  Future<List<String>> _doExtractScrubFrames(String videoPath, String ffmpegExe) async {
    final key = videoPath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    late Directory frameDir;
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      frameDir = Directory('${appDir.path}${sep}thumbnails${sep}scrub$sep$key');
      await frameDir.create(recursive: true);
      debugPrint('[VideoThumb] 帧目录: ${frameDir.path}');
    } catch (e) {
      debugPrint('[VideoThumb] 帧目录创建失败: $e');
      return const <String>[];
    }

    // ── 用 ffprobe 探测真实时长 ─────────────────────────────────────────
    double? probedDuration;
    try {
      final ffprobeExe = await RustFFmpeg.resolveProbe();
      if (ffprobeExe != null) {
        debugPrint('[VideoThumb] ffprobe: $ffprobeExe');
        final probe = await Process.run(ffprobeExe, [
          '-v', 'error',
          '-show_entries', 'format=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          videoPath,
        ]);
        final parsed = double.tryParse((probe.stdout as String).trim());
        if (parsed != null && parsed > 0) {
          probedDuration = parsed;
          debugPrint('[VideoThumb] ffprobe 时长: ${probedDuration}s');
        } else {
          debugPrint('[VideoThumb] ffprobe 返回无效时长 stdout="${probe.stdout}" stderr="${(probe.stderr as String).substring(0, (probe.stderr as String).length.clamp(0, 120))}\"');
        }
      } else {
        debugPrint('[VideoThumb] ffprobe 不可用，跳过时长探测');
      }
    } catch (e) {
      debugPrint('[VideoThumb] ffprobe 异常: $e');
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
      debugPrint('[VideoThumb] ffprobe 失败，降级为 $frameCount 帧 / ${duration}s');
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
      final double t = frameCount == 1
          ? 0.0
          : (duration * 0.9 * i / (frameCount - 1));
      final int secs = t.toInt();
      final String seek =
          '${(secs ~/ 3600).toString().padLeft(2, '0')}'
          ':${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}'
          ':${(secs % 60).toString().padLeft(2, '0')}';
      try {
        // -ss 放在 -i 之前：输入快速定位（避免慢解码导致的 EINVAL）
        final result = await Process.run(ffmpegExe, [
          '-ss', seek,
          '-i', videoPath,
          '-vframes', '1',
          '-vf', 'scale=${qualityLevel.scaleWidth}:-2',
          '-q:v', '${qualityLevel.qv}',
          '-y',
          outFile.path,
        ]);
        if (result.exitCode == 0 && outFile.existsSync() && outFile.lengthSync() > 0) {
          paths.add(outFile.path);
          consecutiveFails = 0;
        } else {
          // 删除可能残留的空文件
          try { if (outFile.existsSync()) outFile.deleteSync(); } catch (_) {}
          debugPrint('[VideoThumb] ffmpeg 帧$i 失败: exitCode=${result.exitCode} seek=$seek');
          consecutiveFails++;
          if (consecutiveFails >= 3) {
            debugPrint('[VideoThumb] 连续 3 帧失败，提前终止');
            break;
          }
        }
      } catch (e) {
        debugPrint('[VideoThumb] ffmpeg 帧$i 异常: $e');
        consecutiveFails++;
      }
    }
    debugPrint('[VideoThumb] 提取完成: ${paths.length}/$frameCount 帧成功');
    return paths;
  }

  // ── Collection Order ─────────────────────────────────────────────────────

  Future<void> _loadCollectionOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_collectionOrderPrefsKeyPrefix)) continue;
        final orderKey = key.substring(_collectionOrderPrefsKeyPrefix.length);
        final json = prefs.getString(key);
        if (json != null) {
          try {
            _collectionOrders[orderKey] = (jsonDecode(json) as List).cast<String>();
          } catch (_) {}
        }
      }
    } catch (e) {
      logger.e('加载集合排序失败: $e');
    }
  }

  Future<void> _saveCollectionOrder(String orderKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_collectionOrderPrefsKeyPrefix$orderKey';
      final ids = _collectionOrders[orderKey];
      if (ids == null || ids.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(ids));
      }
    } catch (e) {
      logger.e('保存集合排序失败: $e');
    }
  }

  /// Reorders [fromId] to the position of [toId] within the current browse level.
  Future<void> reorderCollection(String fromId, String toId) async {
    final orderKey = currentFolderId.value ?? 'root';
    final cols = currentCollections;
    final ids = cols.map((c) => c.id).toList();
    final fromIdx = ids.indexOf(fromId);
    final toIdx = ids.indexOf(toId);
    if (fromIdx == -1 || toIdx == -1 || fromIdx == toIdx) return;
    final moved = ids.removeAt(fromIdx);
    ids.insert(toIdx, moved);
    _collectionOrders[orderKey] = ids;
    collectionOrderVersion.value++;
    await _saveCollectionOrder(orderKey);
  }

  // ── Smart Folder CRUD ────────────────────────────────────────────────────

  Future<File> _getSmartFoldersFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_smartFolderFileName');
  }

  Future<void> _loadSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      debugPrint('[MediaLibrary] _loadSmartFolders: 文件路径=${file.path}');
      final dirExists = await file.parent.exists();
      debugPrint('[MediaLibrary] _loadSmartFolders: 父目录存在=$dirExists');
      final fileExists = await file.exists();
      debugPrint('[MediaLibrary] _loadSmartFolders: 文件存在=$fileExists');
      if (fileExists) {
        final json = await file.readAsString();
        debugPrint('[MediaLibrary] _loadSmartFolders: 读取 ${json.length} 字节');
        if (json.isNotEmpty) {
          final loaded = SmartFolder.listFromJson(json);
          smartFolders.assignAll(loaded);
          debugPrint('[MediaLibrary] _loadSmartFolders: ✅ 加载成功，${loaded.length} 个智能文件夹');
        } else {
          debugPrint('[MediaLibrary] _loadSmartFolders: 文件内容为空');
        }
      } else {
        // 迁移：从 SharedPreferences 读取旧数据
        debugPrint('[MediaLibrary] _loadSmartFolders: 文件不存在，尝试从 SharedPreferences 迁移');
        final prefs = await SharedPreferences.getInstance();
        final oldJson = prefs.getString(_smartFoldersPrefsKey);
        if (oldJson != null && oldJson.isNotEmpty) {
          debugPrint('[MediaLibrary] _loadSmartFolders: SharedPreferences 迁移 ${oldJson.length} 字节');
          final List<SmartFolder> loaded = SmartFolder.listFromJson(oldJson);
          smartFolders.assignAll(loaded);
          await _saveSmartFolders();
          await prefs.remove(_smartFoldersPrefsKey);
          debugPrint('[MediaLibrary] _loadSmartFolders: 迁移完成，${loaded.length} 个智能文件夹');
        } else {
          debugPrint('[MediaLibrary] _loadSmartFolders: 无历史数据，首次使用');
        }
      }
    } catch (err, stack) {
      // 使用 debugPrint 而非 logger 避免外部库未就绪导致嵌套异常
      debugPrint('[MediaLibrary] _loadSmartFolders: ❌ 加载失败 err=$err');
      debugPrint('[MediaLibrary] _loadSmartFolders: stack=$stack');
    }
  }

  /// 立即将智能文件夹列表持久化到磁盘，供调试时主动调用。
  Future<void> debugForceReloadSmartFolders() => _loadSmartFolders();

  Future<void> _saveSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      debugPrint('[MediaLibrary] _saveSmartFolders: 目标路径=${file.path}');
      // 确保父目录存在（Windows 上 AppData 子目录可能尚未创建）
      await file.parent.create(recursive: true);
      final json = SmartFolder.listToJson(smartFolders);
      await file.writeAsString(json, flush: true);
      // 回读验证写入成功
      final written = await file.readAsString();
      if (written == json) {
        debugPrint('[MediaLibrary] _saveSmartFolders: ✅ 写入验证通过，${smartFolders.length} 个智能文件夹，${json.length} 字节');
      } else {
        debugPrint('[MediaLibrary] _saveSmartFolders: ❌ 内容不符！期望 ${json.length} 字节，实际 ${written.length} 字节');
      }
    } catch (err, stack) {
      debugPrint('[MediaLibrary] _saveSmartFolders: ❌ 保存失败 err=$err');
      debugPrint('[MediaLibrary] _saveSmartFolders: stack=$stack');
    }
  }

  Future<void> createSmartFolder(
    String name,
    String pattern, {
    List<String> targetFolderIds = const [],
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final id = '$_smartFolderPrefix${DateTime.now().millisecondsSinceEpoch}';
    final sf = SmartFolder(
      id: id,
      name: normalized,
      regexPattern: pattern.trim(),
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: targetFolderIds,
    );
    smartFolders.add(sf);
    await _saveSmartFolders();
  }

  Future<void> renameSmartFolder(String id, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) return;
    final index = smartFolders.indexWhere((sf) => sf.id == id);
    if (index == -1) return;
    smartFolders[index] = smartFolders[index].copyWith(name: normalized);
    smartFolders.refresh();
    await _saveSmartFolders();
  }

  Future<void> editSmartFolder(
    String id, {
    required String name,
    required String pattern,
    required List<String> targetFolderIds,
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
  }) async {
    final index = smartFolders.indexWhere((sf) => sf.id == id);
    if (index == -1) return;
    final updated = SmartFolder(
      id: id,
      name: name.trim().isEmpty ? smartFolders[index].name : name.trim(),
      regexPattern: pattern.trim(),
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: targetFolderIds,
    );
    smartFolders[index] = updated;
    smartFolders.refresh();
    await _saveSmartFolders();
  }

  Future<void> deleteSmartFolder(String id) async {
    smartFolders.removeWhere((sf) => sf.id == id);
    await _saveSmartFolders();
    if (currentFolderId.value == id) {
      exitToRoot();
    }
  }

  // ── 集合物理转移 ─────────────────────────────────────────────────────────

  /// 将 [folderId] 文件夹（或智能文件夹 [smartFolderId]）内的所有集合
  /// 物理迁移到用户选择的目标目录：
  ///   <目标目录>/<文件夹名>/<集合名>/<原文件> → 移动文件 → reimport 更新 DB。
  ///
  /// [folderId] 与 [smartFolderId] 二选一，传入非 null 值。
  Future<void> transferFolderCollections({
    String? folderId,
    String? smartFolderId,
  }) async {
    // 1. 弹出文件夹选择器
    final targetRoot = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择转移目标目录',
    );
    if (targetRoot == null || targetRoot.isEmpty) return;

    // 2. 确定集合列表
    final List<media_api.MediaCollection> toTransfer;
    final String containerName;
    if (smartFolderId != null) {
      final sf = getSmartFolder(smartFolderId);
      if (sf == null) return;
      containerName = sf.name;
      toTransfer = mergedCollections.where((c) {
        if (!sf.matchesCollection(c)) return false;
        if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
          final paths = _collectionItemPaths[c.id] ?? const [];
          return sf.matchesFileNames(paths);
        }
        return true;
      }).where((c) => !isRemoteCollection(c.id)).toList();
    } else if (folderId != null) {
      final folder = mergedFolders.firstWhereOrNull((f) => f.id == folderId);
      if (folder == null) return;
      containerName = folder.name;
      toTransfer = mergedCollections
          .where((c) => c.folderId == folderId && !isRemoteCollection(c.id))
          .toList();
    } else {
      return;
    }

    if (toTransfer.isEmpty) {
      showSnack('提示', '该文件夹内没有可转移的本地集合');
      return;
    }

    isScanning.value = true;
    scanStatusText.value = '准备转移...';
    int successCount = 0;
    int failCount = 0;

    try {
      final sep = Platform.pathSeparator;
      final containerDir = Directory('$targetRoot$sep$containerName');

      for (final collection in toTransfer) {
        try {
          scanStatusText.value = '转移中: ${collection.title} ($successCount/${toTransfer.length})';

          // 3. 创建目标集合目录：<targetRoot>/<containerName>/<collectionTitle>
          final destCollectionDir = Directory(
            '${containerDir.path}$sep${collection.title}',
          );
          await destCollectionDir.create(recursive: true);

          // 4. 获取集合内所有文件
          final items = media_api.getMediaCollectionItems(collectionId: collection.id);

          // 5. 逐文件物理移动（同盘用 rename，跨盘 fallback 到 copy+delete）
          for (final item in items) {
            final srcFile = File(item.filePath);
            if (!srcFile.existsSync()) {
              debugPrint('[Transfer] 源文件不存在，跳过: ${item.filePath}');
              continue;
            }
            final fileName = srcFile.uri.pathSegments.last;
            final destFile = File('${destCollectionDir.path}$sep$fileName');
            try {
              await srcFile.rename(destFile.path);
            } on FileSystemException {
              // 跨驱动器无法 rename，降级为 copy + delete
              try {
                await srcFile.copy(destFile.path);
                await srcFile.delete();
              } catch (copyErr) {
                debugPrint('[Transfer] copy+delete 失败: ${item.filePath} → ${destFile.path} err=$copyErr');
              }
            }
          }

          // 6. reimport 新路径，在 DB 中建立新集合记录
          final newCollection = await media_api.importMediaFolder(
            folderPath: destCollectionDir.path,
          );

          // 7. 将新集合关联到原来的库文件夹
          if (collection.folderId != null) {
            media_api.moveMediaCollectionToFolder(
              collectionId: newCollection.id,
              folderId: collection.folderId,
            );
          }

          // 8. 删除旧集合 DB 记录
          media_api.deleteMediaCollection(collectionId: collection.id);

          // 9. 删除原空目录（如果已清空）
          try {
            final oldDir = Directory(collection.folderPath);
            if (oldDir.existsSync() && oldDir.listSync().isEmpty) {
              await oldDir.delete();
            }
          } catch (_) {}

          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('[Transfer] 集合"${collection.title}"转移失败: $e');
        }
      }

      await refreshAll();
      if (failCount == 0) {
        showSnack('成功', '成功转移 $successCount 个集合到: $targetRoot');
      } else {
        showSnack('部分完成', '成功 $successCount 个，失败 $failCount 个');
      }
    } catch (e) {
      showSnack('错误', '转移失败: $e');
      debugPrint('[Transfer] 转移异常: $e');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }



  Future<void> createFolderWithName(String name, {String? targetNodeId}) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return;
    }

    try {
      // When inside a smart folder, use its real targetFolderId as parent
      final activeFolderId = effectiveFolderId;
      if (activeFolderId != null && isRemoteFolder(activeFolderId)) {
        final nodeId = getRemoteFolderNodeId(activeFolderId);
        final rawParentId = getRemoteRawFolderId(activeFolderId);
        if (nodeId == null || rawParentId == null) {
          throw StateError('远程媒体文件夹映射不存在');
        }
        await nodeSettingsService.createNodeMediaFolder(
          nodeId: nodeId,
          name: normalized,
          parentId: rawParentId,
        );
        await refreshRemoteLibrary();
        return;
      }

      if (targetNodeId != null) {
        await nodeSettingsService.createNodeMediaFolder(nodeId: targetNodeId, name: normalized);
        await refreshRemoteLibrary();
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        throw UnsupportedError('移动端请在节点上创建文件夹');
      }

      if (activeFolderId == null) {
        media_api.createMediaFolder(name: normalized);
      } else {
        media_api.createChildMediaFolder(name: normalized, parentId: activeFolderId);
      }
      await loadFolders();
    } catch (error) {
      showSnack('错误', '创建文件夹失败: $error');
    }
  }

  Future<void> renameFolder(String folderId, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return;
    }

    try {
      if (isRemoteFolder(folderId)) {
        final nodeId = getRemoteFolderNodeId(folderId);
        final rawId = getRemoteRawFolderId(folderId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程媒体文件夹映射不存在');
        }
        await nodeSettingsService.renameNodeMediaFolder(
          nodeId: nodeId,
          folderId: rawId,
          name: normalized,
        );
        await refreshRemoteLibrary();
      } else {
        media_api.renameMediaFolder(folderId: folderId, name: normalized);
        await loadFolders();
      }
    } catch (error) {
      showSnack('错误', '重命名文件夹失败: $error');
    }
  }

  Future<void> deleteFolder(String folderId) async {
    final parentId = mergedFolders.firstWhereOrNull((folder) => folder.id == folderId)?.parentId;
    try {
      if (isRemoteFolder(folderId)) {
        final nodeId = getRemoteFolderNodeId(folderId);
        final rawId = getRemoteRawFolderId(folderId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程媒体文件夹映射不存在');
        }
        await nodeSettingsService.deleteNodeMediaFolder(nodeId: nodeId, folderId: rawId);
        await refreshRemoteLibrary();
      } else {
        media_api.deleteMediaFolder(folderId: folderId);
        await loadFolders();
        await loadCollections();
      }
      if (currentFolderId.value == folderId) {
        currentFolderId.value = parentId;
      }
    } catch (error) {
      showSnack('错误', '删除文件夹失败: $error');
    }
  }

  Future<void> scanFolder({String? folderPath, String? nodeId}) async {
    try {
      isScanning.value = true;
      scanStatusText.value = '扫描中...';
      if (nodeId != null) {
        final normalized = folderPath?.trim() ?? '';
        if (normalized.isEmpty) {
          throw ArgumentError('请输入节点目录路径');
        }
        final payloads = await nodeSettingsService.scanNodeMediaFolders(
          nodeId: nodeId,
          folderPath: normalized,
        );
        final targetFolderRawId = _resolveRemoteTargetFolderId(nodeId);
        if (targetFolderRawId != null) {
          for (final payload in payloads) {
            final rawId = _stringOrNull(payload['id']);
            if (rawId == null || rawId.isEmpty) {
              continue;
            }
            await nodeSettingsService.moveNodeMediaCollectionToFolder(
              nodeId: nodeId,
              collectionId: rawId,
              folderId: targetFolderRawId,
            );
          }
        }
        await refreshRemoteLibrary();
        scanStatusText.value = '';
        showSnack('成功', '节点媒体目录扫描完成');
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        throw UnsupportedError('移动端请通过节点路径导入');
      }

      // 在打开文件选择器前先捕获文件夹上下文，防止 await 期间状态变化
      final targetFolderId = effectiveFolderId;
      final selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null || selectedPath.isEmpty) {
        scanStatusText.value = '';
        isScanning.value = false;
        return;
      }
      scanStatusText.value = '扫描中...';
      final imported = await media_api.scanMediaFolders(folderPath: selectedPath);
      scanStatusText.value = '导入中...';
      if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
        for (final collection in imported) {
          media_api.moveMediaCollectionToFolder(
            collectionId: collection.id,
            folderId: targetFolderId,
          );
        }
      }
      await loadCollections();
      scanStatusText.value = '';
      if (imported.isEmpty) {
        showSnack('提示', '未发现媒体集合，请确认目录内含有图片或视频文件（支持 jpg/png/heic/mp4 等格式）');
      } else {
        showSnack('成功', '扫描完成，共导入 ${imported.length} 个集合');
      }
    } catch (error) {
      scanStatusText.value = '';
      showSnack('错误', '扫描目录失败: $error');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }

  Future<void> importFolder({String? folderPath, String? nodeId}) async {
    try {
      isScanning.value = true;
      scanStatusText.value = '导入中...';
      if (nodeId != null) {
        final normalized = folderPath?.trim() ?? '';
        if (normalized.isEmpty) {
          throw ArgumentError('请输入节点目录路径');
        }
        final payload = await nodeSettingsService.importNodeMediaFolder(
          nodeId: nodeId,
          folderPath: normalized,
        );
        final targetFolderRawId = _resolveRemoteTargetFolderId(nodeId);
        final rawId = payload == null ? null : _stringOrNull(payload['id']);
        if (targetFolderRawId != null && rawId != null && rawId.isNotEmpty) {
          await nodeSettingsService.moveNodeMediaCollectionToFolder(
            nodeId: nodeId,
            collectionId: rawId,
            folderId: targetFolderRawId,
          );
        }
        await refreshRemoteLibrary();
        scanStatusText.value = '';
        showSnack('成功', '节点媒体目录导入完成');
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        throw UnsupportedError('移动端请通过节点路径导入');
      }

      // 在打开文件选择器前先捕获文件夹上下文，防止 await 期间状态变化
      final targetFolderId = effectiveFolderId;
      final selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null || selectedPath.isEmpty) {
        scanStatusText.value = '';
        isScanning.value = false;
        return;
      }
      scanStatusText.value = '导入中...';
      final collection = await media_api.importMediaFolder(folderPath: selectedPath);
      if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
        media_api.moveMediaCollectionToFolder(
          collectionId: collection.id,
          folderId: targetFolderId,
        );
      }
      await loadCollections();
      scanStatusText.value = '';
      showSnack('成功', '媒体集合导入完成');
    } catch (error) {
      scanStatusText.value = '';
      showSnack('错误', '导入目录失败: $error');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }

  Future<void> renameCollection(String collectionId, String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return;
    }
    try {
      if (isRemoteCollection(collectionId)) {
        final nodeId = getRemoteNodeId(collectionId);
        final rawId = getRemoteRawCollectionId(collectionId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程媒体集合映射不存在');
        }
        await nodeSettingsService.renameNodeMediaCollection(
          nodeId: nodeId,
          collectionId: rawId,
          title: normalized,
        );
        await refreshRemoteLibrary();
      } else {
        media_api.renameMediaCollection(collectionId: collectionId, title: normalized);
        await loadCollections();
      }
      if (currentCollectionId.value == collectionId) {
        await loadCurrentCollectionItems();
      }
    } catch (error) {
      showSnack('错误', '重命名集合失败: $error');
    }
  }

  Future<void> moveCollectionToFolder(String collectionId, String? folderId) async {
    try {
      if (isRemoteCollection(collectionId)) {
        final nodeId = getRemoteNodeId(collectionId);
        final rawCollectionId = getRemoteRawCollectionId(collectionId);
        if (nodeId == null || rawCollectionId == null) {
          throw StateError('远程媒体集合映射不存在');
        }
        final targetNodeId = folderId == null ? nodeId : getRemoteFolderNodeId(folderId);
        if (targetNodeId != nodeId) {
          throw StateError('远程媒体集合只能移动到同一节点中的文件夹');
        }
        await nodeSettingsService.moveNodeMediaCollectionToFolder(
          nodeId: nodeId,
          collectionId: rawCollectionId,
          folderId: folderId == null ? null : getRemoteRawFolderId(folderId),
        );
        await refreshRemoteLibrary();
      } else {
        if (folderId != null && isRemoteFolder(folderId)) {
          throw StateError('本地媒体集合不能移动到远程文件夹');
        }
        media_api.moveMediaCollectionToFolder(collectionId: collectionId, folderId: folderId);
        await loadCollections();
      }
      if (currentCollectionId.value == collectionId) {
        await loadCurrentCollectionItems();
      }
    } catch (error) {
      showSnack('错误', '移动集合失败: $error');
    }
  }

  Future<void> clearLocalLibrary() async {
    isScanning.value = true;
    scanStatusText.value = '清空本地媒体库中…';
    try {
      // 分批删除集合，每 20 条 yield 一次以保持 UI 响应
      final collectionSnapshot = collections.map((c) => c.id).toList();
      for (int i = 0; i < collectionSnapshot.length; i++) {
        media_api.deleteMediaCollection(collectionId: collectionSnapshot[i]);
        if (i % 20 == 19) await Future.delayed(Duration.zero);
      }
      // 删除所有文件夹（遇到已级联删除的忽略错误）
      final folderSnapshot = folders.map((f) => f.id).toList();
      for (int i = 0; i < folderSnapshot.length; i++) {
        try {
          media_api.deleteMediaFolder(folderId: folderSnapshot[i]);
        } catch (_) {}
        if (i % 20 == 19) await Future.delayed(Duration.zero);
      }
      currentCollectionId.value = null;
      currentFolderId.value = null;
      _browseScrollOffsets.clear();
      savedScrollOffset.value = 0.0;
      await loadCollections();
      await loadFolders();
      showSnack('成功', '已清空本地媒体库');
    } catch (error) {
      showSnack('错误', '清空媒体库失败: $error');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    try {
      if (isRemoteCollection(collectionId)) {
        final nodeId = getRemoteNodeId(collectionId);
        final rawId = getRemoteRawCollectionId(collectionId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程媒体集合映射不存在');
        }
        await nodeSettingsService.deleteNodeMediaCollection(nodeId: nodeId, collectionId: rawId);
        await refreshRemoteLibrary();
      } else {
        media_api.deleteMediaCollection(collectionId: collectionId);
        await loadCollections();
      }
      if (currentCollectionId.value == collectionId) {
        exitCollection();
      }
    } catch (error) {
      showSnack('错误', '删除集合失败: $error');
    }
  }

  Future<void> deleteSelectedItems() async {
    final folderIds = selectedIds
        .where((id) => mergedFolders.any((folder) => folder.id == id))
        .toList();
    final collectionIds = selectedIds
        .where((id) => mergedCollections.any((collection) => collection.id == id))
        .toList();
    for (final collectionId in collectionIds) {
      await deleteCollection(collectionId);
    }
    for (final folderId in folderIds) {
      await deleteFolder(folderId);
    }
    exitSelection();
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

    final directCollections = mergedCollections.where(
      (collection) => collection.folderId == folderId,
    );
    if (directCollections.isNotEmpty) {
      return directCollections.first;
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
