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
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaLibraryViewModel extends BaseViewModel {
  static const String _remoteCollectionPrefix = 'remote-media:';
  static const String _remoteFolderPrefix = 'remote-media-folder:';
  static const String _smartFolderPrefix = 'smart-folder:';
  static const String _smartFoldersPrefsKey = 'media_library_smart_folders';
  static const String _collectionOrderPrefsKeyPrefix = 'media_col_order_';

  final NodeSettingsService nodeSettingsService = getIt<NodeSettingsService>();
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

  /// 视频封面异步生成版本计数器（读取即注册响应式依赖）。
  final _asyncCoverVersion = 0.obs;

  /// collectionId → 缩略图路径（仅含成功生成的条目）。
  final _collectionVideoThumbnails = <String, String>{};

  /// 正在生成封面的 collectionId 集合（防重入，失败后移除允许重试）。
  final _pendingCovers = <String>{};

  /// videoPath → scrub 帧路径列表的异步缓存（仅含非空结果）。
  final _videoFrameCache = <String, Future<List<String>>>{};

  final remoteCollectionNodeId = <String, String>{}.obs;
  final remoteCollectionNodeName = <String, String>{}.obs;
  final remoteCollectionRawId = <String, String>{}.obs;
  final remoteFolderNodeId = <String, String>{}.obs;
  final remoteFolderNodeName = <String, String>{}.obs;
  final remoteFolderRawId = <String, String>{}.obs;

  Worker? _nodeMutationWorker;
  Future<void>? _refreshAllFuture;

  @override
  Future<void> onInitAsync() async {
    if (isInitialized) {
      return;
    }
    await super.onInitAsync();
    await nodeSettingsService.init();
    await _loadSmartFolders();
    await _loadCollectionOrders();
    _nodeMutationWorker ??= ever<int>(nodeSettingsService.libraryMutationTick, (_) async {
      await refreshAll();
    });
    await refreshAll();
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
    // Smart folder: filter ALL collections by regex pattern
    if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      if (sf == null) return [];
      return _applySortOrder(
        mergedCollections.where((c) => sf.matches(c)).toList(growable: true),
        folderId,
      );
    }
    return _applySortOrder(
      mergedCollections
          .where((collection) => collection.folderId == folderId)
          .toList(growable: true),
      folderId ?? 'root',
    );
  }

  List<media_api.MediaCollection> _applySortOrder(
    List<media_api.MediaCollection> list,
    String orderKey,
  ) {
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
      if (!_pendingCovers.contains(collection.id)) {
        _pendingCovers.add(collection.id);
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
    getVideoScrubFrames(videoPath)
        .then((frames) {
          _pendingCovers.remove(collectionId);
          if (frames.isEmpty) return; // ffmpeg 未就绪或提取失败，允许下次重试
          _collectionVideoThumbnails[collectionId] = frames[frames.length ~/ 2];
          _asyncCoverVersion.value++;
        })
        .catchError((_) {
          _pendingCovers.remove(collectionId); // 失败后允许重试
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
    final firstMatch = mergedCollections.firstWhereOrNull((c) => sf.matches(c));
    if (firstMatch == null) return null;
    return buildCollectionCoverSource(firstMatch);
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
      folders.assignAll(media_api.getAllMediaFolders());
      if (currentFolderId.value != null && currentFolder == null) {
        currentFolderId.value = null;
      }
    } catch (error) {
      showSnack('错误', '加载媒体文件夹失败: $error');
    }
  }

  Future<void> loadCollections() async {
    try {
      collections.assignAll(media_api.getAllMediaCollections());
      if (currentCollectionId.value != null && currentCollection == null) {
        exitCollection();
      }
    } catch (error) {
      showSnack('错误', '加载媒体集合失败: $error');
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
    // Snapshot scroll position for the current browse level before navigating into folder
    _browseScrollOffsets[currentFolderId.value] = savedScrollOffset.value;
    currentFolderId.value = folderId;
    exitCollection();
    exitSelection();
  }

  void exitFolder() {
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
      // 空结果（ffmpeg 当时未就绪）——移除缓存以便重试
      _videoFrameCache.remove(videoPath);
    }
    final future = _doGetScrubFrames(videoPath);
    _videoFrameCache[videoPath] = future;
    final result = await future;
    if (result.isEmpty) _videoFrameCache.remove(videoPath); // 失败不缓存
    return result;
  }

  Future<List<String>> _doGetScrubFrames(String videoPath) async {
    final ffmpegExe = await RustFFmpeg.resolvePath();
    if (ffmpegExe == null) return const <String>[];
    return _doExtractScrubFrames(videoPath, ffmpegExe);
  }

  Future<List<String>> _doExtractScrubFrames(String videoPath, String ffmpegExe) async {
    const frameCount = 12;
    final key = videoPath.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    late Directory frameDir;
    try {
      final appDir = await getApplicationSupportDirectory();
      final sep = Platform.pathSeparator;
      frameDir = Directory('${appDir.path}${sep}thumbnails${sep}scrub$sep$key');
      await frameDir.create(recursive: true);
    } catch (_) {
      return const <String>[];
    }

    // 检测视频时长（让 ffprobe 失败也无害，默认 60s）
    double duration = 60.0;
    try {
      final ffprobeExe = ffmpegExe == 'ffmpeg'
          ? 'ffprobe'
          : ffmpegExe.replaceAll(
              RegExp(r'ffmpeg(\.exe)?$'),
              Platform.isWindows ? 'ffprobe.exe' : 'ffprobe',
            );
      final probe = await Process.run(ffprobeExe, [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        videoPath,
      ]);
      duration = double.tryParse((probe.stdout as String).trim()) ?? 60.0;
    } catch (_) {}
    if (duration <= 0) duration = 60.0;

    final sep = Platform.pathSeparator;
    final paths = <String>[];
    for (int i = 0; i < frameCount; i++) {
      final outFile = File('${frameDir.path}${sep}frame_${i.toString().padLeft(2, '0')}.jpg');
      if (outFile.existsSync()) {
        paths.add(outFile.path);
        continue;
      }
      final t = duration * i / (frameCount - 1);
      final secs = t.toInt();
      final seek =
          '${(secs ~/ 3600).toString().padLeft(2, '0')}'
          ':${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}'
          ':${(secs % 60).toString().padLeft(2, '0')}';
      try {
        final result = await Process.run(ffmpegExe, [
          '-i',
          videoPath,
          '-ss',
          seek,
          '-vframes',
          '1',
          '-vf',
          'scale=320:-1',
          '-q:v',
          '5',
          '-y',
          outFile.path,
        ]);
        if (result.exitCode == 0 && outFile.existsSync()) {
          paths.add(outFile.path);
        }
      } catch (_) {}
    }
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

  Future<void> _loadSmartFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_smartFoldersPrefsKey);
      if (json != null && json.isNotEmpty) {
        smartFolders.assignAll(SmartFolder.listFromJson(json));
      }
    } catch (error) {
      logger.e('加载智能文件夹失败: $error');
    }
  }

  Future<void> _saveSmartFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_smartFoldersPrefsKey, SmartFolder.listToJson(smartFolders));
    } catch (error) {
      logger.e('保存智能文件夹失败: $error');
    }
  }

  Future<void> createSmartFolder(
    String name,
    String pattern, {
    List<String> targetFolderIds = const [],
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    final id = '$_smartFolderPrefix${DateTime.now().millisecondsSinceEpoch}';
    final sf = SmartFolder(
      id: id,
      name: normalized,
      regexPattern: pattern.trim(),
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
  }) async {
    final index = smartFolders.indexWhere((sf) => sf.id == id);
    if (index == -1) return;
    final updated = SmartFolder(
      id: id,
      name: name.trim().isEmpty ? smartFolders[index].name : name.trim(),
      regexPattern: pattern.trim(),
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

  // ── Regular Folder CRUD ──────────────────────────────────────────────────

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
