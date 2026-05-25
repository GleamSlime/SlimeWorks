part of 'novel_library_viewmodel.dart';

/// 文件夹导航 / CRUD 以及书籍 CRUD / 元数据操作
extension NovelLibraryNovelOps on NovelLibraryViewModel {
  bool _isHiddenNovelPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      if (segment.startsWith('.') || segment.startsWith('._')) {
        return true;
      }
    }
    return false;
  }

  String _normalizePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.replaceAll(RegExp('/+'), '/');
  }

  String? _extractLeafFolderName({required String scanRoot, required String filePath}) {
    final root = _normalizePath(scanRoot).replaceAll(RegExp(r'/+$'), '');
    final normalizedPath = _normalizePath(filePath);
    final rootPrefix = '$root/';

    if (!normalizedPath.startsWith(rootPrefix)) {
      return null;
    }

    final relativePath = normalizedPath.substring(rootPrefix.length);
    final segments = relativePath.split('/');
    if (segments.length < 2) {
      return null;
    }

    final leaf = segments[segments.length - 2].trim();
    if (leaf.isEmpty || leaf == '.' || leaf.startsWith('.') || leaf.startsWith('._')) {
      return null;
    }

    return leaf;
  }

  Future<String> _ensureChildFolderForScan({
    required String parentId,
    required String folderName,
    required Map<String, String> cache,
  }) async {
    final cached = cache[folderName];
    if (cached != null) {
      return cached;
    }

    final existed = folders.firstWhereOrNull((f) => f.parentId == parentId && f.name == folderName);
    if (existed != null) {
      cache[folderName] = existed.id;
      return existed.id;
    }

    try {
      final created = rust_api.createChildFolder(name: folderName, parentId: parentId);
      cache[folderName] = created.id;
      if (!folders.any((f) => f.id == created.id)) {
        folders.add(created);
      }
      return created.id;
    } catch (_) {
      await loadFolders();
      final fallback = folders.firstWhereOrNull(
        (f) => f.parentId == parentId && f.name == folderName,
      );
      if (fallback != null) {
        cache[folderName] = fallback.id;
        return fallback.id;
      }
      rethrow;
    }
  }

  String get _chapterCountFilePath {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    final base = appData != null
        ? '$appData${Platform.pathSeparator}slimeworks'
        : Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}chapter_counts.json';
  }

  Future<void> loadChapterCounts() async {
    try {
      final file = File(_chapterCountFilePath);
      if (!file.existsSync()) return;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final loaded = <String, int>{};
      decoded.forEach((key, value) {
        if (value is int) {
          loaded[key] = value;
        } else if (value is num) {
          loaded[key] = value.toInt();
        }
      });
      chapterCountMap.assignAll(loaded);
    } catch (e) {
      if (kDebugMode) {
        _logger.error('[章节数] 加载失败: $e');
      }
    }
  }

  Future<void> saveChapterCounts() async {
    try {
      final file = File(_chapterCountFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(chapterCountMap), encoding: const Utf8Codec());
    } catch (e) {
      if (kDebugMode) {
        _logger.error('[章节数] 保存失败: $e');
      }
    }
  }

  Future<void> _computeChapterCountsForPaths(List<String> filePaths) async {
    if (filePaths.isEmpty) return;

    bool changed = false;
    for (final path in filePaths) {
      final novel = novels.firstWhereOrNull(
        (n) => n.filePath == path || n.filePath.replaceAll('\\', '/') == path.replaceAll('\\', '/'),
      );
      if (novel == null) continue;
      if (chapterCountMap.containsKey(novel.id)) continue;

      try {
        final content = await rust_api.getNovelContent(filePath: novel.filePath);
        chapterCountMap[novel.id] = content.chapters.length;
        changed = true;
      } catch (e) {
        _logger.log('[ChapterCount] compute failed for ${novel.id}: $e');
      }
    }

    if (changed) {
      await saveChapterCounts();
    }
  }

  // ─────────────────────────────────────────
  // 文件夹导航
  // ─────────────────────────────────────────

  void enterFolder(String folderId) {
    currentFolderId.value = folderId;
    exitSelection();
    resetPagination();
  }

  void exitFolder() {
    currentFolderId.value = null;
    exitSelection();
    resetPagination();
  }

  // ─────────────────────────────────────────
  // 文件夹 CRUD
  // ─────────────────────────────────────────

  /// 创建文件夹（名称由界面层弹窗获取）
  /// 如果当前在文件夹内，则创建为当前文件夹的子文件夹
  Future<void> createFolderWithName(String name) async {
    if (name.isEmpty) return;
    try {
      final parentId = currentFolderId.value;
      if (parentId != null) {
        createChildFolder(name: name, parentId: parentId);
      } else {
        createFolder(name: name);
      }
      await loadFolders();
      showSnack('成功', '已创建文件夹 "$name"');
    } catch (e) {
      showSnack('错误', '创建文件夹失败: $e');
    }
  }

  /// 重命名文件夹
  Future<void> renameFolder(String folderId, String name) async {
    if (name.isEmpty) return;
    try {
      rust_api.renameFolder(folderId: folderId, name: name);
      await loadFolders();
    } catch (e) {
      showSnack('错误', '重命名失败: $e');
    }
  }

  /// 删除文件夹（书籍移至根目录）
  Future<void> deleteFolder(String folderId) async {
    try {
      rust_api.deleteFolder(folderId: folderId);
      await loadData();
      showSnack('成功', '已删除文件夹');
    } catch (e) {
      showSnack('错误', '删除文件夹失败: $e');
    }
  }

  /// 删除文件夹及其中的所有书籍
  Future<void> deleteFolderWithNovels(String folderId) async {
    try {
      rust_api.deleteFolderWithNovels(folderId: folderId);
      await loadData();
      showSnack('成功', '已删除文件夹及其中所有书籍');
    } catch (e) {
      showSnack('错误', '删除文件夹失败: $e');
    }
  }

  /// 获取当前文件夹的子文件夹列表
  List<NovelFolder> getChildFolders(String parentId) {
    return folders.where((f) => f.parentId == parentId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  // ─────────────────────────────────────────
  // 书籍操作
  // ─────────────────────────────────────────

  /// 扫描文件夹（优化版，支持大量书籍）。如果当前在文件夹内，自动将扫描到的书籍归入该文件夹
  Future<void> scanFolder() async {
    try {
      _logger.log('[ScanDebug] 触发 scanFolder，platform=${Platform.operatingSystem}', name: '书库');
      scanStatusText.value = '准备扫描...';
      scanProgressText.value = '';
      if (Platform.isIOS || Platform.isAndroid) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt', 'epub'],
          allowMultiple: true,
        );
        if (picked == null || picked.files.isEmpty) {
          showSnack('提示', '已取消导入');
          return;
        }

        final paths = picked.files.map((f) => f.path).whereType<String>().toList();
        if (paths.isEmpty) {
          showSnack('错误', '未获取到可导入的文件路径');
          scanStatusText.value = '';
          return;
        }

        scanStatusText.value = '导入中...';
        scanProgressText.value = '0/${paths.length}';

        final fid = currentFolderId.value;
        if (fid != null) {
          addNovelToFolder(filePaths: paths, folderId: fid);
        } else {
          addNovel(filePaths: paths);
        }
        await loadNovels();
        await _computeChapterCountsForPaths(paths);
        await _autoTagByPaths(paths);
        scanStatusText.value = '';
        scanProgressText.value = '';
        showSnack('成功', '已导入 ${paths.length} 本书籍');
        return;
      }

      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) {
        showSnack('提示', '已取消扫描');
        _logger.log('[ScanDebug] 用户取消目录选择', name: '书库');
        return;
      }
      showSnack('扫描中', '正在扫描目录，请稍候...', duration: const Duration(seconds: 1));
      _logger.log('[ScanDebug] 已选择目录: $result', name: '书库');
      scanStatusText.value = '扫描中...';

      isScanning.value = true;
      final scanRoot = result;
      final fid = currentFolderId.value;
      final childFolderIdCache = <String, String>{};
      if (fid != null) {
        for (final folder in folders.where((f) => f.parentId == fid)) {
          childFolderIdCache[folder.name] = folder.id;
        }
      }

      final batches = await scanNovelsFolderBatched(
        folderPath: scanRoot,
        batchSize: BigInt.from(100),
      );
      _logger.log('[ScanDebug] Rust返回批次数: ${batches.length}', name: '书库');

      int totalFound = 0;
      final allScannedPaths = <String>[];
      for (final batch in batches) {
        scanProgressText.value = '${batch.completed}/${batch.total}';
        final visibleNovels = <NovelMetadata>[];
        for (final novel in batch.novels) {
          if (_isHiddenNovelPath(novel.filePath)) {
            rust_api.removeNovel(novelId: novel.id);
            continue;
          }
          visibleNovels.add(novel);
        }

        totalFound += visibleNovels.length;
        allScannedPaths.addAll(visibleNovels.map((n) => n.filePath));
        await loadNovels();

        // 如果在文件夹内，按扫描路径自动创建子文件夹并归类书籍
        if (fid != null) {
          for (final novel in visibleNovels) {
            final leafFolder = _extractLeafFolderName(scanRoot: scanRoot, filePath: novel.filePath);
            String targetFolderId = fid;

            if (leafFolder != null) {
              targetFolderId = await _ensureChildFolderForScan(
                parentId: fid,
                folderName: leafFolder,
                cache: childFolderIdCache,
              );
              _logger.log(
                '[ScanDebug] 目录映射: file=${novel.filePath} -> childFolder=$leafFolder($targetFolderId)',
                name: '书库',
              );
            }

            rust_api.moveNovelToFolder(novelId: novel.id, folderId: targetFolderId);
          }
          await loadNovels();
          await loadFolders();
        }

        if (!batch.isFinished) {
          showSnack(
            '扫描中',
            '已扫描 ${batch.completed}/${batch.total} 个文件，找到 $totalFound 本书籍',
            duration: const Duration(seconds: 1),
          );
        }
      }

      await loadNovels();
      await _computeChapterCountsForPaths(allScannedPaths);
      // 对本次扫描中的新书籍应用 Dart 端关键词规则
      await _autoTagByPaths(allScannedPaths);
      scanStatusText.value = '';
      scanProgressText.value = '';
      showSnack('成功', '扫描完成，共找到 $totalFound 本新书籍');
    } catch (e) {
      scanStatusText.value = '';
      scanProgressText.value = '';
      showSnack('错误', '扫描失败: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// 添加单个书籍。如果当前在文件夹内，自动将导入的书籍归入该文件夹
  Future<void> addSingleNovel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      final paths = result.files.map((f) => f.path!).toList();
      final fid = currentFolderId.value;
      if (fid != null) {
        addNovelToFolder(filePaths: paths, folderId: fid);
      } else {
        addNovel(filePaths: paths);
      }
      await loadNovels();
      await _computeChapterCountsForPaths(paths);
      await _autoTagByPaths(paths);
      showSnack('成功', '已添加 ${result.files.length} 本书籍');
    } catch (e) {
      showSnack('错误', '添加书籍失败: $e');
    }
  }

  /// 删除书籍
  Future<void> deleteNovel(String novelId) async {
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.deleteNodeNovel(nodeId: nodeId, novelId: rawId);
        await refreshRemoteNovels();
        showSnack('成功', '已删除远程书籍');
        return;
      }

      removeNovel(novelId: novelId);
      novels.removeWhere((n) => n.id == novelId);
      chapterCountMap.remove(novelId);
      await saveChapterCounts();
      showSnack('成功', '已删除书籍');
    } catch (e) {
      showSnack('错误', '删除失败: $e');
    }
  }

  /// 清空所有书籍（由界面层完成二次确认后调用）
  Future<void> clearAllNovelsAction() async {
    try {
      isClearingNovels.value = true;
      clearAllNovels();
      await Future.delayed(const Duration(milliseconds: 100));
      await loadData();
      chapterCountMap.clear();
      await saveChapterCounts();
      showSnack('成功', '已清空所有书籍');
    } catch (e) {
      showSnack('错误', '清空失败: $e');
    } finally {
      isClearingNovels.value = false;
    }
  }

  /// 将书籍移动到指定文件夹（folderId 为 null 时移回根目录）
  Future<void> moveNovelToFolder(String novelId, String? folderId) async {
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.moveNodeNovelToFolder(
          nodeId: nodeId,
          novelId: rawId,
          folderId: folderId,
        );
        await refreshRemoteNovels();
        return;
      }
      rust_api.moveNovelToFolder(novelId: novelId, folderId: folderId);
      await loadNovels();
    } catch (e) {
      showSnack('错误', '移动书籍失败: $e');
    }
  }

  /// 重命名书籍
  Future<void> renameNovel(String novelId, String title) async {
    if (title.isEmpty) return;
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.updateNodeNovelInfo(nodeId: nodeId, novelId: rawId, title: title);
        await refreshRemoteNovels();
        return;
      }

      rust_api.renameNovel(novelId: novelId, title: title);
      await loadNovels();
    } catch (e) {
      showSnack('错误', '重命名失败: $e');
    }
  }

  /// 切换书籍收藏状态
  Future<void> toggleFavorite(String novelId) async {
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        final novel = remoteNovels.firstWhereOrNull((n) => n.id == novelId);
        if (nodeId == null || rawId == null || novel == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.setNodeNovelFavorite(
          nodeId: nodeId,
          novelId: rawId,
          isFavorite: !novel.isFavorite,
        );
        await refreshRemoteNovels();
        return;
      }

      final novel = novels.firstWhereOrNull((n) => n.id == novelId);
      if (novel == null) return;
      rust_api.setNovelFavorite(novelId: novelId, isFavorite: !novel.isFavorite);
      await loadNovels();
    } catch (e) {
      showSnack('错误', '收藏操作失败: $e');
    }
  }

  // ─────────────────────────────────────────
  // 书籍元数据操作
  // ─────────────────────────────────────────

  /// 更新书籍封面（会压缩图片，异步执行避免 UI 阻塞）
  Future<void> updateNovelCover(String novelId, String imagePath) async {
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.updateNodeNovelCover(
          nodeId: nodeId,
          novelId: rawId,
          imagePath: imagePath,
        );
        await refreshRemoteNovels();
        return;
      }

      // 主动清除旧封面缓存，避免 Flutter 返回旧图
      final oldCover = novels.firstWhereOrNull((n) => n.id == novelId)?.coverPath;
      if (oldCover != null) {
        try {
          FileImage(File(oldCover)).evict();
        } catch (_) {}
      }
      await rust_api.updateNovelCover(novelId: novelId, imagePath: imagePath);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await loadNovels();
    } catch (e) {
      showSnack('错误', '更新封面失败: $e');
    }
  }

  /// 批量更新书籍信息（标题、作者、备注、标签）
  Future<void> updateNovelInfo({
    required String novelId,
    String? title,
    String? author,
    String? notes,
    List<String>? tags,
  }) async {
    try {
      if (isRemoteNovel(novelId)) {
        final nodeId = getRemoteNodeId(novelId);
        final rawId = getRemoteRawNovelId(novelId);
        if (nodeId == null || rawId == null) {
          throw StateError('远程节点映射不存在');
        }
        await nodeSettingsService.updateNodeNovelInfo(
          nodeId: nodeId,
          novelId: rawId,
          title: title,
          author: author,
          notes: notes,
          tags: tags,
        );
        await refreshRemoteNovels();
        return;
      }

      rust_api.updateNovelInfo(
        novelId: novelId,
        title: title,
        author: author,
        notes: notes,
        tags: tags,
      );
      await loadNovels();
    } catch (e) {
      showSnack('错误', '更新书籍信息失败: $e');
    }
  }

  // ─────────────────────────────────────────
  // 外部拖拽文件导入
  // ─────────────────────────────────────────

  /// 从外部拖入若干文件路径，过滤出支持的格式并导入
  /// 如果当前在文件夹内，自动关联到该文件夹
  Future<void> addDroppedFiles(List<String> filePaths) async {
    final supported = filePaths
        .where((p) => p.toLowerCase().endsWith('.txt') || p.toLowerCase().endsWith('.epub'))
        .toList();
    if (supported.isEmpty) return;
    try {
      final fid = currentFolderId.value;
      if (fid != null) {
        addNovelToFolder(filePaths: supported, folderId: fid);
      } else {
        addNovel(filePaths: supported);
      }
      await loadNovels();
      await _computeChapterCountsForPaths(supported);
      await _autoTagByPaths(supported);
      showSnack('导入成功', '已导入 ${supported.length} 本书籍');
    } catch (e) {
      showSnack('错误', '导入失败: $e');
    }
  }

  /// 把一本书拖入【返回】时调用，将其移至当前文件夹的上一级
  Future<void> moveNovelToParentFolder(String novelId) async {
    final parentId = folders.firstWhereOrNull((f) => f.id == currentFolderId.value)?.parentId;
    await moveNovelToFolder(novelId, parentId);
  }
  // ─────────────────────────────────────────
  // 关键词规则管理（导入自动打标签）
  // ─────────────────────────────────────────

  /// 关键词规则欲存文件路径
  String get _keywordRulesFilePath {
    final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
    final base = appData != null
        ? '$appData${Platform.pathSeparator}slimeworks'
        : Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}keyword_rules.json';
  }

  /// 加载关键词规则（从 JSON 文件）
  Future<void> loadKeywordRules() async {
    try {
      final file = File(_keywordRulesFilePath);
      if (!file.existsSync()) return;
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      keywordRules.value = list
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, String>.from(m))
          .toList();
      _logger.log('[KeywordRules] loaded ${keywordRules.length} rules from $_keywordRulesFilePath');
    } catch (e) {
      if (kDebugMode) _logger.error('[关键词规则] 加载失败: $e');
    }
  }

  /// 保存关键词规则到 JSON 文件
  Future<void> saveKeywordRules() async {
    try {
      final file = File(_keywordRulesFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(keywordRules.toList()), encoding: const Utf8Codec());
    } catch (e) {
      if (kDebugMode) _logger.error('[关键词规则] 保存失败: $e');
    }
  }

  /// 添加一条关键词规则并保存
  Future<void> addKeywordRule(String keyword, String tag) async {
    if (keyword.trim().isEmpty) return;
    final k = keyword.trim();
    final t = tag.trim().isEmpty ? k : tag.trim();
    // 去重
    if (keywordRules.any((r) => r['keyword'] == k && r['tag'] == t)) return;
    keywordRules.add({'keyword': k, 'tag': t});
    await saveKeywordRules();
  }

  /// 按索引删除关键词规则并保存
  Future<void> removeKeywordRule(int index) async {
    if (index < 0 || index >= keywordRules.length) return;
    keywordRules.removeAt(index);
    await saveKeywordRules();
  }

  /// 对指定书籍应用关键词规则，匹配的关键词自动添加对应 tag
  Future<void> applyKeywordRulesToNovel(String novelId, String filePath) async {
    if (keywordRules.isEmpty) return;
    _logger.log(
      '[KeywordRules] apply to novel $novelId, rules=${keywordRules.length}, file=$filePath',
    );
    final currentNovel = novels.firstWhereOrNull((n) => n.id == novelId);
    if (currentNovel == null) return;
    final matchedTags = <String>{...currentNovel.tags};
    for (final rule in keywordRules) {
      final keyword = rule['keyword'] ?? '';
      final tag = rule['tag'] ?? keyword;
      if (keyword.isEmpty || tag.isEmpty) continue;
      try {
        _logger.log('[KeywordRules] checking keyword="$keyword" -> tag="$tag" for novel=$novelId');
        final matches = await searchInNovel(filePath: filePath, keyword: keyword);
        _logger.log(
          '[KeywordRules] search returned ${matches.length} matches for keyword="$keyword"',
        );
        if (matches.isNotEmpty) {
          matchedTags.add(tag);
        }
      } catch (e) {
        _logger.log('[KeywordRules] searchInNovel error for keyword="$keyword" novel=$novelId: $e');
      }
    }
    // 仅在有新 tag 时才更新
    if (matchedTags.length > currentNovel.tags.length) {
      _logger.log('[KeywordRules] updating tags for $novelId -> ${matchedTags.toList()}');
      rust_api.updateNovelTags(novelId: novelId, tags: matchedTags.toList());
    }
  }

  /// 对当前库中所有书籍批量应用关键词规则（冘倒挂载）
  Future<void> applyKeywordRulesToAll() async {
    await loadKeywordRules();
    if (keywordRules.isEmpty) {
      showSnack('提示', '请先添加关键词规则');
      return;
    }
    try {
      isScanning.value = true;
      keywordApplyCompleted.value = 0;
      keywordApplyTotal.value = novels.length;

      final rules = keywordRules
          .map(
            (rule) => rust_api.KeywordRuleInput(
              keyword: (rule['keyword'] ?? '').trim(),
              tag:
                  ((rule['tag'] ?? '').trim().isEmpty ? (rule['keyword'] ?? '') : rule['tag'] ?? '')
                      .trim(),
            ),
          )
          .where((r) => r.keyword.isNotEmpty && r.tag.isNotEmpty)
          .toList();

      if (rules.isEmpty) {
        showSnack('提示', '规则为空，请先添加有效关键词规则');
        return;
      }

      BigInt start = BigInt.zero;
      BigInt total = BigInt.zero;
      int updated = 0;

      final BigInt batchSize = BigInt.from(24);
      while (true) {
        final batch = await rust_api.applyKeywordRulesToAllNovelsBatch(
          rules: rules,
          start: start,
          batchSize: batchSize,
        );
        total = batch.total;
        updated += batch.updated.toInt();
        keywordApplyTotal.value = total.toInt();
        keywordApplyCompleted.value = batch.completed.toInt();

        if (batch.isFinished || batch.completed >= total) {
          break;
        }

        start = batch.completed;
      }

      await loadNovels();
      showSnack(
        '完成',
        '已处理 ${keywordApplyCompleted.value}/${keywordApplyTotal.value} 本书籍，更新 $updated 本',
      );
    } catch (e) {
      showSnack('错误', '批量打标失败: $e');
    } finally {
      keywordApplyCompleted.value = 0;
      keywordApplyTotal.value = 0;
      isScanning.value = false;
    }
  }

  /// 导入后对指定路径对应的新书籍追港应用关键词规则
  Future<void> _autoTagByPaths(List<String> filePaths) async {
    if (keywordRules.isEmpty) {
      _logger.log('[KeywordRules] no rules to apply, skip auto-tag');
      return;
    }
    _logger.log(
      '[KeywordRules] auto-tagging paths: ${filePaths.length}, rules=${keywordRules.length}',
    );
    for (final path in filePaths) {
      final novel = novels.firstWhereOrNull(
        (n) => n.filePath == path || n.filePath.replaceAll('\\', '/') == path.replaceAll('\\', '/'),
      );
      if (novel == null) continue;
      await applyKeywordRulesToNovel(novel.id, novel.filePath);
    }
    await loadNovels();
  }
}
