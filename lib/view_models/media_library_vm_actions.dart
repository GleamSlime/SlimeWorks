part of 'media_library_viewmodel.dart';

/// 文件操作、远程映射查询、通用辅助与解析工具。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibraryActionsExt on MediaLibraryViewModel {
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

  bool isRemoteCollection(String collectionId) =>
      remoteCollectionNodeId.containsKey(collectionId);

  bool isRemoteFolder(String folderId) =>
      remoteFolderNodeId.containsKey(folderId);

  String? getRemoteNodeId(String collectionId) =>
      remoteCollectionNodeId[collectionId];

  String? getRemoteNodeName(String collectionId) =>
      remoteCollectionNodeName[collectionId];

  String? getRemoteRawCollectionId(String collectionId) =>
      remoteCollectionRawId[collectionId];

  String? getRemoteFolderNodeId(String folderId) =>
      remoteFolderNodeId[folderId];

  String? getRemoteFolderNodeName(String folderId) =>
      remoteFolderNodeName[folderId];

  String? getRemoteRawFolderId(String folderId) => remoteFolderRawId[folderId];

  List<NodeEndpoint> get enabledRemoteNodes =>
      nodeSettingsService.enabledRemoteNodes;

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
          SnackBar(
            content: Text('$title：$message'),
            behavior: SnackBarBehavior.floating,
          ),
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

    final children = mergedFolders.where(
      (folder) => folder.parentId == folderId,
    );
    for (final child in children) {
      final collection = _findFirstCollectionForFolder(child.id, visited: seen);
      if (collection != null) {
        return collection;
      }
    }
    return null;
  }

  String _buildRemoteCollectionId(String nodeId, String rawId) {
    return '${MediaLibraryViewModel._remoteCollectionPrefix}$nodeId:$rawId';
  }

  String _buildRemoteFolderId(String nodeId, String rawId) {
    return '${MediaLibraryViewModel._remoteFolderPrefix}$nodeId:$rawId';
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
    return BigInt.tryParse(normalized) ??
        BigInt.from(num.tryParse(normalized)?.toInt() ?? 0);
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
