part of 'media_library_viewmodel.dart';

/// 集合物理转移，集合/文件夹 CRUD 操作。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension CollectionsCrudExt on MediaLibraryViewModel {
  // ── 集合物理转移 ─────────────────────────────────────────────────────────

  /// 将 [folderId] 文件夹（或智能文件夹 [smartFolderId]）内的所有集合
  /// 物理迁移到用户选择的目标目录。
  Future<void> transferFolderCollections({String? folderId, String? smartFolderId}) async {
    // 1. 弹出文件夹选择器
    final targetRoot = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择转移目标目录');
    if (targetRoot == null || targetRoot.isEmpty) return;

    // 2. 确定集合列表
    final List<media_api.MediaCollection> toTransfer;
    final String containerName;
    if (smartFolderId != null) {
      final sf = getSmartFolder(smartFolderId);
      if (sf == null) return;
      containerName = sf.name;
      toTransfer = mergedCollections
          .where((c) {
            if (!sf.matchesCollection(c)) return false;
            if (sf.regexTarget == SmartFolderRegexTarget.fileName) {
              final paths = _collectionItemPaths[c.id] ?? const [];
              return sf.matchesFileNames(paths);
            }
            return true;
          })
          .where((c) => !isRemoteCollection(c.id))
          .toList();
    } else if (folderId != null) {
      final folder = mergedFolders.firstWhereOrNull((f) => f.id == folderId);
      if (folder == null) return;
      containerName = folder.name;
      toTransfer = mergedCollections
          .where((c) => c.folderId == folderId && !isRemoteCollection(c.id))
          .toList();
    } else {
      return;
    }

    if (toTransfer.isEmpty) {
      showSnack('提示', '该文件夹内没有可转移的本地集合');
      return;
    }

    isScanning.value = true;
    scanStatusText.value = '准备转移...';
    int successCount = 0;
    int failCount = 0;

    try {
      final sep = Platform.pathSeparator;
      final containerDir = Directory('$targetRoot$sep$containerName');

      for (final collection in toTransfer) {
        try {
          scanStatusText.value = '转移中: ${collection.title} ($successCount/${toTransfer.length})';

          final destCollectionDir = Directory('${containerDir.path}$sep${collection.title}');
          await destCollectionDir.create(recursive: true);

          final items = media_api.getMediaCollectionItems(collectionId: collection.id);

          for (final item in items) {
            final srcFile = File(item.filePath);
            if (!srcFile.existsSync()) {
              debugPrint('[Transfer] 源文件不存在，跳过: ${item.filePath}');
              continue;
            }
            final fileName = srcFile.uri.pathSegments.last;
            final destFile = File('${destCollectionDir.path}$sep$fileName');
            try {
              await srcFile.rename(destFile.path);
            } on FileSystemException {
              try {
                await srcFile.copy(destFile.path);
                await srcFile.delete();
              } catch (copyErr) {
                debugPrint('[Transfer] copy+delete 失败: ${item.filePath} err=$copyErr');
              }
            }
          }

          final newCollection = await media_api.importMediaFolder(
            folderPath: destCollectionDir.path,
          );
          if (collection.folderId != null) {
            media_api.moveMediaCollectionToFolder(
              collectionId: newCollection.id,
              folderId: collection.folderId,
            );
          }
          media_api.deleteMediaCollection(collectionId: collection.id);
          try {
            final oldDir = Directory(collection.folderPath);
            if (oldDir.existsSync() && oldDir.listSync().isEmpty) {
              await oldDir.delete();
            }
          } catch (_) {}

          successCount++;
        } catch (e) {
          failCount++;
          debugPrint('[Transfer] 集合"${collection.title}"转移失败: $e');
        }
      }

      await refreshAll();
      if (failCount == 0) {
        showSnack('成功', '成功转移 $successCount 个集合到: $targetRoot');
      } else {
        showSnack('部分完成', '成功 $successCount 个，失败 $failCount 个');
      }
    } catch (e) {
      showSnack('错误', '转移失败: $e');
      debugPrint('[Transfer] 转移异常: $e');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }

  // ── 文件夹 CRUD ──────────────────────────────────────────────────────────

  Future<void> createFolderWithName(String name, {String? targetNodeId}) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return;
    }

    try {
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

  // ── 集合扫描/导入 ────────────────────────────────────────────────────────

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
            if (rawId == null || rawId.isEmpty) continue;
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

  // ── 集合 CRUD ────────────────────────────────────────────────────────────

  /// 处理桌面端拖入的文件或文件夹路径列表。
  /// - 目录 → 调用 scanMediaFolders，递归发现子目录，每个子目录创建一个集合
  /// - 文件 → 去重后按父目录分组，对每个父目录调用 importMediaFolder
  Future<void> importDroppedPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    if (isScanning.value) return;

    isScanning.value = true;
    scanStatusText.value = '正在分析拖入文件...';

    final directoryPaths = <String>{};
    final filePaths = <String>{};
    for (final path in paths) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        directoryPaths.add(path);
      } else if (entity == FileSystemEntityType.file) {
        filePaths.add(path);
      }
    }

    // 文件：取不重复的父目录，每个目录 importMediaFolder（单集合）
    final fileParentDirs = filePaths.map((p) => File(p).parent.path).toSet();

    if (directoryPaths.isEmpty && fileParentDirs.isEmpty) {
      isScanning.value = false;
      scanStatusText.value = '';
      showSnack('提示', '未检测到有效路径');
      return;
    }

    int success = 0;
    int fail = 0;
    final targetFolderId = effectiveFolderId;

    // 目录：使用 scanMediaFolders，每个子目录创建独立集合
    for (final dir in directoryPaths) {
      scanStatusText.value = '扫描: ${dir.split(Platform.pathSeparator).last}';
      try {
        final collections = await media_api.scanMediaFolders(folderPath: dir);
        for (final collection in collections) {
          if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
            media_api.moveMediaCollectionToFolder(
              collectionId: collection.id,
              folderId: targetFolderId,
            );
          }
        }
        success += collections.length;
        if (collections.isEmpty) {
          debugPrint('[DragDrop] 目录无媒体: $dir');
        }
      } catch (e) {
        fail++;
        debugPrint('[DragDrop] 扫描目录失败: $dir => $e');
      }
    }

    // 文件父目录：importMediaFolder（单集合，只包含该目录直接文件）
    for (final dir in fileParentDirs) {
      scanStatusText.value = '导入: ${dir.split(Platform.pathSeparator).last}';
      try {
        final collection = await media_api.importMediaFolder(folderPath: dir);
        if (targetFolderId != null && !isRemoteFolder(targetFolderId)) {
          media_api.moveMediaCollectionToFolder(
            collectionId: collection.id,
            folderId: targetFolderId,
          );
        }
        success++;
      } catch (e) {
        fail++;
        debugPrint('[DragDrop] 导入失败: $dir => $e');
      }
    }

    await loadCollections();
    scanStatusText.value = '';
    isScanning.value = false;

    if (success > 0 && fail == 0) {
      showSnack('成功', '成功导入 $success 个集合');
    } else if (success > 0) {
      showSnack('部分完成', '成功 $success 个，失败 $fail 个');
    } else {
      showSnack('失败', '导入失败，请检查文件夹是否含有支持的媒体文件');
    }
  }

  /// 从相册/文件系统选取媒体，上传到当前远程集合。
  Future<void> uploadMediaToCurrentCollection() async {
    final collectionId = currentCollectionId.value;
    if (collectionId == null || !isRemoteCollection(collectionId)) return;

    final nodeId = getRemoteNodeId(collectionId);
    final rawId = getRemoteRawCollectionId(collectionId);
    if (nodeId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    isScanning.value = true;
    int success = 0;
    int fail = 0;

    for (int i = 0; i < result.files.length; i++) {
      final path = result.files[i].path;
      if (path == null) continue;
      scanStatusText.value = '上传 ${i + 1}/${result.files.length}...';
      try {
        await nodeSettingsService.uploadMediaToNode(
          nodeId: nodeId,
          localPath: path,
          collectionId: rawId,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }

    isScanning.value = false;
    scanStatusText.value = '';

    if (fail == 0) {
      showSnack('成功', '已上传 $success 个文件');
    } else {
      showSnack('部分完成', '上传 $success 成功，$fail 失败');
    }

    // 刷新远程集合列表 + 当前集合内容
    await refreshRemoteLibrary();
    await loadCurrentCollectionItems();
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
      final collectionSnapshot = collections.map((c) => c.id).toList();
      for (int i = 0; i < collectionSnapshot.length; i++) {
        media_api.deleteMediaCollection(collectionId: collectionSnapshot[i]);
        if (i % 20 == 19) await Future.delayed(Duration.zero);
      }
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
}
