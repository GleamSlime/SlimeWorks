part of 'media_library_viewmodel.dart';

/// 远程节点数据刷新操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension RemoteNodeOperationsExt on MediaLibraryViewModel {
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
        _logger.error('刷新远程媒体文件夹失败: ${node.name} -> $error');
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
    final remoteSfMap = <String, List<SmartFolder>>{};

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
          // 解析服务端返回的集合总大小
          final totalSizeRaw = payload['total_size'];
          if (totalSizeRaw != null) {
            _collectionSizes[syntheticId] = _parseBigIntLike(totalSizeRaw);
          }
        }
      } catch (error) {
        _logger.error('刷新远程媒体集合失败: ${node.name} -> $error');
      }

      // 获取远程节点的智能文件夹，并以 "smart-folder:remote:<nodeId>:<rawId>" 命名
      try {
        final sfPayloads = await nodeSettingsService.fetchNodeSmartFolders(node);
        final nodeSfs = <SmartFolder>[];
        for (final payload in sfPayloads) {
          final rawSfId = (payload['id'] ?? '').toString();
          if (rawSfId.isEmpty) continue;
          final syntheticSfId =
              '${MediaLibraryViewModel._remoteSmartFolderPrefix}${node.id}:$rawSfId';
          // 用合成 ID 重建 SmartFolder；targetFolderIds 在客户端无效，清空即可
          final sf = SmartFolder.fromJson({
            ...Map<String, dynamic>.from(payload as Map),
            'id': syntheticSfId,
            'targetFolderIds': <String>[],
          });
          nodeSfs.add(sf);
        }
        remoteSfMap[node.id] = nodeSfs;
      } catch (error) {
        _logger.error('刷新远程智能文件夹失败: ${node.name} -> $error');
      }
    }

    remoteCollections.assignAll(remote);
    remoteCollectionNodeId.assignAll(nodeIdMap);
    remoteCollectionNodeName.assignAll(nodeNameMap);
    remoteCollectionRawId.assignAll(rawIdMap);
    _remoteSmartFolders.assignAll(remoteSfMap);
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
      kind: kindRaw == 'video'
          ? media_api.MediaKind.video
          : kindRaw == 'audio'
          ? media_api.MediaKind.audio
          : media_api.MediaKind.image,
      fileSize: _parseBigIntLike(payload['file_size']),
      modifiedAt: _parseIntLike(payload['modified_at']),
      width: _parseNullableIntLike(payload['width']),
      height: _parseNullableIntLike(payload['height']),
      durationMs: durationMsRaw == null ? null : _parseBigIntLike(durationMsRaw),
      order: _parseIntLike(payload['order']),
    );
  }
}
