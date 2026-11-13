part of 'media_library_viewmodel.dart';

/// 「原路径软链」导入与重新扫描。
///
/// 语义：把拖入/选择的源目录按原始层级完整镜像成库内文件夹树（**含没有任何资源的
/// 空目录**），集合仍指向源路径（本库导入本就不拷贝文件，这里进一步明确为链接语义），
/// 并把「根文件夹 ID → 源路径」登记进 SharedPreferences，供右键/顶栏「重新扫描」
/// 做增量同步：新增目录、新增集合、新增文件、删除目录、删除文件，并重新生成封面。
///
/// 约束：仅本地桌面端可用；不动 Rust（FRB 签名全部复用现有 FFI）；
/// 删除集合/文件夹只删库记录，绝不触碰磁盘文件。
extension MediaLinkImportExt on MediaLibraryViewModel {
  /// 软链登记表持久化键（JSON：{根文件夹ID: {"path": 源目录, "name": 导入时目录名}}）。
  String get _mediaLinkRootsPrefKey => 'media_link_roots';

  /// 媒体扩展名清单（与 Rust `MediaKind::from_extension` 保持一致）。
  static const Set<String> _kLinkMediaExts = {
    // 图片
    'jpg', 'jpeg', 'jfif', 'png', 'gif', 'webp', 'bmp', 'avif', 'heic', 'heif', 'tif', 'tiff',
    // 视频
    'mp4', 'mov', 'm4v', 'mkv', 'avi', 'webm', 'wmv', 'flv', 'ts',
    // 音频
    'mp3', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wav', 'wma', 'ape', 'aiff', 'alac',
  };

  // ── 登记表读写 ───────────────────────────────────────────────────────────

  /// 从 SharedPreferences 恢复软链登记表（onInitAsync 调用一次）。
  Future<void> loadMediaLinkRoots() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_mediaLinkRootsPrefKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _mediaLinkRoots.clear();
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (entry.key is String && value is Map) {
            final path = value['path'];
            final name = value['name'];
            if (path is String && name is String) {
              _mediaLinkRoots[entry.key as String] = {'path': path, 'name': name};
            }
          }
        }
      }
    } catch (e) {
      _logger.error('[软链] 登记表解析失败: $e');
    }
  }

  /// 写回软链登记表。
  Future<void> _saveMediaLinkRoots() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_mediaLinkRootsPrefKey, jsonEncode(_mediaLinkRoots));
  }

  /// 该文件夹是否是软链导入的**根**文件夹（右键菜单据此决定是否出现「重新扫描」）。
  bool isMediaLinkFolder(String folderId) => _mediaLinkRoots.containsKey(folderId);

  /// 直接把 [folderId] 登记成软链根（仅供单测构造场景）。
  ///
  /// 生产路径一律经 [_importFolderSoftLinkSync] / [_syncMediaLinkFromDisk] 登记，
  /// 那里要连带镜像整棵目录树；单测只关心「这个文件夹是否属于软链树」的判定，
  /// 不该为此去造一棵真实目录。
  @visibleForTesting
  void debugRegisterMediaLinkRoot({
    required String folderId,
    required String sourcePath,
    String? name,
  }) {
    _mediaLinkRoots[folderId] = {
      'path': sourcePath,
      'name': name ?? _linkBaseName(sourcePath),
    };
  }

  /// 软链根对应的源目录路径（非根返回 null）。
  String? mediaLinkSourcePath(String folderId) => _mediaLinkRoots[folderId]?['path'];

  /// 从 [folderId] 沿父链上溯，返回其所属（或自身）软链根文件夹 ID；不在任何软链内返回 null。
  String? resolveMediaLinkRoot(String? folderId) {
    var cursor = folderId;
    final guard = <String>{};
    while (cursor != null && cursor.isNotEmpty && guard.add(cursor)) {
      if (_mediaLinkRoots.containsKey(cursor)) return cursor;
      cursor = mergedFolders.firstWhereOrNull((f) => f.id == cursor)?.parentId;
    }
    return null;
  }

  /// 当前浏览上下文所处软链根（顶栏「重新扫描」按钮据此切换行为）。
  /// 在 Obx 构建期调用时可正常建立响应式依赖（folders/currentFolderId 均为 Rx）。
  String? get mediaLinkRootForContext => resolveMediaLinkRoot(effectiveFolderId);

  /// 登记根文件夹已被删除（任何途径）时清掉对应表项，避免重扫幽灵路径。
  Future<void> pruneMissingMediaLinkRoots() async {
    if (_mediaLinkRoots.isEmpty) return;
    final before = _mediaLinkRoots.length;
    _mediaLinkRoots.removeWhere((rootId, _) => !folders.any((f) => f.id == rootId));
    if (_mediaLinkRoots.length != before) {
      await _saveMediaLinkRoots();
      _logger.info('[软链] 清理失效登记 ${before - _mediaLinkRoots.length} 条');
    }
  }

  // ── 磁盘遍历 ─────────────────────────────────────────────────────────────

  /// 统一分隔符、去掉 Windows 长路径前缀与结尾斜杠，用于路径前缀比较
  /// （Rust 侧存的是规范化路径，normalize_folder_path 会剥掉 \\?\ 前缀）。
  String _linkPathKey(String path) => path
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^//\?/'), '')
      .replaceAll(RegExp(r'/+$'), '');

  /// 取路径最后一段（兼容两种分隔符）。
  String _linkBaseName(String path) {
    final cut = _linkPathKey(path);
    final i = cut.lastIndexOf('/');
    return i < 0 ? cut : cut.substring(i + 1);
  }

  /// 无限深度遍历 [root]，返回「相对路径 → 该目录是否含直属媒体文件」；
  /// '' 表示根目录自身。与 Rust 扫描器同口径：跳过隐藏条目（`.`/`._` 开头）、
  /// 跟随软链（follow_links(true) 语义）并用已访问集合防环。
  Future<Map<String, bool>> _walkLinkTree(String root) async {
    final result = <String, bool>{};
    final visited = <String>{};
    try {
      visited.add(_linkPathKey(await Directory(root).resolveSymbolicLinks()));
    } catch (_) {
      visited.add(_linkPathKey(root));
    }
    final queue = <List<String>>[
      [root, ''],
    ];
    while (queue.isNotEmpty) {
      final item = queue.removeLast();
      final abs = item[0];
      final rel = item[1];
      var hasMedia = false;
      try {
        await for (final entity in Directory(abs).list(followLinks: true)) {
          final name = _linkBaseName(entity.path);
          if (name.isEmpty || name.startsWith('.') || name.startsWith('._')) continue;
          if (entity is File) {
            final dot = name.lastIndexOf('.');
            if (dot > 0 && _kLinkMediaExts.contains(name.substring(dot + 1).toLowerCase())) {
              hasMedia = true;
            }
          } else if (entity is Directory) {
            String canonical;
            try {
              canonical = await entity.resolveSymbolicLinks();
            } catch (_) {
              continue;
            }
            if (!visited.add(_linkPathKey(canonical))) continue; // 软链成环或重复挂载
            queue.add([entity.path, rel.isEmpty ? name : '$rel/$name']);
          }
        }
      } catch (e) {
        _logger.error('[软链] 目录读取失败: $abs => $e');
      }
      result[rel] = hasMedia;
    }
    return result;
  }

  /// 按层级深度升序排列相对路径（父先于子），供镜像建树时父节点必然已存在。
  List<String> _linkRelsByDepth(Iterable<String> rels) {
    final sorted = rels.toList();
    sorted.sort((a, b) {
      final depthCompare = a.split('/').length.compareTo(b.split('/').length);
      return depthCompare != 0 ? depthCompare : a.compareTo(b);
    });
    return sorted;
  }

  // ── 导入 ─────────────────────────────────────────────────────────────────

  /// 「原路径软链」导入的核心同步过程（不管理 isScanning，由调用方统一控制）。
  /// 返回 (本次入库的集合列表, 镜像文件夹数)；失败抛异常由调用方兜底提示。
  Future<(List<media_api.MediaCollection>, int)> _syncMediaLinkFromDisk({
    required String root,
    required String wrapperId,
    bool generateThumbnails = false,
  }) async {
    final rootKey = _linkPathKey(root);
    // 1) 无限深度扫描磁盘目录树
    final tree = await _walkLinkTree(root);
    // 2) 把磁盘上的**全部**目录（含空目录）镜像成文件夹节点；''=包裹根
    final nodeIds = <String, String>{'': wrapperId};
    for (final rel in _linkRelsByDepth(tree.keys.where((r) => r.isNotEmpty))) {
      final slash = rel.lastIndexOf('/');
      final parentRel = slash < 0 ? '' : rel.substring(0, slash);
      final parentId = nodeIds[parentRel];
      if (parentId == null) continue;
      nodeIds[rel] = await _findOrCreateLocalFolder(rel.substring(slash + 1), parentId);
    }
    // 3) 有媒体的目录逐个入库：scanMediaFolders 按目录建集合且自动跳过已导入路径
    final dirWithMedia = tree.entries.where((e) => e.value).map((e) => e.key).toSet();
    final created = <media_api.MediaCollection>[];
    final scanned = await media_api.scanMediaFolders(folderPath: root);
    for (final collection in scanned) {
      if (collection.itemCount == BigInt.zero) {
        media_api.deleteMediaCollection(collectionId: collection.id);
        continue;
      }
      final key = _linkPathKey(collection.folderPath);
      final rel = key == rootKey
          ? ''
          : key.startsWith('$rootKey/')
          ? key.substring(rootKey.length + 1)
          : null;
      final nodeId = (rel != null && dirWithMedia.contains(rel)) ? nodeIds[rel] : null;
      if (nodeId != null) {
        media_api.moveMediaCollectionToFolder(collectionId: collection.id, folderId: nodeId);
        created.add(collection);
      } else {
        // 磁盘上没见到该目录（并发变动的兜底）：仍入库到根，避免丢弃扫描结果
        media_api.moveMediaCollectionToFolder(collectionId: collection.id, folderId: wrapperId);
        created.add(collection);
      }
    }
    // 4) 登记源路径
    _mediaLinkRoots[wrapperId] = {'path': root, 'name': _linkBaseName(root)};
    await _saveMediaLinkRoots();
    if (generateThumbnails && created.isNotEmpty) {
      await _enqueueBulkItemThumbnails(created);
    }
    return (created, nodeIds.length - 1);
  }

  /// importFolder(softLink) 的落地过程：路径已由外层选好，
  /// isScanning / scanStatusText / 异常提示均由外层 importFolder 统一管理。
  Future<void> _importFolderSoftLinkSync({
    required String selectedPath,
    required String? targetFolderId,
    bool generateThumbnails = false,
  }) async {
    String canonical;
    try {
      canonical = await Directory(selectedPath).resolveSymbolicLinks();
    } catch (_) {
      canonical = selectedPath;
    }
    if (!Directory(canonical).existsSync()) {
      showSnack('错误', '源目录不存在: $canonical');
      return;
    }
    final dirName = _linkBaseName(canonical);
    if (dirName.isEmpty) {
      showSnack('错误', '无法从路径取得目录名');
      return;
    }
    final baseId =
        (targetFolderId != null && !isRemoteFolder(targetFolderId)) ? targetFolderId : null;
    // 每次导入独立成树：新建同名包裹夹（同名允许共存）。若复用旧夹，
    // 下方 _syncMediaLinkFromDisk 会用新源路径覆盖旧夹的软链登记，旧树就丢了
    final wrapperId = await _createLocalFolder(dirName, baseId);
    final result = await _syncMediaLinkFromDisk(
      root: canonical,
      wrapperId: wrapperId,
      generateThumbnails: generateThumbnails,
    );
    await loadFolders();
    await loadCollections();
    showSnack(
      '成功',
      '软链导入完成：${result.$1.length} 个集合、${result.$2} 个镜像文件夹（源路径已登记，可重新扫描）',
    );
  }

  /// 拖入目录的软链导入过程：返回本次入库的集合列表；
  /// isScanning / scanStatusText / try-catch 均由 importDroppedPaths 外层管理。
  Future<List<media_api.MediaCollection>> _importDroppedPathSoftLink({
    required String dir,
    required String? targetFolderId,
  }) async {
    String canonical;
    try {
      canonical = await Directory(dir).resolveSymbolicLinks();
    } catch (_) {
      canonical = dir;
    }
    final dirName = _linkBaseName(canonical);
    if (dirName.isEmpty) return const [];
    final baseId =
        (targetFolderId != null && !isRemoteFolder(targetFolderId)) ? targetFolderId : null;
    // 与点击软链导入一致：每次新建同名包裹夹，同名共存不合并、不覆盖旧登记
    final wrapperId = await _createLocalFolder(dirName, baseId);
    final result = await _syncMediaLinkFromDisk(root: canonical, wrapperId: wrapperId);
    return result.$1;
  }

  // ── 重新扫描 ─────────────────────────────────────────────────────────────

  /// 重新扫描一个软链根：磁盘 ↔ 库 全量增量同步。
  /// - 新增目录（含空目录）→ 建文件夹节点
  /// - 新增媒体目录/目录新增文件 → 导入或 rescanMediaFolder 覆盖
  /// - 目录消失 / 目录内媒体清空 → 删除集合库记录（不删磁盘文件）
  /// - 文件夹节点在磁盘上已不存在且不含任何集合 → 删除文件夹节点
  /// - 受影响集合清理封面负缓存并重新入队封面/缩略图生成
  Future<void> rescanMediaLinkFolder(String rootFolderId) async {
    if (isScanning.value) return;
    final entry = _mediaLinkRoots[rootFolderId];
    if (entry == null) {
      showSnack('提示', '该文件夹不是原路径软链文件夹');
      return;
    }
    final root = entry['path'] ?? '';
    if (root.isEmpty || !Directory(root).existsSync()) {
      await pruneMissingMediaLinkRoots();
      showSnack('错误', '源目录已不存在，无法重新扫描: $root');
      return;
    }
    isScanning.value = true;
    scanStatusText.value = '软链重新扫描: ${entry['name'] ?? _linkBaseName(root)}';
    var newCount = 0;
    var rescanCount = 0;
    var removedCount = 0;
    try {
      final rootKey = _linkPathKey(root);
      final tree = await _walkLinkTree(root);
      // 1) 现有镜像节点 rel → folderId
      final nodeIds = <String, String>{'': rootFolderId};
      final walkQueue = <List<String>>[
        [rootFolderId, ''],
      ];
      while (walkQueue.isNotEmpty) {
        final item = walkQueue.removeLast();
        final parentId = item[0];
        final rel = item[1];
        try {
          final children = await media_api.getChildMediaFolders(parentId: parentId);
          for (final child in children) {
            final childRel = rel.isEmpty ? child.name : '$rel/${child.name}';
            nodeIds[childRel] = child.id;
            walkQueue.add([child.id, childRel]);
          }
        } catch (e) {
          _logger.error('[软链] 镜像树读取失败: $parentId => $e');
        }
      }
      // 2) 磁盘目录（含空目录）补建缺失节点（父先于子）
      for (final rel in _linkRelsByDepth(tree.keys)) {
        if (rel.isEmpty || nodeIds.containsKey(rel)) continue;
        final slash = rel.lastIndexOf('/');
        final parentRel = slash < 0 ? '' : rel.substring(0, slash);
        final parentId = nodeIds[parentRel];
        if (parentId == null) continue;
        nodeIds[rel] = await _findOrCreateLocalFolder(rel.substring(slash + 1), parentId);
      }
      // 3) 磁盘新增媒体目录：scanMediaFolders 会跳过已导入路径，只回新增集合
      final touched = <media_api.MediaCollection>[];
      final scanned = await media_api.scanMediaFolders(folderPath: root);
      for (final collection in scanned) {
        if (collection.itemCount == BigInt.zero) {
          media_api.deleteMediaCollection(collectionId: collection.id);
          continue;
        }
        final key = _linkPathKey(collection.folderPath);
        final rel = key == rootKey
            ? ''
            : key.startsWith('$rootKey/')
            ? key.substring(rootKey.length + 1)
            : null;
        final nodeId = (rel != null && nodeIds.containsKey(rel))
            ? nodeIds[rel]!
            : rootFolderId;
        media_api.moveMediaCollectionToFolder(collectionId: collection.id, folderId: nodeId);
        touched.add(collection);
        newCount++;
      }
      // 4) 已在库的集合：目录存在则 rescan 覆盖（补新增文件），目录/媒体消失则删库记录
      final inside = collections
          .where((c) => !isRemoteCollection(c.id))
          .where((c) {
            final key = _linkPathKey(c.folderPath);
            return key == rootKey || key.startsWith('$rootKey/');
          })
          .toList(growable: false);
      for (final col in inside) {
        if (touched.any((t) => t.id == col.id)) continue;
        final key = _linkPathKey(col.folderPath);
        final rel = key == rootKey ? '' : key.substring(rootKey.length + 1);
        // 仅当目录本身从磁盘消失才直接删记录；目录还在但媒体清空时，
        // rescanMediaFolder 会报「No media found」，由下方 catch 按失效清理
        // （集合条目是递归口径，不能只看目录直属文件）
        final dirExists = tree.containsKey(rel);
        if (!dirExists) {
          // 目录已从磁盘消失：只删库记录，不动原始文件
          media_api.deleteMediaCollection(collectionId: col.id);
          removedCount++;
          continue;
        }
        try {
          final oldPaths = (await media_api.getMediaCollectionItems(collectionId: col.id))
              .map((item) => item.filePath)
              .toSet();
          final refreshed = await media_api.rescanMediaFolder(folderPath: col.folderPath);
          // 集合归属可能对不上镜像节点（磁盘改名/移动或人工挪动），纠回正确层级
          final nodeId = nodeIds[rel];
          if (nodeId != null && refreshed.folderId != nodeId) {
            media_api.moveMediaCollectionToFolder(collectionId: refreshed.id, folderId: nodeId);
          }
          final newItems = (await media_api.getMediaCollectionItems(collectionId: refreshed.id))
              .where((item) => !oldPaths.contains(item.filePath))
              .toList(growable: false);
          for (final item in newItems) {
            _enqueueItemThumbnail(item.filePath);
          }
          touched.add(refreshed);
          rescanCount++;
        } catch (e) {
          // 空媒体等错误按「目录失效」处理，删除旧集合记录
          removedCount++;
          media_api.deleteMediaCollection(collectionId: col.id);
          _logger.error('[软链] 重扫集合失败，按失效清理: ${col.title} => $e');
        }
      }
      // 5) 磁盘上已不存在的镜像文件夹节点：先刷集合，空壳才删（保护用户手动放入的集合）
      await loadCollections();
      final staleIds = <String, String>{}; // folderId → rel
      for (final entryPair in nodeIds.entries) {
        if (entryPair.key.isEmpty) continue;
        if (!tree.containsKey(entryPair.key)) {
          staleIds[entryPair.value] = entryPair.key;
        }
      }
      if (staleIds.isNotEmpty) {
        final protectedIds = <String>{};
        for (final col in collections) {
          final fid = col.folderId;
          if (fid != null && staleIds.containsKey(fid)) protectedIds.add(fid);
        }
        // 深层优先删除；被保护的节点连同其祖先链一并保留（避免整枝被拆散）
        final relsByDepth = staleIds.values.toList()
          ..sort((a, b) => b.split('/').length.compareTo(a.split('/').length));
        for (final rel in relsByDepth) {
          final slash = rel.lastIndexOf('/');
          final parentRel = slash < 0 ? '' : rel.substring(0, slash);
          final staleId = staleIds.entries.toList().firstWhereOrNull((e) => e.value == rel)?.key;
          if (staleId == null || protectedIds.contains(staleId)) continue;
          if (parentRel.isNotEmpty) {
            final parentId = nodeIds[parentRel];
            if (parentId != null && protectedIds.contains(parentId)) continue;
          }
          media_api.deleteMediaFolder(folderId: staleId);
          removedCount++;
        }
      }
      // 6) 封面重新生成：清负缓存 + 入队（与 rescanFolderCovers 同口径）
      if (touched.isNotEmpty) {
        if (thumbGenerationPaused.value) resumeThumbGeneration();
        for (final collection in touched) {
          _collectionCoverFailed.remove(collection.id);
          _audioCoverEmptyCollections.remove(collection.id);
        }
        _notifyCoverChanged();
        for (final collection in touched) {
          enqueueLocalCollectionCover(collection, trackFolder: false);
        }
      }
      await loadFolders();
      await loadCollections();
      final openId = currentCollectionId.value;
      if (openId != null &&
          !isRemoteCollection(openId) &&
          touched.any((c) => c.id == openId)) {
        await loadCurrentCollectionItems();
      }
      _logger.info(
        '[软链] 重扫完成: root=$root 新增 $newCount 重扫 $rescanCount 清理 $removedCount',
      );
      if (newCount + rescanCount + removedCount == 0) {
        showSnack('提示', '软链重新扫描完成，目录无变化');
      } else {
        showSnack(
          '成功',
          '软链重新扫描完成：新增 $newCount 个集合，重扫 $rescanCount 个，清理 $removedCount 项',
        );
      }
    } catch (error) {
      _logger.error('[软链] 重新扫描失败: $root => $error');
      showSnack('错误', '软链重新扫描失败: $error');
    } finally {
      isScanning.value = false;
      scanStatusText.value = '';
    }
  }
}
