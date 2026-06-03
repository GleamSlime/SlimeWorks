import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/widgets/common_widget.dart';
import 'package:slime_works/pages/collection/library/components/library_book_info_dialog.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class RemoteNovelReaderDialog extends StatefulWidget {
  final NovelMetadata metadata;
  final String nodeId;
  final String nodeName;

  const RemoteNovelReaderDialog({
    super.key,
    required this.metadata,
    required this.nodeId,
    required this.nodeName,
  });

  @override
  State<RemoteNovelReaderDialog> createState() => _RemoteNovelReaderDialogState();
}

class _RemoteNovelReaderDialogState extends State<RemoteNovelReaderDialog> {
  final NodeSettingsService _service = getIt<NodeSettingsService>();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chapters = await _service.fetchNodeNovelContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
      );
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loading = false;
        _selected = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters.isEmpty ? null : _chapters[_selected];
    final chapterText = (chapter?['content'] ?? '').toString();

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 960,
        height: 680,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: appMetrics.kSpace12,
                vertical: appMetrics.kSpace10,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.metadata.title}  ·  ${widget.nodeName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('加载失败: $_error'))
                  : Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: ListView.separated(
                            itemCount: _chapters.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final title = (_chapters[index]['title'] ?? '章节 ${index + 1}')
                                  .toString();
                              return ListTile(
                                selected: index == _selected,
                                title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                onTap: () => setState(() => _selected = index),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(appMetrics.kSpace12),
                            child: _buildChapterContent(context, chapterText),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemoteNovelReaderPage extends StatefulWidget {
  final NovelMetadata metadata;
  final String nodeId;
  final String nodeName;

  const RemoteNovelReaderPage({
    super.key,
    required this.metadata,
    required this.nodeId,
    required this.nodeName,
  });

  @override
  State<RemoteNovelReaderPage> createState() => _RemoteNovelReaderPageState();
}

class _RemoteNovelReaderPageState extends State<RemoteNovelReaderPage> {
  final NodeSettingsService _service = getIt<NodeSettingsService>();
  final DesktopScreenProvider _desktopScreen = getIt<DesktopScreenProvider>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const double _kChapterSwipeTrigger = 72;

  bool _loading = true;
  bool _chapterLoading = false;
  String? _error;
  String? _chapterError;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;
  String _chapterText = '';
  Color _readerBgColor = const Color(0xFFF6F0E7);
  double _readerFontSize = 16;
  double _readerLineHeight = 1.8;
  double _leadingOverscroll = 0;
  double _trailingOverscroll = 0;
  bool _chapterSwipeLocked = false;

  String _chapterTitleAt(int index) {
    if (index < 0 || index >= _chapters.length) {
      return widget.metadata.title;
    }
    final title = (_chapters[index]['title'] ?? '').toString().trim();
    if (title.isEmpty) {
      return '章节 ${index + 1}';
    }
    return title;
  }

  EdgeInsets _mobileReaderImmersivePadding() {
    return EdgeInsets.only(top: AppTheme.metrics.kSpace16, bottom: AppTheme.metrics.kSpace24);
  }

  double _mobileReaderBottomBarHeight() {
    return scaleW(64);
  }

  EdgeInsets _mobileReaderContentPadding(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final immersivePadding = _mobileReaderImmersivePadding();
    final isImmersiveMode = _desktopScreen.mobileImmersiveMode.value;

    return EdgeInsets.fromLTRB(
      appMetrics.kSpace12,
      mediaPadding.top +
          immersivePadding.top +
          (isImmersiveMode ? 0 : AppTheme.metrics.kSpace48 + AppTheme.metrics.kSpace24),
      appMetrics.kSpace12,
      mediaPadding.bottom +
          immersivePadding.bottom +
          (isImmersiveMode ? 0 : _mobileReaderBottomBarHeight()),
    );
  }

  void _resetChapterSwipe() {
    _leadingOverscroll = 0;
    _trailingOverscroll = 0;
    _chapterSwipeLocked = false;
  }

  bool _handleChapterSwipeNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _resetChapterSwipe();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      if (metrics.pixels > metrics.minScrollExtent && metrics.pixels < metrics.maxScrollExtent) {
        _leadingOverscroll = 0;
        _trailingOverscroll = 0;
      }
      return false;
    }

    if (notification is OverscrollNotification && !_chapterSwipeLocked) {
      final metrics = notification.metrics;
      if (notification.overscroll < 0 &&
          _selected > 0 &&
          metrics.pixels <= metrics.minScrollExtent + 0.5) {
        _leadingOverscroll += -notification.overscroll;
        _trailingOverscroll = 0;
        if (_leadingOverscroll >= _kChapterSwipeTrigger) {
          _chapterSwipeLocked = true;
          HapticFeedback.selectionClick();
          _loadChapter(_selected - 1);
        }
      } else if (notification.overscroll > 0 &&
          _selected < _chapters.length - 1 &&
          metrics.pixels >= metrics.maxScrollExtent - 0.5) {
        _trailingOverscroll += notification.overscroll;
        _leadingOverscroll = 0;
        if (_trailingOverscroll >= _kChapterSwipeTrigger) {
          _chapterSwipeLocked = true;
          HapticFeedback.selectionClick();
          _loadChapter(_selected + 1);
        }
      }
      return false;
    }

    if (notification is ScrollEndNotification ||
        notification is UserScrollNotification && notification.direction == ScrollDirection.idle) {
      _resetChapterSwipe();
    }

    return false;
  }

  void _showBookInfoDialog() {
    final vm = Get.find<NovelLibraryViewModel>();
    showDialog<void>(
      context: context,
      builder: (ctx) => LibraryBookInfoDialog(metadata: widget.metadata, viewModel: vm),
    );
  }

  void _showReaderSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
                    Text(
                      '阅读设置',
                      style: TextStyle(
                        fontSize: AppTheme.metrics.fontSize15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace12),
                    Row(
                      children: [
                        const Text('字体大小'),
                        const Spacer(),
                        Text(_readerFontSize.toStringAsFixed(0)),
                      ],
                    ),
                    Slider(
                      value: _readerFontSize,
                      min: 12,
                      max: 32,
                      divisions: 10,
                      label: _readerFontSize.toStringAsFixed(0),
                      onChanged: (value) {
                        setState(() => _readerFontSize = value);
                        setModalState(() {});
                      },
                    ),
                    Row(
                      children: [
                        const Text('行间距'),
                        const Spacer(),
                        Text(_readerLineHeight.toStringAsFixed(1)),
                      ],
                    ),
                    Slider(
                      value: _readerLineHeight,
                      min: 1.2,
                      max: 2.6,
                      divisions: 7,
                      label: _readerLineHeight.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _readerLineHeight = value);
                        setModalState(() {});
                      },
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace8),
                    const Text('背景色'),
                    SizedBox(height: AppTheme.metrics.kSpace8),
                    Wrap(
                      spacing: 10,
                      children:
                          [
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chapters = await _service.fetchNodeNovelContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
      );
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loading = false;
        _selected = 0;
      });
      if (chapters.isNotEmpty) {
        await _loadChapter(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadChapter(int index) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    setState(() {
      _selected = index;
      _chapterLoading = true;
      _chapterError = null;
    });

    try {
      final content = await _service.fetchNodeChapterContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
        chapterIndex: index,
      );
      if (!mounted) return;
      setState(() {
        _chapterText = content;
        _chapterLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chapterText = '';
        _chapterError = e.toString();
        _chapterLoading = false;
      });
    }
  }

  ScreenChromeData _buildMobileScreenChromeData() {
    return ScreenChromeData(
      title: widget.metadata.title,
      enableMobileImmersiveMode: true,
      mobileBodyHandlesInsets: true,
      mobileImmersivePadding: _mobileReaderImmersivePadding(),
      leading: appBarBackButton(context, prevRoutePath: '/collection/library'),
      toolbarHeight: AppTheme.metrics.kSpace24,
      toolbar: Text(_chapterTitleAt(_selected), maxLines: 1, overflow: TextOverflow.ellipsis),
      bottomBarHeight: _mobileReaderBottomBarHeight(),
      bottomBar: _RemoteReaderBottomBar(
        canGoPrevious: _selected > 0,
        canGoNext: _selected < _chapters.length - 1,
        onPrevious: _selected > 0 ? () => _loadChapter(_selected - 1) : null,
        onNext: _selected < _chapters.length - 1 ? () => _loadChapter(_selected + 1) : null,
        onOpenCatalog: () => _scaffoldKey.currentState?.openDrawer(),
        onShowBookInfo: _showBookInfoDialog,
        onShowReaderSettings: _showReaderSettingsSheet,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      data: _buildMobileScreenChromeData(),
      child: Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    appMetrics.kSpace12,
                    appMetrics.kSpace12,
                    appMetrics.kSpace12,
                    appMetrics.kSpace8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.metadata.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: appMetrics.kSpace4),
                      Text(
                        widget.nodeName,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          itemCount: _chapters.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final title = _chapterTitleAt(index);
                            return ListTile(
                              selected: index == _selected,
                              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                _loadChapter(index);
                                Navigator.of(context).maybePop();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('加载失败: $_error'))
            : _chapterLoading
            ? const Center(child: CircularProgressIndicator())
            : _chapterError != null
            ? Center(child: Text('加载章节失败: $_chapterError'))
            : Container(
                color: _readerBgColor,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleChapterSwipeNotification,
                  child: _buildChapterContent(
                    context,
                    _chapterText,
                    contentPadding: _mobileReaderContentPadding(context),
                    fontSize: _readerFontSize,
                    lineHeight: _readerLineHeight,
                  ),
                ),
              ),
      ),
    );
  }
}

Widget _buildChapterContent(
  BuildContext context,
  String content, {
  EdgeInsets contentPadding = EdgeInsets.zero,
  double fontSize = 16,
  double lineHeight = 1.8,
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const Center(child: Text('正文为空'));
  }

  final looksLikeHtml =
      trimmed.contains('<p') ||
      trimmed.contains('<div') ||
      trimmed.contains('<span') ||
      trimmed.contains('<img') ||
      trimmed.contains('<br') ||
      trimmed.contains('</');

  if (looksLikeHtml) {
    return SingleChildScrollView(
      padding: contentPadding,
      child: HtmlWidget(
        trimmed,
        textStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontSize: fontSize, height: lineHeight),
        customStylesBuilder: (element) {
          switch (element.localName) {
            case 'p':
            case 'div':
              return {
                'display': 'block',
                'line-height': lineHeight.toStringAsFixed(2),
                'margin-bottom': '16px',
              };
          }
          return null;
        },
      ),
    );
  }

  return SingleChildScrollView(
    padding: contentPadding,
    child: SelectableText(
      trimmed,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: fontSize, height: lineHeight),
    ),
  );
}

class _RemoteReaderBottomBar extends StatelessWidget {
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onOpenCatalog;
  final VoidCallback onShowBookInfo;
  final VoidCallback onShowReaderSettings;

  const _RemoteReaderBottomBar({
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenCatalog,
    required this.onShowBookInfo,
    required this.onShowReaderSettings,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withAlpha(245),
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8),
        child: Row(
          children: [
            IconButton(
              tooltip: '目录',
              onPressed: onOpenCatalog,
              icon: const Icon(Icons.menu_book_outlined),
            ),
            IconButton(
              tooltip: '上一章',
              onPressed: canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(child: Text('章节', style: theme.textTheme.labelLarge)),
            ),
            IconButton(
              tooltip: '下一章',
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: '书籍详情',
              onPressed: onShowBookInfo,
              icon: const Icon(Icons.info_outline),
            ),
            IconButton(
              tooltip: '阅读设置',
              onPressed: onShowReaderSettings,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      ),
    );
  }
}
