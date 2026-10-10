library;

/// Manga 漫画页放大预览
///
/// 交互对齐媒体库图片预览（MediaViewerPage）：缩放/平移/旋转、翻页、
/// 滚轮与键盘导航、玻璃浮层。差异在于图片源：漫画页是字节流
/// （MangaService 的 LRU 缓存），不是本地文件路径或节点 URL。

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

part 'manga_image_viewer_chrome.dart';
part 'manga_image_viewer_image.dart';

class MangaImageViewerPage extends StatefulWidget {
  const MangaImageViewerPage({
    super.key,
    required this.pages,
    required this.initialIndex,
    this.chapterTitle = '',
  });

  /// 本页所在章节的全部页（与阅读器同一份列表，可前后翻页）
  final List<MangaPage> pages;
  final int initialIndex;

  /// 章节标题，用于顶栏展示
  final String chapterTitle;

  @override
  State<MangaImageViewerPage> createState() => _MangaImageViewerPageState();
}

class _MangaImageViewerPageState extends State<MangaImageViewerPage>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _dragPending = false;

  // ── 跟手拖动状态 ─────────────────────────────────────────────────────────
  // 当前正在拖动时的像素偏移（水平拖动 → dx≠0，垂直拖动 → dy≠0）
  double _dragOffset = 0.0;
  bool _isDraggingH = false;
  bool _isDragging = false;

  // 松手后的弹性动画
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _snapFrom = 0.0;
  double _snapTo = 0.0;

  // 松手提交时的目标页（null = 弹回原页）
  int? _pendingIndex;

  // 邻页缓存，避免切换时重建；不变式：_currPageWidget 始终对应 _currentIndex
  Widget? _prevPageWidget;
  Widget? _currPageWidget;
  Widget? _nextPageWidget;

  // 鼠标滚轮/触摸板累积
  double _scrollAccum = 0.0;
  static const double _kScrollThreshold = 60.0;
  static const double _kDragCommitFraction = 0.3;
  int _lastJumpTimeMs = 0;
  static const int _kJumpCooldownMs = 400;

  // ── 沉浸模式 ──────────────────────────────────────────────────────────────
  bool _uiVisible = true;
  Timer? _immersiveTimer;
  static const Duration _kImmersiveDelay = Duration(seconds: 10);

  // ── 图片缩放状态（缩放时禁用外层翻页手势）────────────────────────────────
  bool _imageIsZoomed = false;

  /// 鼠标中键是否处于按下状态（中键按住 + 滚轮 = 缩放模式）。
  bool _middleButtonHeld = false;

  // ── 滚轮缩放通信 ───────────────────────────────────────────────────────
  // 外层 Listener 独占指针信号（框架规则：先注册者胜，命中遍历从根到叶），
  // 内层 Listener 永远收不到事件，因此缩放由外层判定后经此 Notifier 定向通知。
  // 元组含义：(序号, 目标页 index, 鼠标位置, 滚轮 dy)
  int _wheelZoomSeq = 0;
  final _wheelZoomNotifier = ValueNotifier<(int, int, Offset, double)>((0, -1, Offset.zero, 0));

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  String get _pageLabel {
    final name = widget.pages[_currentIndex].media.originalName.trim();
    if (name.isEmpty) return '第 ${_currentIndex + 1} 页';
    return name;
  }

  void _resetImmersiveTimer() {
    if (!_isMobile) return; // PC 端 UI 永久可见
    _immersiveTimer?.cancel();
    if (!_uiVisible) {
      setState(() => _uiVisible = true);
    }
    _immersiveTimer = Timer(_kImmersiveDelay, () {
      if (mounted) setState(() => _uiVisible = false);
    });
  }

  void _toggleUi() {
    if (!_isMobile) return; // PC 端点击不隐藏 UI
    _immersiveTimer?.cancel();
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _immersiveTimer = Timer(_kImmersiveDelay, () {
        if (mounted) setState(() => _uiVisible = false);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.pages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _currentIndex = widget.initialIndex.clamp(0, widget.pages.length - 1);
    _snapCtrl = AnimationController(vsync: this, duration: AppMotion.base);
    _snapCtrl.addListener(_onSnapTick);
    _snapCtrl.addStatusListener(_onSnapStatus);
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _resetImmersiveTimer();
    }
  }

  @override
  void didUpdateWidget(MangaImageViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages != oldWidget.pages) {
      if (_dragPending) return; // 翻页动画期间不重算当前页
      // 章节续载后列表变长：按 id 找回当前页，找不到说明列表已被整体替换
      final currentId = oldWidget.pages[_currentIndex].id;
      final newIndex = widget.pages.indexWhere((page) => page.id == currentId);
      if (newIndex != -1 && newIndex != _currentIndex) {
        _currentIndex = newIndex;
      }
      // 列表变动后邻页缓存一律作废，由 build() 懒建
      _prevPageWidget = null;
      _currPageWidget = null;
      _nextPageWidget = null;
    }
  }

  @override
  void dispose() {
    _immersiveTimer?.cancel();
    _snapCtrl.dispose();
    _wheelZoomNotifier.dispose();
    if (_isMobile) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  // ── 弹性动画回调 ─────────────────────────────────────────────────────────

  void _onSnapTick() {
    if (_snapCtrl.isAnimating) {
      setState(() {
        _dragOffset = _snapFrom + (_snapTo - _snapFrom) * _snapAnim.value;
      });
    }
  }

  void _onSnapStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final pending = _pendingIndex;
      _imageIsZoomed = false;
      setState(() {
        if (pending != null) {
          _prevPageWidget = null;
          _currPageWidget = null;
          _nextPageWidget = null;
          _currentIndex = pending;
        }
        _dragOffset = 0.0;
        _isDragging = false;
        _dragPending = false;
        _pendingIndex = null;
      });
    }
  }

  // ── 即时跳转（键盘 / 滚轮，不需要跟手） ──────────────────────────────────

  void _jumpInstant(int delta, {bool horizontal = false}) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final next = (_currentIndex + delta).clamp(0, widget.pages.length - 1);
    if (next == _currentIndex) return;
    final size = MediaQuery.sizeOf(context);
    final screenExtent = horizontal ? size.width : size.height;
    _isDraggingH = horizontal;
    _isDragging = true;
    _dragPending = true;
    _snapFrom = 0.0;
    _snapTo = delta < 0 ? screenExtent : -screenExtent;
    _pendingIndex = next;
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: AppMotion.decelerate);
    // 非相邻跳转时清空邻页缓存，确保 build() 重建正确的邻页
    if (delta.abs() > 1) {
      _prevPageWidget = null;
      _nextPageWidget = null;
    }
    _snapCtrl.forward(from: 0.0);
    setState(() {});
  }

  // ── 拖动手势 ─────────────────────────────────────────────────────────────

  void _onDragStart({required bool horizontal}) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    _isDraggingH = horizontal;
    _isDragging = true;
    _dragPending = true;
    _dragOffset = 0.0;
    _pendingIndex = null;
    setState(() {});
  }

  void _onDragUpdate(double delta) {
    if (!_isDragging) return;
    setState(() => _dragOffset += delta);
  }

  void _onDragEnd(double velocity, double screenExtent) {
    if (!_isDragging) return;
    final frac = _dragOffset / screenExtent;
    int? next;
    // 正 offset = 当前页右移/下移 = "往回翻"（看上一项）
    if (_dragOffset > 0 && (frac > _kDragCommitFraction || velocity > 400) && _currentIndex > 0) {
      next = _currentIndex - 1;
    } else if (_dragOffset < 0 &&
        (-frac > _kDragCommitFraction || velocity < -400) &&
        _currentIndex < widget.pages.length - 1) {
      next = _currentIndex + 1;
    }

    _snapFrom = _dragOffset;
    if (next != null) {
      // 提交：动画到屏幕边缘
      _snapTo = _dragOffset > 0 ? screenExtent : -screenExtent;
      _pendingIndex = next;
    } else {
      // 弹回原位
      _snapTo = 0.0;
      _pendingIndex = null;
    }
    _snapAnim = CurvedAnimation(
      parent: _snapCtrl,
      curve: next != null ? AppMotion.decelerate : AppMotion.springCurve,
    );
    _snapCtrl.forward(from: 0.0);
  }

  // ── 鼠标滚轮 ─────────────────────────────────────────────────────────────

  void _handlePointerScroll(PointerScrollEvent event) {
    if (_isDragging) return;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed;
    // 中键按下（以事件自身 buttons 兜底，防止 down/up 监听遗漏）
    final middleHeld = _middleButtonHeld || (event.buttons & kMiddleMouseButton) != 0;
    // 按住 Ctrl 或鼠标中键：禁用翻页，滚轮作为缩放
    if (ctrlPressed || middleHeld) {
      _requestZoom(event);
      return;
    }
    // 图片已缩放：滚轮继续缩放，禁用翻页（直到重置缩放恢复 100%）
    if (_imageIsZoomed) {
      _requestZoom(event);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastJumpTimeMs < _kJumpCooldownMs) return;
    _resetImmersiveTimer();
    final dy = event.scrollDelta.dy;
    if (dy.abs() >= 100) {
      _scrollAccum = 0;
      _lastJumpTimeMs = now;
      _jumpInstant(dy > 0 ? 1 : -1);
      return;
    }
    _scrollAccum += dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      _lastJumpTimeMs = now;
      _jumpInstant(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  /// 将滚轮事件转发给当前页的 _MangaPageViewer 执行锚点缩放。
  void _requestZoom(PointerScrollEvent event) {
    _resetImmersiveTimer();
    _wheelZoomSeq++;
    _wheelZoomNotifier.value = (
      _wheelZoomSeq,
      _currentIndex,
      event.localPosition,
      event.scrollDelta.dy,
    );
  }

  // ── 子页面垂直滑动回调（图片缩放后手指平移越界时改为翻页）────────────────

  void _handleSwipeDelta(double dy) {
    _scrollAccum -= dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastJumpTimeMs < _kJumpCooldownMs) return;
      _lastJumpTimeMs = now;
      _jumpInstant(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  // ── 页面构建 ─────────────────────────────────────────────────────────────

  Widget _buildPageContent(BuildContext context, int index) {
    if (index < 0 || index >= widget.pages.length) {
      return const SizedBox.expand();
    }
    return _MangaPageViewer(
      image: widget.pages[index].media,
      pageIndex: index,
      wheelZoomNotifier: _wheelZoomNotifier,
      onSwipeDelta: _handleSwipeDelta,
      onSwipeEnd: () => _scrollAccum = 0,
      onSave: _isMobile ? () => _saveCurrentPage(context) : null,
      onZoomChanged: (zoomed) {
        if (_imageIsZoomed != zoomed) setState(() => _imageIsZoomed = zoomed);
      },
    );
  }

  // ── 将当前页保存到系统相册 ────────────────────────────────────────────────

  Future<void> _saveCurrentPage(BuildContext context) async {
    final image = widget.pages[_currentIndex].media;
    // 先取 messenger：await 之后 context 可能已失效，异步间隙里只碰 messenger
    final messenger = ScaffoldMessenger.of(context);
    void tip(String message) => messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
    try {
      const maxAttempts = 3;
      bool hasAccess = await Gal.hasAccess(toAlbum: true);
      for (int attempt = 0; !hasAccess && attempt < maxAttempts; attempt++) {
        hasAccess = await Gal.requestAccess(toAlbum: true);
        if (!hasAccess && attempt < maxAttempts - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      if (!hasAccess) {
        tip('没有相册写入权限，请在系统设置中手动授权');
        return;
      }

      final bytes = await getIt<MangaService>().fetchImageBytes(image);
      final tmpDir = await getTemporaryDirectory();
      final rawExt = image.path.split('.').last.toLowerCase();
      const validExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
      final ext = validExt.contains(rawExt) ? rawExt : 'jpg';
      final tmpFile = File(
        '${tmpDir.path}/slimeworks_manga_'
        '${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await tmpFile.writeAsBytes(bytes);
      await Gal.putImage(tmpFile.path);
      await tmpFile.delete().catchError((_) => tmpFile);
      tip('已保存到相册');
    } catch (e) {
      tip('保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final size = MediaQuery.sizeOf(context);
    if (_currentIndex >= widget.pages.length) {
      return const SizedBox.shrink();
    }

    // 懒填充：只建还没构建的槽，已有的直接复用
    _currPageWidget ??= _buildPageContent(context, _currentIndex);
    if (_currentIndex > 0) {
      if (_prevPageWidget == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _dragPending) return;
          setState(() {
            _prevPageWidget = _buildPageContent(context, _currentIndex - 1);
          });
        });
      }
    } else {
      _prevPageWidget = null;
    }
    if (_currentIndex < widget.pages.length - 1) {
      if (_nextPageWidget == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _dragPending) return;
          setState(() {
            _nextPageWidget = _buildPageContent(context, _currentIndex + 1);
          });
        });
      }
    } else {
      _nextPageWidget = null;
    }

    // 判断当前拖动轴和方向，决定邻页应放在哪里
    final offset = _isDragging ? _dragOffset : 0.0;
    final screenExtent = _isDraggingH ? size.width : size.height;

    Widget buildPositioned(Widget? page, double base) {
      if (page == null) return const SizedBox.shrink();
      final dx = _isDraggingH ? (base + offset) : 0.0;
      final dy = _isDraggingH ? 0.0 : (base + offset);
      return Positioned.fill(
        child: Transform.translate(offset: Offset(dx, dy), child: page),
      );
    }

    final currDx = _isDraggingH ? offset : 0.0;
    final currDy = _isDraggingH ? 0.0 : offset;

    return Scaffold(
      // 查看器是沉浸式深色画布：黑底固定，不跟随明暗主题
      backgroundColor: s.mediaStage,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _jumpInstant(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _jumpInstant(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _jumpInstant(-1, horizontal: true);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _jumpInstant(1, horizontal: true);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // ── 跟手拖动层 ──────────────────────────────────────────────────
            Positioned.fill(
              child: Listener(
                // 跟踪鼠标中键按下状态：中键按住 + 滚轮 = 缩放模式
                onPointerDown: (event) {
                  if ((event.buttons & kMiddleMouseButton) != 0) {
                    _middleButtonHeld = true;
                  }
                },
                onPointerUp: (event) {
                  // 抬起后剩余按下按钮不再包含中键时清除标记
                  if ((event.buttons & kMiddleMouseButton) == 0) {
                    _middleButtonHeld = false;
                  }
                },
                onPointerCancel: (_) => _middleButtonHeld = false,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _handlePointerScroll(event);
                },
                child: GestureDetector(
                  onHorizontalDragStart: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (_) => _onDragStart(horizontal: true),
                  onHorizontalDragUpdate: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (d) => _onDragUpdate(d.delta.dx),
                  onHorizontalDragEnd: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (d) => _onDragEnd(d.velocity.pixelsPerSecond.dx, size.width),
                  onVerticalDragStart: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (_) => _onDragStart(horizontal: false),
                  onVerticalDragUpdate: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (d) => _onDragUpdate(d.delta.dy),
                  onVerticalDragEnd: (!_isMobile || _imageIsZoomed)
                      ? null
                      : (d) => _onDragEnd(d.velocity.pixelsPerSecond.dy, size.height),
                  // 单击空白区域切换 UI 可见性
                  onTap: _toggleUi,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        // 邻页（在当前页下方，被 offset 带出）
                        buildPositioned(_prevPageWidget, -screenExtent),
                        buildPositioned(_nextPageWidget, screenExtent),
                        // 当前页
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(currDx, currDy),
                            child: _currPageWidget ?? const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── 底部：页码 + 浮动操作菜单 ────────────────────────────────────
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + AppTheme.metrics.kSpace24,
              left: AppTheme.metrics.kSpace16,
              right: AppTheme.metrics.kSpace16,
              child: AnimatedOpacity(
                opacity: _uiVisible ? 1.0 : 0.0,
                duration: AppMotion.base,
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _GlassChip(current: _currentIndex, total: widget.pages.length),
                      _FloatingActionMenu(
                        canGoPrev: _currentIndex > 0,
                        canGoNext: _currentIndex < widget.pages.length - 1,
                        onSave: _isMobile ? () => _saveCurrentPage(context) : null,
                        onPrev: () => _jumpInstant(-1),
                        onNext: () => _jumpInstant(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 左上角：返回按钮 + 章节 / 页名 ───────────────────────────────
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + scaleW(4),
              left: appMetrics.kSpace4,
              right: appMetrics.kSpace4,
              child: AnimatedOpacity(
                opacity: _uiVisible ? 1.0 : 0.0,
                duration: AppMotion.base,
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: '返回',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: AppTheme.metrics.kSpace10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: AppTheme.metrics.radius10,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: AppGlass.blurSoft,
                              sigmaY: AppGlass.blurSoft,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: appMetrics.kSpace10,
                                vertical: appMetrics.kSpace10,
                              ),
                              // 深色玻璃标题条上的白字不随明暗翻转
                              color: s.immersivePanel,
                              child: Text(
                                widget.chapterTitle.isEmpty
                                    ? _pageLabel
                                    : '${widget.chapterTitle} · $_pageLabel',
                                style: AppTextStyles.role(
                                  context,
                                  color: s.onMedia,
                                  fontSize: AppTheme.metrics.fontSize13,
                                  weight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
