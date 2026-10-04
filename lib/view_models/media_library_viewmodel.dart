import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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
import 'package:slime_works/core/utils/timing_trace.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/components/dialogs/node_directory_picker.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/extract.dart' as extract_api;
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

part 'media_library_vm_remote.dart';
part 'media_library_vm_smart_folders.dart';
part 'media_library_vm_collections.dart';
part 'media_library_vm_cover_check.dart';
part 'media_library_vm_selection.dart';
part 'media_library_vm_browse.dart';
part 'media_library_vm_search.dart';
part 'media_library_vm_sources.dart';
part 'media_library_vm_refresh.dart';
part 'media_library_vm_navigation.dart';
part 'media_library_vm_favorites.dart';
part 'media_library_vm_actions.dart';

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

  // ── 浏览层派生缓存（详见 media_library_vm_selection.dart） ──────────────────
  /// 浏览层派生数据的重算代数：visibleItems / currentCollections 的任一输入变化时自增。
  /// 浏览网格的唯一数据 Obx 只订阅它（订阅面收敛为 1 个 Rx），
  /// 替代旧结构「外层大 Obx + 每卡一个 Obx」的多路重查。
  final visibleVersion = 0.obs;

  /// visibleItems 派生缓存：缓存命中时网格 build 不再重跑过滤+排序+同名分组聚合。
  List<MediaLibraryItem>? _visibleItemsOut;

  /// currentCollections 派生缓存（visibleItems 的上游，一并失效）。
  List<media_api.MediaCollection>? _currentCollectionsOut;

  /// 浏览卡片派生数据懒缓存（key = item.id），与上面两个缓存同代失效。
  /// 卡片 build 从这里拿纯数据快照，不再逐卡回查 VM 的各个查询方法。
  final Map<String, BrowseCardData> _browseCardCache = {};

  /// 卡片级选中通知器缓存：id → ValueNotifier(isSelected)。
  /// 选择变化时只通知真正变化的卡片（diff），而不是让全部卡片重查。
  /// removed 的 notifier 置 false 后保留在表里：正在订阅的 ListenableBuilder
  /// 仍持有它，清表会让后续再选中时卡片收不到通知（描述见 selectionOf 注释）。
  final _selectionNotifiers = <String, ValueNotifier<bool>>{};

  /// isSelecting 的 Listenable 代理：GetX 的 RxBool 不是 Flutter Listenable
  /// （RxInterface 是 GetX 自己的接口），浏览卡片外壳的 ListenableBuilder
  /// 需要订阅它来感知选择模式进出，由下方 worker 从 RxBool 单向同步。
  final isSelectingProxy = ValueNotifier<bool>(false);

  /// isSelecting → isSelectingProxy 的同步 worker。
  Worker? _isSelectingWorker;

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

  /// 相似查找是否激活及查询词（被右击集合的名称）。
  final similarSearchQuery = ''.obs;

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

  /// collectionId → 该集合「磁盘上仍然存在」的体积与条数。
  /// 库里记录的 fileSize 不会因外部删文件而变小，父级文件夹要如实汇总现存体积
  /// 就得逐条 stat；这份数据由 [refreshCollectionLiveStats] 后台批量刷。
  final _collectionLiveStats = <String, ({BigInt size, int count})>{};

  /// 现存资源统计的刷新代数：既是 [liveStatsVersion] 的重建信号，也是汇总缓存的失效键。
  final liveStatsVersion = 0.obs;
  bool _liveStatsInFlight = false;
  bool _liveStatsDirty = false;

  /// 文件夹递归汇总缓存（子级卡片数 / 资源数 / 体积）及其输入快照。
  Map<String, MediaFolderSummary>? _folderSummaryOut;
  List<media_api.MediaFolder>? _folderSummarySrc;
  int _folderSummaryGeneration = -1;
  int _folderSummaryLiveEpoch = -1;

  /// 上次排序的输入快照（本地+远程的未排序拼接）与对应输出。
  ///
  /// MediaCollection 字段全为 final，元素实例不变即内容不变，
  /// 因此按实例身份逐项比对即可判定命中，无需版本号。
  /// 输出以 unmodifiable 暴露：全部调用方均为只读用途。
  List<media_api.MediaCollection>? _mergedCollectionsSrc;
  List<media_api.MediaCollection>? _mergedCollectionsOut;

  /// [mergedCollections] 的重算代数，供智能文件夹匹配缓存判定失效。
  int _mergedCollectionsGeneration = 0;

  /// 文件路径预热缓存的写入代数：文件名模式的智能文件夹匹配依赖它。
  int _itemPathsEpoch = 0;

  /// sfId → 智能文件夹匹配结果缓存。
  final _sfMatchCache = <String, _SmartFolderMatch>{};

  /// 视频封面异步生成版本计数器（读取即注册响应式依赖）。
  final _asyncCoverVersion = 0.obs;

  /// 封面版本号节流定时器：32ms 窗口内的多次变更合并为一次通知。
  Timer? _coverNotifyTimer;

  /// 请求刷新封面依赖 UI。
  ///
  /// 缩略图/封面任务是逐条异步完成的，原先每条完成都独立 ++ 一次计数器，
  /// 会让每张已显示卡片各自重建一次（N 条完成 × M 张卡 = N×M 次重建）。
  /// 这里合并到约 30Hz：定时器触发时的 ++ 晚于窗口内所有缓存写入，
  /// 故被丢弃的中间 ++ 不会漏掉最终状态。
  void _notifyCoverChanged() {
    if (_coverNotifyTimer?.isActive ?? false) return;
    _coverNotifyTimer = Timer(const Duration(milliseconds: 32), () {
      _coverNotifyTimer = null;
      if (isClosed) return;
      _asyncCoverVersion.value += 1;
    });
  }

  /// collectionId → 缩略图路径（仅含成功生成的条目）。
  final _collectionVideoThumbnails = <String, String>{};

  /// 本地图片条目缩略图缓存：key = 原始文件路径，value = .SlimeWorks/tmp 内缩略图路径。
  final _itemThumbnails = <String, String>{};

  /// 缩略图生成失败的文件路径集合（不重试，继续显示原图）。
  final _itemThumbFailed = <String>{};

  /// 音频封面提取返回空的集合 id（文件里确实没有内嵌封面）。
  /// 页内多次刷新会反复入队同一集合，而重建 VM 又要重新付一次 FFI 往返；
  /// 落盘的负缓存标记由 Rust 侧按文件身份维护，这里只做本页实例内的去重。
  final _audioCoverEmptyCollections = <String>{};

  /// 正在执行中的封面任务 key（contains() 只覆盖等待中任务，运行中任务需单独去重）。
  final _inFlightCoverKeys = <String>{};

  /// 封面生成是否被用户暂停（取消后自动入队逻辑不再重新入队，直到手动恢复）。
  final thumbGenerationPaused = false.obs;

  /// 同名集合分组虚拟文件夹 ID 前缀。
  static const dupGroupPrefix = 'dup-group:';

  /// 分组 ID → 所属父文件夹 ID（null = 根目录），在 visibleItems 构建时登记。
  final _dupGroupParents = <String, String?>{};

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

  /// 条目丢失状态缓存：key = "item:{itemId}:{filePath}"，避免 build 期间同步 FFI 调用。
  final _lostItems = <String, bool>{};
  final _itemCheckTimestamps = <String, int>{};

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

  /// 进页面触发的远程刷新节流窗口：距上次远程刷新完成不足此时长时跳过远程部分。
  /// 强制全量路径（首次初始化 / 节点变更 tick / 手动刷新按钮）不走这个窗口。
  static const _kRemoteRefreshThrottle = Duration(seconds: 60);

  /// 上次远程刷新完成时刻（[refreshAllOnEnter] 的节流基准）。
  DateTime? _lastRemoteRefreshAt;

  /// 浏览层派生缓存失效监听的 worker 列表（onClose 时统一销毁）。
  List<Worker>? _visibleInvalidationWorkers;

  /// 远程节点缩略图进度轮询定时器（每 2 秒）。
  Timer? _remoteThumbPollTimer;

  /// 上一轮远程缩略图进度轮询是否仍在执行（防重叠）。
  bool _remoteThumbPolling = false;

  /// 缩略图生成后触发缓存清理的防抖定时器（1 分钟后执行）。
  Timer? _trimCacheTimer;

  /// 缩略图进度"100% 完成"短暂显示防抖定时器。
  /// 避免从 (n-1)/n 直接消失，给用户视觉反馈再清空。
  Timer? _thumbCompleteTimer;

  /// 浏览层派生缓存失效监听：任一派生输入变化 → 清缓存 + visibleVersion++。
  /// 网格唯一数据 Obx 只订阅 visibleVersion，Rx 变化从「N 路全网格重建」
  /// 收敛为「1 路一次重建」。_itemPathsEpoch 为非 Rx 计数，在写入点手动调用失效。
  ///
  /// 必须在构造时就绑定：派生缓存的读写不依赖 Get 生命周期，若只等 onInitAsync
  /// 才注册，未经该生命周期的实例（如单测直接 new）会永远读到失效前的陈旧缓存。
  void _bindVisibleInvalidation() {
    _visibleInvalidationWorkers ??= [
      ever<String?>(currentFolderId, (_) => _invalidateVisible()),
      ever<String>(searchQuery, (_) => _invalidateVisible()),
      ever<String>(similarSearchQuery, (_) => _invalidateVisible()),
      ever<CollectionSortOrder>(
        collectionSortOrder,
        (_) => _invalidateVisible(),
      ),
      ever<int>(collectionOrderVersion, (_) => _invalidateVisible()),
      ever<bool>(showFavoritesOnly, (_) => _invalidateVisible()),
      ever<Set<String>>(favoriteCollectionIds, (_) => _invalidateVisible()),
      ever<List<media_api.MediaFolder>>(folders, (_) => _invalidateVisible()),
      ever<List<media_api.MediaFolder>>(
        remoteFolders,
        (_) => _invalidateVisible(),
      ),
      ever<List<media_api.MediaCollection>>(
        collections,
        (_) => _invalidateVisible(),
      ),
      ever<List<media_api.MediaCollection>>(
        remoteCollections,
        (_) => _invalidateVisible(),
      ),
      ever<List<SmartFolder>>(smartFolders, (_) => _invalidateVisible()),
      ever<Map<String, List<SmartFolder>>>(
        _remoteSmartFolders,
        (_) => _invalidateVisible(),
      ),
      ever<int>(_searchVersion, (_) => _invalidateVisible()),
      // 封面/存活统计落地后需要卡片换图换数（32ms 节流后的全局版本）
      ever<int>(_asyncCoverVersion, (_) => _invalidateVisible()),
      ever<int>(liveStatsVersion, (_) => _invalidateVisible()),
    ];
  }

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

  /// 构造即绑定派生缓存失效监听，见 [_bindVisibleInvalidation]。
  MediaLibraryViewModel() {
    _bindVisibleInvalidation();
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
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (
      _,
    ) async {
      await refreshAll();
    });
    // isSelecting → Listenable 代理的单向同步（代理本体常驻，worker 幂等重建）
    _isSelectingWorker ??= ever<bool>(isSelecting, (v) {
      isSelectingProxy.value = v;
    });
    isSelectingProxy.value = isSelecting.value;
    // 浏览层派生缓存失效监听（构造时已绑定，onClose 销毁后此处重建）
    _bindVisibleInvalidation();
    if (isInitialized) {
      // 永久 ViewModel 再次进入页面时：刷新数据 + 重新加载智能文件夹（磁盘上的数据描和内存始终保持同步）
      _logger.info('[媒体库] onInitAsync: 已初始化，重新加载智能文件夹 + 执行数据刷新');
      // _loadSmartFolders 已在 refreshAll 内部调用，此处不重复调，避免重复读 redb
      await _loadFavorites();
      // 进页面走节流入口：本地 FFI 始终刷，远程节点 60s 窗口内不重复打接口
      await refreshAllOnEnter();
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
    // 延后到首屏渲染后执行，避免大量任务入队阻塞首帧绘制
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restorePendingThumbnailTasks();
    });
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
    _isSelectingWorker?.dispose();
    _isSelectingWorker = null;
    isSelectingProxy.dispose();
    // 浏览层派生缓存失效监听一并销毁（permanent ViewModel 理论上不关闭，此为兜底）
    final invalidationWorkers = _visibleInvalidationWorkers;
    _visibleInvalidationWorkers = null;
    for (final w in invalidationWorkers ?? const <Worker>[]) {
      w.dispose();
    }
    _remoteThumbPollTimer?.cancel();
    _remoteThumbPollTimer = null;
    _trimCacheTimer?.cancel();
    _trimCacheTimer = null;
    _thumbCompleteTimer?.cancel();
    _thumbCompleteTimer = null;
    _coverNotifyTimer?.cancel();
    _coverNotifyTimer = null;
    super.onClose();
  }

  /// 相似查找/深度搜索/远程条目路径加载（实现见 media_library_vm_search.dart）
  /// 注：_pathBasename/_isCjkChar 静态方法保留在本文件，供 search part 限定调用。

  /// 取路径的文件名部分（兼容 Windows 分隔符）。
  static String _pathBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  /// 是否为中文字符（CJK 统一表意文字 U+4E00-U+9FFF）。
  static bool _isCjkChar(int rune) => rune >= 0x4E00 && rune <= 0x9FFF;

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

  /// 资源管理操作 / 远程节点身份解析 / 媒体源构建
  /// （实现见 media_library_vm_actions.dart / media_library_vm_sources.dart）

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

  /// 封面/缩略图生成与文件夹封面（实现见 media_library_vm_sources.dart）

  static const int _kHoverScrubFrames = 20;
  final _hoverSourcesCache = <String, List<String?>>{};

  /// collectionId → 集合内按均匀采样的视频路径列表（用于实时取帧）。
  final _hoverVideoPathsCache = <String, List<String>>{};

  /// 悬停预览 / 实时取帧 / scrub 帧预取（实现见 media_library_vm_sources.dart）

  /// 文件夹/集合体积汇总（实现见 media_library_vm_browse.dart）

  /// 刷新「磁盘上仍然存在」的资源体积与条数（Rust 侧并发逐文件 stat）。
  ///
  /// 全库扫描有真实开销，所以不挂在首屏链路上：每次 loadCollections 之后补一轮，
  /// 期间再来请求就标记脏，本轮跑完补一次，保证删除动作最终会反映到父级汇总上。
  /// 数据刷新 / 缓存预热 / 集合项加载（实现见 media_library_vm_refresh.dart）
  /// 收藏相关（实现见 media_library_vm_favorites.dart）

  /// 集合进入/退出、文件夹导航、选择模式
  /// （实现见 media_library_vm_navigation.dart / media_library_vm_selection.dart）

  /// 悬停悔放帧 / 音频封面 / 远程节点身份解析 / 工具解析
  /// （实现见 media_library_vm_sources.dart / media_library_vm_actions.dart）
}

/// [MediaLibraryViewModel.folderSummary] 的结果：文件夹卡片的三个展示口径。
class MediaFolderSummary {
  const MediaFolderSummary({
    required this.childCards,
    required this.resources,
    required this.size,
  });

  /// 点开该文件夹能看到的卡片数（直接子文件夹 + 本层集合，同名集合算一张）。
  final int childCards;

  /// 子树内仍然存在的资源条数。
  final int resources;

  /// 子树内仍然存在的资源体积。
  final BigInt size;

  /// BigInt.zero 不是编译期常量，所以这里只能是 final。
  static final empty = MediaFolderSummary(
    childCards: 0,
    resources: 0,
    size: BigInt.zero,
  );
}

/// [MediaLibraryViewModel.collectionsMatchingSmartFolder] 的一条缓存记录。
class _SmartFolderMatch {
  const _SmartFolderMatch({
    required this.sf,
    required this.generation,
    required this.pathsEpoch,
    required this.collections,
  });

  final SmartFolder sf;

  /// 生成时 mergedCollections 的重算代数。
  final int generation;

  /// 生成时文件路径预热缓存的代数（文件名模式匹配依赖它）。
  final int pathsEpoch;

  final List<media_api.MediaCollection> collections;
}
