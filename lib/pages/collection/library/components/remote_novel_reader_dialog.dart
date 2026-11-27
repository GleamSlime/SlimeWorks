import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/reader_paginator.dart';
import 'package:slime_works/pages/collection/library/components/library_book_info_dialog.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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
  // 当前章节正文：必须单独向节点请求（EPUB 的 content 恒为 None）
  bool _chapterLoading = false;
  String? _chapterError;
  String _chapterText = '';

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
        // 恢复到上次读到的章节。
        // metadata.progress 是 0~1 的归一化进度（节点侧持久化），
        // 之前远程阅读路径完全不用它，所以永远是第 1 章。
        _selected = _chapterIndexForProgress(chapters.length, widget.metadata.progress);
      });
      // 列表到手后再取正文（EPUB 的 content 是延迟加载的）
      if (chapters.isNotEmpty) {
        await _loadChapter(_selected);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 加载指定章节的正文。
  ///
  /// 必须单独请求：EPUB 解析器把每章标成 `content: None`（延迟加载），
  /// 正文只能靠 `get_chapter_content` 按 index 取。桌面对话框此前直接用
  /// payload 里的 content，导致 **EPUB 书正文永远空白**（TXT 内联全文所以看不出来）。
  Future<void> _loadChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
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

  /// 把 0~1 的进度换算成章节下标（夹在合法范围内）。
  int _chapterIndexForProgress(int count, double progress) {
    if (count <= 0) return 0;
    final raw = (progress.clamp(0.0, 1.0) * count).floor();
    return raw.clamp(0, count - 1);
  }

  /// 把当前章节位置写回节点。
  ///
  /// 只在「章节真的切过」或关闭时保存——翻页（同一章内滚动）不必每次写节点。
  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final progress = (_selected + 1) / _chapters.length;
    // ★ 必须用节点侧的原始 id。
    // `metadata.id` 是客户端合成的 `remote:<nodeId>:<rawId>`，直接发过去节点
    // 按 id 精确查库必然查不到 → require_changed 报错 → 被 catch 吞掉 →
    // **进度永远存不进去**，表现就是「退出后又是从头读」。
    final novelId = _rawNovelIdFor(widget.metadata.id);
    try {
      await _service.updateNodeNovelProgress(
        nodeId: widget.nodeId,
        novelId: novelId,
        progress: progress.clamp(0.0, 1.0),
      );
    } catch (e) {
      // 进度保存失败不该打断阅读，但要留痕（这是「下次打开还在原处」的保证）
      debugPrint('保存远程阅读进度失败: $e');
    }
  }

  /// 从合成 id 取节点侧原始 novel id：`remote:<nodeId>:<rawId>` → `<rawId>`。
  /// 不是合成格式时原样返回（兼容本机/旧数据）。
  String _rawNovelIdFor(String id) {
    const prefix = 'remote:';
    if (!id.startsWith(prefix)) return id;
    final rest = id.substring(prefix.length);
    final sep = rest.indexOf(':');
    return sep < 0 ? rest : rest.substring(sep + 1);
  }

  @override
  void dispose() {
    // 关闭对话框时补存一次：用户往往是读完直接关
    _persistProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ★ 正文一律取 `_chapterText`，不要用 `_chapters[_selected]['content']`：
    // EPUB 解析器把每章标成 `content: None`（延迟加载，见 parser_epub.rs 里
    // `content: None, // 延迟加载，由 get_chapter_content 提供`）。
    // 用 payload 里的 content 会让 **EPUB 书正文永远空白**——TXT 因为内联了
    // 全文才看不出问题，所以这个 bug 只在 epub 上暴露。
    final chapterText = _chapterText;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: scaleW(960),
        height: scaleH(680),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: appMetrics.kSpace12,
                vertical: appMetrics.kSpace10,
              ),
              color: AppSemantic.of(context).surfaceRaised,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.metadata.title}  ·  ${widget.nodeName}',
                      style: AppTextStyles.role(
                        context,
                        fontSize: appMetrics.fontSize14,
                        weight: FontWeight.w500,
                        color: AppSemantic.of(context).textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: DrawIcon(StrokeIcons.close),
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
                          width: scaleW(280),
                          child: ListView.separated(
                            itemCount: _chapters.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final title = (_chapters[index]['title'] ?? '章节 ${index + 1}')
                                  .toString();
                              return ListTile(
                                selected: index == _selected,
                                title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  // 必须走 _loadChapter：它负责取正文 + 置加载态。
                                  // 旧实现只 setState(_selected)，正文压根不跟着变
                                  // （EPUB 尤其明显：content 恒 null，永远是空白）
                                  _loadChapter(index);
                                  // 切章即保存：用户读完一章往往直接关掉，
                                  // 只在 dispose 存会让「读完没关」那一下丢失
                                  _persistProgress();
                                },
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(appMetrics.kSpace12),
                            child: _chapterLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _chapterError != null
                                ? Center(child: Text('加载章节失败: $_chapterError'))
                                : _buildChapterContent(context, chapterText),
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
  final PageController _pageController = PageController();
  final List<GlobalKey> _chapterKeys = <GlobalKey>[];

  bool _loading = true;
  bool _chapterLoading = false;
  String? _error;
  String? _chapterError;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;
  int _furthestChapterReached = 0;
  int _chapterRequestId = 0;
  String _chapterText = '';
  List<String> _pages = <String>[''];
  int _pageIndex = 0;
  int? _pendingPageTarget;
  double? _pendingPageFraction;
  Object? _paginationKey;
  bool _selectionActive = false;
  int? _pointerId;
  Offset? _pointerDown;
  Offset? _pointerLast;
  bool _pointerStartedWithSelection = false;
  Color _readerBgColor = AppReaderPaper.parchment;
  double _readerFontSize = 16;
  double _readerLineHeight = 1.8;

  /// 本地沉浸模式状态。
  ///
  /// ★ 不要用全局 `DesktopScreenProvider.mobileImmersiveMode`：实测
  /// `ScreenChromeData.enableMobileImmersiveMode` 在 ScreenChrome 里**从未被消费**
  /// （是个死参数），所以走全局状态不会有任何视觉变化。
  /// 本地阅读器 `novel_reader_page.dart` 早就改成"自己画覆盖层 + AnimatedSlide"，
  /// 远程阅读页照同一套做，两边观感才一致。
  final RxBool _isImmersive = false.obs;

  /// 收藏状态：初值取列表传进来的 metadata，切换后本地先反馈再写节点。
  late bool _isFavorite = widget.metadata.isFavorite;
  Timer? _immersiveTimer;
  static const Duration _kOverlayAnim = AppMotion.fast;

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

  double _mobileReaderBottomBarHeight() {
    return scaleW(64);
  }

  /// 正文区的内边距。
  ///
  /// 本页的顶栏/底栏是 `Stack` 里的覆盖层（为了做沉浸滑动动画），
  /// 它们**不占布局空间**，所以正文要自己把顶上那一条和底下那一条让出来。
  /// 沉浸模式下两者都滑走，正文就能占满整屏。
  EdgeInsets _mobileReaderContentPadding(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final isImmersive = _isImmersive.value;
    return EdgeInsets.fromLTRB(
      appMetrics.kSpace12, // 左右呼吸
      insets.top +
          AppTheme.metrics.kSpace48 +
          (isImmersive ? 0 : AppTheme.metrics.kSpace8),
      appMetrics.kSpace12,
      insets.bottom +
          (isImmersive
              ? AppTheme.metrics.kSpace16
              : _mobileReaderBottomBarHeight()),
    );
  }

  void _setImmersive(bool on) {
    if (!mounted) return;
    if (_isImmersive.value == on) return;
    _immersiveTimer?.cancel();
    _isImmersive.value = on;
    if (!on) _scheduleImmersiveIdle();
  }

  /// 停留一段时间无操作后自动进入沉浸（把屏幕还给文字）
  void _scheduleImmersiveIdle() {
    _immersiveTimer?.cancel();
    if (_isImmersive.value) return;
    _immersiveTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _setImmersive(true);
    });
  }

  void _schedulePageJump(int page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (page < 0 || page >= _pages.length) return;
      _pageController.jumpToPage(page);
    });
  }

  void _syncPagination(Object key, List<String> nextPages) {
    if (_paginationKey == key) return;

    final hadLayout = _paginationKey != null;
    var target = _pageIndex;
    if (_pendingPageTarget != null) {
      final pending = _pendingPageTarget!;
      target = pending < 0 ? nextPages.length - 1 : pending;
      _pendingPageTarget = null;
    } else if (_pendingPageFraction != null) {
      final fraction = _pendingPageFraction!.clamp(0.0, 1.0);
      target = nextPages.length <= 1
          ? 0
          : (fraction * (nextPages.length - 1)).round();
      _pendingPageFraction = null;
    } else if (hadLayout && _pages.isNotEmpty) {
      final previousLength = _pages.fold<int>(
        0,
        (sum, page) => sum + page.length,
      );
      final consumed = _pages
          .take(_pageIndex.clamp(0, _pages.length - 1))
          .fold<int>(0, (sum, page) => sum + page.length);
      final fraction = previousLength == 0 ? 0.0 : consumed / previousLength;
      target = (fraction * nextPages.length).floor();
    }
    target = target.clamp(0, nextPages.length - 1);

    _paginationKey = key;
    _pages = nextPages;
    if (target != _pageIndex) {
      _pageIndex = target;
      _schedulePageJump(target);
    }
  }

  void _onPageChanged(int index) {
    if (_pageIndex == index) return;
    setState(() => _pageIndex = index);
    if (!_isImmersive.value) _scheduleImmersiveIdle();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length || index == _pageIndex) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: AppMotion.base,
        curve: AppMotion.decelerate,
      );
    } else {
      setState(() => _pageIndex = index);
    }
    if (!_isImmersive.value) _scheduleImmersiveIdle();
  }

  void _turnPage(int direction) {
    if (_chapterLoading || _selectionActive || _pages.isEmpty) return;
    if (direction > 0) {
      if (_pageIndex < _pages.length - 1) {
        _goToPage(_pageIndex + 1);
      } else if (_selected < _chapters.length - 1) {
        HapticFeedback.selectionClick();
        _loadChapter(_selected + 1, initialPage: 0);
      }
    } else {
      if (_pageIndex > 0) {
        _goToPage(_pageIndex - 1);
      } else if (_selected > 0) {
        HapticFeedback.selectionClick();
        _loadChapter(_selected - 1, initialPage: -1);
      }
    }
  }

  void _handleReaderPointerDown(PointerDownEvent event) {
    if (_pointerId != null || event.buttons != kPrimaryButton) return;
    _pointerId = event.pointer;
    _pointerDown = event.localPosition;
    _pointerLast = event.localPosition;
    _pointerStartedWithSelection = _selectionActive;
  }

  void _handleReaderPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerLast = event.localPosition;
  }

  void _handleReaderPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointerId) return;
    final down = _pointerDown;
    final last = _pointerLast ?? event.localPosition;
    _pointerId = null;
    _pointerDown = null;
    _pointerLast = null;
    final startedWithSelection = _pointerStartedWithSelection;
    _pointerStartedWithSelection = false;
    if (down == null ||
        startedWithSelection ||
        _chapterLoading ||
        _selectionActive) {
      return;
    }

    final delta = last - down;
    final tapSlop = scaleW(12);
    final swipeSlop = scaleW(48);
    if (delta.dx.abs() >= swipeSlop && delta.dx.abs() > delta.dy.abs()) {
      _turnPage(delta.dx < 0 ? 1 : -1);
      return;
    }
    if (delta.dy.abs() >= swipeSlop && delta.dy.abs() > delta.dx.abs()) {
      _setImmersive(delta.dy > 0);
      return;
    }
    if (delta.distance > tapSlop) return;

    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    if (down.dx < width / 3) {
      _turnPage(-1);
    } else if (down.dx > width * 2 / 3) {
      _turnPage(1);
    } else {
      _setImmersive(!_isImmersive.value);
    }
  }

  void _handleReaderPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointerId) return;
    _pointerId = null;
    _pointerDown = null;
    _pointerLast = null;
    _pointerStartedWithSelection = false;
  }

  void _handleReaderSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    final active = !selection.isCollapsed;
    if (_selectionActive == active) return;
    setState(() => _selectionActive = active);
  }

  void _openCatalog() {
    _setImmersive(false);
    _scaffoldKey.currentState?.openDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selected < 0 || _selected >= _chapterKeys.length) return;
      final targetContext = _chapterKeys[_selected].currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: AppMotion.base,
        curve: AppMotion.decelerate,
      );
    });
  }

  void _showBookInfoDialog() {
    final vm = Get.find<NovelLibraryViewModel>();
    showDialog<void>(
      context: context,
      builder: (ctx) =>
          LibraryBookInfoDialog(metadata: widget.metadata, viewModel: vm),
    );
  }

  /// 书中搜索：在本书全部章节里找关键词，点结果直接跳到那一章。
  ///
  /// 节点侧 `search_in_novel` 早就实现了，缺的一直是这个入口。
  void _showInBookSearch() {
    _setImmersive(false);
    final controller = TextEditingController();
    var searching = false;
    var queried = false;
    List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    String? err;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> runSearch() async {
              final kw = controller.text.trim();
              if (kw.isEmpty) return;
              setModal(() {
                searching = true;
                err = null;
              });
              try {
                final found = await _service.searchInNodeNovel(
                  nodeId: widget.nodeId,
                  filePath: widget.metadata.filePath,
                  keyword: kw,
                );
                if (!ctx.mounted) return;
                setModal(() {
                  results = found;
                  queried = true;
                  searching = false;
                });
              } catch (e) {
                if (!ctx.mounted) return;
                setModal(() {
                  err = e.toString();
                  searching = false;
                  queried = true;
                });
              }
            }

            return Padding(
              // 键盘弹起时把内容顶上去，否则输入框被遮住
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppTheme.metrics.kSpace16,
                          0,
                          AppTheme.metrics.kSpace16,
                          AppTheme.metrics.kSpace8,
                        ),
                        child: Text(
                          '在本书中搜索',
                          style: AppTextStyles.sectionTitle(ctx),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.metrics.kSpace16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => runSearch(),
                                decoration: const InputDecoration(
                                  hintText: '输入关键词',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace8),
                            FilledButton(
                              onPressed: searching ? null : runSearch,
                              child: searching
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('搜索'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppTheme.metrics.kSpace12),
                      Expanded(
                        child: err != null
                            ? Center(child: Text('搜索失败: $err'))
                            : !queried
                            ? const Center(child: Text('输入关键词后点搜索'))
                            : results.isEmpty
                            ? const Center(child: Text('没有找到匹配内容'))
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final r = results[i];
                                  final idx =
                                      int.tryParse(
                                        '${r['chapter_index'] ?? 0}',
                                      ) ??
                                      0;
                                  return ListTile(
                                    title: Text(
                                      '${r['chapter_title'] ?? '第 ${idx + 1} 章'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${r['snippet'] ?? ''}'.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _loadChapter(idx);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
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
                padding: EdgeInsets.fromLTRB(
                  AppTheme.metrics.kSpace16,
                  AppTheme.metrics.kSpace16,
                  AppTheme.metrics.kSpace16,
                  AppTheme.metrics.kSpace24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('阅读设置', style: AppTextStyles.sectionTitle(context)),
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
                      spacing: AppTheme.metrics.kSpace10,
                      children: AppReaderPaper.presets
                          .map(
                            (color) => GestureDetector(
                              onTap: () {
                                setState(() => _readerBgColor = color);
                                setModalState(() {});
                              },
                              child: Container(
                                width: scaleW(30),
                                height: scaleW(30),
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    // 未选中的纸色样品只靠描边分层，选中才升到强调底
                                    color: _readerBgColor == color
                                        ? AppSemantic.of(context).accent
                                        : AppSemantic.of(context).borderStrong,
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
    _scheduleImmersiveIdle();
  }

  /// 把 0~1 的进度换算成章节下标（夹在合法范围内）。
  int _chapterIndexForProgress(int count, double progress) {
    if (count <= 0) return 0;
    final raw = (progress.clamp(0.0, 1.0) * count).floor();
    return raw.clamp(0, count - 1);
  }

  /// 合成 id → 节点侧原始 id（`remote:<node>:<raw>` → `<raw>`）。
  String _rawNovelIdFor(String id) {
    const prefix = 'remote:';
    if (!id.startsWith(prefix)) return id;
    final rest = id.substring(prefix.length);
    final sep = rest.indexOf(':');
    return sep < 0 ? rest : rest.substring(sep + 1);
  }

  /// 切换收藏：先本地乐观更新（按钮立刻响应），再落节点。
  /// 失败则回滚并提示，避免"看起来收藏了其实没存"。
  Future<void> _toggleFavorite() async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      final raw = _rawNovelIdFor(widget.metadata.id);
      await _service.setNodeNovelFavorite(
        nodeId: widget.nodeId,
        novelId: raw,
        isFavorite: next,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = !next);
      debugPrint('切换远程收藏失败: $e');
    }
  }

  /// 把当前章节位置写回节点（下次打开能续读）。
  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final pageFraction = _pages.length <= 1
        ? 1.0
        : _pageIndex / (_pages.length - 1);
    final progress = (_selected + pageFraction) / _chapters.length;
    try {
      await _service.updateNodeNovelProgress(
        nodeId: widget.nodeId,
        novelId: _rawNovelIdFor(widget.metadata.id),
        progress: progress.clamp(0.0, 1.0),
      );
    } catch (e) {
      debugPrint('保存远程阅读进度失败: $e');
    }
  }

  @override
  void dispose() {
    // 关页补存一次：用户往往读完直接退
    _persistProgress();
    _immersiveTimer?.cancel();
    _pageController.dispose();
    _isImmersive.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final chapters = await _service.fetchNodeNovelContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
      );
      if (!mounted) return;
      // 恢复到上次读到的章节。此前这里硬编码 _selected = 0，
      // 于是每次打开都从头开始（用户报的「没有阅读历史」）。
      final resume = _chapterIndexForProgress(
        chapters.length,
        widget.metadata.progress,
      );
      setState(() {
        _chapters = chapters;
        _chapterKeys
          ..clear()
          ..addAll(
            List<GlobalKey>.generate(chapters.length, (_) => GlobalKey()),
          );
        _loading = false;
        _selected = resume;
        _furthestChapterReached = resume;
      });
      if (chapters.isNotEmpty) {
        final rawPosition =
            widget.metadata.progress.clamp(0.0, 1.0) * chapters.length;
        final pageFraction =
            resume == chapters.length - 1 && rawPosition >= chapters.length
            ? 1.0
            : rawPosition - resume;
        await _loadChapter(resume, pageFraction: pageFraction.clamp(0.0, 1.0));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadChapter(
    int index, {
    int? initialPage,
    double? pageFraction,
  }) async {
    if (index < 0 || index >= _chapters.length) {
      return;
    }

    final requestId = ++_chapterRequestId;
    setState(() {
      _selected = index;
      _furthestChapterReached = index > _furthestChapterReached
          ? index
          : _furthestChapterReached;
      _chapterLoading = true;
      _chapterError = null;
      _pageIndex = 0;
      _selectionActive = false;
      _pendingPageTarget = initialPage;
      _pendingPageFraction = pageFraction;
    });

    try {
      final content = await _service.fetchNodeChapterContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
        chapterIndex: index,
      );
      if (!mounted || requestId != _chapterRequestId) return;
      setState(() {
        _chapterText = content;
        _chapterLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _chapterRequestId) return;
      setState(() {
        _chapterText = '';
        _chapterError = e.toString();
        _chapterLoading = false;
      });
    }
  }

  Widget _buildPagedReader(
    BuildContext context,
    BoxConstraints constraints,
    bool isImmersive,
  ) {
    final contentPadding = _mobileReaderContentPadding(context);
    final width = constraints.maxWidth - contentPadding.horizontal;
    final height = constraints.maxHeight - contentPadding.vertical;
    final viewport = Size(width > 0 ? width : 0, height > 0 ? height : 0);
    final textScaler = MediaQuery.textScalerOf(context);
    final textStyle = AppTextStyles.body(
      context,
    ).copyWith(fontSize: _readerFontSize, height: _readerLineHeight);
    final trimmed = _chapterText.trim();
    final looksLikeHtml = _looksLikeReaderHtml(trimmed);
    final hasImages =
        looksLikeHtml &&
        RegExp(r'<img\b', caseSensitive: false).hasMatch(trimmed);
    final source = hasImages
        ? trimmed
        : looksLikeHtml
        ? _readerHtmlToPlainText(trimmed)
        : trimmed;
    final pages = hasImages
        ? <String>[trimmed]
        : ReaderPaginator.paginate(
            text: source,
            size: viewport,
            style: textStyle,
            scaler: textScaler,
          );
    final paginationKey = (
      chapter: _selected,
      text: _chapterText,
      width: viewport.width,
      height: viewport.height,
      fontSize: _readerFontSize,
      lineHeight: _readerLineHeight,
      textScale: textScaler.scale(_readerFontSize),
      immersive: isImmersive,
      hasImages: hasImages,
    );
    _syncPagination(paginationKey, pages);

    return Listener(
      key: const ValueKey<String>('remote-reader-gestures'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleReaderPointerDown,
      onPointerMove: _handleReaderPointerMove,
      onPointerUp: _handleReaderPointerUp,
      onPointerCancel: _handleReaderPointerCancel,
      child: PageView.builder(
        key: const ValueKey<String>('remote-reader-pages'),
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        allowImplicitScrolling: false,
        itemCount: _pages.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final page = _pages[index];
          if (hasImages) {
            return _buildChapterContent(
              context,
              page,
              contentPadding: contentPadding,
              fontSize: _readerFontSize,
              lineHeight: _readerLineHeight,
            );
          }
          if (page.trim().isEmpty) {
            return const Center(child: Text('正文为空'));
          }
          return Padding(
            padding: contentPadding,
            child: Align(
              alignment: Alignment.topLeft,
              child: SelectableText(
                page,
                style: textStyle,
                textScaler: textScaler,
                contextMenuBuilder: _readerTextContextMenu,
                onSelectionChanged: _handleReaderSelectionChanged,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ★ 本页自己画顶栏/底栏覆盖层，不走 ScreenChrome 的 appBar/bottomNavigationBar：
    // 沉浸模式需要"滑动隐藏 + 动画"，而 Scaffold 的 appBar/bottomNav 一旦换 widget
    // 高度就会跳变，做不出平滑滑动。本地阅读器 nl_reader_page 也是这么做的，
    // 两边观感才能一致。
    return ScreenChrome(
      data: ScreenChromeData.empty,
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
                        style: AppTextStyles.role(
                          context,
                          fontSize: appMetrics.fontSize14,
                          weight: FontWeight.w500,
                          color: AppSemantic.of(context).textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: appMetrics.kSpace4),
                      Text(
                        widget.nodeName,
                        style: AppTextStyles.role(
                          context,
                          fontSize: appMetrics.fontSize12,
                          color: AppSemantic.of(context).textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: appMetrics.kSpace8),
                      Text(
                        _chapters.isEmpty
                            ? '暂无阅读进度'
                            : '正在阅读 · 第 ${_selected + 1}/${_chapters.length} 章 · '
                                  '${_pageIndex + 1}/${_pages.length} 页',
                        key: const ValueKey<String>('reader-catalog-position'),
                        style: AppTextStyles.role(
                          context,
                          fontSize: appMetrics.fontSize12,
                          color: AppSemantic.of(context).accent,
                        ),
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
                            final isCurrent = index == _selected;
                            final isRead =
                                index < _furthestChapterReached ||
                                (index == _furthestChapterReached &&
                                    _pageIndex >= _pages.length - 1);
                            return ListTile(
                              key: _chapterKeys[index],
                              selected: isCurrent,
                              title: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: isCurrent
                                  ? Text(
                                      '正在阅读 · ${_pageIndex + 1}/${_pages.length} 页',
                                    )
                                  : isRead
                                  ? const Text('已读')
                                  : null,
                              trailing: isCurrent
                                  ? SizedBox(
                                      width: scaleW(52),
                                      child: Text(
                                        '${_pageIndex + 1}/${_pages.length}',
                                        textAlign: TextAlign.end,
                                        style: AppTextStyles.role(
                                          context,
                                          fontSize: appMetrics.fontSize12,
                                          color: AppSemantic.of(context).accent,
                                        ),
                                      ),
                                    )
                                  : isRead
                                  ? Icon(
                                      Icons.check,
                                      key: ValueKey<String>(
                                        'reader-catalog-read-$index',
                                      ),
                                      size: appMetrics.iconSize18,
                                      color: AppSemantic.of(
                                        context,
                                      ).textTertiary,
                                    )
                                  : null,
                              onTap: () {
                                if (!isCurrent) {
                                  _persistProgress();
                                  _loadChapter(index);
                                }
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
        body: Obx(() {
          final isImmersive = _isImmersive.value;
          final s2 = AppSemantic.of(context);
          return LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                // ★ 必须 expand：Stack 默认 loose，会用「非 Positioned 子元素」定尺寸；
                // 一旦没有这样的子元素（本页全 Positioned），就会塌成 0 尺寸，
                // 表现为「文字在 widget 树里、但屏幕上一片空白」（实测正文宽度算成 0）。
                fit: StackFit.expand,
                children: [
                  // ── 正文（最底层）───────────────────────────────────────
                  Positioned.fill(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(child: Text('加载失败: $_error'))
                        : _chapterLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _chapterError != null
                        ? Center(child: Text('加载章节失败: $_chapterError'))
                        : Container(
                            color: _readerBgColor,
                            child: _buildPagedReader(
                              context,
                              constraints,
                              isImmersive,
                            ),
                          ),
                  ),

                  // ── 顶部 AppBar 覆盖层（沉浸时上滑隐藏）─────────────────
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: isImmersive,
                      child: AnimatedSlide(
                        duration: _kOverlayAnim,
                        curve: AppMotion.decelerate,
                        offset: isImmersive ? const Offset(0, -1) : Offset.zero,
                        child: Material(
                          color: s2.surface,
                          elevation: 4,
                          child: SafeArea(
                            bottom: false,
                            child: SizedBox(
                              height: AppTheme.metrics.kSpace48,
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: '返回',
                                    icon: DrawIcon(StrokeIcons.arrowBack),
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _chapterTitleAt(_selected),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: appMetrics.fontSize14,
                                        color: s2.textPrimary,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  // 与本地阅读器对齐：章节列表 / 书中搜索 / 设置
                                  IconButton(
                                    tooltip: '章节列表',
                                    icon: DrawIcon(StrokeIcons.list),
                                    onPressed: _openCatalog,
                                  ),
                                  IconButton(
                                    tooltip: '搜索',
                                    icon: DrawIcon(StrokeIcons.search),
                                    onPressed: _showInBookSearch,
                                  ),
                                  IconButton(
                                    tooltip: '设置',
                                    icon: DrawIcon(StrokeIcons.settings),
                                    onPressed: _showReaderSettingsSheet,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── 底部 BottomBar 覆盖层（沉浸时下滑隐藏）──────────────
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: isImmersive,
                      child: AnimatedSlide(
                        duration: _kOverlayAnim,
                        curve: AppMotion.decelerate,
                        offset: isImmersive ? const Offset(0, 1) : Offset.zero,
                        child: Material(
                          color: s2.surface.withAlpha(245),
                          elevation: 8,
                          child: SafeArea(
                            top: false,
                            child: SizedBox(
                              height: _mobileReaderBottomBarHeight(),
                              child: _RemoteReaderBottomBar(
                                canGoPrevious: _pageIndex > 0 || _selected > 0,
                                canGoNext:
                                    _pageIndex < _pages.length - 1 ||
                                    _selected < _chapters.length - 1,
                                onPrevious: () => _turnPage(-1),
                                onNext: () => _turnPage(1),
                                onOpenCatalog: _openCatalog,
                                onShowBookInfo: _showBookInfoDialog,
                                onShowReaderSettings: _showReaderSettingsSheet,
                                currentIndex: _selected,
                                totalChapters: _chapters.length,
                                currentPage: _pageIndex,
                                totalPages: _pages.length,
                                isFavorite: _isFavorite,
                                onToggleFavorite: _toggleFavorite,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }),
      ),
    );
  }
}

bool _looksLikeReaderHtml(String value) {
  return RegExp(
    r'<\s*(?:p|div|span|img|br)\b|</',
    caseSensitive: false,
  ).hasMatch(value);
}

String _readerHtmlToPlainText(String html) {
  var text = html.replaceAll(
    RegExp(
      r'<(script|style)\b[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    ),
    '',
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(
    RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false),
    '\n\n',
  );
  text = text.replaceAll(
    RegExp(r'<(p|div|h[1-6]|li|blockquote)\b[^>]*>', caseSensitive: false),
    '\n\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), '');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
  text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    return _readerDecodeCodePoint(int.tryParse(match.group(1)!));
  });
  text = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    return _readerDecodeCodePoint(int.tryParse(match.group(1)!, radix: 16));
  });
  text = text
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String _readerDecodeCodePoint(int? code) {
  if (code == null ||
      code < 0 ||
      code > 0x10ffff ||
      (code >= 0xd800 && code <= 0xdfff)) {
    return '\ufffd';
  }
  return String.fromCharCodes(<int>[code]);
}

List<ContextMenuButtonItem> _readerMenuItems(
  List<ContextMenuButtonItem> items,
) {
  return items
      .where(
        (item) =>
            item.type == ContextMenuButtonType.copy ||
            item.type == ContextMenuButtonType.selectAll,
      )
      .toList(growable: false);
}

Widget _readerTextContextMenu(BuildContext context, EditableTextState state) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: _readerMenuItems(state.contextMenuButtonItems),
    anchors: state.contextMenuAnchors,
  );
}

Widget _readerRegionContextMenu(
  BuildContext context,
  SelectableRegionState state,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: _readerMenuItems(state.contextMenuButtonItems),
    anchors: state.contextMenuAnchors,
  );
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

  final looksLikeHtml = _looksLikeReaderHtml(trimmed);

  if (looksLikeHtml) {
    return SingleChildScrollView(
      padding: contentPadding,
      child: SelectionArea(
        contextMenuBuilder: _readerRegionContextMenu,
        child: HtmlWidget(
          trimmed,
          // 字号/行距由阅读设置面板的用户取值覆盖，字族仍要从角色层拿
          textStyle: AppTextStyles.body(
            context,
          ).copyWith(fontSize: fontSize, height: lineHeight),
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
      ),
    );
  }

  return SingleChildScrollView(
    padding: contentPadding,
    child: SelectableText(
      trimmed,
      style: AppTextStyles.body(
        context,
      ).copyWith(fontSize: fontSize, height: lineHeight),
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

  /// 当前章节序号（0 起）与总章数：与本地阅读器一致显示「1/12」
  final int currentIndex;
  final int totalChapters;

  /// 当前页序号（0 起）与本章总页数：底栏显示真实页内进度
  final int currentPage;
  final int totalPages;

  /// 收藏状态与切换（远程书收藏状态同样落节点）
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _RemoteReaderBottomBar({
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenCatalog,
    required this.onShowBookInfo,
    required this.onShowReaderSettings,
    required this.currentIndex,
    required this.totalChapters,
    required this.currentPage,
    required this.totalPages,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);

    final pageFraction = totalPages <= 1 ? 1.0 : currentPage / (totalPages - 1);
    final progress = totalChapters <= 0
        ? 0.0
        : ((currentIndex + pageFraction) / totalChapters).clamp(0.0, 1.0);

    return Material(
      color: s.surface.withAlpha(245),
      elevation: 8,
      child: Column(
        children: [
          LinearProgressIndicator(
            key: const ValueKey<String>('reader-progress'),
            value: progress,
            minHeight: scaleW(2),
            backgroundColor: s.border,
            valueColor: AlwaysStoppedAnimation<Color>(s.accent),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace8,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '目录',
                    onPressed: onOpenCatalog,
                    icon: DrawIcon(StrokeIcons.menuBook),
                  ),
                  IconButton(
                    tooltip: '上一页',
                    onPressed: canGoPrevious ? onPrevious : null,
                    icon: DrawIcon(StrokeIcons.chevronLeft),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            totalChapters <= 0
                                ? '0/0'
                                : '${currentIndex + 1}/$totalChapters',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.role(
                              context,
                              fontSize: appMetrics.fontSize13,
                              weight: FontWeight.w500,
                              color: s.textPrimary,
                              height: 1.2,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            totalPages <= 0
                                ? '0/0 页'
                                : '${currentPage + 1}/$totalPages 页',
                            key: const ValueKey<String>(
                              'reader-page-indicator',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.role(
                              context,
                              fontSize: appMetrics.fontSize11,
                              color: s.textTertiary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下一页',
                    onPressed: canGoNext ? onNext : null,
                    icon: DrawIcon(StrokeIcons.chevronRight),
                  ),
                  // 收藏：与本地阅读器对齐
                  IconButton(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    onPressed: onToggleFavorite,
                    icon: DrawIcon(
                      isFavorite
                          ? StrokeIcons.favorite
                          : StrokeIcons.favoriteBorder,
                    ),
                  ),
                  IconButton(
                    tooltip: '书籍详情',
                    onPressed: onShowBookInfo,
                    icon: DrawIcon(StrokeIcons.infoOutline),
                  ),
                  IconButton(
                    tooltip: '阅读设置',
                    onPressed: onShowReaderSettings,
                    icon: DrawIcon(StrokeIcons.tune),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
