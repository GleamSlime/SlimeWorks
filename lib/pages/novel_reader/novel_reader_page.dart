import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/pages/novel_reader/components/chapter_list.dart';
import 'package:slime_works/pages/novel_reader/components/reader_toolbar.dart';
import 'package:slime_works/pages/novel_reader/components/reader_content.dart';

/// 书籍阅读器页面
class NovelReaderPage extends StatefulWidget {
  final NovelMetadata? novel;

  const NovelReaderPage({super.key, this.novel});

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  late final NovelMetadata novel;
  late final NovelReaderViewModel controller;

  @override
  void initState() {
    super.initState();
    // 优先使用传入的 novel，如果没有则尝试从 Get.arguments 获取（兼容旧代码）
    novel = widget.novel ?? Get.arguments as NovelMetadata;
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
    // 注入 context 供 ViewModel 显示对话框（MaterialApp.router 不支持 Get.dialog）
    controller.setContext(context);
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // 左右方向键：切换章节
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (controller.hasPreviousChapter()) {
              controller.previousChapter();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (controller.hasNextChapter()) {
              controller.nextChapter();
            }
            return KeyEventResult.handled;
          }
          // 上下方向键：在书籍列表中切换书本（返回并切换）
          else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            controller.switchToAdjacentBook(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            controller.switchToAdjacentBook(1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _buildContent(context, isNarrow),
    );
  }

  Widget _buildContent(BuildContext context, bool isNarrow) {
    if (isNarrow) {
      // 移动端布局：章节列表使用抽屉
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/collection/library');
              }
            },
          ),
          title: Row(
            children: [
              _buildHeroCover(32),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(novel.title, overflow: TextOverflow.ellipsis, maxLines: 1),
                    if (novel.tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: novel.tags
                            .take(3)
                            .map(
                              (tag) => Chip(
                                label: Text(tag, style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Obx(() {
              final libraryVm = Get.find<NovelLibraryViewModel>();
              final isFav =
                  libraryVm.novels.firstWhereOrNull((n) => n.id == novel.id)?.isFavorite ?? false;
              return IconButton(
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                onPressed: () => libraryVm.toggleFavorite(novel.id),
              );
            }),
            Obx(
              () => controller.showChapterList.value
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: controller.toggleChapterList,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        body: Stack(
          children: [
            // 主阅读区域
            Column(
              children: [
                ReaderToolbar(controller: controller),
                const Divider(height: 1),
                Expanded(
                  child: Obx(() {
                    if (controller.isLoading.value) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (controller.errorMessage.value.isNotEmpty) {
                      return _buildErrorView();
                    }

                    return ReaderContent(controller: controller);
                  }),
                ),
              ],
            ),

            // 章节列表（覆盖显示）
            Obx(
              () => controller.showChapterList.value
                  ? Positioned.fill(
                      child: GestureDetector(
                        onTap: controller.toggleChapterList,
                        child: Container(
                          color: Colors.black54,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () {}, // 防止点击列表关闭
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width * 0.75,
                                child: ChapterList(controller: controller),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    // 桌面端布局
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/collection/library');
            }
          },
        ),
        title: Row(
          children: [
            _buildHeroCover(32),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(novel.title, overflow: TextOverflow.ellipsis, maxLines: 1),
                  if (novel.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: novel.tags
                          .take(3)
                          .map(
                            (tag) => Chip(
                              label: Text(tag, style: const TextStyle(fontSize: 10)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Obx(() {
            final libraryVm = Get.find<NovelLibraryViewModel>();
            final isFav =
                libraryVm.novels.firstWhereOrNull((n) => n.id == novel.id)?.isFavorite ?? false;
            return IconButton(
              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
              onPressed: () => libraryVm.toggleFavorite(novel.id),
            );
          }),
        ],
      ),
      body: Row(
        children: [
          // 章节列表侧边栏（可调节宽度）
          Obx(() {
            final showList = controller.showChapterList.value;
            final width = controller.chapterListWidth.value;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: showList ? width : 0,
              child: showList
                  ? Row(
                      children: [
                        // 章节列表内容
                        Expanded(child: ChapterList(controller: controller)),
                        // 可拖动的分隔条
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              final newWidth = width + details.delta.dx;
                              // 限制宽度范围：200-600
                              controller.chapterListWidth.value = newWidth.clamp(200.0, 600.0);
                            },
                            child: Container(
                              width: 8,
                              color: Colors.transparent,
                              child: Center(
                                child: Container(width: 2, color: Theme.of(context).dividerColor),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            );
          }),

          // 主阅读区域
          Expanded(
            child: Column(
              children: [
                ReaderToolbar(controller: controller),
                const Divider(height: 1),
                Expanded(
                  child: Obx(() {
                    if (controller.isLoading.value) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (controller.errorMessage.value.isNotEmpty) {
                      return _buildErrorView();
                    }

                    return ReaderContent(controller: controller);
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            controller.errorMessage.value,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => controller.loadNovelContent(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// AppBar 中的 Hero 封面缩略图，与书籍列表的 Hero 动画配对
  Widget _buildHeroCover(double size) {
    Widget cover;
    if (novel.coverPath != null) {
      try {
        final file = File(novel.coverPath!);
        if (file.existsSync()) {
          cover = ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(file, width: size, height: size * 1.4, fit: BoxFit.cover),
          );
        } else {
          cover = _defaultCoverThumb(size);
        }
      } catch (_) {
        cover = _defaultCoverThumb(size);
      }
    } else {
      cover = _defaultCoverThumb(size);
    }
    return Hero(tag: 'book_cover_${novel.id}', child: cover);
  }

  Widget _defaultCoverThumb(double size) {
    return Container(
      width: size,
      height: size * 1.4,
      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
      child: Icon(Icons.book, size: size * 0.5, color: Colors.white70),
    );
  }
}
