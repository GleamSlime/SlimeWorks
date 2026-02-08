import 'package:flutter/material.dart';
import 'dart:io';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 小说阅读器 ViewModel
class NovelReaderViewModel extends GetxController {
  final NovelMetadata novel;

  final chapters = <NovelChapter>[].obs;
  final currentChapterIndex = 0.obs;
  final currentContent = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final showChapterList = true.obs;
  final fontSize = 16.0.obs;
  // 搜索结果状态
  final searchMatches = <SearchMatch>[].obs;
  final selectedSearchIndex = (-1).obs;
  final searchScrollTrigger = 0.obs; // 用于触发滚动到搜索结果
  final lastSearchQuery = ''.obs; // 记录最近一次搜索的原始关键词，供 UI 高亮使用

  // HTML内容缓存，避免重复转换（key: chapterIndex）
  final Map<int, String> _processedHtmlCache = {};

  NovelReaderViewModel(this.novel);

  @override
  void onInit() {
    super.onInit();
    loadNovelContent();
  }

  void _showSnack(String title, String message, {SnackPosition? position, Color? backgroundColor, Color? colorText, Duration? duration}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Get.snackbar(title, message, snackPosition: position, backgroundColor: backgroundColor, colorText: colorText, duration: duration);
      } catch (_) {}
    });
  }

  @override
  void onClose() {
    // 清空HTML缓存
    _processedHtmlCache.clear();

    // 尝试删除基于 novel.id 的临时目录（如果存在）
    try {
      final base = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}slimeworks${Platform.pathSeparator}epub_images${Platform.pathSeparator}${novel.id}',
      );
      if (base.existsSync()) {
        base.deleteSync(recursive: true);
        debugPrint('[Novel UI] Cleared epub image cache: ${base.path}');
      }
    } catch (e) {
      debugPrint('[Novel UI] Failed to clear epub image cache: $e');
    }

    // 退出阅读器时保存当前阅读位置
    try {
      if (chapters.isNotEmpty) {
        final progress = (currentChapterIndex.value + 1) / (chapters.length);
        updateReadingProgress(novelId: novel.id, progress: progress);
        debugPrint('[Novel UI] Saved progress $progress for novel ${novel.id} on close');
      }
    } catch (e) {
      debugPrint('[Novel UI] Failed to save progress on close: $e');
    }

    super.onClose();
  }

  /// 获取已处理的HTML内容（带缓存）
  String? getCachedHtml(int chapterIndex) {
    return _processedHtmlCache[chapterIndex];
  }

  /// 缓存已处理的HTML内容
  void cacheHtml(int chapterIndex, String html) {
    _processedHtmlCache[chapterIndex] = html;
    // 限制缓存大小，只保留最近3个章节
    if (_processedHtmlCache.length > 3) {
      final keysToRemove = _processedHtmlCache.keys.toList()
        ..sort()
        ..removeRange(_processedHtmlCache.length - 3, _processedHtmlCache.length);
      for (final key in keysToRemove) {
        _processedHtmlCache.remove(key);
      }
    }
  }

  /// 加载小说内容
  Future<void> loadNovelContent() async {
    final startTime = DateTime.now();
    try {
      isLoading.value = true;
      errorMessage.value = '';

      debugPrint('[Novel UI] ========== Loading novel ==========');
      debugPrint('[Novel UI] File: ${novel.filePath}');
      debugPrint('[Novel UI] Start time: $startTime');

      debugPrint('[Novel UI] Calling Rust getNovelContent...');
      final beforeRust = DateTime.now();
      final content = await getNovelContent(filePath: novel.filePath);
      final rustDuration = DateTime.now().difference(beforeRust);
      debugPrint('[Novel UI] Rust call completed in ${rustDuration.inMilliseconds}ms');

      chapters.value = content.chapters;
      debugPrint('[Novel UI] Loaded ${chapters.length} chapters');

      if (chapters.isNotEmpty) {
        // 根据上次阅读进度恢复到对应章节
        final len = chapters.length;
        int startIndex = 0;
        try {
          final p = novel.progress;
          if (p > 0) {
            startIndex = (p * len).ceil() - 1;
            if (startIndex < 0) startIndex = 0;
            if (startIndex >= len) startIndex = len - 1;
          }
        } catch (_) {
          startIndex = 0;
        }
        debugPrint('[Novel UI] Restoring chapter index $startIndex from progress=${novel.progress}');
        // 先设置索引以更新 UI 选中状态，再加载章节内容
        currentChapterIndex.value = startIndex;
        debugPrint('[Novel UI] Set currentChapterIndex to $startIndex before loading content');
        await loadChapterContent(startIndex);
      }

      final totalDuration = DateTime.now().difference(startTime);
      debugPrint('[Novel UI] ========== Total load time: ${totalDuration.inMilliseconds}ms ==========');
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('[Novel UI] ERROR after ${duration.inMilliseconds}ms: $e');
      debugPrint('[Novel UI] Stack trace: $stackTrace');
      errorMessage.value = '加载失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 加载章节内容
  Future<void> loadChapterContent(int index) async {
    if (index < 0 || index >= chapters.length) return;

    final startTime = DateTime.now();
    try {
      isLoading.value = true;
      errorMessage.value = '';

      debugPrint('[Novel UI] --- Loading chapter $index ---');
      debugPrint('[Novel UI] Chapter title: ${chapters[index].title}');

      final beforeRust = DateTime.now();
      final content = await getChapterContent(filePath: novel.filePath, chapterIndex: BigInt.from(index));
      final rustDuration = DateTime.now().difference(beforeRust);

      debugPrint('[Novel UI] Chapter loaded in ${rustDuration.inMilliseconds}ms, length: ${content.length} chars');

      // currentChapterIndex 已由 goToChapter 设置，此处不再重复设置
      currentContent.value = content;

      // 更新阅读进度
      final progress = (index + 1) / chapters.length;
      updateReadingProgress(novelId: novel.id, progress: progress);
      print('[Reader] Updated progress for ${novel.title} to $progress (chapter ${index + 1}/${chapters.length})');

      final totalDuration = DateTime.now().difference(startTime);
      debugPrint('[Novel UI] --- Chapter display ready in ${totalDuration.inMilliseconds}ms ---');
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(startTime);
      debugPrint('[Novel UI] ERROR loading chapter after ${duration.inMilliseconds}ms: $e');
      debugPrint('[Novel UI] Stack trace: $stackTrace');
      errorMessage.value = '加载章节失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 跳转到指定章节
  void goToChapter(int index) {
    // 立即更新索引，让UI能及时响应（章节列表选中状态等）
    if (index >= 0 && index < chapters.length) {
      currentChapterIndex.value = index;
    }
    loadChapterContent(index);
  }

  /// 上一章
  void previousChapter() {
    if (hasPreviousChapter()) {
      final newIndex = currentChapterIndex.value - 1;
      currentChapterIndex.value = newIndex;
      loadChapterContent(newIndex);
    }
  }

  /// 下一章
  void nextChapter() {
    if (hasNextChapter()) {
      final newIndex = currentChapterIndex.value + 1;
      currentChapterIndex.value = newIndex;
      loadChapterContent(newIndex);
    }
  }

  /// 是否有上一章
  bool hasPreviousChapter() {
    return currentChapterIndex.value > 0;
  }

  /// 是否有下一章
  bool hasNextChapter() {
    return currentChapterIndex.value < chapters.length - 1;
  }

  /// 切换章节列表显示
  void toggleChapterList() {
    showChapterList.value = !showChapterList.value;
  }

  /// 增大字体
  void increaseFontSize() {
    if (fontSize.value < 32) {
      fontSize.value += 2;
    }
  }

  /// 减小字体
  void decreaseFontSize() {
    if (fontSize.value > 12) {
      fontSize.value -= 2;
    }
  }

  /// 显示搜索对话框
  void showSearchDialog() {
    final controller = TextEditingController();

    Get.dialog(
      AlertDialog(
        title: const Text('搜索内容'),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(hintText: '输入关键词', border: OutlineInputBorder()),
          onSubmitted: (value) {
            Get.back();
            if (value.isNotEmpty) {
              searchKeyword(value);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final keyword = controller.text;
              Get.back();
              if (keyword.isNotEmpty) {
                searchKeyword(keyword);
              }
            },
            child: const Text('搜索'),
          ),
        ],
      ),
    );
  }

  /// 搜索关键词
  Future<void> searchKeyword(String keyword) async {
    // 记录原始搜索关键词，供 ReaderContent 优先使用以确定高亮范围
    lastSearchQuery.value = keyword;
    try {
      final matches = await searchInNovel(filePath: novel.filePath, keyword: keyword);
      searchMatches.value = matches;
      selectedSearchIndex.value = matches.isNotEmpty ? 0 : -1;
      debugPrint('[Novel VM] searchKeyword: matches=${matches.length} selectedIndex=${selectedSearchIndex.value}');

      if (matches.isEmpty) {
        _showSnack('搜索', '未找到匹配内容');
        return;
      }

      // 显示搜索结果并跳转到第一个结果
      _showSearchResultsDialog(matches);

      // 如果第一个结果在当前章节，触发滚动
      if (matches.isNotEmpty && matches[0].chapterIndex.toInt() == currentChapterIndex.value) {
        // 通知 UI 滚动到搜索结果
        searchScrollTrigger.value++;
      }
    } catch (e) {
      _showSnack('错误', '搜索失败: $e');
    }
  }

  void _showSearchResultsDialog(List<SearchMatch> matches) {
    Get.dialog(
      AlertDialog(
        title: Text('找到 ${matches.length} 个结果'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.builder(
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              return ListTile(
                title: Text(match.chapterTitle),
                subtitle: Text(match.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  // 切换到该结果并关闭列表
                  selectedSearchIndex.value = index;
                  debugPrint('[Novel VM] search result tapped: index=$index chapterIndex=${match.chapterIndex}');
                  final chapterIndex = match.chapterIndex.toInt();
                  Get.back();

                  // 如果已经在当前章节，只需触发滚动；否则切换章节
                  if (chapterIndex == currentChapterIndex.value) {
                    searchScrollTrigger.value++;
                  } else {
                    goToChapter(chapterIndex);
                    // 延迟触发滚动，等待章节加载完成
                    Future.delayed(const Duration(milliseconds: 300), () {
                      searchScrollTrigger.value++;
                    });
                  }
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Get.back(), child: const Text('关闭'))],
      ),
    );
  }

  /// 切换到下一个搜索结果
  void nextSearchResult() {
    if (searchMatches.isEmpty) return;
    selectedSearchIndex.value = (selectedSearchIndex.value + 1) % searchMatches.length;
    final idx = selectedSearchIndex.value;
    final chapterIndex = searchMatches[idx].chapterIndex.toInt();
    // 如果目标在当前章节，直接触发滚动；否则切换章节后延迟触发滚动以等待加载
    if (chapterIndex == currentChapterIndex.value) {
      searchScrollTrigger.value++;
    } else {
      goToChapter(chapterIndex);
      Future.delayed(const Duration(milliseconds: 300), () {
        searchScrollTrigger.value++;
      });
    }
  }

  /// 切换到上一个搜索结果
  void previousSearchResult() {
    if (searchMatches.isEmpty) return;
    selectedSearchIndex.value = (selectedSearchIndex.value - 1 + searchMatches.length) % searchMatches.length;
    final idx = selectedSearchIndex.value;
    final chapterIndex = searchMatches[idx].chapterIndex.toInt();
    if (chapterIndex == currentChapterIndex.value) {
      searchScrollTrigger.value++;
    } else {
      goToChapter(chapterIndex);
      Future.delayed(const Duration(milliseconds: 300), () {
        searchScrollTrigger.value++;
      });
    }
  }

  /// 打开搜索结果列表（再次显示）
  void openSearchResultsList() {
    if (searchMatches.isEmpty) return;
    _showSearchResultsDialog(searchMatches);
  }

  /// 清除搜索结果
  void clearSearch() {
    searchMatches.clear();
    selectedSearchIndex.value = -1;
  }

  /// 切换到相邻的书本（用于快捷键）
  void switchToAdjacentBook(int direction) async {
    try {
      // 获取所有书籍列表
      final allNovels = getAllNovels();

      // 找到当前书籍的索引
      final currentIndex = allNovels.indexWhere((n) => n.id == novel.id);
      if (currentIndex == -1) return;

      // 计算目标索引
      final targetIndex = currentIndex + direction;
      if (targetIndex < 0 || targetIndex >= allNovels.length) {
        _showSnack('提示', direction < 0 ? '已经是第一本书' : '已经是最后一本书');
        return;
      }

      // 跳转到目标书籍
      final targetNovel = allNovels[targetIndex];
      // 使用 GoRouter 导航 - 需要从上下文获取，这里暂时保留原逻辑
      // 由于 ViewModel 中无法直接访问 context，保持使用 Get.back() 和路由跳转
      Get.back(); // 返回书籍列表
      // 延迟一下再打开新书，确保前一个页面已经销毁
      // Future.delayed(const Duration(milliseconds: 100), () {
      //   // TODO: 需要通过回调或其他方式传递 context 来使用 GoRouter
      //   Get.toNamed(Routes.novelReader, arguments: targetNovel);
      // });
    } catch (e) {
      debugPrint('[Novel VM] Failed to switch book: $e');
    }
  }

  /// 显示删除书本对话框
  void showDeleteDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('删除书本'),
        content: Text('确定要删除《${novel.title}》吗？'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Get.back();
              _deleteNovel(false);
            },
            child: const Text('仅删除记录'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _deleteNovel(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除记录和文件'),
          ),
        ],
      ),
    );
  }

  /// 在系统文件管理器中显示当前小说文件并选中（若支持）
  Future<void> revealFileInFolder() async {
    try {
      final path = novel.filePath;
      if (path.isEmpty) {
        _showSnack('错误', '未找到文件路径');
        return;
      }

      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else {
        // Linux / other: 打开父目录
        final dir = File(path).parent.path;
        await Process.run('xdg-open', [dir]);
      }
    } catch (e) {
      debugPrint('[Novel VM] revealFileInFolder failed: $e');
      _showSnack('错误', '无法打开所在文件夹: $e');
    }
  }

  /// 删除小说
  Future<void> _deleteNovel(bool deleteFile) async {
    try {
      if (deleteFile) {
        removeNovelWithFile(novelId: novel.id);
        _showSnack('成功', '已删除小说及文件');
      } else {
        removeNovel(novelId: novel.id);
        _showSnack('成功', '已删除小说记录');
      }

      // 返回书籍列表
      Get.back();
    } catch (e) {
      _showSnack('错误', '删除失败: $e');
    }
  }
}
