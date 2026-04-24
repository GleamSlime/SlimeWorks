part of 'media_library_viewmodel.dart';

/// 集合排序和智能文件夹 CRUD 操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension SmartFoldersCrudExt on MediaLibraryViewModel {
  // ── 集合排序（持久化由 Rust FFI 负责）────────────────────────────────────

  /// 从 Rust 层加载所有集合排序记录到内存缓存。
  void _loadCollectionOrders() {
    try {
      final orders = media_api.loadAllCollectionOrders();
      for (final order in orders) {
        _collectionOrders[order.key] = order.ids;
      }
      logger.d('_loadCollectionOrders: 共加载 ${orders.length} 条排序记录');
    } catch (e) {
      logger.e('加载集合排序失败: $e');
    }
  }

  /// 将单条集合排序写入 Rust 持久化层。
  void _saveCollectionOrder(String orderKey, List<String> ids) {
    try {
      media_api.saveCollectionOrder(orderKey: orderKey, ids: ids);
      logger.d('_saveCollectionOrder: orderKey=$orderKey count=${ids.length}');
    } catch (e) {
      logger.e('保存集合排序失败: key=$orderKey err=$e');
    }
  }

  /// 将 [fromId] 集合重新排序到 [toId] 的位置。
  /// 使用未经收藏过滤的完整集合列表以避免 showFavoritesOnly 时排序丢失。
  Future<void> reorderCollection(String fromId, String toId) async {
    final folderId = currentFolderId.value;
    final orderKey = folderId ?? 'root';

    // 始终使用完整（未过滤收藏）的集合列表构建排序 ID 列表，防止 showFavoritesOnly=true 时保存不完整
    final List<String> ids;
    if (folderId != null && isSmartFolder(folderId)) {
      final sf = getSmartFolder(folderId);
      ids = sf == null
          ? currentCollections.map((c) => c.id).toList()
          : mergedCollections
                .where((c) => collectionMatchesSmartFolder(sf, c))
                .map((c) => c.id)
                .toList();
    } else {
      ids = mergedCollections.where((c) => c.folderId == folderId).map((c) => c.id).toList();
    }

    // 应用当前已有的自定义排序作为基准
    final existing = _collectionOrders[orderKey];
    if (existing != null && existing.isNotEmpty) {
      ids.sort((a, b) {
        final ai = existing.indexOf(a);
        final bi = existing.indexOf(b);
        if (ai == -1 && bi == -1) return 0;
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    }

    final fromIdx = ids.indexOf(fromId);
    final toIdx = ids.indexOf(toId);
    if (fromIdx == -1 || toIdx == -1 || fromIdx == toIdx) return;
    final moved = ids.removeAt(fromIdx);
    ids.insert(toIdx, moved);
    _collectionOrders[orderKey] = ids;
    collectionOrderVersion.value++;
    logger.d('reorderCollection: orderKey=$orderKey newOrder=${ids.join(",")}');
    _saveCollectionOrder(orderKey, ids);
  }

  // ── 智能文件夹 CRUD（持久化由 Rust FFI 负责）─────────────────────────────

  /// 将 Rust FFI 返回的 [SmartFolderData] 转换为 Dart 端的 [SmartFolder]。
  SmartFolder _fromFfiSmartFolder(media_api.SmartFolderData data) {
    SmartFolderRegexTarget regexTarget;
    try {
      regexTarget = SmartFolderRegexTarget.values.byName(data.regexTarget);
    } catch (_) {
      regexTarget = SmartFolderRegexTarget.collectionName;
    }
    SmartFolderFileType fileTypeFilter;
    try {
      fileTypeFilter = SmartFolderFileType.values.byName(data.fileTypeFilter);
    } catch (_) {
      fileTypeFilter = SmartFolderFileType.all;
    }
    return SmartFolder(
      id: data.id,
      name: data.name,
      regexPattern: data.regexPattern,
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: data.targetFolderIds,
    );
  }

  /// 将 Dart 端 [SmartFolder] 列表转换为 Rust FFI 所需的 [SmartFolderData] 列表。
  List<media_api.SmartFolderData> _toFfiSmartFolders(List<SmartFolder> folders) {
    return folders
        .map(
          (sf) => media_api.SmartFolderData(
            id: sf.id,
            name: sf.name,
            regexPattern: sf.regexPattern,
            regexTarget: sf.regexTarget.name,
            fileTypeFilter: sf.fileTypeFilter.name,
            targetFolderIds: sf.targetFolderIds,
          ),
        )
        .toList();
  }

  /// 从 Rust 层加载智能文件夹到内存（同步 FFI 调用）。
  void _loadSmartFolders() {
    try {
      final data = media_api.listSmartFolders();
      final loaded = data.map(_fromFfiSmartFolder).toList();
      smartFolders.assignAll(loaded);
      logger.i('_loadSmartFolders: 加载成功，${loaded.length} 个智能文件夹');
    } catch (err) {
      logger.e('_loadSmartFolders: 加载失败 err=$err');
    }
  }

  /// 将智能文件夹列表持久化到 Rust 层（同步 FFI 调用）。
  void _saveSmartFolders() {
    try {
      media_api.saveAllSmartFolders(folders: _toFfiSmartFolders(smartFolders));
      logger.d('_saveSmartFolders: 保存成功，${smartFolders.length} 个智能文件夹');
    } catch (err) {
      logger.e('_saveSmartFolders: 保存失败 err=$err');
    }
  }

  /// 重新从 Rust 层加载智能文件夹（供调试使用）。
  void debugForceReloadSmartFolders() => _loadSmartFolders();

  Future<void> createSmartFolder(
    String name,
    String pattern, {
    List<String> targetFolderIds = const [],
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
    String? targetNodeId,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;

    // 若指定远程节点，则在节点上创建并重新拉取该节点的完整智能文件夹列表
    if (targetNodeId != null) {
      try {
        await nodeSettingsService.callNodeAction(
          nodeId: targetNodeId,
          action: 'create_smart_folder',
          params: {
            'name': normalized,
            'regex_pattern': pattern.trim(),
            'target_folder_ids': targetFolderIds,
            'regex_target': regexTarget.name,
            'file_type_filter': fileTypeFilter.name,
          },
        );
        // 重新拉取该节点的所有数据（含最新智能文件夹）
        await refreshRemoteLibrary();
        showSnack('成功', '已在节点上创建智能文件夹');
      } catch (e) {
        showSnack('错误', '在节点上创建智能文件夹失败: $e');
      }
      return;
    }

    final id =
        '${MediaLibraryViewModel._smartFolderPrefix}${DateTime.now().millisecondsSinceEpoch}';
    final sf = SmartFolder(
      id: id,
      name: normalized,
      regexPattern: pattern.trim(),
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: targetFolderIds,
    );
    smartFolders.add(sf);
    _saveSmartFolders();
  }

  Future<void> renameSmartFolder(String id, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) return;
    final index = smartFolders.indexWhere((sf) => sf.id == id);
    if (index == -1) return;
    smartFolders[index] = smartFolders[index].copyWith(name: normalized);
    smartFolders.refresh();
    _saveSmartFolders();
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
    _saveSmartFolders();
  }

  Future<void> deleteSmartFolder(String id) async {
    smartFolders.removeWhere((sf) => sf.id == id);
    _saveSmartFolders();
    if (currentFolderId.value == id) {
      exitToRoot();
    }
  }

  /// 解析 'smart-folder:remote:nodeId:rawId' 返回 (nodeId, rawId)。
  (String nodeId, String rawId)? _parseRemoteSmartFolderId(String id) {
    const prefix = 'smart-folder:remote:';
    if (!id.startsWith(prefix)) return null;
    final suffix = id.substring(prefix.length);
    final sep = suffix.indexOf(':');
    if (sep <= 0) return null;
    return (suffix.substring(0, sep), suffix.substring(sep + 1));
  }

  /// 编辑远程节点上的智能文件夹，更新完成后刷新远程数据。
  Future<void> editRemoteSmartFolder(
    String id, {
    required String name,
    required String pattern,
    required List<String> targetFolderIds,
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
  }) async {
    final parsed = _parseRemoteSmartFolderId(id);
    if (parsed == null) {
      showSnack('错误', '无效的远程智能文件夹 ID');
      return;
    }
    final (nodeId, rawId) = parsed;
    try {
      await nodeSettingsService.callNodeAction(
        nodeId: nodeId,
        action: 'update_smart_folder',
        params: {
          'id': rawId,
          'name': name.trim(),
          'regex_pattern': pattern.trim(),
          'target_folder_ids': targetFolderIds,
          'regex_target': regexTarget.name,
          'file_type_filter': fileTypeFilter.name,
        },
      );
      await refreshRemoteLibrary();
      showSnack('成功', '远程智能文件夹已更新');
    } catch (e) {
      showSnack('错误', '更新远程智能文件夹失败: $e');
    }
  }

  /// 删除远程节点上的智能文件夹，删除完成后刷新远程数据。
  Future<void> deleteRemoteSmartFolder(String id) async {
    final parsed = _parseRemoteSmartFolderId(id);
    if (parsed == null) {
      showSnack('错误', '无效的远程智能文件夹 ID');
      return;
    }
    final (nodeId, rawId) = parsed;
    try {
      await nodeSettingsService.callNodeAction(
        nodeId: nodeId,
        action: 'delete_smart_folder',
        params: {'id': rawId},
      );
      await refreshRemoteLibrary();
      if (currentFolderId.value == id) exitToRoot();
      showSnack('成功', '远程智能文件夹已删除');
    } catch (e) {
      showSnack('错误', '删除远程智能文件夹失败: $e');
    }
  }
}
