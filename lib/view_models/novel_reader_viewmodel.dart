import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:html/parser.dart' as html_parser;

final Loggers logger = Loggers(name: '书籍');

/// 书籍阅读器 ViewModel
class NovelReaderViewModel extends GetxController {
  final NovelMetadata novel;

  final chapters = <NovelChapter>[].obs;
  final currentChapterIndex = 0.obs;
  final currentContent = ''.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final showChapterList = true.obs;
  final chapterListWidth = 280.0.obs; // 章节列表侧边栏宽度
  final fontSize = 16.0.obs;
  final lineHeight = 1.8.obs;
  // 搜索结果状态
  final searchMatches = <SearchMatch>[].obs;
  final selectedSearchIndex = (-1).obs;
  final searchScrollTrigger = 0.obs; // 用于触发滚动到搜索结果
  final lastSearchQuery = ''.obs; // 记录最近一次搜索的原始关键词，供 UI 高亮使用

  // 翻译相关状态
  final isAutoTranslateEnabled = false.obs; // 是否开启自动翻译
  final isTranslating = false.obs; // 正在翻译中
  final translationProgress = 0.obs; // 当前翻译进度 (已完成段落数)
  final translationTotal = 0.obs; // 总段落数
  final RxnString translationModel = RxnString(null); // 翻译模型
  final Rx<TranslationLanguagePair> translationLanguagePair =
      TranslationLanguagePair.presets[0].obs; // 翻译语言对
  final useStreamingTranslation = false.obs; // 是否使用流式输出
  final translationTimeout = 60.obs; // 翻译超时时间（秒）
  String? _originalContent; // 原文内容（用于切换译文/原文）
  CancelToken? _translationCancelToken; // 翻译请求取消令牌

  // HTML内容缓存，避免重复转换（key: chapterIndex）
  final Map<int, String> _processedHtmlCache = {};

  // 章节标题翻译缓存（key: original title, value: translated title）
  final Map<String, String> _chapterTitleCache = {};

  // 翻译失败的段落原文列表
  final failedTranslations = <String>[].obs;

  /// 由 Page build 时注入，用于弹窗（MaterialApp.router 不支持 Get.dialog）
  BuildContext? _pageContext;
  void setContext(BuildContext ctx) => _pageContext = ctx;

  NovelReaderViewModel(this.novel);

  @override
  void onInit() {
    super.onInit();
    loadNovelContent();
  }

  void _showSnack(
    String title,
    String message, {
    Color? backgroundColor,
    Color? colorText,
    Duration? duration,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final context = _pageContext ?? navigatorKey.currentContext;
        if (context == null) return;

        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '$title：$message',
                style: colorText == null ? null : TextStyle(color: colorText),
              ),
              duration: duration ?? const Duration(seconds: 2),
              backgroundColor: backgroundColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
      } catch (_) {}
    });
  }

  @override
  void onClose() {
    // 关闭页面时，立即取消所有翻译任务
    logger.info('[Novel UI] onClose: 开始清理资源');
    _cancelTranslation();

    // 清除翻译相关状态
    isTranslating.value = false;
    isAutoTranslateEnabled.value = false;
    failedTranslations.clear();
    _chapterTitleCache.clear();
    _originalContent = null;

    // 清空HTML缓存
    _processedHtmlCache.clear();

    // 先清除 Rust 内容解析缓存，确保下次打开重新解压图片
    try {
      clearNovelCache(filePath: novel.filePath);
      logger.info('Cleared Rust content cache for: ${novel.filePath}');
    } catch (e) {
      logger.info('[Novel UI] Failed to clear Rust content cache: $e');
    }

    // 尝试删除基于 novel.id 的临时目录（如果存在）
    try {
      final base = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}slimeworks${Platform.pathSeparator}epub_images${Platform.pathSeparator}${novel.id}',
      );
      if (base.existsSync()) {
        base.deleteSync(recursive: true);
        logger.info('[Novel UI] Cleared epub image cache: ${base.path}');
      }
    } catch (e) {
      logger.info('[Novel UI] Failed to clear epub image cache: $e');
    }

    // 退出阅读器时保存当前阅读位置
    try {
      if (chapters.isNotEmpty) {
        final progress = (currentChapterIndex.value + 1) / (chapters.length);
        updateReadingProgress(novelId: novel.id, progress: progress);
        logger.info('[Novel UI] Saved progress $progress for novel ${novel.id} on close');
      }
    } catch (e) {
      logger.info('[Novel UI] Failed to save progress on close: $e');
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

  /// 加载书籍内容
  Future<void> loadNovelContent() async {
    final startTime = DateTime.now();
    final startMs = startTime.millisecondsSinceEpoch;
    try {
      isLoading.value = true;
      errorMessage.value = '';

      logger.info('[Novel UI] ========== Loading novel ==========');
      logger.info('[Novel UI] Title: ${novel.title}');
      logger.info('[Novel UI] File: ${novel.filePath}');
      final fileSize = File(novel.filePath).existsSync() ? File(novel.filePath).lengthSync() : 0;
      final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(2);
      logger.info('[Novel UI] File size: ${fileSizeMB}MB');
      logger.info('[Novel UI] Start time: $startTime');

      logger.info('[Novel UI] Calling Rust getNovelContent...');
      final callStart = DateTime.now();
      final beforeRust = DateTime.now();
      final content = await getNovelContent(filePath: novel.filePath);
      final afterRust = DateTime.now();
      final rustDuration = afterRust.difference(beforeRust);
      logger.info('[Novel UI] Rust getNovelContent completed in ${rustDuration.inMilliseconds}ms');

      // 记录从调用到 Dart 层收到结果的总时长（包含 FFI + 序列化开销）
      final afterReceive = DateTime.now();
      final totalCallMs = afterReceive.difference(callStart).inMilliseconds;
      logger.info(
        '[Novel UI] getNovelContent total await elapsed: ${totalCallMs}ms (includes FFI/serialization)',
      );

      // 赋值并记录耗时
      final assignStart = DateTime.now();
      chapters.value = content.chapters;
      final assignDuration = DateTime.now().difference(assignStart).inMilliseconds;
      final chaptersLen = chapters.length;
      logger.info('[Novel UI] Loaded $chaptersLen chapters (assign took ${assignDuration}ms)');

      // TODO: 暂时注释掉章节标题翻译，避免加载时卡顿
      // if (isAutoTranslateEnabled.value && translationModel.value != null) {
      //   _translateChapterTitles();
      // }

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
        logger.info(
          '[Novel UI] Restoring chapter index $startIndex (progress=${(novel.progress * 100).toStringAsFixed(1)}%)',
        );
        // 先设置索引以更新 UI 选中状态，再加载章节内容
        currentChapterIndex.value = startIndex;
        logger.info('[Novel UI] Set currentChapterIndex to $startIndex before loading content');

        final beforeChapter = DateTime.now();
        await loadChapterContent(startIndex);
        final chapterLoadMs = DateTime.now().difference(beforeChapter).inMilliseconds;
        logger.info('[Novel UI] Initial chapter load took ${chapterLoadMs}ms');
      }

      final now = DateTime.now();
      final totalDuration = now.millisecondsSinceEpoch - startMs;
      logger.info('[Novel UI] ========== Total load time: ${totalDuration}ms ==========');
    } catch (e, stackTrace) {
      final now = DateTime.now();
      final duration = now.millisecondsSinceEpoch - startMs;
      logger.info('[Novel UI] *** ERROR after ${duration}ms: $e ***');
      logger.info('[Novel UI] Stack trace: $stackTrace');
      errorMessage.value = '加载失败: $e';
    } finally {
      isLoading.value = false;
      // 在章节显示后异步执行翻译（不阻塞显示）
      if (isAutoTranslateEnabled.value && translationModel.value != null) {
        translateCurrentChapter();
      }
    }
  }

  /// 加载章节内容
  Future<void> loadChapterContent(int index) async {
    if (index < 0 || index >= chapters.length) return;

    // 切换章节时取消正在进行的翻译
    _cancelTranslation();

    final startTime = DateTime.now();
    final startMs = startTime.millisecondsSinceEpoch;
    try {
      isLoading.value = true;
      errorMessage.value = '';

      logger.info('[Novel UI] --- Loading chapter $index ---');
      final chTitle = chapters[index].title;
      logger.info('[Novel UI] Chapter title: $chTitle');

      final beforeRust = DateTime.now();
      final content = await getChapterContent(
        filePath: novel.filePath,
        chapterIndex: BigInt.from(index),
      );
      final rustDuration = DateTime.now().difference(beforeRust);
      final contentLenKB = (content.length / 1024).toStringAsFixed(1);

      logger.info(
        '[Novel UI] Chapter loaded in ${rustDuration.inMilliseconds}ms, length: ${content.length} chars (${contentLenKB}KB)',
      );

      // currentChapterIndex 已由 goToChapter 设置，此处不再重复设置
      currentContent.value = content;
      logger.info('[Novel UI] Updated currentContent.value');

      // 更新阅读进度
      final progress = (index + 1) / chapters.length;
      updateReadingProgress(novelId: novel.id, progress: progress);
      debugPrint(
        '[Reader] Updated progress for ${novel.title} to ${(progress * 100).toStringAsFixed(1)}% (chapter ${index + 1}/${chapters.length})',
      );

      final now = DateTime.now();
      final totalDuration = now.millisecondsSinceEpoch - startMs;
      logger.info('[Novel UI] --- Chapter display ready in ${totalDuration}ms ---');
    } catch (e, stackTrace) {
      final now = DateTime.now();
      final duration = now.millisecondsSinceEpoch - startMs;
      logger.info('[Novel UI] *** ERROR loading chapter after ${duration}ms: $e ***');
      logger.info('[Novel UI] Stack trace: $stackTrace');
      errorMessage.value = '加载章节失败: $e';
    } finally {
      isLoading.value = false;

      // 在章节显示后异步执行翻译（不阻塞显示）
      if (isAutoTranslateEnabled.value && translationModel.value != null) {
        translateCurrentChapter();
      }
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

  void setLineHeight(double value) {
    lineHeight.value = value.clamp(1.2, 2.6);
  }

  /// 显示搜索对话框
  void showSearchDialog() {
    final ctx = _pageContext;
    if (ctx == null || !ctx.mounted) return;
    final controller = TextEditingController();

    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('搜索内容'),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(hintText: '输入关键词', border: OutlineInputBorder()),
          onSubmitted: (value) {
            Navigator.of(dlgCtx).pop();
            if (value.isNotEmpty) searchKeyword(value);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dlgCtx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final keyword = controller.text;
              Navigator.of(dlgCtx).pop();
              if (keyword.isNotEmpty) searchKeyword(keyword);
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
      logger.info(
        '[Novel VM] searchKeyword: matches=${matches.length} selectedIndex=${selectedSearchIndex.value}',
      );

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
    final ctx = _pageContext;
    if (ctx == null || !ctx.mounted) return;

    final scrollCtrl = ScrollController();

    showDialog(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (_, setModalState) {
          // 列表打开后滚动到上次点击的结果
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!scrollCtrl.hasClients) return;
            final idx = selectedSearchIndex.value;
            if (idx < 0) return;
            const itemH = 72.0;
            final target = (idx * itemH - scrollCtrl.position.viewportDimension / 2 + itemH / 2)
                .clamp(0.0, scrollCtrl.position.maxScrollExtent);
            scrollCtrl.jumpTo(target);
          });

          return AlertDialog(
            title: Text('找到 ${matches.length} 个结果'),
            content: SizedBox(
              width: 500,
              height: 400,
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: matches.length,
                itemBuilder: (_, index) {
                  final match = matches[index];
                  final isSelected = selectedSearchIndex.value == index;
                  return Material(
                    color: isSelected
                        ? Theme.of(dlgCtx).colorScheme.primaryContainer
                        : Colors.transparent,
                    child: ListTile(
                      selected: isSelected,
                      selectedColor: Theme.of(dlgCtx).colorScheme.onPrimaryContainer,
                      title: Text(match.chapterTitle.replaceAll(RegExp(r'<[^>]+>'), '').trim()),
                      subtitle: Text(match.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        selectedSearchIndex.value = index;
                        setModalState(() {});
                        final chapterIndex = match.chapterIndex.toInt();
                        Navigator.of(dlgCtx).pop();
                        if (chapterIndex == currentChapterIndex.value) {
                          searchScrollTrigger.value++;
                        } else {
                          goToChapter(chapterIndex);
                          Future.delayed(const Duration(milliseconds: 500), () {
                            searchScrollTrigger.value++;
                          });
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dlgCtx).pop(), child: const Text('关闭')),
            ],
          );
        },
      ),
    ).whenComplete(() => scrollCtrl.dispose());
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
      Future.delayed(const Duration(milliseconds: 500), () {
        searchScrollTrigger.value++;
      });
    }
  }

  /// 切换到上一个搜索结果
  void previousSearchResult() {
    if (searchMatches.isEmpty) return;
    selectedSearchIndex.value =
        (selectedSearchIndex.value - 1 + searchMatches.length) % searchMatches.length;
    final idx = selectedSearchIndex.value;
    final chapterIndex = searchMatches[idx].chapterIndex.toInt();
    if (chapterIndex == currentChapterIndex.value) {
      searchScrollTrigger.value++;
    } else {
      goToChapter(chapterIndex);
      Future.delayed(const Duration(milliseconds: 500), () {
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

      final context = _pageContext ?? navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      Navigator.of(context).maybePop();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!context.mounted) return;
        NovelReaderRoute($extra: targetNovel).go(context);
      });
    } catch (e) {
      logger.info('[Novel VM] Failed to switch book: $e');
    }
  }

  /// 显示删除书本对话框
  void showDeleteDialog() {
    final ctx = _pageContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('删除书本'),
        content: Text('确定要删除《${novel.title}》吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dlgCtx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.of(dlgCtx).pop();
              _deleteNovel(false);
            },
            child: const Text('仅删除记录'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dlgCtx).pop();
              _deleteNovel(true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除记录和文件'),
          ),
        ],
      ),
    );
  }

  /// 在系统文件管理器中显示当前书籍文件并选中（若支持）
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
      logger.info('[Novel VM] revealFileInFolder failed: $e');
      _showSnack('错误', '无法打开所在文件夹: $e');
    }
  }

  /// 删除书籍
  Future<void> _deleteNovel(bool deleteFile) async {
    try {
      if (deleteFile) {
        removeNovelWithFile(novelId: novel.id);
        _showSnack('成功', '已删除书籍及文件');
      } else {
        removeNovel(novelId: novel.id);
        _showSnack('成功', '已删除书籍记录');
      }

      // 返回书籍列表
      final context = _pageContext ?? navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      _showSnack('错误', '删除失败: $e');
    }
  }

  /// 显示翻译配置面板
  void showTranslationPanel() {
    // 由 toolbar 处理
  }

  /// 翻译当前章节
  Future<void> translateCurrentChapter() async {
    final model = translationModel.value;
    if (model == null) {
      _showSnack('错误', '请先配置翻译模型');
      return;
    }

    if (currentContent.value.isEmpty) {
      _showSnack('提示', '当前章节没有内容');
      return;
    }

    try {
      isTranslating.value = true;
      _originalContent = currentContent.value; // 保存原文

      // 创建新的取消令牌
      _translationCancelToken = CancelToken();

      logger.info('开始翻译章节, model=$model, lang=${translationLanguagePair.value.displayName}');

      // 解析 HTML，创建可修改的 document
      final document = html_parser.parse(_originalContent);
      final textNodes = _extractTextNodesFromDocument(document);
      logger.info('提取到 ${textNodes.length} 个文本节点');

      if (textNodes.isEmpty) {
        _showSnack('提示', '当前章节没有可翻译的内容');
        return;
      }

      // 逐段翻译并实时更新UI
      final ollamaService = getIt.get<OllamaService>();

      // 清空失败列表
      failedTranslations.clear();

      // 初始化翻译进度
      translationProgress.value = 0;
      translationTotal.value = textNodes.length;

      // 优化：批量更新减少UI刷新频率（每5个段落或每2秒更新一次）
      int lastUpdateIndex = -1;
      DateTime lastUpdateTime = DateTime.now();
      const updateInterval = Duration(seconds: 2);
      DateTime? lastStreamUpdate; // 流式输出节流控制

      for (int i = 0; i < textNodes.length; i++) {
        // 检查是否已取消翻译
        if (_translationCancelToken?.isCancelled ?? false) {
          logger.info('翻译已取消，退出循环 (${i + 1}/${textNodes.length})');
          break;
        }

        final textNode = textNodes[i];
        final originalText = textNode.text.trim();
        if (originalText.isEmpty) {
          // 跳过空内容但也更新进度
          translationProgress.value = i + 1;
          continue;
        }

        try {
          logger.info('正在翻译节点 ${i + 1}/${textNodes.length}');

          // 翻译单个段落（带超时控制）
          final translated = await ollamaService
              .translate(
                model: model,
                text: originalText,
                languagePair: translationLanguagePair.value,
                onChunk: useStreamingTranslation.value
                    ? (chunk) {
                        // 流式更新：每500ms更新一次UI，避免过于频繁
                        final now = DateTime.now();
                        if (lastStreamUpdate == null ||
                            now.difference(lastStreamUpdate!) > const Duration(milliseconds: 500)) {
                          textNode.text = _cleanTranslationResult(textNode.text + chunk);
                          currentContent.value = document.outerHtml;
                          lastStreamUpdate = now;
                        } else {
                          // 仅更新文本，不触发UI
                          textNode.text = _cleanTranslationResult(textNode.text + chunk);
                        }
                      }
                    : null,
                cancelToken: _translationCancelToken,
              )
              .timeout(
                Duration(seconds: translationTimeout.value),
                onTimeout: () {
                  logger.error('翻译节点 ${i + 1} 超时 (${translationTimeout.value}秒)');
                  throw TimeoutException('翻译超时', Duration(seconds: translationTimeout.value));
                },
              );

          // 清理翻译结果中的标签
          final cleanedTranslation = _cleanTranslationResult(translated);
          logger.info(
            '节点 ${i + 1} 翻译完成, 原文=${originalText.substring(0, originalText.length > 20 ? 20 : originalText.length)}... => 译文=${cleanedTranslation.substring(0, cleanedTranslation.length > 20 ? 20 : cleanedTranslation.length)}...',
          );

          // 更新文本内容
          textNode.text = cleanedTranslation;

          // 在父元素上标记原文（用于重试）
          final parent = textNode.parent;
          if (parent != null) {
            // HTML转义原文
            final escapedOriginal = originalText
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;')
                .replaceAll('"', '&quot;')
                .replaceAll("'", '&#39;');
            parent.attributes['data-original-text'] = escapedOriginal;
            parent.attributes['data-translated'] = 'true';
          }

          // 更新翻译进度
          translationProgress.value = i + 1;

          // 优化UI刷新：每5个段落或每2秒更新一次UI，减少document.outerHtml调用
          final now = DateTime.now();
          final shouldUpdate =
              (i - lastUpdateIndex >= 5) ||
              (now.difference(lastUpdateTime) >= updateInterval) ||
              (i == textNodes.length - 1); // 最后一个必须更新

          if (shouldUpdate) {
            currentContent.value = document.outerHtml;
            lastUpdateIndex = i;
            lastUpdateTime = now;
            logger.info('更新UI: 已翻译 ${i + 1}/${textNodes.length} 个节点');
          }
        } catch (e) {
          logger.error('翻译节点 ${i + 1} 失败', error: e);
          // 失败时保留原文，并记录失败段落
          if (!failedTranslations.contains(originalText)) {
            failedTranslations.add(originalText);
          }
        }
      }

      // 翻译完成，确保最终UI更新
      currentContent.value = document.outerHtml;
      logger.info('章节翻译完成，最终UI已更新');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        logger.info('翻译已取消');
        // 取消时不显示错误
      } else {
        logger.error('翻译失败', error: e);
        _showSnack('错误', '翻译失败: $e');
        // 恢复原文
        if (_originalContent != null) {
          currentContent.value = _originalContent!;
        }
      }
    } catch (e, st) {
      logger.error('翻译失败', error: e, stackTrace: st);
      _showSnack('错误', '翻译失败: $e');
      // 恢复原文
      if (_originalContent != null) {
        currentContent.value = _originalContent!;
      }
    } finally {
      isTranslating.value = false;
      _translationCancelToken = null;
    }
  }

  /// 提取单个元素中的文本节点
  List<dynamic> _extractTextNodesFromElement(dynamic element) {
    final textNodes = <dynamic>[];

    // 如果元素直接包含文本
    if (element.nodes.any((node) => node.nodeType == 3)) {
      return [element];
    }

    // 递归查找文本节点
    for (final child in element.children) {
      final childTextNodes = _extractTextNodesFromElement(child);
      textNodes.addAll(childTextNodes);
    }

    return textNodes;
  }

  /// 提取 HTML 中所有包含文本的节点（不仅限于 <p> 标签）
  List<dynamic> _extractTextNodesFromDocument(dynamic document) {
    try {
      final textNodes = <dynamic>[];
      final Set<dynamic> visited = {};

      // 递归提取所有有意义的文本节点
      void extractFromNode(dynamic node) {
        // 避免重复处理
        if (visited.contains(node)) return;
        visited.add(node);

        final nodeName = node.localName?.toLowerCase() ?? '';

        // 特别处理 title 标签
        if (nodeName == 'title') {
          final text = node.text?.trim() ?? '';
          if (text.isNotEmpty) {
            textNodes.add(node);
          }
          return;
        }

        // 排除 script、style 等标签，但不排除 head（因为title在head里）
        if (['script', 'style', 'meta', 'link'].contains(nodeName)) {
          return;
        }

        // 改进的逻辑：检查节点是否包含直接文本节点（nodeType == 3）
        // 如果包含直接文本节点，说明这是一个需要翻译的节点（可能包含混合内容）
        final hasDirectText = node.nodes.any(
          (n) => n.nodeType == 3 && (n.text?.trim().isNotEmpty ?? false),
        );

        if (hasDirectText) {
          // 这个节点包含直接文本，将其作为翻译单元
          textNodes.add(node);
          return;
        }

        // 如果节点有子元素节点但没有直接文本，递归处理子节点
        final hasElementChildren = node.children.any((child) => child.nodeType == 1);
        if (hasElementChildren) {
          for (final child in node.children) {
            extractFromNode(child);
          }
          return;
        }

        // 叶子节点，如果有文本就提取
        final text = node.text?.trim() ?? '';
        if (text.isNotEmpty) {
          textNodes.add(node);
        }
      }

      extractFromNode(document.body ?? document);
      logger.info('成功提取 ${textNodes.length} 个有效文本节点');
      return textNodes;
    } catch (e) {
      logger.error('提取文本节点失败', error: e);
      return [];
    }
  }

  /// 清理翻译结果中的 XML/HTML 标签
  String _cleanTranslationResult(String translated) {
    String cleaned = translated.trim();

    // 移除常见的 XML 标签包装
    final tagPatterns = [
      RegExp(r'^<target>\s*(.+?)\s*</target>\s*$', dotAll: true),
      RegExp(r'^<translation>\s*(.+?)\s*</translation>\s*$', dotAll: true),
      RegExp(r'^<result>\s*(.+?)\s*</result>\s*$', dotAll: true),
    ];

    for (final pattern in tagPatterns) {
      final match = pattern.firstMatch(cleaned);
      if (match != null && match.groupCount >= 1) {
        cleaned = match.group(1)!.trim();
        break;
      }
    }

    return cleaned;
  }

  /// 取消正在进行的翻译
  void _cancelTranslation() {
    if (_translationCancelToken != null && !_translationCancelToken!.isCancelled) {
      logger.info('取消正在进行的翻译请求');
      _translationCancelToken!.cancel('切换章节');
    }
    _translationCancelToken = null;
    isTranslating.value = false;
  }

  /// 切换自动翻译
  void toggleAutoTranslate() {
    isAutoTranslateEnabled.value = !isAutoTranslateEnabled.value;
    if (isAutoTranslateEnabled.value) {
      logger.info('开启自动翻译');
      // TODO: 暂时注释掉章节标题翻译
      // if (translationModel.value != null) {
      //   _translateChapterTitles();
      // }
      // 立即翻译当前章节
      if (translationModel.value != null) {
        translateCurrentChapter();
      }
    } else {
      logger.info('关闭自动翻译');
      // 取消正在进行的翻译
      _cancelTranslation();
      // 恢复原文
      if (_originalContent != null) {
        currentContent.value = _originalContent!;
        _originalContent = null;
      }
      // 清除章节标题缓存
      _chapterTitleCache.clear();
    }
  }

  /// Debug: 复制当前章节原始HTML到剪贴板
  Future<void> copyOriginalHtmlToClipboard() async {
    try {
      final content = _originalContent ?? currentContent.value;
      if (content.isEmpty) {
        _showSnack('提示', '当前没有内容');
        return;
      }

      // 使用 Flutter 的剪贴板API
      await Clipboard.setData(ClipboardData(text: content));
      _showSnack('成功', '已复制原始HTML (${content.length}字符) 到剪贴板');
      logger.info('已复制HTML到剪贴板, length=${content.length}');
    } catch (e) {
      logger.error('复制HTML失败', error: e);
      _showSnack('错误', '复制失败: $e');
    }
  }

  /// 从HTML中提取原文并重新翻译
  Future<void> handleRetryFromHtml(String escapedOriginalText) async {
    // HTML反转义
    final originalText = escapedOriginalText
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    await retryTranslateParagraph(originalText);
  }

  /// 重新翻译指定段落（用于重试）
  Future<void> retryTranslateParagraph(String originalText) async {
    final model = translationModel.value;
    if (model == null) {
      _showSnack('错误', '请先配置翻译模型');
      return;
    }

    if (_originalContent == null) {
      _showSnack('错误', '没有可用的原文内容');
      return;
    }

    try {
      logger.info('重试翻译段落: $originalText');

      final ollamaService = getIt.get<OllamaService>();
      final cancelToken = CancelToken();

      // 翻译段落
      final translated = await ollamaService
          .translate(
            model: model,
            text: originalText,
            languagePair: translationLanguagePair.value,
            cancelToken: cancelToken,
          )
          .timeout(
            Duration(seconds: translationTimeout.value),
            onTimeout: () {
              throw TimeoutException('翻译超时', Duration(seconds: translationTimeout.value));
            },
          );

      final cleanedTranslation = _cleanTranslationResult(translated);

      // 更新当前内容中的该段落
      final document = html_parser.parse(currentContent.value);

      // 查找包含原文标记的元素
      final allElements = document.querySelectorAll('[data-original-text]');
      for (final element in allElements) {
        final dataText = element.attributes['data-original-text'];
        if (dataText == null) continue;

        // HTML反转义比对
        final unescapedData = dataText
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'");

        if (unescapedData == originalText) {
          // 找到对应元素，提取其文本节点并更新
          final textNodes = _extractTextNodesFromElement(element);
          if (textNodes.isNotEmpty) {
            textNodes.first.text = cleanedTranslation;
            currentContent.value = document.outerHtml;
            logger.info('成功重试翻译段落');
            _showSnack('成功', '已重新翻译该段落');

            // 从失败列表中移除（如果存在）
            failedTranslations.remove(originalText);
            return;
          }
        }
      }

      _showSnack('错误', '找不到指定段落');
    } catch (e) {
      logger.error('重试翻译失败', error: e);
      _showSnack('错误', '重试翻译失败: $e');
    }
  }

  /// 重试所有翻译失败的段落
  Future<void> retryAllFailedTranslations() async {
    if (failedTranslations.isEmpty) {
      _showSnack('提示', '没有翻译失败的段落');
      return;
    }

    final failedList = List<String>.from(failedTranslations);
    logger.info('开始重试 ${failedList.length} 个失败段落');

    for (final text in failedList) {
      await retryTranslateParagraph(text);
      // 如果成功，从失败列表中移除
      failedTranslations.remove(text);
    }

    if (failedTranslations.isEmpty) {
      _showSnack('成功', '所有段落已重新翻译');
    } else {
      _showSnack('部分成功', '仍有 ${failedTranslations.length} 个段落翻译失败');
    }
  }
}
