part of 'media_library_viewmodel.dart';

/// 集合排序和智能文件夹 CRUD 操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension SmartFoldersCrudExt on MediaLibraryViewModel {
  // ── 集合排序 ─────────────────────────────────────────────────────────────

  Future<void> _loadCollectionOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(MediaLibraryViewModel._collectionOrderPrefsKeyPrefix)) continue;
        final orderKey = key.substring(MediaLibraryViewModel._collectionOrderPrefsKeyPrefix.length);
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
      final key = '${MediaLibraryViewModel._collectionOrderPrefsKeyPrefix}$orderKey';
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

  /// 将 [fromId] 集合重新排序到 [toId] 的位置。
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

  // ── 智能文件夹 CRUD ───────────────────────────────────────────────────────

  Future<File> _getSmartFoldersFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${MediaLibraryViewModel._smartFolderFileName}');
  }

  Future<void> _loadSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      debugPrint('[MediaLibrary] _loadSmartFolders: 文件路径=${file.path}');
      final dirExists = await file.parent.exists();
      debugPrint('[MediaLibrary] _loadSmartFolders: 父目录存在=$dirExists');
      final fileExists = await file.exists();
      debugPrint('[MediaLibrary] _loadSmartFolders: 文件存在=$fileExists');
      if (fileExists) {
        final json = await file.readAsString();
        debugPrint('[MediaLibrary] _loadSmartFolders: 读取 ${json.length} 字节');
        if (json.isNotEmpty) {
          final loaded = SmartFolder.listFromJson(json);
          smartFolders.assignAll(loaded);
          debugPrint('[MediaLibrary] _loadSmartFolders: ✅ 加载成功，${loaded.length} 个智能文件夹');
        } else {
          debugPrint('[MediaLibrary] _loadSmartFolders: 文件内容为空');
        }
      } else {
        // 迁移：从 SharedPreferences 读取旧数据
        debugPrint('[MediaLibrary] _loadSmartFolders: 文件不存在，尝试从 SharedPreferences 迁移');
        final prefs = await SharedPreferences.getInstance();
        final oldJson = prefs.getString(MediaLibraryViewModel._smartFoldersPrefsKey);
        if (oldJson != null && oldJson.isNotEmpty) {
          debugPrint('[MediaLibrary] _loadSmartFolders: SharedPreferences 迁移 ${oldJson.length} 字节');
          final List<SmartFolder> loaded = SmartFolder.listFromJson(oldJson);
          smartFolders.assignAll(loaded);
          await _saveSmartFolders();
          await prefs.remove(MediaLibraryViewModel._smartFoldersPrefsKey);
          debugPrint('[MediaLibrary] _loadSmartFolders: 迁移完成，${loaded.length} 个智能文件夹');
        } else {
          debugPrint('[MediaLibrary] _loadSmartFolders: 无历史数据，首次使用');
        }
      }
    } catch (err, stack) {
      debugPrint('[MediaLibrary] _loadSmartFolders: ❌ 加载失败 err=$err');
      debugPrint('[MediaLibrary] _loadSmartFolders: stack=$stack');
    }
  }

  /// 立即将智能文件夹列表持久化到磁盘，供调试时主动调用。
  Future<void> debugForceReloadSmartFolders() => _loadSmartFolders();

  Future<void> _saveSmartFolders() async {
    try {
      final file = await _getSmartFoldersFile();
      debugPrint('[MediaLibrary] _saveSmartFolders: 目标路径=${file.path}');
      // 确保父目录存在（Windows 上 AppData 子目录可能尚未创建）
      await file.parent.create(recursive: true);
      final json = SmartFolder.listToJson(smartFolders);
      await file.writeAsString(json, flush: true);
      // 回读验证写入成功
      final written = await file.readAsString();
      if (written == json) {
        debugPrint(
          '[MediaLibrary] _saveSmartFolders: ✅ 写入验证通过，${smartFolders.length} 个智能文件夹，${json.length} 字节',
        );
      } else {
        debugPrint(
          '[MediaLibrary] _saveSmartFolders: ❌ 内容不符！期望 ${json.length} 字节，实际 ${written.length} 字节',
        );
      }
    } catch (err, stack) {
      debugPrint('[MediaLibrary] _saveSmartFolders: ❌ 保存失败 err=$err');
      debugPrint('[MediaLibrary] _saveSmartFolders: stack=$stack');
    }
  }

  Future<void> createSmartFolder(
    String name,
    String pattern, {
    List<String> targetFolderIds = const [],
    SmartFolderRegexTarget regexTarget = SmartFolderRegexTarget.collectionName,
    SmartFolderFileType fileTypeFilter = SmartFolderFileType.all,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
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
    await _saveSmartFolders();
  }

  Future<void> deleteSmartFolder(String id) async {
    smartFolders.removeWhere((sf) => sf.id == id);
    await _saveSmartFolders();
    if (currentFolderId.value == id) {
      exitToRoot();
    }
  }
}
