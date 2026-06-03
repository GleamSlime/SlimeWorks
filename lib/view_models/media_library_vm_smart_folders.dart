part of 'media_library_viewmodel.dart';

/// 集合排序和智能文件夹 CRUD 操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension SmartFoldersCrudExt on MediaLibraryViewModel {
  // ── 集合排序 ─────────────────────────────────────────────────────────────

  Future<void> _loadCollectionOrders() async {
    try {
      final orders = media_api.getAllCollectionOrders();
      for (final (orderKey, ids) in orders) {
        _collectionOrders[orderKey] = ids;
        _logger.info('_loadCollectionOrders: orderKey=$orderKey count=${ids.length}');
      }
      _logger.info('_loadCollectionOrders: 共加载 ${orders.length} 条排序记录');
    } catch (e) {
      _logger.error('加载集合排序失败: $e');
    }
  }

  Future<void> _saveCollectionOrder(String orderKey, List<String> ids) async {
    try {
      media_api.saveCollectionOrder(orderKey: orderKey, ids: ids);
      _logger.info('_saveCollectionOrder: orderKey=$orderKey count=${ids.length}');
    } catch (e) {
      _logger.error('保存集合排序失败: key=$orderKey err=$e');
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
    _logger.info('reorderCollection: orderKey=$orderKey newOrder=${ids.join(",")}');
    await _saveCollectionOrder(orderKey, ids);
  }

  // ── 智能文件夹 CRUD ───────────────────────────────────────────────────────

  /// 通过 FFI 从 Rust redb 加载智能文件夹（替代直接读写 JSON 文件）
  Future<void> _loadSmartFolders() async {
    try {
      final result = media_api.getAllSmartFolders();
      final loaded = result
          .map(
            (sf) => SmartFolder(
              id: sf.id,
              name: sf.name,
              regexPattern: sf.regexPattern,
              keywords: sf.keywords,
              regexTarget: _convertRegexTarget(sf.regexTarget),
              fileTypeFilter: _convertFileType(sf.fileTypeFilter),
              targetFolderIds: sf.targetFolderIds,
            ),
          )
          .toList();
      smartFolders.assignAll(loaded);
      _logger.info('[智能文件夹] ✅ 从 redb 加载成功，${loaded.length} 个智能文件夹');
    } catch (err, stack) {
      _logger.info('[智能文件夹] ❌ 加载失败 err=$err');
      _logger.info('[智能文件夹] stack=$stack');
    }
  }

  /// 立即从 Rust redb 重新加载智能文件夹，供调试时主动调用。
  Future<void> debugForceReloadSmartFolders() => _loadSmartFolders();

  SmartFolderRegexTarget _convertRegexTarget(media_api.SmartFolderRegexTarget target) {
    return switch (target) {
      media_api.SmartFolderRegexTarget.fileName => SmartFolderRegexTarget.fileName,
      _ => SmartFolderRegexTarget.collectionName,
    };
  }

  SmartFolderFileType _convertFileType(media_api.SmartFolderFileType filter) {
    return switch (filter) {
      media_api.SmartFolderFileType.images => SmartFolderFileType.images,
      media_api.SmartFolderFileType.videos => SmartFolderFileType.videos,
      _ => SmartFolderFileType.all,
    };
  }

  Future<void> createSmartFolder(
    String name,
    String pattern, {
    List<String> keywords = const [],
    List<String> targetFolderIds = const [],
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
    String? targetNodeId,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;

    if (targetNodeId != null) {
      try {
        await nodeSettingsService.callNodeAction(
          nodeId: targetNodeId,
          action: 'create_smart_folder',
          params: {
            'name': normalized,
            'regex_pattern': pattern.trim(),
            'keywords': keywords,
            'target_folder_ids': targetFolderIds,
            'regex_target': regexTarget.name,
            'file_type_filter': fileTypeFilter.name,
          },
        );
        await refreshRemoteLibrary();
        showSnack('成功', '已在节点上创建智能文件夹');
      } catch (e) {
        showSnack('错误', '在节点上创建智能文件夹失败: $e');
      }
      return;
    }

    // 本机创建：通过 FFI 调用 Rust
    try {
      final sf = media_api.createSmartFolder(
        name: normalized,
        regexPattern: pattern.trim(),
        keywords: keywords,
        regexTarget: regexTarget.name,
        fileTypeFilter: fileTypeFilter.name,
        targetFolderIds: targetFolderIds,
      );
      smartFolders.add(
        SmartFolder(
          id: sf.id,
          name: sf.name,
          regexPattern: sf.regexPattern,
          keywords: sf.keywords,
          regexTarget: _convertRegexTarget(sf.regexTarget),
          fileTypeFilter: _convertFileType(sf.fileTypeFilter),
          targetFolderIds: sf.targetFolderIds,
        ),
      );
    } catch (e) {
      _logger.error('[智能文件夹] 创建失败: $e');
      showSnack('错误', '创建智能文件夹失败: $e');
    }
  }

  Future<void> renameSmartFolder(String id, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) return;
    final existing = smartFolders.firstWhereOrNull((sf) => sf.id == id);
    if (existing == null) return;

    try {
      final sf = media_api.updateSmartFolder(
        id: id,
        name: normalized,
        regexPattern: existing.regexPattern,
        keywords: existing.keywords,
        regexTarget: existing.regexTarget.name,
        fileTypeFilter: existing.fileTypeFilter.name,
        targetFolderIds: existing.targetFolderIds,
      );
      final index = smartFolders.indexWhere((sf) => sf.id == id);
      if (index != -1) {
        smartFolders[index] = SmartFolder(
          id: sf.id,
          name: sf.name,
          regexPattern: sf.regexPattern,
          keywords: sf.keywords,
          regexTarget: _convertRegexTarget(sf.regexTarget),
          fileTypeFilter: _convertFileType(sf.fileTypeFilter),
          targetFolderIds: sf.targetFolderIds,
        );
        smartFolders.refresh();
      }
    } catch (e) {
      _logger.error('[智能文件夹] 重命名失败: $e');
    }
  }

  Future<void> editSmartFolder(
    String id, {
    required String name,
    required String pattern,
    List<String> keywords = const [],
    required List<String> targetFolderIds,
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
  }) async {
    try {
      final sf = media_api.updateSmartFolder(
        id: id,
        name: name.trim().isEmpty
            ? smartFolders.firstWhereOrNull((s) => s.id == id)?.name ?? name
            : name.trim(),
        regexPattern: pattern.trim(),
        keywords: keywords,
        regexTarget: regexTarget.name,
        fileTypeFilter: fileTypeFilter.name,
        targetFolderIds: targetFolderIds,
      );
      final index = smartFolders.indexWhere((sf) => sf.id == id);
      if (index != -1) {
        smartFolders[index] = SmartFolder(
          id: sf.id,
          name: sf.name,
          regexPattern: sf.regexPattern,
          keywords: sf.keywords,
          regexTarget: _convertRegexTarget(sf.regexTarget),
          fileTypeFilter: _convertFileType(sf.fileTypeFilter),
          targetFolderIds: sf.targetFolderIds,
        );
        smartFolders.refresh();
      }
    } catch (e) {
      _logger.error('[智能文件夹] 编辑失败: $e');
    }
  }

  Future<void> deleteSmartFolder(String id) async {
    try {
      media_api.deleteSmartFolder(id: id);
      smartFolders.removeWhere((sf) => sf.id == id);
      if (currentFolderId.value == id) {
        exitToRoot();
      }
    } catch (e) {
      _logger.error('[智能文件夹] 删除失败: $e');
    }
  }

  /// 解析 'smart-folder:remote:nodeId:rawId' 返回 (nodeId, rawId)。
  /// nodeId 是 UUID（不含冒号），rawId 可能包含冒号（如 'smart-folder:xxx'）。
  (String nodeId, String rawId)? _parseRemoteSmartFolderId(String id) {
    const prefix = 'smart-folder:remote:';
    if (!id.startsWith(prefix)) return null;
    final suffix = id.substring(prefix.length);
    // nodeId 是 UUID 格式，不含冒号，取到第一个冒号之前
    final sep = suffix.indexOf(':');
    if (sep <= 0) return null;
    return (suffix.substring(0, sep), suffix.substring(sep + 1));
  }

  /// 编辑远程节点上的智能文件夹，更新完成后刷新远程数据。
  Future<void> editRemoteSmartFolder(
    String id, {
    required String name,
    required String pattern,
    List<String> keywords = const [],
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
          'keywords': keywords,
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
