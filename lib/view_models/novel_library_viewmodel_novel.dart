part of 'novel_library_viewmodel.dart';

/// 文件夹导航 / CRUD 以及书籍 CRUD / 元数据操作
extension NovelLibraryNovelOps on NovelLibraryViewModel {
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
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      isScanning.value = true;
      final fid = currentFolderId.value;

      final batches = await scanNovelsFolderBatched(
        folderPath: result,
        batchSize: BigInt.from(100),
      );

      int totalFound = 0;
      final allScannedPaths = <String>[];
      for (final batch in batches) {
        totalFound += batch.novels.length;
        allScannedPaths.addAll(batch.novels.map((n) => n.filePath));
        await loadNovels();
        // 如果在文件夹内，批量将新添加的书籍归入当前文件夹
        if (fid != null) {
          for (final novel in batch.novels) {
            rust_api.moveNovelToFolder(novelId: novel.id, folderId: fid);
          }
          await loadNovels();
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
      // 对本次扫描中的新书籍应用 Dart 端关键词规则
      await _autoTagByPaths(allScannedPaths);
      showSnack('成功', '扫描完成，共找到 $totalFound 本新书籍');
    } catch (e) {
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
      await _autoTagByPaths(paths);
      showSnack('成功', '已添加 ${result.files.length} 本书籍');
    } catch (e) {
      showSnack('错误', '添加书籍失败: $e');
    }
  }

  /// 删除书籍
  Future<void> deleteNovel(String novelId) async {
    try {
      removeNovel(novelId: novelId);
      novels.removeWhere((n) => n.id == novelId);
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
      rust_api.renameNovel(novelId: novelId, title: title);
      await loadNovels();
    } catch (e) {
      showSnack('错误', '重命名失败: $e');
    }
  }

  /// 切换书籍收藏状态
  Future<void> toggleFavorite(String novelId) async {
    try {
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
      logger.log('[KeywordRules] loaded ${keywordRules.length} rules from $_keywordRulesFilePath');
    } catch (e) {
      if (kDebugMode) print('[KeywordRules] load failed: $e');
    }
  }

  /// 保存关键词规则到 JSON 文件
  Future<void> saveKeywordRules() async {
    try {
      final file = File(_keywordRulesFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(keywordRules.toList()), encoding: const Utf8Codec());
    } catch (e) {
      if (kDebugMode) print('[KeywordRules] save failed: $e');
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
    logger.log(
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
        logger.log('[KeywordRules] checking keyword="$keyword" -> tag="$tag" for novel=$novelId');
        final matches = await searchInNovel(filePath: filePath, keyword: keyword);
        logger.log(
          '[KeywordRules] search returned ${matches.length} matches for keyword="$keyword"',
        );
        if (matches.isNotEmpty) {
          matchedTags.add(tag);
        }
      } catch (e) {
        logger.log('[KeywordRules] searchInNovel error for keyword="$keyword" novel=$novelId: $e');
      }
    }
    // 仅在有新 tag 时才更新
    if (matchedTags.length > currentNovel.tags.length) {
      logger.log('[KeywordRules] updating tags for $novelId -> ${matchedTags.toList()}');
      rust_api.updateNovelTags(novelId: novelId, tags: matchedTags.toList());
    }
  }

  /// 对当前库中所有书籍批量应用关键词规则（冘倒挂载）
  Future<void> applyKeywordRulesToAll() async {
    if (keywordRules.isEmpty) {
      showSnack('提示', '请先添加关键词规则');
      return;
    }
    try {
      isScanning.value = true;
      int processed = 0;
      for (final novel in novels.toList()) {
        await applyKeywordRulesToNovel(novel.id, novel.filePath);
        processed++;
      }
      await loadNovels();
      showSnack('完成', '已对 $processed 本书籍应用关键词规则');
    } catch (e) {
      showSnack('错误', '批量打标失败: $e');
    } finally {
      isScanning.value = false;
    }
  }

  /// 导入后对指定路径对应的新书籍追港应用关键词规则
  Future<void> _autoTagByPaths(List<String> filePaths) async {
    if (keywordRules.isEmpty) {
      logger.log('[KeywordRules] no rules to apply, skip auto-tag');
      return;
    }
    logger.log(
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
