import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/pages/collection/library/components/library_book_info_dialog.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/pages/novel_reader/components/chapter_list.dart';
import 'package:slime_works/pages/novel_reader/components/reader_toolbar.dart';
import 'package:slime_works/pages/novel_reader/components/reader_content.dart';
import 'dart:async';

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
  final DesktopScreenProvider _desktopScreen = getIt<DesktopScreenProvider>();
  bool _immersiveMode = false;
  Timer? _immersiveTimer;
  Color _readerBgColor = const Color(0xFFF6F0E7);
  String? _lastSyncedTitle;
  bool? _lastSyncedShowChapterList;
  bool? _lastSyncedIsNarrow;

  @override
  void initState() {
    super.initState();
    // 优先使用传入的 novel，如果没有则尝试从 Get.arguments 获取（兼容旧代码）
    novel = widget.novel ?? Get.arguments as NovelMetadata;
    controller = Get.put(NovelReaderViewModel(novel), tag: novel.id);
    debugPrint('NovelReaderPage initialized with novel: ${novel.title} (ID: ${novel.id})');
  }

  @override
  void dispose() {
    _immersiveTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _desktopScreen.setTitle('');
      _desktopScreen.setScreenHeadToolsWidget(null);
    });
    try {
      Get.delete<NovelReaderViewModel>(tag: novel.id);
    } catch (_) {}
    super.dispose();
  }

  void _scheduleImmersiveMode() {
    _immersiveTimer?.cancel();
    _immersiveTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() {
        _immersiveMode = true;
      });
    });
  }

  void _exitImmersiveMode() {
    _immersiveTimer?.cancel();
    if (!mounted || !_immersiveMode) return;
    setState(() {
      _immersiveMode = false;
    });
  }

  void _showReaderSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('阅读设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('字体大小'),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            controller.decreaseFontSize();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Obx(() => Text(controller.fontSize.value.toStringAsFixed(0))),
                        IconButton(
                          onPressed: () {
                            controller.increaseFontSize();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('背景色'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        const Color(0xFFF6F0E7),
                        const Color(0xFFFFFFFF),
                        const Color(0xFFEAF4E8),
                        const Color(0xFFEAF1F8),
                        const Color(0xFF1F1F1F),
                      ]
                          .map(
                            (color) => GestureDetector(
                              onTap: () {
                                setState(() => _readerBgColor = color);
                                setModalState(() {});
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _readerBgColor == color
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: _readerBgColor == color ? 2 : 1,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBookInfoDialog() {
    final libraryVm = Get.find<NovelLibraryViewModel>();
    showDialog<void>(
      context: context,
      builder: (ctx) => LibraryBookInfoDialog(metadata: novel, viewModel: libraryVm),
    );
  }

  String _currentChapterTitle() {
    final index = controller.currentChapterIndex.value;
    if (index >= 0 && index < controller.chapters.length) {
      final title = controller.chapters[index].title.trim();
      if (title.isNotEmpty) {
        return title;
      }
    }
    return '目录';
  }

  String _mobileLayoutTitle() {
    return controller.showChapterList.value ? _currentChapterTitle() : novel.title;
  }

  void _syncMobileTopBar() {
    if (!mounted) return;
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final showChapterList = controller.showChapterList.value;
    final appBarTitle = _mobileLayoutTitle();

    if (_lastSyncedIsNarrow == isNarrow &&
        _lastSyncedShowChapterList == showChapterList &&
        _lastSyncedTitle == appBarTitle) {
      return;
    }

    _lastSyncedIsNarrow = isNarrow;
    _lastSyncedShowChapterList = showChapterList;
    _lastSyncedTitle = appBarTitle;

    if (!isNarrow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _desktopScreen.setTitle('');
        _desktopScreen.setScreenHeadToolsWidget(null);
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _desktopScreen.setTitle(appBarTitle);

      _desktopScreen.setScreenHeadToolsWidget(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DesktopHeadToolsButton(
              icon: const Icon(Icons.info_outline),
              size: AppTheme.metrics.kSpace40,
              onTap: _showBookInfoDialog,
            ),
            DesktopHeadToolsButton(
              icon: const Icon(Icons.tune),
              size: AppTheme.metrics.kSpace40,
              onTap: _showReaderSettingsSheet,
            ),
            Obx(() {
              final libraryVm = Get.find<NovelLibraryViewModel>();
              final isFav =
                  libraryVm.novels.firstWhereOrNull((n) => n.id == novel.id)?.isFavorite ?? false;
              return DesktopHeadToolsButton(
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                size: AppTheme.metrics.kSpace40,
                onTap: () => libraryVm.toggleFavorite(novel.id),
              );
            }),
            DesktopHeadToolsButton(
              icon: Icon(
                showChapterList ? Icons.chrome_reader_mode_outlined : Icons.menu_book_outlined,
              ),
              size: AppTheme.metrics.kSpace40,
              onTap: controller.toggleChapterList,
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 注入 context 供 ViewModel 显示对话框（MaterialApp.router 不支持 Get.dialog）
    controller.setContext(context);
    final isNarrow = MediaQuery.of(context).size.width < 600;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMobileTopBar());

    // 移动端默认收起章节列表
    if (isNarrow && controller.chapters.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.showChapterList.value) {
          controller.showChapterList.value = false;
        }
      });
    }

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
      return Obx(() {
        final showChapterList = controller.showChapterList.value;
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncMobileTopBar());

        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _scheduleImmersiveMode,
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  color: _readerBgColor,
                  child: Column(
                    children: [
                      Expanded(
                        child: NotificationListener<UserScrollNotification>(
                          onNotification: (notification) {
                            if (notification.direction == ScrollDirection.reverse) {
                              _scheduleImmersiveMode();
                            } else if (notification.direction == ScrollDirection.forward) {
                              _exitImmersiveMode();
                            }
                            return false;
                          },
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
                      ),
                    ],
                  ),
                ),
                if (showChapterList)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: controller.toggleChapterList,
                      child: Container(
                        color: Colors.black54,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () {},
                            child: SizedBox(
                                  width: MediaQuery.of(context).size.width * 0.75,
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: ChapterList(controller: controller),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_immersiveMode)
                  Positioned(
                    right: 16,
                    bottom: 24,
                    child: FloatingActionButton.small(
                      heroTag: 'immersive_tools',
                      onPressed: _showReaderSettingsSheet,
                      child: const Icon(Icons.tune),
                    ),
                  ),
              ],
            ),
          ),
        );
      });
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
          IconButton(
            tooltip: '书籍详情',
            onPressed: _showBookInfoDialog,
            icon: const Icon(Icons.info_outline),
          ),
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
