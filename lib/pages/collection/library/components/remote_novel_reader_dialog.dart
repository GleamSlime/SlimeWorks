import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
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
  static const double _kChapterSwipeTrigger = 72;

  bool _loading = true;
  bool _chapterLoading = false;
  String? _error;
  String? _chapterError;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;
  String _chapterText = '';
  Color _readerBgColor = AppReaderPaper.parchment;
  double _readerFontSize = 16;
  double _readerLineHeight = 1.8;
  double _leadingOverscroll = 0;
  double _trailingOverscroll = 0;
  bool _chapterSwipeLocked = false;

  /// 本地沉浸模式状态。
  ///
  /// ★ 不要用全局 `DesktopScreenProvider.mobileImmersiveMode`：实测
  /// `ScreenChromeData.enableMobileImmersiveMode` 在 ScreenChrome 里**从未被消费**
  /// （是个死参数），所以走全局状态不会有任何视觉变化。
  /// 本地阅读器 `novel_reader_page.dart` 早就改成"自己画覆盖层 + AnimatedSlide"，
  /// 远程阅读页照同一套做，两边观感才一致。
  final RxBool _isImmersive = false.obs;
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
      insets.top + AppTheme.metrics.kSpace48 + (isImmersive ? 0 : AppTheme.metrics.kSpace8),
      appMetrics.kSpace12,
      insets.bottom + (isImmersive ? AppTheme.metrics.kSpace16 : _mobileReaderBottomBarHeight()),
    );
  }

  void _setImmersive(bool on) {
    if (!mounted) return;
    if (_isImmersive.value == on) return;
    _isImmersive.value = on;
    if (!on) _scheduleImmersiveIdle();
  }

  /// 停留一段时间无操作后自动进入沉浸（把屏幕还给文字）
  void _scheduleImmersiveIdle() {
    _immersiveTimer?.cancel();
    _immersiveTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      _setImmersive(true);
    });
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
      // ── 沉浸模式联动 ────────────────────────────────────────────────
      // 向下滚动（阅读正文，scrollDelta > 0）→ 隐藏顶部 AppBar 与底栏，
      // 把屏幕还给文字；向上滚动 → 立即恢复。
      // 只有阅读页会开着这个开关（enableMobileImmersiveMode），
      // 其它页面不受影响。
      final delta = notification.scrollDelta ?? 0;
      if (delta > 2) {
        _setImmersive(true);
      } else if (delta < -2) {
        _setImmersive(false);
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
                      children:
                          AppReaderPaper.presets
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

  /// 把当前章节位置写回节点（下次打开能续读）。
  Future<void> _persistProgress() async {
    if (_chapters.isEmpty) return;
    final progress = (_selected + 1) / _chapters.length;
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
        _loading = false;
        _selected = resume;
      });
      if (chapters.isNotEmpty) {
        await _loadChapter(resume);
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
        body: Obx(() {
          final isImmersive = _isImmersive.value;
          final s2 = AppSemantic.of(context);
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
                        child: GestureDetector(
                          // 点正文：沉浸中就退出沉浸，否则重新计时
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (isImmersive) {
                              _setImmersive(false);
                            } else {
                              _scheduleImmersiveIdle();
                            }
                          },
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
                                onPressed: () => Navigator.of(context).maybePop(),
                              ),
                              Expanded(
                                child: Text(
                                  _chapterTitleAt(_selected),
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
                            canGoPrevious: _selected > 0,
                            canGoNext: _selected < _chapters.length - 1,
                            onPrevious: _selected > 0 ? () => _loadChapter(_selected - 1) : null,
                            onNext: _selected < _chapters.length - 1 ? () => _loadChapter(_selected + 1) : null,
                            onOpenCatalog: () => _scaffoldKey.currentState?.openDrawer(),
                            onShowBookInfo: _showBookInfoDialog,
                            onShowReaderSettings: _showReaderSettingsSheet,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
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
        // 字号/行距由阅读设置面板的用户取值覆盖，字族仍要从角色层拿
        textStyle: AppTextStyles.body(context).copyWith(
          fontSize: fontSize,
          height: lineHeight,
        ),
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
      style: AppTextStyles.body(context).copyWith(fontSize: fontSize, height: lineHeight),
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
    final s = AppSemantic.of(context);

    return Material(
      color: s.surface.withAlpha(245),
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8),
        child: Row(
          children: [
            IconButton(
              tooltip: '目录',
              onPressed: onOpenCatalog,
              icon: DrawIcon(StrokeIcons.menuBook),
            ),
            IconButton(
              tooltip: '上一章',
              onPressed: canGoPrevious ? onPrevious : null,
              icon: DrawIcon(StrokeIcons.chevronLeft),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '章节',
                  style: AppTextStyles.role(
                    context,
                    fontSize: appMetrics.fontSize13,
                    weight: FontWeight.w500,
                    color: AppSemantic.of(context).textPrimary,
                    height: 1.2,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '下一章',
              onPressed: canGoNext ? onNext : null,
              icon: DrawIcon(StrokeIcons.chevronRight),
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
    );
  }
}
