part of 'media_library_viewmodel.dart';

/// 远程节点数据刷新操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension RemoteNodeOperationsExt on MediaLibraryViewModel {
  /// 轮询所有已启用远程节点的缩略图生成进度，合计后写入 [remoteThumbProgress]。
  /// 节点不可达时忽略本轮结果，避免误清正在显示的进度。
  ///
  /// 只轮询「当前在线且未熔断」的节点：死节点的复活探测交给进页面/手动刷新时的
  /// recheckOfflineNodes，轮询这条常驻链路不再每 15s（忙时 2s）对每个死节点付
  /// 一整轮确认档复探（审计 H1：K 个死节点每轮 K×3s 常驻探测流量）。
  /// 节点恢复时 libraryMutationTick 触发全量刷新，自然重新纳入轮询。
  /// 公开供定时器与单测直接驱动（无其它生产调用方）。
  Future<void> pollRemoteThumbProgress() async {
    if (_remoteThumbPolling) return;
    final nodes = nodeSettingsService.enabledRemoteNodes
        .where((n) =>
            !nodeSettingsService.isNodeCircuitBreaked(n.id) &&
            nodeSettingsService.nodeConnectivity[n.id] == true)
        .toList(growable: false);
    if (nodes.isEmpty) {
      if (remoteThumbProgress.value != null) {
        remoteThumbProgress.value = null;
      }
      // 一个启用节点都没有：停表（与旧行为一致，启用节点由 UI 操作触发
      // refreshAll 重新拉起）。有启用节点但全离线：维持 15s 心跳，
      // 节点恢复连接后（checkNodeConnectivity 只写 nodeConnectivity）
      // 下一轮能自动纳入，不必等用户再进一次页面
      if (nodeSettingsService.enabledRemoteNodes.isNotEmpty) {
        _scheduleRemoteThumbPoll(const Duration(seconds: 15));
      }
      return;
    }
    _remoteThumbPolling = true;
    // 每 2s 一轮，只在明显变慢时留痕（这条链一慢就会连带拖住首屏取数）
    final trace = TimingTrace('轮询远程缩略图进度', scope: '${nodes.length}个节点');
    try {
      // 节点间并发：旧串行 for 里一个挂起节点会吞掉整轮 54s+（审计 H2 的
      // 轮询侧），并发后本轮墙钟 = 最慢单节点，快节点的进度不被扣住
      final results = await Future.wait(nodes.map((node) async {
        try {
          final response = await nodeSettingsService.callNodeAction(
            nodeId: node.id,
            action: 'get_thumb_progress',
          );
          final data = response['data'];
          if (data is Map) {
            return (
              total: int.tryParse('${data['total']}') ?? 0,
              completed: int.tryParse('${data['completed']}') ?? 0,
            );
          }
        } catch (_) {
          // 单个节点失败不影响其余节点进度汇总
        }
        return (total: 0, completed: 0);
      }));
      var total = 0;
      var completed = 0;
      for (final r in results) {
        total += r.total;
        completed += r.completed;
      }
      if (total > 0 && completed < total) {
        remoteThumbProgress.value = (completed, total);
        _scheduleRemoteThumbPoll(const Duration(seconds: 2));
      } else if (total > 0 && completed >= total) {
        // 100% 完成时短暂显示再清空，给用户视觉反馈
        remoteThumbProgress.value = (completed, total);
        _remoteThumbCompleteTimer?.cancel();
        _remoteThumbCompleteTimer = Timer(const Duration(seconds: 2), () {
          final cur = remoteThumbProgress.value;
          if (cur != null && cur.$1 >= cur.$2) {
            remoteThumbProgress.value = null;
          }
        });
        _scheduleRemoteThumbPoll(const Duration(seconds: 15));
      } else {
        remoteThumbProgress.value = null;
        _scheduleRemoteThumbPoll(const Duration(seconds: 15));
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

    // 旧快照按节点分桶：某一路失败（超时/报错）时用它兜底。
    // ★ 这是「删除节点本地文件后列表整片清空、要重启才恢复」的直接修复点：
    // 删除瞬间节点正被批量删文件的负载拖着，list_media_collections 超时几乎必现，
    // 而失败的那一路在 NodeMediaMetadata 里只是一份**空列表**，旧代码照单
    // assignAll → 该节点的远程集合被清成 0 条。重启后重新取数才回来。
    final prevFoldersByNode = <String, List<media_api.MediaFolder>>{};
    for (final folder in remoteFolders) {
      final nodeId = remoteFolderNodeId[folder.id];
      if (nodeId != null) prevFoldersByNode.putIfAbsent(nodeId, () => []).add(folder);
    }
    final prevCollectionsByNode = <String, List<media_api.MediaCollection>>{};
    for (final collection in remoteCollections) {
      final nodeId = remoteCollectionNodeId[collection.id];
      if (nodeId != null) {
        prevCollectionsByNode.putIfAbsent(nodeId, () => []).add(collection);
      }
    }

    final remote = <media_api.MediaFolder>[];
    final nodeIdMap = <String, String>{};
    final nodeNameMap = <String, String>{};
    final rawIdMap = <String, String>{};

    final remoteColl = <media_api.MediaCollection>[];
    final collNodeIdMap = <String, String>{};
    final collNameMap = <String, String>{};
    final collRawIdMap = <String, String>{};
    final remoteSfMap = <String, List<SmartFolder>>{};

    final staleNodes = <String>[];

    for (final item in results) {
      final node = item.node;
      final meta = item.metadata;
      // 整节点取数失败：沿用该节点上一次成功拿到的数据，绝不当成「节点空了」。
      // 首次取数就失败时没有旧快照可沿用，这时该节点本就不该出现在列表里。
      if (meta == null) {
        staleNodes.add('${node.name}(全部)');
        _carryOverNodeEntries(
          nodeId: node.id,
          folders: prevFoldersByNode[node.id] ?? const [],
          collections: prevCollectionsByNode[node.id] ?? const [],
          smartFolders: _remoteSmartFolders[node.id] ?? const [],
          remote: remote,
          nodeIdMap: nodeIdMap,
          nodeNameMap: nodeNameMap,
          rawIdMap: rawIdMap,
          remoteColl: remoteColl,
          collNodeIdMap: collNodeIdMap,
          collNameMap: collNameMap,
          collRawIdMap: collRawIdMap,
          remoteSfMap: remoteSfMap,
        );
        continue;
      }
      // 单路失败：只把该路回退到旧快照，另外两路照常用新结果。
      if (meta.foldersOk) {
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
      } else {
        staleNodes.add('${node.name}(文件夹)');
        for (final folder in prevFoldersByNode[node.id] ??
            const <media_api.MediaFolder>[]) {
          remote.add(folder);
          final mappedNode = remoteFolderNodeId[folder.id];
          final rawId = remoteFolderRawId[folder.id];
          if (mappedNode != null) nodeIdMap[folder.id] = mappedNode;
          if (rawId != null) rawIdMap[folder.id] = rawId;
          nodeNameMap[folder.id] =
              remoteFolderNodeName[folder.id] ?? node.name;
        }
      }
      final nodeSfs = <SmartFolder>[];
      if (meta.collectionsOk) {
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
      } else {
        staleNodes.add('${node.name}(集合)');
        for (final collection in prevCollectionsByNode[node.id] ??
            const <media_api.MediaCollection>[]) {
          remoteColl.add(collection);
          final mappedNode = remoteCollectionNodeId[collection.id];
          final rawId = remoteCollectionRawId[collection.id];
          if (mappedNode != null) collNodeIdMap[collection.id] = mappedNode;
          if (rawId != null) collRawIdMap[collection.id] = rawId;
          collNameMap[collection.id] =
              remoteCollectionNodeName[collection.id] ?? node.name;
        }
      }
      if (meta.smartFoldersOk) {
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
      } else {
        staleNodes.add('${node.name}(智能文件夹)');
        final prev = _remoteSmartFolders[node.id];
        if (prev != null) remoteSfMap[node.id] = prev;
      }
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

    // 记下「集合那一路没取到」的节点：删除流程据此拒绝把「列表里没有」
    // 当成「节点上已经没有了」（否则一次超时就会把节点侧集合记录一起删掉）。
    remoteCollectionsStaleNodes
      ..clear()
      ..addAll(
        results
            .where((r) => r.metadata == null || !r.metadata!.collectionsOk)
            .map((r) => r.node.id),
      );

    if (currentFolderId.value != null && currentFolder == null) {
      currentFolderId.value = null;
    }
    trace.end(
      note: staleNodes.isEmpty ? null : '沿用旧快照: ${staleNodes.join(' | ')}',
    );
  }

  /// 整节点取数失败时把该节点上一次的远程条目原样搬进本轮结果。
  ///
  /// 映射表（节点/名称/原始 ID）一并搬回来：少了它们，这些卡片会被当成
  /// 「本地集合」渲染并出现在错误的层级里。
  void _carryOverNodeEntries({
    required String nodeId,
    required List<media_api.MediaFolder> folders,
    required List<media_api.MediaCollection> collections,
    required List<SmartFolder> smartFolders,
    required List<media_api.MediaFolder> remote,
    required Map<String, String> nodeIdMap,
    required Map<String, String> nodeNameMap,
    required Map<String, String> rawIdMap,
    required List<media_api.MediaCollection> remoteColl,
    required Map<String, String> collNodeIdMap,
    required Map<String, String> collNameMap,
    required Map<String, String> collRawIdMap,
    required Map<String, List<SmartFolder>> remoteSfMap,
  }) {
    for (final folder in folders) {
      remote.add(folder);
      final mappedNode = remoteFolderNodeId[folder.id] ?? nodeId;
      final rawId = remoteFolderRawId[folder.id];
      nodeIdMap[folder.id] = mappedNode;
      nodeNameMap[folder.id] = remoteFolderNodeName[folder.id] ?? mappedNode;
      if (rawId != null) rawIdMap[folder.id] = rawId;
    }
    for (final collection in collections) {
      remoteColl.add(collection);
      final mappedNode = remoteCollectionNodeId[collection.id] ?? nodeId;
      final rawId = remoteCollectionRawId[collection.id];
      collNodeIdMap[collection.id] = mappedNode;
      collNameMap[collection.id] =
          remoteCollectionNodeName[collection.id] ?? mappedNode;
      if (rawId != null) collRawIdMap[collection.id] = rawId;
    }
    if (smartFolders.isNotEmpty) remoteSfMap[nodeId] = smartFolders;
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
