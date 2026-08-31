import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/video_thumb_queue.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/natural_compare.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

part 'media_library_vm_remote.dart';
part 'media_library_vm_smart_folders.dart';
part 'media_library_vm_collections.dart';
part 'media_library_vm_cover_check.dart';

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

  /// 鼠标当前悬停的集合 ID（浏览层，供 Delete 快捷键定位目标）
  final hoveredCollectionId = RxnString();
  final isScanning = false.obs;
  final scanStatusText = ''.obs;
  final isLoadingItems = false.obs;

  /// 远程集合加载进度（0.0~1.0），null 表示未开始或无进度信息可用。
  final itemLoadProgress = Rxn<double>();

  /// 远程节点数据是否正在后台异步加载中。
  final isLoadingRemote = false.obs;

  /// 缩略图生成进度：completed/total，null 表示无任务。
  final thumbProgress = Rxn<(int, int)>();

  /// 远程节点缩略图生成进度（各节点合计 completed/total），null 表示无任务。
  final remoteThumbProgress = Rxn<(int, int)>();

  /// 库内搜索关键词（非空时列表仅展示匹配项，直到手动清除）。
  final searchQuery = ''.obs;

  /// 搜索框是否展开。
  final isSearchActive = false.obs;

  /// 远程集合条目路径缓存（供深度搜索匹配资源文件名）。
  final _remoteCollectionItemPaths = <String, List<String>>{};

  /// 正在异步加载条目路径的远程集合 ID。
  final _remoteItemPathsLoading = <String>{};

  /// 搜索结果版本号（远程条目路径加载完成后自增以触发重建）。
  final _searchVersion = 0.obs;

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

  /// 本地图片条目缩略图缓存：key = 原始文件路径，value = .SlimeWorks/tmp 内缩略图路径。
  final _itemThumbnails = <String, String>{};

  /// 缩略图生成失败的文件路径集合（不重试，继续显示原图）。
  final _itemThumbFailed = <String>{};

  /// 正在执行中的封面任务 key（contains() 只覆盖等待中任务，运行中任务需单独去重）。
  final _inFlightCoverKeys = <String>{};

  /// 封面生成是否被用户暂停（取消后自动入队逻辑不再重新入队，直到手动恢复）。
  final thumbGenerationPaused = false.obs;

  /// 同名集合分组虚拟文件夹 ID 前缀。
  static const dupGroupPrefix = 'dup-group:';

  /// 是否为同名集合分组虚拟文件夹。
  bool isDupGroup(String id) => id.startsWith(dupGroupPrefix);

  /// 从分组 ID 中提取集合标题。
  String? dupGroupTitle(String id) => isDupGroup(id) ? id.substring(dupGroupPrefix.length) : null;

  /// 分组 ID → 所属父文件夹 ID（null = 根目录），在 visibleItems 构建时登记。
  final _dupGroupParents = <String, String?>{};

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

  /// 用于集合封面生成的串行队列。
  /// 并发数与 Rust 端全局 ffmpeg 信号量一致，双重保障 ffmpeg 进程数不超限。
  final _coverQueue = VideoThumbQueue(concurrency: 2);

  /// 用于 scrub 帧提取的串行队列。
  final _scrubQueue = VideoThumbQueue(concurrency: 2);

  /// 当前文件夹对应的封面任务 key 列表（退出文件夹时取消）。
  final _currentFolderCoverKeys = <String>{};

  /// videoPath → scrub 帧路径列表的异步缓存（仅含非空结果）。
  final _videoFrameCache = <String, Future<List<String>>>{};

  /// videoPath → 已完成的帧结果（同步可读，供 getCollectionVideoFrameAtFraction 使用）。
  final _videoFrameResults = <String, List<String>>{};

  /// filePath → 音频封面缩略图路径的异步缓存。
  final _audioCoverCache = <String, Future<String?>>{};

  final _lostCollections = <String, bool>{};
  final _lostFolders = <String, bool>{};
  final _lostSmartFolders = <String, bool>{};
  final _checkTimestamps = <String, int>{};

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

  /// 集合排序方式的持久化键（重启后恢复，防止拖拽排序因排序模式重置而失效）。
  static const String _kSortOrderPrefKey = 'media_collection_sort_order';

  /// 集合拖拽顺序的 SharedPreferences 键前缀（与历史版本保持一致，完整键 = 前缀 + orderKey）。
  static const String _kColOrderPrefPrefix = 'media_col_order_';

  /// 媒体库偏好实例（onInitAsync 中初始化，供排序持久化扩展使用）。
  SharedPreferences? _prefs;

  /// 拖拽顺序 prefs 键前缀（实例访问器，供 part 扩展使用；扩展内不能直接引用静态成员）。
  String get _colOrderPrefPrefix => _kColOrderPrefPrefix;

  Worker? _nodeMutationWorker;
  Future<void>? _refreshAllFuture;

  /// 集合文件夹自动扫描定时器（每 30 秒后台轮询）。
  Timer? _folderWatchTimer;

  /// 远程节点缩略图进度轮询定时器（每 2 秒）。
  Timer? _remoteThumbPollTimer;

  /// 上一轮远程缩略图进度轮询是否仍在执行（防重叠）。
  bool _remoteThumbPolling = false;

  /// 缩略图生成后触发缓存清理的防抖定时器（1 分钟后执行）。
  Timer? _trimCacheTimer;

  /// 缩略图进度"100% 完成"短暂显示防抖定时器。
  /// 避免从 (n-1)/n 直接消失，给用户视觉反馈再清空。
  Timer? _thumbCompleteTimer;

  /// 上次扫描时各集合的 item 数量快照，用于判断是否有新增。
  final _collectionItemCountSnapshot = <String, int>{};

  /// 将并发量同步到 Rust 端全局 ffmpeg 信号量，同时更新 Flutter 端队列并发限制。
  void _syncConcurrency(int v) {
    _coverQueue.concurrency = v;
    _scrubQueue.concurrency = v;
    try {
      media_api.registerFfmpegConcurrency(limit: v);
      _logger.info('[FFmpeg] 并发上限已同步到 Rust 端: $v');
    } catch (e) {
      _logger.error('[FFmpeg] 同步并发上限到 Rust 端失败: $e');
    }
  }

  @override
  Future<void> onInitAsync() async {
    _logger.info('[媒体库] onInitAsync: isInitialized=$isInitialized');
    // 初始化媒体偏好设置，并将并发量同步到 Rust 端和队列
    await mediaPrefs.init();
    _syncConcurrency(mediaPrefs.concurrency.value);
    // 监听并发量变化，动态更新 Rust 端信号量和队列并发限制
    ever(mediaPrefs.concurrency, _syncConcurrency);

    // 缩略图生成完成后，防抖 1 分钟触发一次缓存大小检查
    void scheduleTrimCache() {
      _trimCacheTimer?.cancel();
      _trimCacheTimer = Timer(const Duration(minutes: 1), () {
        mediaPrefs.trimCacheToLimit();
      });
    }

    _coverQueue.onTaskComplete = scheduleTrimCache;
    _scrubQueue.onTaskComplete = scheduleTrimCache;

    // 缩略图进度回调：合并两个队列的进度
    void updateProgress(int completed, int total) {
      // 暂停期间忽略在途任务的进度回调，保持状态栏停留在暂停状态
      if (thumbGenerationPaused.value) return;
      final c = _coverQueue.completed + _scrubQueue.completed;
      final t = _coverQueue.total + _scrubQueue.total;
      if (t > 0 && c < t) {
        thumbProgress.value = (c, t);
        _logger.info('[ThumbProgress] $c/$t');
      } else if (t > 0 && c >= t) {
        // 100% 完成时短暂显示再清空，避免从 (n-1)/n 直接消失无反馈
        thumbProgress.value = (c, t);
        _thumbCompleteTimer?.cancel();
        _thumbCompleteTimer = Timer(const Duration(seconds: 2), () {
          // 2 秒内若有新任务进入，thumbProgress 已被新值覆盖，此处只在仍为完成态时清空
          final cur = thumbProgress.value;
          if (cur != null && cur.$1 >= cur.$2) {
            thumbProgress.value = null;
          }
        });
      } else {
        thumbProgress.value = null;
      }
    }

    _coverQueue.onProgress = updateProgress;
    _scrubQueue.onProgress = updateProgress;

    // 无论是否已初始化都重建 worker（onClose 后 worker 会被置 null）
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) async {
      await refreshAll();
    });
    if (isInitialized) {
      // 永久 ViewModel 再次进入页面时：刷新数据 + 重新加载智能文件夹（磁盘上的数据描和内存始终保持同步）
      _logger.info('[媒体库] onInitAsync: 已初始化，重新加载智能文件夹 + 执行数据刷新');
      await _loadSmartFolders();
      // 重新加载收藏：若首次初始化时因数据库未就绪等原因加载失败，此处可恢复
      await _loadFavorites();
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
    // 恢复集合排序方式（持久化），并监听变更实时写回，防止重启后回到默认排序
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final stored = prefs.getString(_kSortOrderPrefKey);
      if (stored != null) {
        collectionSortOrder.value = CollectionSortOrder.values.firstWhere(
          (e) => e.name == stored,
          orElse: () => CollectionSortOrder.dateUpdated,
        );
        _logger.info('[媒体库] 已恢复集合排序方式: $stored');
      }
      ever(collectionSortOrder, (v) {
        prefs.setString(_kSortOrderPrefKey, v.name);
      });
    } catch (e) {
      _logger.error('[媒体库] 恢复排序方式失败: $e');
    }
    _logger.info('[媒体库] onInitAsync: 开始 refreshAll');
    await refreshAll();
    _logger.info(
      '[媒体库] onInitAsync: refreshAll 完成，collections=${collections.length}，folders=${folders.length}',
    );
    // 应用启动时恢复未完成的缩略图任务（pending/running/failed 全部重新入队）
    await _restorePendingThumbnailTasks();
    // 启动集合文件夹自动扫描定时器（每 30 秒轮询）
    _folderWatchTimer?.cancel();
    _folderWatchTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollCollectionFolders(),
    );
    // 启动远程节点缩略图进度轮询（节点端生成封面时客户端可见状态与进度）
    _remoteThumbPollTimer?.cancel();
    _remoteThumbPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollRemoteThumbProgress(),
    );
  }

  @override
  void onClose() {
    _nodeMutationWorker?.dispose();
    _nodeMutationWorker = null;
    _folderWatchTimer?.cancel();
    _folderWatchTimer = null;
    _remoteThumbPollTimer?.cancel();
    _remoteThumbPollTimer = null;
    _trimCacheTimer?.cancel();
    _trimCacheTimer = null;
    _thumbCompleteTimer?.cancel();
    _thumbCompleteTimer = null;
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
    return mergedCollections.firstWhereOrNull((collection) => collection.id == collectionId);
  }

  String get currentCollectionTitle => currentCollection?.title ?? '';

  String get currentBrowseTitle =>
      currentSmartFolder?.name ?? currentDupGroupTitle ?? currentFolder?.name ?? '媒体库';

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
    return mergedFolders.where((folder) => folder.parentId == folderId).toList(growable: false);
  }

  /// 判断集合是否匹配智能文件夹。
  /// - 远程集合 或 远程智能文件夹：忽略文件夹范围过滤，仅对标题和路径做正则匹配。
  /// - 本地集合 + 本地智能文件夹：执行完整的 matchesCollection 逻辑。
  bool collectionMatchesSmartFolder(SmartFolder sf, media_api.MediaCollection c) {
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

  List<media_api.MediaCollection> get currentCollections {
    final folderId = currentFolderId.value;
    _logger.info(
      '[currentCollections] folderId=$folderId, isSmartFolder=${folderId != null && isSmartFolder(folderId)}, smartFolderCount=${smartFolders.length}, localCollections=${collections.length}, remoteCollections=${remoteCollections.length}',
    );
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
      var filtered = mergedCollections
          .where((c) => collectionMatchesSmartFolder(sf, c))
          .toList(growable: true);
      _logger.info(
        '[currentCollections] 智能文件夹=${sf.name}, folderId=$folderId, merged=${mergedCollections.length}, matched=${filtered.length}, regexTarget=${sf.regexTarget}, targetFolderIds=${sf.targetFolderIds}, regexPattern=${sf.regexPattern}, keywords=${sf.keywords}',
      );
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
    _logger.info('_applySortOrder: dateUpdated orderKey=$orderKey sorted by updatedAt desc');
    return result;
  }

  List<MediaLibraryItem> get visibleItems {
    // 搜索激活时：深度搜索当前层级并仅展示匹配项
    final query = searchQuery.value.trim().toLowerCase();
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
        final groupId = '$dupGroupPrefix${c.title}';
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
              paths.any((p) => _pathBasename(p).toLowerCase().contains(query));
        } else {
          itemHit = _getCollectionItemPaths(c.id)
              .any((p) => _pathBasename(p).toLowerCase().contains(query));
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
    nodeSettingsService
        .fetchNodeMediaCollectionItems(nodeId: nodeId, collectionId: rawId)
        .then((payloads) {
          _remoteCollectionItemPaths[collectionId] = payloads
              .map((p) => (p['file_path'] ?? '').toString())
              .toList();
          _searchVersion.value++;
        })
        .catchError((_) {})
        .whenComplete(() => _remoteItemPathsLoading.remove(collectionId));
  }

  /// 取路径的文件名部分（兼容 Windows 分隔符）。
  static String _pathBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  /// \u5f53\u524d\u96c6\u5408\u5185\u8d44\u6e90\u6309 [itemSortOrder] \u6392\u5e8f\u540e\u7684\u5217\u8868\uff08\u54cd\u5e94\u5f0f\uff09\u3002
  List<media_api.MediaItem> get sortedCurrentItems {
    // \u8bfb\u53d6 itemSortOrder.value \u4ee5\u6ce8\u518c\u54cd\u5e94\u5f0f\u4f9d\u8d56
    final order = itemSortOrder.value;
    // 搜索激活时：按文件名模糊过滤资源列表
    final searchQueryText = searchQuery.value.trim().toLowerCase();
    var items = [...currentItems];
    if (searchQueryText.isNotEmpty) {
      items = items
          .where((i) => i.title.toLowerCase().contains(searchQueryText))
          .toList();
    }
    switch (order) {
      case MediaItemSortOrder.nameAsc:
        items.sort((a, b) => naturalCompare(a.title, b.title));
      case MediaItemSortOrder.nameDesc:
        items.sort((a, b) => naturalCompare(b.title, a.title));
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

  /// 在资源管理器中显示该文件所在文件夹（通过 Rust FFI 跨平台调用）。
  Future<void> openItemInFolder(media_api.MediaItem item) async {
    try {
      await media_api.openInFileManager(filePath: item.filePath);
    } catch (e) {
      showSnack('错误', '打开文件夹失败: $e');
    }
  }

  /// 删除物理文件并通过 Rust 重新导入集合目录以同步数据库。
  Future<void> deleteItemFile(media_api.MediaItem item) async {
    try {
      media_api.deleteMediaItemFile(itemFilePath: item.filePath);
    } catch (e) {
      showSnack('错误', '删除文件失败: $e');
      return;
    }
    await loadCollections();
    await loadCurrentCollectionItems();
    showSnack('成功', '文件已删除');
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
      // 本地图片：网格缩略图（isCover=true）走缩略图管线，生成后缓存到资源旁的 .SlimeWorks/tmp；
      // 预览大图（isCover=false）仍用原图。
      if (isCover && item.kind == media_api.MediaKind.image) {
        // 读取异步版本号，注册响应式依赖（缩略图生成完成后触发重建）
        _asyncCoverVersion.value;
        final cached = _itemThumbnails[item.filePath];
        if (cached != null) return cached;
        _enqueueItemThumbnail(item.filePath);
      }
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

  /// 远程图片兜底原图 URL：不带缩放参数，节点直接传输原始文件。
  /// 供缩略图 2s 超时临时充当封面使用。
  String? buildRemoteOriginalMediaSource(media_api.MediaItem item, {String? collectionId}) {
    final targetCollectionId = collectionId ?? currentCollectionId.value;
    if (targetCollectionId == null || !isRemoteCollection(targetCollectionId)) {
      return null;
    }
    if (item.kind != media_api.MediaKind.image) {
      return null;
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
    // 本地视频封面 — 异步生成缩略图（暂停期间不入队）
    if (_isVideoPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!thumbGenerationPaused.value &&
          !_coverQueue.contains(collection.id) &&
          !_inFlightCoverKeys.contains(collection.id)) {
        _generateCollectionVideoThumbnailAsync(collection.id, coverPath);
      }
      return null;
    }
    // 本地音频封面 — 异步提取嵌入专辑封面（暂停期间不入队）
    if (_isAudioPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!thumbGenerationPaused.value &&
          !_coverQueue.contains(collection.id) &&
          !_inFlightCoverKeys.contains(collection.id)) {
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

  /// 从帧列表中挑选封面帧：优先选第一个文件体积大于 1KB 的帧，
  /// 避免选中纯黑帧（部分视频开头/中间为黑屏，生成的封面看起来像没有封面）。
  String _pickCoverFrame(List<String> frames) {
    for (final path in frames) {
      try {
        if (File(path).lengthSync() > 1024) return path;
      } catch (_) {}
    }
    return frames[frames.length ~/ 2];
  }

  void _generateCollectionVideoThumbnailAsync(String collectionId, String videoPath) {
    _logger.info('[VideoThumb] 入队封面: collectionId=$collectionId');
    _currentFolderCoverKeys.add(collectionId);
    _inFlightCoverKeys.add(collectionId);
    _coverQueue
        .enqueue(collectionId, () async {
          _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
          try {
            final frames = await _doGetScrubFrames(videoPath);
            if (frames.isEmpty) {
              _logger.info('[VideoThumb] 帧为空，不缓存: collectionId=$collectionId');
              return;
            }
            final thumb = _pickCoverFrame(frames);
            _logger.info('[VideoThumb] 封面生成成功: collectionId=$collectionId thumb=$thumb');
            _collectionVideoThumbnails[collectionId] = thumb;
            _asyncCoverVersion.value++;
          } catch (e) {
            _logger.error('[VideoThumb] 封面生成失败: collectionId=$collectionId err=$e');
          }
        })
        .whenComplete(() {
          // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
          _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
        });
  }

  void _generateCollectionAudioCoverAsync(String collectionId, String audioPath) {
    _logger.info('[AudioCover] 入队集合封面: collectionId=$collectionId');
    _currentFolderCoverKeys.add(collectionId);
    _inFlightCoverKeys.add(collectionId);
    _coverQueue
        .enqueue(collectionId, () async {
          _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
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
        })
        .whenComplete(() {
          // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
          _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
        });
  }

  /// 为本地图片条目入队缩略图生成任务（宽度取「本地图片清晰度」设置，或 widthOverride）。
  /// 生成期间网格先显示原图，成功后切换到缩略图并缓存进 .SlimeWorks/tmp。
  void _enqueueItemThumbnail(String filePath, {int? widthOverride}) {
    if (thumbGenerationPaused.value) return;
    if (_itemThumbnails.containsKey(filePath) || _itemThumbFailed.contains(filePath)) {
      return;
    }
    final key = 'item-thumb:$filePath';
    if (_coverQueue.contains(key) || _inFlightCoverKeys.contains(key)) return;
    _inFlightCoverKeys.add(key);
    _coverQueue
        .enqueue(key, () async {
          _inFlightCoverKeys.remove(key);
          try {
            final w = widthOverride ?? mediaPrefs.localPreviewWidth.value;
            final width = w > 0 ? w : 480;
            // FRB 异步调用（Rust 端在后台线程池解码缩放，不阻塞 UI 线程）
            final thumb = await media_api.ensureCoverThumbnail(filePath: filePath, width: width);
            if (thumb == null || thumb.isEmpty) {
              _itemThumbFailed.add(filePath);
              return;
            }
            _logger.info('[ItemThumb] 缩略图已生成: $thumb');
            _itemThumbnails[filePath] = thumb;
            _asyncCoverVersion.value++;
          } catch (e) {
            _logger.error('[ItemThumb] 缩略图生成失败: $filePath err=$e');
            _itemThumbFailed.add(filePath);
          }
        })
        .whenComplete(() {
          // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
          _inFlightCoverKeys.remove(key);
        });
  }

  /// 应用启动时从持久化任务表恢复未完成的缩略图任务。
  /// 包括 pending/running/failed 状态，全部重新入队到 VideoThumbQueue。
  /// failed 任务从 _itemThumbFailed 移除以允许重试。
  Future<void> _restorePendingThumbnailTasks() async {
    try {
      final tasks = media_api.getAllPendingThumbnailTasks();
      if (tasks.isEmpty) return;
      _logger.info('[ThumbRestore] 发现 ${tasks.length} 个未完成缩略图任务，开始重新入队');
      int restored = 0;
      for (final task in tasks) {
        if (task.filePath.isEmpty) continue;
        // 失败任务重新尝试：从失败集合中移除以便重新入队
        _itemThumbFailed.remove(task.filePath);
        _enqueueItemThumbnail(
          task.filePath,
          widthOverride: task.width > 0 ? task.width : null,
        );
        restored++;
      }
      _logger.info('[ThumbRestore] 已重新入队 $restored 个任务');
    } catch (e) {
      _logger.error('[ThumbRestore] 恢复未完成缩略图任务失败: $e');
    }
  }

  String? buildFolderCoverSource(media_api.MediaFolder folder) {
    // 注册响应式依赖：集合排序变更时同步更新文件夹封面
    collectionOrderVersion.value;
    // 同名集合分组封面：取分组内排序后的第一个集合封面；
    // 依赖 _asyncCoverVersion 使视频封面异步生成后能触发重建。
    if (isDupGroup(folder.id)) {
      _asyncCoverVersion.value;
      final grouped = dupGroupCollections(folder.id);
      if (grouped.isEmpty) return null;
      final sorted = _applySortOrder(List.of(grouped), folder.id);
      return buildCollectionCoverSource(sorted.first);
    }
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
          if (thumb == null &&
              !thumbGenerationPaused.value &&
              !_coverQueue.contains(hoverKey) &&
              !_inFlightCoverKeys.contains(hoverKey)) {
            _generateHoverVideoThumbnailAsync(collection.id, p, i, count);
          }
        } else {
          result.add(p);
        }
      }
      if (videoPaths.isNotEmpty) {
        _hoverVideoPathsCache[collection.id] = videoPaths;
      }
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
        _logger.error(
          '[VideoThumb] hover 封面生成失败: collectionId=$collectionId slotIdx=$slotIdx err=$e',
        );
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
    // 用户暂停封面生成期间不入队 scrub 帧任务
    if (thumbGenerationPaused.value) return;
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
    // 同名集合分组：统计分组内集合数量而非真实文件夹下的集合
    if (isDupGroup(folderId)) {
      return dupGroupCollections(folderId).length;
    }
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
    await _loadSmartFolders();
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

  /// 后台轮询：通过 Rust FFI 检查本地集合文件数量变化，有则静默增量更新。
  Future<void> _pollCollectionFolders() async {
    // 只处理本地集合，跳过远程
    final localCols = collections.toList(growable: false);
    _logger.info('_pollCollectionFolders: 开始轮询 ${localCols.length} 个本地集合');
    bool anyChanged = false;
    try {
      // 轻量级 FFI：只获取集合 item count，不含文件路径列表
      final countsList = media_api.getAllCollectionCounts();
      for (final col in localCols) {
        try {
          final prev = _collectionItemCountSnapshot[col.id] ?? col.itemCount.toInt();
          final countEntry = countsList.where((c) => c.collectionId == col.id).firstOrNull;
          final count = countEntry?.itemCount ?? 0;
          _collectionItemCountSnapshot[col.id] = count;
          if (count != prev) {
            _logger.info('_pollCollectionFolders: 集合[${col.title}] prev=$prev now=$count，触发增量扫描');
            await media_api.importMediaFolder(folderPath: col.folderPath);
            anyChanged = true;
          }
        } catch (e) {
          _logger.info('_pollCollectionFolders: 集合 ${col.id} 检查异常: $e');
        }
      }
    } catch (e) {
      _logger.error('_pollCollectionFolders: 批量统计失败: $e');
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
      _hoverSourcesCache.clear();
      clearCoverCheckCache();
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
        // 轻量级 FFI：只获取集合 size，不含文件路径列表（避免大量序列化传输）
        final countsList = media_api.getAllCollectionCounts();
        for (final c in countsList) {
          _collectionSizes[c.collectionId] = c.totalSize;
        }
        // _collectionItemPaths 改为按需加载（见 _getCollectionItemPaths）
      } catch (e) {
        _logger.error('[媒体库] _computeCollectionSizesAsync 批量统计失败: $e');
      }
    });
  }

  /// 按需加载集合的文件路径列表（从 Rust FFI 获取）。
  List<String> _getCollectionItemPaths(String collectionId) {
    return _collectionItemPaths.putIfAbsent(collectionId, () {
      try {
        return media_api
            .getMediaCollectionItems(collectionId: collectionId)
            .map((i) => i.filePath)
            .toList();
      } catch (_) {
        return const [];
      }
    });
  }

  BigInt getCollectionTotalSize(String id) => _collectionSizes[id] ?? BigInt.zero;

  /// 返回指定集合内所有媒体文件路径（可能为空列表，异步缓存未就绪时）。
  List<String> collectionItemPaths(String id) => _getCollectionItemPaths(id);

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
        final ids = media_api.getFavoriteCollectionIds();
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
    // 同名集合分组：返回其登记的父文件夹（null = 根目录）
    final fid = currentFolderId.value;
    if (fid != null && isDupGroup(fid)) {
      final parent = _dupGroupParents[fid];
      _browseScrollOffsets.remove(fid);
      currentFolderId.value = parent;
      exitCollection();
      exitSelection();
      return;
    }
    final parentId = currentFolder?.parentId;
    _browseScrollOffsets.remove(currentFolderId.value);
    currentFolderId.value = parentId;
    exitCollection();
    exitSelection();
  }

  /// 暂停封面生成：清空两个缩略图队列中未执行的任务，
  /// 并置暂停标志阻止 Obx 重建时的自动重新入队，直到调用 [resumeThumbGeneration]。
  void cancelThumbGeneration() {
    thumbGenerationPaused.value = true;
    _coverQueue.cancelAll();
    _scrubQueue.cancelAll();
    _currentFolderCoverKeys.clear();
    thumbProgress.value = null;
  }

  /// 恢复封面生成：解除暂停标志并触发重建，卡片会重新检查并自动入队缺失封面。
  void resumeThumbGeneration() {
    thumbGenerationPaused.value = false;
    _asyncCoverVersion.value++;
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
          : mergedCollections.where((c) => collectionMatchesSmartFolder(sf, c)).toList();
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
    isSelecting.value = true;
    selectedIds.assignAll(unfavoritedIds);
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
    // 通过 Rust FFI 调用 ensure_cover_thumbnail（已支持音频封面提取）
    try {
      return await media_api.ensureCoverThumbnail(filePath: filePath, width: 300);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _doGetScrubFrames(String videoPath) async {
    // 通过 Rust FFI 调用 extract_video_scrub_frames
    try {
      final frameCount = mediaPrefs.currentLevel.frameCount;
      final result = media_api.extractVideoScrubFrames(
        videoPath: videoPath,
        frameCount: frameCount,
      );
      return result;
    } catch (e) {
      _logger.error('[VideoThumb] scrub 帧提取失败: $e');
      return const <String>[];
    }
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
