import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaLibraryViewModel extends BaseViewModel {
  static const String _remoteCollectionPrefix = 'remote-media:';
  static const String _remoteFolderPrefix = 'remote-media-folder:';

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
  final isLoadingItems = false.obs;
  final currentFolderId = RxnString();
  final currentCollectionId = RxnString();
  final savedScrollOffset = 0.0.obs;

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

  media_api.MediaCollection? get currentCollection {
    final collectionId = currentCollectionId.value;
    if (collectionId == null) {
      return null;
    }
    return mergedCollections.firstWhereOrNull((collection) => collection.id == collectionId);
  }

  String get currentCollectionTitle => currentCollection?.title ?? '';

  String get currentBrowseTitle => currentFolder?.name ?? '媒体库';

  List<media_api.MediaFolder> get currentFolderTrail {
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
    final folderId = currentFolderId.value;
    return mergedFolders.where((folder) => folder.parentId == folderId).toList(growable: false);
  }

  List<media_api.MediaCollection> get currentCollections {
    final folderId = currentFolderId.value;
    return mergedCollections
        .where((collection) => collection.folderId == folderId)
        .toList(growable: false);
  }

  List<MediaLibraryItem> get visibleItems {
    return <MediaLibraryItem>[
      ...currentChildFolders.map(MediaLibraryFolderItem.new),
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
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    if (!isRemoteCollection(collection.id)) {
      return coverPath;
    }
    final nodeId = getRemoteNodeId(collection.id);
    if (nodeId == null) {
      return null;
    }
    return nodeSettingsService.buildNodeMediaUrl(nodeId: nodeId, filePath: coverPath);
  }

  String? buildFolderCoverSource(media_api.MediaFolder folder) {
    final collection = _findFirstCollectionForFolder(folder.id);
    if (collection == null) {
      return null;
    }
    return buildCollectionCoverSource(collection);
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
    currentCollectionId.value = collectionId;
    exitSelection();
    await loadCurrentCollectionItems();
  }

  void exitCollection() {
    currentCollectionId.value = null;
    currentItems.clear();
    exitSelection();
  }

  void enterFolder(String folderId) {
    currentFolderId.value = folderId;
    exitCollection();
    exitSelection();
  }

  void exitFolder() {
    currentFolderId.value = currentFolder?.parentId;
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

  Future<void> createFolderWithName(String name, {String? targetNodeId}) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return;
    }

    try {
      final activeFolderId = currentFolderId.value;
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
        showSnack('成功', '节点媒体目录扫描完成');
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        throw UnsupportedError('移动端请通过节点路径导入');
      }

      final selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null || selectedPath.isEmpty) {
        return;
      }
      final imported = await media_api.scanMediaFolders(folderPath: selectedPath);
      final targetFolderId = currentFolderId.value;
      if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
        for (final collection in imported) {
          media_api.moveMediaCollectionToFolder(
            collectionId: collection.id,
            folderId: targetFolderId,
          );
        }
      }
      await loadCollections();
      showSnack('成功', '目录扫描完成');
    } catch (error) {
      showSnack('错误', '扫描目录失败: $error');
    } finally {
      isScanning.value = false;
    }
  }

  Future<void> importFolder({String? folderPath, String? nodeId}) async {
    try {
      isScanning.value = true;
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
        showSnack('成功', '节点媒体目录导入完成');
        return;
      }

      if (Platform.isIOS || Platform.isAndroid) {
        throw UnsupportedError('移动端请通过节点路径导入');
      }

      final selectedPath = await FilePicker.platform.getDirectoryPath();
      if (selectedPath == null || selectedPath.isEmpty) {
        return;
      }
      final collection = await media_api.importMediaFolder(folderPath: selectedPath);
      final targetFolderId = currentFolderId.value;
      if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
        media_api.moveMediaCollectionToFolder(
          collectionId: collection.id,
          folderId: targetFolderId,
        );
      }
      await loadCollections();
      showSnack('成功', '媒体集合导入完成');
    } catch (error) {
      showSnack('错误', '导入目录失败: $error');
    } finally {
      isScanning.value = false;
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
    final folderId = currentFolderId.value;
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
