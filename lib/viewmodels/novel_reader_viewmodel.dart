import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  NovelReaderViewModel(this.novel);

  @override
  void onInit() {
    super.onInit();
    loadNovelContent();
  }

  @override
  void onClose() {
    super.onClose();
  }

  /// 加载小说内容
  Future<void> loadNovelContent() async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      debugPrint('NovelReaderViewModel: loading novel content from ${novel.filePath}');
      final content = await getNovelContent(filePath: novel.filePath);
      chapters.value = content.chapters;

      if (chapters.isNotEmpty) {
        await loadChapterContent(0);
      }
    } catch (e) {
      errorMessage.value = '加载失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 加载章节内容
  Future<void> loadChapterContent(int index) async {
    if (index < 0 || index >= chapters.length) return;

    try {
      isLoading.value = true;
      errorMessage.value = '';

      debugPrint('NovelReaderViewModel: loading chapter $index for ${novel.filePath}');
      final content = await getChapterContent(filePath: novel.filePath, chapterIndex: BigInt.from(index));

      currentChapterIndex.value = index;
      currentContent.value = content;

      // 更新阅读进度
      final progress = (index + 1) / chapters.length;
      updateReadingProgress(novelId: novel.id, progress: progress);
    } catch (e) {
      errorMessage.value = '加载章节失败: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// 跳转到指定章节
  void goToChapter(int index) {
    loadChapterContent(index);
  }

  /// 上一章
  void previousChapter() {
    if (hasPreviousChapter()) {
      loadChapterContent(currentChapterIndex.value - 1);
    }
  }

  /// 下一章
  void nextChapter() {
    if (hasNextChapter()) {
      loadChapterContent(currentChapterIndex.value + 1);
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
    try {
      final matches = await searchInNovel(filePath: novel.filePath, keyword: keyword);
      searchMatches.value = matches;
      selectedSearchIndex.value = matches.isNotEmpty ? 0 : -1;

      if (matches.isEmpty) {
        Get.snackbar('搜索', '未找到匹配内容');
        return;
      }

      // 显示搜索结果
      _showSearchResultsDialog(matches);
    } catch (e) {
      Get.snackbar('错误', '搜索失败: $e');
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
                  final chapterIndex = match.chapterIndex.toInt();
                  Get.back();
                  goToChapter(chapterIndex);
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
    goToChapter(chapterIndex);
  }

  /// 切换到上一个搜索结果
  void previousSearchResult() {
    if (searchMatches.isEmpty) return;
    selectedSearchIndex.value = (selectedSearchIndex.value - 1 + searchMatches.length) % searchMatches.length;
    final idx = selectedSearchIndex.value;
    final chapterIndex = searchMatches[idx].chapterIndex.toInt();
    goToChapter(chapterIndex);
  }

  /// 打开搜索结果列表（再次显示）
  void openSearchResultsList() {
    if (searchMatches.isEmpty) return;
    _showSearchResultsDialog(searchMatches);
  }
}
