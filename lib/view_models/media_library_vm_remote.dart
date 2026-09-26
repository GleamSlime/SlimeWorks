part of 'media_library_viewmodel.dart';

/// 远程节点数据刷新操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension RemoteNodeOperationsExt on MediaLibraryViewModel {
  /// 轮询所有已启用远程节点的缩略图生成进度，合计后写入 [remoteThumbProgress]。
  /// 节点不可达时忽略本轮结果，避免误清正在显示的进度。
  Future<void> _pollRemoteThumbProgress() async {
    if (_remoteThumbPolling) return;
    final nodes = nodeSettingsService.enabledRemoteNodes;
    if (nodes.isEmpty) {
      if (remoteThumbProgress.value != null) {
        remoteThumbProgress.value = null;
      }
      return;
    }
    _remoteThumbPolling = true;
    // 每 2s 一轮，只在明显变慢时留痕（这条链一慢就会连带拖住首屏取数）
    final trace = TimingTrace('轮询远程缩略图进度', scope: '${nodes.length}个节点');
    try {
      var total = 0;
      var completed = 0;
      for (final node in nodes) {
        try {
          final response = await nodeSettingsService.callNodeAction(
            nodeId: node.id,
            action: 'get_thumb_progress',
          );
          final data = response['data'];
          if (data is Map) {
            total += int.tryParse('${data['total']}') ?? 0;
            completed += int.tryParse('${data['completed']}') ?? 0;
          }
        } catch (_) {
          // 单个节点失败不影响其余节点进度汇总
        }
      }
      if (total > 0 && completed < total) {
        remoteThumbProgress.value = (completed, total);
      } else if (total > 0 && completed >= total) {
        // 100% 完成时短暂显示再清空，给用户视觉反馈
        remoteThumbProgress.value = (completed, total);
        _thumbCompleteTimer?.cancel();
        _thumbCompleteTimer = Timer(const Duration(seconds: 2), () {
          final cur = remoteThumbProgress.value;
          if (cur != null && cur.$1 >= cur.$2) {
            remoteThumbProgress.value = null;
          }
        });
      } else {
        remoteThumbProgress.value = null;
      }
    } finally {
      trace.end(slowOnlyMs: 1000);
      _remoteThumbPolling = false;
    }
  }

  Future<void> refreshRemoteLibrary() async {
    final nodes = nodeSettingsService.enabledRemoteNodes;
    final trace = TimingTrace('刷新远程媒体库', scope: '${nodes.length}个节点');

    // 节点之间并发、节点内三路（文件夹/集合/智能文件夹）也并发：
    // 旧实现是「先所有节点的文件夹、再所有节点的集合」的串行链，
    // N 个节点首屏要付 2N 轮往返，任何一个地址慢都会把整屏拖住。
    final results = await Future.wait(
      nodes.map(_loadNodeMetadata),
    );

    final remote = <media_api.MediaFolder>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};

    final remoteColl = <media_api.MediaCollection>[];
    final collNodeIdMap = <String, String>{};
    final collNameMap = <String, String>{};
    final collRawIdMap = <String, String>{};
    final remoteSfMap = <String, List<SmartFolder>>{};

    for (final item in results) {
      final node = item.node;
      final meta = item.metadata;
      if (meta == null) {
        continue;
      }
      for (final payload in meta.folders) {
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
      final nodeSfs = <SmartFolder>[];
      for (final payload in meta.collections) {
        final rawId = (payload['id'] ?? '').toString();
        if (rawId.isEmpty) {
          continue;
        }
        final syntheticId = _buildRemoteCollectionId(node.id, rawId);
        remoteColl.add(_buildRemoteCollection(payload, syntheticId, node.id));
        collNodeIdMap[syntheticId] = node.id;
        collNameMap[syntheticId] = node.name;
        collRawIdMap[syntheticId] = rawId;
        // 解析服务端返回的集合总大小
        final totalSizeRaw = payload['total_size'];
        if (totalSizeRaw != null) {
          _collectionSizes[syntheticId] = _parseBigIntLike(totalSizeRaw);
        }
      }
      for (final payload in meta.smartFolders) {
        final rawSfId = (payload['id'] ?? '').toString();
        if (rawSfId.isEmpty) continue;
        // 用合成 ID 重建 SmartFolder；targetFolderIds 在客户端无效，清空即可
        nodeSfs.add(
          SmartFolder.fromJson({
            ...Map<String, dynamic>.from(payload),
            'id': '${MediaLibraryViewModel._remoteSmartFolderPrefix}${node.id}:$rawSfId',
            'targetFolderIds': <String>[],
          }),
        );
      }
      remoteSfMap[node.id] = nodeSfs;
    }

    remoteFolders.assignAll(remote);
    remoteFolderNodeId.assignAll(nodeIdMap);
    remoteFolderNodeName.assignAll(nodeNameMap);
    remoteFolderRawId.assignAll(rawIdMap);

    remoteCollections.assignAll(remoteColl);
    remoteCollectionNodeId.assignAll(collNodeIdMap);
    remoteCollectionNodeName.assignAll(collNameMap);
    remoteCollectionRawId.assignAll(collRawIdMap);
    _remoteSmartFolders.assignAll(remoteSfMap);

    if (currentFolderId.value != null && currentFolder == null) {
      currentFolderId.value = null;
    }
    trace.end();
  }

  Future<void> refreshRemoteCollections() async {
    await refreshRemoteLibrary();
  }

  /// 取单个节点的媒体元数据；失败只记日志并返回空结果，不连带拖垮其它节点。
  Future<_NodeMetadataResult> _loadNodeMetadata(NodeEndpoint node) async {
    final nodeTrace = TimingTrace('节点取数', scope: node.name);
    try {
      final meta = await nodeSettingsService.fetchNodeMediaMetadata(node.id);
      nodeTrace.end(
        note: '文件夹=${meta.folders.length} 集合=${meta.collections.length} '
            '智能文件夹=${meta.smartFolders.length}',
      );
      return _NodeMetadataResult(node: node, metadata: meta);
    } catch (error) {
      nodeTrace.end(note: '失败');
      _logger.error('刷新远程媒体库失败: ${node.name} -> $error');
      return _NodeMetadataResult(node: node, metadata: null);
    }
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

/// [RemoteNodeOperationsExt.refreshRemoteLibrary] 单节点取数结果。
/// 失败只落在这一行上，不连带影响其它节点。
class _NodeMetadataResult {
  const _NodeMetadataResult({required this.node, required this.metadata});

  final NodeEndpoint node;
  final NodeMediaMetadata? metadata;
}
