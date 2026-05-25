part of 'media_library_viewmodel.dart';

/// 集合排序和智能文件夹 CRUD 操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension SmartFoldersCrudExt on MediaLibraryViewModel {
  // ── 集合排序 ─────────────────────────────────────────────────────────────

  Future<void> _loadCollectionOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int loaded = 0;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(MediaLibraryViewModel._collectionOrderPrefsKeyPrefix)) continue;
        final orderKey = key.substring(MediaLibraryViewModel._collectionOrderPrefsKeyPrefix.length);
        final json = prefs.getString(key);
        if (json != null) {
          try {
            final ids = (jsonDecode(json) as List).cast<String>();
            _collectionOrders[orderKey] = ids;
            _logger.info('_loadCollectionOrders: orderKey=$orderKey count=${ids.length}');
            loaded++;
          } catch (e) {
            _logger.error('_loadCollectionOrders: 解析失败 key=$key err=$e');
          }
        }
      }
      _logger.info('_loadCollectionOrders: 共加载 $loaded 条排序记录');
    } catch (e) {
      _logger.error('加载集合排序失败: $e');
    }
  }

  Future<void> _saveCollectionOrder(String orderKey, List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${MediaLibraryViewModel._collectionOrderPrefsKeyPrefix}$orderKey';
      if (ids.isEmpty) {
        await prefs.remove(key);
        _logger.info('_saveCollectionOrder: removed key=$key (empty)');
      } else {
        final encoded = jsonEncode(ids);
        final success = await prefs.setString(key, encoded);
        _logger.info('_saveCollectionOrder: key=$key count=${ids.length} success=$success');
      }
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

  Future<File> _getSmartFoldersFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${MediaLibraryViewModel._smartFolderFileName}');
  }

  Future<void> _loadSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      _logger.info('[智能文件夹] 文件路径=${file.path}');
      final dirExists = await file.parent.exists();
      _logger.info('[智能文件夹] 父目录存在=$dirExists');
      final fileExists = await file.exists();
      _logger.info('[智能文件夹] 文件存在=$fileExists');
      if (fileExists) {
        final json = await file.readAsString();
        _logger.info('[智能文件夹] 读取 ${json.length} 字节');
        if (json.isNotEmpty) {
          final loaded = SmartFolder.listFromJson(json);
          smartFolders.assignAll(loaded);
          _logger.info('[智能文件夹] ✅ 加载成功，${loaded.length} 个智能文件夹');
        } else {
          _logger.info('[智能文件夹] 文件内容为空');
        }
      } else {
        // 迁移：从 SharedPreferences 读取旧数据
        _logger.info('[智能文件夹] 文件不存在，尝试从 SharedPreferences 迁移');
        final prefs = await SharedPreferences.getInstance();
        final oldJson = prefs.getString(MediaLibraryViewModel._smartFoldersPrefsKey);
        if (oldJson != null && oldJson.isNotEmpty) {
          _logger.info('[智能文件夹] SharedPreferences 迁移 ${oldJson.length} 字节');
          final List<SmartFolder> loaded = SmartFolder.listFromJson(oldJson);
          smartFolders.assignAll(loaded);
          await _saveSmartFolders();
          await prefs.remove(MediaLibraryViewModel._smartFoldersPrefsKey);
          _logger.info('[智能文件夹] 迁移完成，${loaded.length} 个智能文件夹');
        } else {
          _logger.info('[智能文件夹] 无历史数据，首次使用');
        }
      }
    } catch (err, stack) {
      _logger.info('[智能文件夹] ❌ 加载失败 err=$err');
      _logger.info('[智能文件夹] stack=$stack');
    }
  }

  /// 立即将智能文件夹列表持久化到磁盘，供调试时主动调用。
  Future<void> debugForceReloadSmartFolders() => _loadSmartFolders();

  Future<void> _saveSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      _logger.info('[智能文件夹] 目标路径=${file.path}');
      // 确保父目录存在（Windows 上 AppData 子目录可能尚未创建）
      await file.parent.create(recursive: true);
      final json = SmartFolder.listToJson(smartFolders);
      await file.writeAsString(json, flush: true);
      // 回读验证写入成功
      final written = await file.readAsString();
      if (written == json) {
        _logger.info(
          '[MediaLibrary] _saveSmartFolders: ✅ 写入验证通过，${smartFolders.length} 个智能文件夹，${json.length} 字节',
        );
      } else {
        _logger.info(
          '[MediaLibrary] _saveSmartFolders: ❌ 内容不符！期望 ${json.length} 字节，实际 ${written.length} 字节',
        );
      }
    } catch (err, stack) {
      _logger.info('[智能文件夹] ❌ 保存失败 err=$err');
      _logger.info('[智能文件夹] stack=$stack');
    }
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

    final id =
        '${MediaLibraryViewModel._smartFolderPrefix}${DateTime.now().millisecondsSinceEpoch}';
    final sf = SmartFolder(
      id: id,
      name: normalized,
      regexPattern: pattern.trim(),
      keywords: keywords,
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
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
    List<String> keywords = const [],
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
      keywords: keywords,
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
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
