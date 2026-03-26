import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
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
                            separatorBuilder: (_, __) => const Divider(height: 1),
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final DesktopScreenProvider _desktopScreen = getIt<DesktopScreenProvider>();

  bool _loading = true;
  bool _chapterLoading = false;
  String? _error;
  String? _chapterError;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;
  String _chapterText = '';

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

  void _showBookInfoDialog() {
    final vm = Get.find<NovelLibraryViewModel>();
    showDialog<void>(
      context: context,
      builder: (ctx) => LibraryBookInfoDialog(metadata: widget.metadata, viewModel: vm),
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
      leading: appBarBackButton(context, prevRoutePath: '/collection/library'),
      toolbarHeight: AppTheme.metrics.kSpace24,
      toolbar: Text(_chapterTitleAt(_selected), maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          padding: EdgeInsets.zero,
          tooltip: '书籍详情',
          onPressed: _showBookInfoDialog,
          icon: const Icon(Icons.info_outline),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          tooltip: '目录',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_book_outlined),
        ),
      ],
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
                          separatorBuilder: (_, __) => const Divider(height: 1),
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
        floatingActionButton: FloatingActionButton(
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          child: const Icon(Icons.menu_book_outlined),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('加载失败: $_error'))
            : _chapterLoading
            ? const Center(child: CircularProgressIndicator())
            : _chapterError != null
            ? Center(child: Text('加载章节失败: $_chapterError'))
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace12),
                child: _buildChapterContent(context, _chapterText),
              ),
      ),
    );
  }
}

Widget _buildChapterContent(BuildContext context, String content) {
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
      child: HtmlWidget(trimmed, textStyle: Theme.of(context).textTheme.bodyMedium),
    );
  }

  return SingleChildScrollView(
    child: SelectableText(trimmed, style: Theme.of(context).textTheme.bodyMedium),
  );
}
