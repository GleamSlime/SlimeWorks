import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 书籍阅读器页面
class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key});

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  late final NovelMetadata novel;
  late final NovelReaderViewModel controller;

  @override
  void initState() {
    super.initState();
    novel = Get.arguments as NovelMetadata;
    controller = Get.put(NovelReaderViewModel(novel), tag: novel.id);
  }

  @override
  void dispose() {
    try {
      Get.delete<NovelReaderViewModel>(tag: novel.id);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 章节列表侧边栏
        Obx(
          () => controller.showChapterList.value
              ? Container(
                  width: 250,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: _ChapterList(controller: controller),
                )
              : const SizedBox(),
        ),

        // 主阅读区域
        Expanded(
          child: Column(
            children: [
              // 工具栏
              _ReaderToolbar(controller: controller),
              const Divider(height: 1),

              // 阅读内容
              Expanded(
                child: Obx(() {
                  if (controller.isLoading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (controller.errorMessage.value.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: AppTheme.metrics.iconSize48, color: Theme.of(context).colorScheme.error),
                          SizedBox(height: AppTheme.metrics.kSpace16),
                          Text(
                            controller.errorMessage.value,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ],
                      ),
                    );
                  }

                  return _ReaderContent(controller: controller);
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 章节列表
class _ChapterList extends StatelessWidget {
  final NovelReaderViewModel controller;

  const _ChapterList({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.chapters.isEmpty) {
        return const Center(child: Text('暂无章节'));
      }

      return ListView.builder(
        itemCount: controller.chapters.length,
        itemBuilder: (context, index) {
          final chapter = controller.chapters[index];
          final isCurrent = controller.currentChapterIndex.value == index;

          return ListTile(
            dense: true,
            selected: isCurrent,
            title: Text(
              chapter.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal),
            ),
            onTap: () => controller.goToChapter(index),
          );
        },
      );
    });
  }
}

/// 阅读器工具栏
class _ReaderToolbar extends StatelessWidget {
  final NovelReaderViewModel controller;

  const _ReaderToolbar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16, vertical: AppTheme.metrics.kSpace8),
      child: Row(
        children: [
          // 章节列表切换
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: '章节列表',
            onPressed: controller.toggleChapterList,
          ),
          SizedBox(width: AppTheme.metrics.kSpace8),

          // 上一章
          Obx(
            () => IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一章',
              onPressed: controller.hasPreviousChapter() ? controller.previousChapter : null,
            ),
          ),

          // 章节信息
          Obx(
            () => Text(
              controller.chapters.isEmpty
                  ? ''
                  : '${controller.currentChapterIndex.value + 1}/${controller.chapters.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          // 下一章
          Obx(
            () => IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一章',
              onPressed: controller.hasNextChapter() ? controller.nextChapter : null,
            ),
          ),

          const Spacer(),

          // 搜索按钮
          Obx(() {
            if (controller.searchMatches.isNotEmpty) {
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: '上一个搜索结果',
                    onPressed: controller.previousSearchResult,
                  ),
                  IconButton(
                    icon: const Icon(Icons.list),
                    tooltip: '搜索结果列表',
                    onPressed: controller.openSearchResultsList,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    tooltip: '下一个搜索结果',
                    onPressed: controller.nextSearchResult,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                ],
              );
            }
            return IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: controller.showSearchDialog,
            );
          }),

          // 字体大小
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: '减小字体',
            onPressed: controller.decreaseFontSize,
          ),
          Obx(() => Text('${controller.fontSize.value.toInt()}')),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: '增大字体',
            onPressed: controller.increaseFontSize,
          ),
        ],
      ),
    );
  }
}

/// 阅读内容区域
class _ReaderContent extends StatefulWidget {
  final NovelReaderViewModel controller;

  const _ReaderContent({required this.controller});

  @override
  State<_ReaderContent> createState() => _ReaderContentState();
}

class _ReaderContentState extends State<_ReaderContent> {
  late final ScrollController _localController;

  @override
  void initState() {
    super.initState();
    _localController = ScrollController();
  }

  @override
  void dispose() {
    _localController.dispose();
    super.dispose();
  }

  void _maybeScrollToTop() {
    if (_localController.hasClients) {
      _localController.jumpTo(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_localController.hasClients) {
          _localController.jumpTo(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Obx(() {
      final currentContent = controller.currentContent.value;

      if (currentContent.isEmpty) {
        return const Center(child: Text('暂无内容'));
      }

      // 当章节或内容变化时尝试滚动到顶部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeScrollToTop();
      });

      return SingleChildScrollView(
        controller: _localController,
        padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            if (controller.chapters.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace24),
                child: Text(
                  controller.chapters[controller.currentChapterIndex.value].title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),

            // 正文内容
            SelectableText(
              currentContent,
              style: TextStyle(
                fontSize: controller.fontSize.value,
                height: 1.8,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    });
  }
}
