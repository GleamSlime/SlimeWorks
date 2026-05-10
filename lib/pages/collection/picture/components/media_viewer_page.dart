import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_controls;
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/core/index.dart';

import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';

class MediaViewerPage extends StatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.collectionId,
    required this.viewModel,
  });

  final List<media_api.MediaItem> items;
  final int initialIndex;
  final String collectionId;
  final MediaLibraryViewModel viewModel;

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> with TickerProviderStateMixin {
  int _currentIndex = 0;
  String? _currentItemId;

  // ── 跟手拖动状态 ─────────────────────────────────────────────────────────
  // 当前正在拖动时的像素偏移（horizontal drag → dx≠0，vertical drag → dy≠0）
  double _dragOffset = 0.0;
  bool _isDraggingH = false; // true = 水平拖动，false = 垂直拖动
  bool _isDragging = false;

  // 松手后的弹性动画
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _snapFrom = 0.0;
  double _snapTo = 0.0;

  // 松手提交时的目标页（null = 弹回原页）
  int? _pendingIndex;

  // 上一页和下一页 widget 缓存，避免切换时重建
  // 不变式：_currPageWidget 始终对应 _currentIndex，邻页 null 时在 build() 懒建
  Widget? _prevPageWidget;
  Widget? _currPageWidget;
  Widget? _nextPageWidget;

  // 鼠标滚轮/触摸板累积
  double _scrollAccum = 0.0;
  static const double _kScrollThreshold = 60.0;
  static const double _kDragCommitFraction = 0.3; // 拖动超过屏幕 30% 即提交

  // ── 沉浸模式 ──────────────────────────────────────────────────────────────
  bool _uiVisible = true;
  Timer? _immersiveTimer;

  // ── 图片缩放状态（缩放时禁用外层翻页手势）────────────────────────────────
  bool _imageIsZoomed = false;
  static const Duration _kImmersiveDelay = Duration(seconds: 10);

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

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
    if (widget.items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _currentItemId = widget.items[_currentIndex].id;
    _snapCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _snapCtrl.addListener(_onSnapTick);
    _snapCtrl.addStatusListener(_onSnapStatus);
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _resetImmersiveTimer();
    }
  }

  @override
  void didUpdateWidget(MediaViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items && _currentItemId != null) {
      final newIndex = widget.items.indexWhere((item) => item.id == _currentItemId);
      if (newIndex != -1 && newIndex != _currentIndex) {
        _currentIndex = newIndex;
        _prevPageWidget = null;
        _currPageWidget = null;
        _nextPageWidget = null;
      }
    }
  }

  @override
  void dispose() {
    _immersiveTimer?.cancel();
    _snapCtrl.dispose();
    if (Platform.isAndroid || Platform.isIOS) {
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
      // 动画完成：旋转复用已渲染的邻页，避免重建闪烁
      final pending = _pendingIndex;
      // 翻页后重置缩放状态（新页面默认未缩放）
      _imageIsZoomed = false;
      setState(() {
        if (pending != null) {
          if (pending == _currentIndex + 1) {
            // 前进：next → curr，curr → prev，next 置 null 懒建
            _prevPageWidget = _currPageWidget;
            _currPageWidget = _nextPageWidget;
            _nextPageWidget = null;
          } else if (pending == _currentIndex - 1) {
            // 后退：prev → curr，curr → next，prev 置 null 懒建
            _nextPageWidget = _currPageWidget;
            _currPageWidget = _prevPageWidget;
            _prevPageWidget = null;
          } else {
            // 非相邻跳转：全部清空重建
            _prevPageWidget = null;
            _currPageWidget = null;
            _nextPageWidget = null;
          }
          _currentIndex = pending;
          _currentItemId = widget.items.isNotEmpty ? widget.items[_currentIndex].id : null;
        }
        _dragOffset = 0.0;
        _isDragging = false;
        _pendingIndex = null;
      });
    }
  }

  // ── 即时跳转（键盘 / 滚轮，不需要跟手） ──────────────────────────────────

  void _jumpInstant(int delta, {bool horizontal = false}) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final next = (_currentIndex + delta).clamp(0, widget.items.length - 1);
    if (next == _currentIndex) return;
    final size = MediaQuery.sizeOf(context);
    final screenExtent = horizontal ? size.width : size.height;
    _isDraggingH = horizontal;
    _isDragging = true;
    _snapFrom = 0.0;
    _snapTo = delta < 0 ? screenExtent : -screenExtent;
    _pendingIndex = next;
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic);
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
        _currentIndex < widget.items.length - 1) {
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
      curve: next != null ? Curves.easeOutCubic : Curves.easeOutBack,
    );
    _snapCtrl.forward(from: 0.0);
  }

  // ── 鼠标滚轮 ─────────────────────────────────────────────────────────────

  void _handlePointerScroll(PointerScrollEvent event) {
    if (_isDragging) return;
    _resetImmersiveTimer();
    final dy = event.scrollDelta.dy;
    if (dy.abs() >= 100) {
      _scrollAccum = 0;
      _jumpInstant(dy > 0 ? 1 : -1);
      return;
    }
    _scrollAccum += dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      _jumpInstant(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  // ── 子页面垂直滑动回调（图片缩放后用 onSwipeDelta 代替 drag）────────────

  void _handleSwipeDelta(double dy) {
    // 图片缩放模式下不跟手，只累积阈值翻页
    _scrollAccum -= dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      _jumpInstant(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  // ── 页面构建 ─────────────────────────────────────────────────────────────

  Widget _buildPageContent(BuildContext context, int index) {
    if (index < 0 || index >= widget.items.length) {
      return const SizedBox.expand();
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final item = widget.items[index];
    final source = widget.viewModel.buildMediaSource(item, collectionId: widget.collectionId);
    if (item.kind == media_api.MediaKind.video || item.kind == media_api.MediaKind.audio) {
      // 构建封面 URL：本地视频用文件路径，远程视频用节点封面 URL（mode=cover）
      final coverSource = widget.viewModel.buildMediaSource(
        item,
        collectionId: widget.collectionId,
        isCover: true,
      );
      return _VideoPreview(
        source: source,
        title: item.title,
        coverSource: coverSource,
        onSwipeDelta: _handleSwipeDelta,
        onSwipeEnd: () => _scrollAccum = 0,
        isAudio: item.kind == media_api.MediaKind.audio,
      );
    }
    if (source == null || source.isEmpty) {
      return const Center(
        child: Text('无法加载图片', style: TextStyle(color: Colors.white)),
      );
    }
    return _ImageViewer(
      source: source,
      onSwipeDelta: _handleSwipeDelta,
      onSwipeEnd: () => _scrollAccum = 0,
      onSave: isMobile ? () => _saveCurrentItem(context) : null,
      onZoomChanged: (zoomed) {
        if (_imageIsZoomed != zoomed) setState(() => _imageIsZoomed = zoomed);
      },
    );
  }

  // ── 将当前图片保存到系统相册 ──────────────────────────────────────────────

  Future<void> _saveCurrentItem(BuildContext context) async {
    final item = widget.items[_currentIndex];
    if (item.kind != media_api.MediaKind.image) return;
    final source = widget.viewModel.buildMediaSource(item, collectionId: widget.collectionId);
    if (source == null || source.isEmpty) return;

    const maxAttempts = 3;
    bool hasAccess = await Gal.hasAccess(toAlbum: true);
    for (int attempt = 0; !hasAccess && attempt < maxAttempts; attempt++) {
      hasAccess = await Gal.requestAccess(toAlbum: true);
      if (!hasAccess && attempt < maxAttempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (!hasAccess) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有相册写入权限，请在系统设置中手动授权'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      String localPath;
      File? tmpFile;
      if (source.startsWith('http')) {
        final resp = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        final tmpDir = await getTemporaryDirectory();
        final ext = source.split('?').first.split('.').last.toLowerCase();
        final validExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
        tmpFile = File(
          '${tmpDir.path}/slimeworks_img_${DateTime.now().millisecondsSinceEpoch}.$validExt',
        );
        await tmpFile.writeAsBytes(resp.bodyBytes);
        localPath = tmpFile.path;
      } else {
        localPath = source;
      }
      await Gal.putImage(localPath);
      tmpFile?.delete().ignore();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final item = widget.items[_currentIndex];
    final isImage = item.kind == media_api.MediaKind.image;

    // 懒填充：只建还没构建的槽，已有的直接复用
    _currPageWidget ??= _buildPageContent(context, _currentIndex);
    if (_currentIndex > 0) {
      _prevPageWidget ??= _buildPageContent(context, _currentIndex - 1);
    } else {
      _prevPageWidget = null;
    }
    if (_currentIndex < widget.items.length - 1) {
      _nextPageWidget ??= _buildPageContent(context, _currentIndex + 1);
    } else {
      _nextPageWidget = null;
    }

    // 判断当前拖动轴和方向，决定邻页应放在哪里
    final offset = _isDragging ? _dragOffset : 0.0;
    final screenExtent = _isDraggingH ? size.width : size.height;

    // 邻页相对于当前页的基准偏移（单位：像素）
    // 上一页在左/上（-screenExtent），下一页在右/下（+screenExtent）
    // 手指右划 offset>0 → current 右移，prev 从左进：-screenExtent + offset → 趋近 0 ✓
    // 手指左划 offset<0 → current 左移，next 从右进：+screenExtent + offset → 趋近 0 ✓
    final prevBase = -screenExtent;
    final nextBase = screenExtent;

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
      backgroundColor: Colors.black,
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
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _handlePointerScroll(event);
                },
                child: GestureDetector(
                  // 移动端：水平拖动（图片缩放时禁用，由 _ImageViewer 内部处理平移）
                  onHorizontalDragStart: (isMobile && !_imageIsZoomed)
                      ? (_) => _onDragStart(horizontal: true)
                      : null,
                  onHorizontalDragUpdate: (isMobile && !_imageIsZoomed)
                      ? (d) => _onDragUpdate(d.delta.dx)
                      : null,
                  onHorizontalDragEnd: (isMobile && !_imageIsZoomed)
                      ? (d) => _onDragEnd(d.velocity.pixelsPerSecond.dx, size.width)
                      : null,
                  // 移动端：垂直拖动（图片缩放时禁用）
                  onVerticalDragStart: (isMobile && !_imageIsZoomed)
                      ? (_) => _onDragStart(horizontal: false)
                      : null,
                  onVerticalDragUpdate: (isMobile && !_imageIsZoomed)
                      ? (d) => _onDragUpdate(d.delta.dy)
                      : null,
                  onVerticalDragEnd: (isMobile && !_imageIsZoomed)
                      ? (d) => _onDragEnd(d.velocity.pixelsPerSecond.dy, size.height)
                      : null,
                  // 单击空白区域切换 UI 可见性
                  onTap: _toggleUi,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        // 邻页（在当前页下方，被 offset 带出）
                        buildPositioned(_prevPageWidget, prevBase),
                        buildPositioned(_nextPageWidget, nextBase),
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

            // ── 右下角：浮动操作菜单 ─────────────────────────────────────────
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              left: AppTheme.metrics.kSpace16,
              right: AppTheme.metrics.kSpace16,
              child: AnimatedOpacity(
                opacity: _uiVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _GlassChip(current: _currentIndex, total: widget.items.length),
                      _FloatingActionMenu(
                        canGoPrev: _currentIndex > 0,
                        canGoNext: _currentIndex < widget.items.length - 1,
                        onSave: isImage ? () => _saveCurrentItem(context) : null,
                        onPrev: () => _jumpInstant(-1),
                        onNext: () => _jumpInstant(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 左上角：返回按钮 + 文件名 ────────────────────────────────────
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + scaleW(4),
              left: appMetrics.kSpace4,
              right: appMetrics.kSpace4,
              child: AnimatedOpacity(
                opacity: _uiVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
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
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: appMetrics.kSpace10,
                                vertical: appMetrics.kSpace10,
                              ),
                              color: Colors.black.withValues(alpha: 0.42),
                              child: Text(
                                widget.items[_currentIndex].title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTheme.metrics.fontSize13,
                                  fontWeight: FontWeight.w500,
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

// ── 玻璃磨砂 icon 按钮 ─────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppTheme.metrics.radius22,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 42,
            height: 42,
            color: Colors.black.withValues(alpha: 0.42),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: AppTheme.metrics.iconSize22),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

// ── 玻璃计数标签（带滚动动画） ──────────────────────────────────────────────

class _GlassChip extends StatefulWidget {
  const _GlassChip({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_GlassChip> createState() => _GlassChipState();
}

class _GlassChipState extends State<_GlassChip> {
  bool _goingForward = true;

  @override
  void didUpdateWidget(_GlassChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      _goingForward = widget.current > oldWidget.current;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius14,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace10, vertical: AppTheme.metrics.kSpace4),
          color: Colors.black.withValues(alpha: 0.42),
          // 固定宽度避免数字变化时容器宽度跳动
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 只有当前数字有滚动动画
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  final isIncoming = child.key == ValueKey(widget.current);
                  final begin = isIncoming
                      ? Offset(0, _goingForward ? 1.0 : -1.0)
                      : Offset(0, _goingForward ? -1.0 : 1.0);
                  final pos = Tween<Offset>(
                    begin: begin,
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                  return ClipRect(
                    child: SlideTransition(position: pos, child: child),
                  );
                },
                child: Text(
                  '${widget.current + 1}',
                  key: ValueKey(widget.current),
                  style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize13),
                ),
              ),
              // 总数静止，无动画
              Text(
                ' / ${widget.total}',
                style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 浮动操作菜单（右下角，点击展开向上弹出独立圆形按钮，3s 自动收起）───────────

class _FloatingActionMenu extends StatefulWidget {
  const _FloatingActionMenu({
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    this.onSave,
  });

  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// null = 不显示保存按钮
  final VoidCallback? onSave;

  @override
  State<_FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<_FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  Timer? _autoCollapseTimer;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _collapse();
    } else {
      _expand();
    }
  }

  void _expand() {
    setState(() => _expanded = true);
    _animController.forward();
    _resetAutoCollapse();
  }

  void _collapse() {
    setState(() => _expanded = false);
    _animController.reverse();
    _autoCollapseTimer?.cancel();
  }

  void _resetAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _expanded) _collapse();
    });
  }

  void _handleAction(VoidCallback action) {
    _collapse();
    action();
  }

  /// 构建一个独立的圆形玻璃按钮，带 fade+scale 动画。
  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required int delayMs,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _animController,
        curve: Interval(delayMs / 300.0, 1.0, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: _animController,
          curve: Interval(delayMs / 300.0, 1.0, curve: Curves.easeOutBack),
        ),
        child: _GlassIconButton(icon: icon, tooltip: tooltip, onTap: () => _handleAction(onTap)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 按顺序收集需要展示的操作按钮（从上到下：保存、上一项、下一项）
    final actionBtns = <Widget>[];
    var delay = 0;
    if (widget.onSave != null) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.save_alt_rounded,
          tooltip: '保存到相册',
          onTap: widget.onSave!,
          delayMs: delay,
        ),
      );
      delay += 60;
    }
    if (widget.canGoPrev) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.expand_less_rounded,
          tooltip: '上一项',
          onTap: widget.onPrev,
          delayMs: delay,
        ),
      );
      delay += 60;
    }
    if (widget.canGoNext) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.expand_more_rounded,
          tooltip: '下一项',
          onTap: widget.onNext,
          delayMs: delay,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 展开的独立圆形按钮，每个之间有 10px 间距
        if (_expanded) ...[
          for (final btn in actionBtns) ...[btn, SizedBox(height: AppTheme.metrics.kSpace10)],
        ],
        // 常驻折叠/展开总按钮
        _GlassIconButton(
          icon: Icons.more_vert_rounded,
          tooltip: _expanded ? '收起' : '更多操作',
          onTap: _toggle,
        ),
      ],
    );
  }
}

// ── 图片预览 ───────────────────────────────────────────────────────────────

/// 图片预览页：
/// - 单指未缩放：上下滑触发翻页
/// - 单指已缩放/旋转：平移图片
/// - 双指：捏合缩放 + 旋转
/// - 双击：复原（重置缩放/旋转/位移）
/// - 长按：触发保存（移动端）
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.source,
    required this.onSwipeDelta,
    required this.onSwipeEnd,
    this.onSave,
    this.onZoomChanged,
  });

  final String source;

  /// 父级翻页 delta（dy 正 = 手指向下 = 上一项）
  final void Function(double dy) onSwipeDelta;
  final VoidCallback onSwipeEnd;

  /// 移动端长按时触发保存。
  final VoidCallback? onSave;

  /// 图片缩放状态变化时回调（true = 已缩放/变换，false = 恢复原样）。
  final void Function(bool isZoomed)? onZoomChanged;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  // 当前变换状态
  double _scale = 1.0;
  double _rotation = 0.0; // 弧度
  double _offsetX = 0.0;
  double _offsetY = 0.0;

  // 手势开始时的快照
  double _baseScale = 1.0;
  double _baseRotation = 0.0;
  double _baseOffsetX = 0.0;

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  double _baseOffsetY = 0.0;
  double _startFocalX = 0.0;
  double _startFocalY = 0.0;

  bool get _isTransformed =>
      _scale > 1.02 || _rotation.abs() > 0.05 || _offsetX.abs() > 5 || _offsetY.abs() > 5;

  void _reset() {
    setState(() {
      _scale = 1.0;
      _rotation = 0.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
    widget.onZoomChanged?.call(false);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseScale = _scale;
    _baseRotation = _rotation;
    _baseOffsetX = _offsetX;
    _baseOffsetY = _offsetY;
    _startFocalX = d.localFocalPoint.dx;
    _startFocalY = d.localFocalPoint.dy;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    // On macOS/desktop the trackpad generates BOTH a PointerScrollEvent (caught by the
    // outer Listener → _handlePointerScroll) and a PointerPanZoomUpdateEvent that reaches
    // onScaleUpdate with pointerCount==0.  Handling it here too would double-process or
    // cancel the scroll accumulation, so we skip it entirely for desktop.
    if (isDesktop && d.pointerCount < 2) return;

    // Two-finger gesture without a real scale/rotation change is a pan swipe for navigation,
    // NOT an image transform — treat it like a single-finger swipe.
    final isScrollSwipe =
        d.pointerCount >= 2 &&
        (d.scale - 1.0).abs() < 0.03 &&
        d.rotation.abs() < 0.05 &&
        !_isTransformed;
    if (!_isTransformed && d.pointerCount < 2 || isScrollSwipe) {
      widget.onSwipeDelta(d.focalPointDelta.dy);
      return;
    }

    // Already transformed or genuine pinch / rotate — update the transform.
    final newScale = (_baseScale * d.scale).clamp(1.0, 8.0);
    final focalDx = d.localFocalPoint.dx - _startFocalX;
    final focalDy = d.localFocalPoint.dy - _startFocalY;
    setState(() {
      _scale = newScale;
      _rotation = _baseRotation + d.rotation;
      _offsetX = _baseOffsetX + focalDx;
      _offsetY = _baseOffsetY + focalDy;
    });
    // 通知父级缩放状态（避免重复通知）
    final nowZoomed = _isTransformed;
    final wasZoomed =
        _baseScale > 1.02 ||
        _baseRotation.abs() > 0.05 ||
        _baseOffsetX.abs() > 5 ||
        _baseOffsetY.abs() > 5;
    if (nowZoomed != wasZoomed) {
      widget.onZoomChanged?.call(nowZoomed);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_scale < 1.0) _reset();
    widget.onSwipeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.source;
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTap: _reset,
          onLongPress: widget.onSave,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final Widget imgWidget;
                if (src.startsWith('http')) {
                  imgWidget = Image.network(
                    src,
                    fit: BoxFit.contain,
                    width: w,
                    height: h,
                    loadingBuilder: (_, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      final total = loadingProgress.expectedTotalBytes;
                      final loaded = loadingProgress.cumulativeBytesLoaded;
                      final pct = total != null ? loaded / total : null;
                      String label;
                      if (total != null) {
                        final pctInt = (pct! * 100).toStringAsFixed(0);
                        label = '${_fmtBytes(loaded)} / ${_fmtBytes(total)} ($pctInt%)';
                      } else {
                        label = _fmtBytes(loaded);
                      }
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              value: pct,
                              color: Colors.white70,
                              strokeWidth: 2.5,
                            ),
                            SizedBox(height: AppTheme.metrics.kSpace12),
                            Text(
                              label,
                              style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize11),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.broken_image_outlined, size: AppTheme.metrics.iconSize64, color: Colors.white38),
                    ),
                  );
                } else {
                  imgWidget = Image.file(
                    File(src),
                    fit: BoxFit.contain,
                    width: w,
                    height: h,
                    frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded || frame != null) return child;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          child,
                          const CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5),
                        ],
                      );
                    },
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(Icons.broken_image_outlined, size: AppTheme.metrics.iconSize64, color: Colors.white38),
                    ),
                  );
                }
                return Transform.translate(
                  offset: Offset(_offsetX, _offsetY),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateZ(_rotation)
                      ..scaleByDouble(_scale, _scale, 1.0, 1.0),
                    child: SizedBox(width: w, height: h, child: imgWidget),
                  ),
                );
              },
            ),
          ),
        ),
        // 已变换时显示「复原」按钮
        if (_isTransformed)
          Positioned(
            bottom: AppTheme.metrics.kSpace24,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: AppTheme.metrics.radius22,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: FilledButton.icon(
                    onPressed: _reset,
                    icon: Icon(Icons.zoom_out_map_rounded, size: AppTheme.metrics.iconSize18),
                    label: const Text('复原'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black.withAlpha(42),
                      foregroundColor: Colors.white,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── 视频预览 ───────────────────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.source,
    required this.onSwipeDelta,
    required this.onSwipeEnd,
    this.isAudio = false,
    this.title,
    this.coverSource,
  });

  final String? source;
  final void Function(double dy) onSwipeDelta;
  final VoidCallback onSwipeEnd;

  /// 是否为纯音频（无视频轨道），显示音乐占位背景
  final bool isAudio;

  /// 媒体标题（用于系统播放控件显示）
  final String? title;

  /// 封面图路径或 URL（用于系统播放控件显示）
  final String? coverSource;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  Player? _player;
  VideoController? _videoController;
  BoxFit _videoFit = BoxFit.contain;

  /// 原生 Media Session / Now Playing 通道（iOS + Android）
  static const _mediaChannel = MethodChannel('slime_works/media_session');

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    final source = widget.source;
    if (source == null || source.isEmpty) return;
    _player = Player();
    _videoController = VideoController(_player!);
    final uri = source.startsWith('http') ? source : Uri.file(source).toString();
    _player!.open(Media(uri));
    _player!.setPlaylistMode(PlaylistMode.loop);
    _updateNowPlaying();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEmpty = oldWidget.source == null || oldWidget.source!.isEmpty;
    final newEmpty = widget.source == null || widget.source!.isEmpty;
    if (oldEmpty && !newEmpty) {
      _initPlayer();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// 把封面图读成字节并通过 MethodChannel 发给原生层，由原生层更新
  /// MPNowPlayingInfoCenter (iOS) 或 MediaSession (Android)。
  Future<void> _updateNowPlaying() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      Uint8List? artBytes;
      final cover = widget.coverSource;
      if (cover != null && cover.isNotEmpty) {
        if (cover.startsWith('http')) {
          final resp = await http.get(Uri.parse(cover)).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) artBytes = resp.bodyBytes;
        } else {
          final f = File(cover);
          if (f.existsSync()) artBytes = await f.readAsBytes();
        }
      }
      await _mediaChannel.invokeMethod<void>('setNowPlaying', {
        'title': widget.title ?? '',
        'artist': '',
        'artwork': artBytes,
      });
    } catch (_) {
      // 非致命：系统控件显示默认信息即可
    }
  }

  /// 请求进入画中画（Picture-in-Picture）模式。
  Future<void> _enterPip(BuildContext context) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final supported = await _mediaChannel.invokeMethod<bool>('isPipSupported') ?? false;
      if (!supported) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当前设备不支持画中画')));
        }
        return;
      }
      await _mediaChannel.invokeMethod<void>('enterPip');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法进入画中画模式')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final controller = _videoController;
    if (player == null || controller == null) {
      return const Center(
        child: Text('无法加载视频', style: TextStyle(color: Colors.white)),
      );
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final viewPad = MediaQuery.viewPaddingOf(context);
    final bottomInset = isMobile ? viewPad.bottom : 0.0;

    // 底部控制栏：进度指示器 + 弹簧 + [速度, 适应, 音量, 窗口, 全屏]
    // 控制栏已离开屏幕最底端，会有额外 margin
    final bottomBar = [
      const media_controls.MaterialPositionIndicator(),
      const Spacer(),
      _VideoSpeedButton(player: player),
      _VideoFitButton(
        currentFit: _videoFit,
        onToggle: () =>
            setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain),
      ),
      _VideoVolumeButton(player: player),
      // 窗口播放（画中画）
      if (isMobile)
        IconButton(
          tooltip: '画中画',
          icon: Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: AppTheme.metrics.iconSize22),
          onPressed: () => _enterPip(context),
        ),
      const media_controls.MaterialFullscreenButton(),
    ];

    // 按钮栏高度来自 media_kit_video 默认值（56），进度条紧贴其上方
    const double buttonBarH = 56.0;
    final videoWidget = media_controls.MaterialVideoControlsTheme(
      normal: media_controls.MaterialVideoControlsThemeData(
        // 顶部工具栏清空，按钮全部移到底部
        topButtonBar: const [],
        topButtonBarMargin: EdgeInsets.zero,
        // 进度条位于按钮栏正上方
        seekBarMargin: EdgeInsets.only(bottom: bottomInset + 16 + buttonBarH, left: AppTheme.metrics.kSpace8, right: AppTheme.metrics.kSpace8),
        // 底部控制栏：上移 + 安全区保护
        bottomButtonBar: bottomBar,
        bottomButtonBarMargin: EdgeInsets.only(bottom: bottomInset + 16, left: AppTheme.metrics.kSpace8, right: AppTheme.metrics.kSpace8),
      ),
      fullscreen: const media_controls.MaterialVideoControlsThemeData(),
      child: Video(controller: controller, fit: _videoFit),
    );

    // 控制栏高度估算 = 进度条(48) + 按钮行(48) + 底部安全区 + 上移量
    final controlsHeight = 96.0 + bottomInset + 16;

    return Stack(
      children: [
        if (widget.isAudio)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 封面图（若有）
                  if (widget.coverSource != null && widget.coverSource!.isNotEmpty)
                    ClipRRect(
                      borderRadius: AppTheme.metrics.radius12,
                      child: widget.coverSource!.startsWith('http')
                          ? Image.network(
                              widget.coverSource!,
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(widget.coverSource!),
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                    )
                  else
                    Icon(Icons.music_note_rounded, color: Colors.white38, size: AppTheme.metrics.iconSize96),
                  SizedBox(height: AppTheme.metrics.kSpace16),
                  if (widget.title != null && widget.title!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace32),
                      child: Text(
                        widget.title!,
                        style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Text('音频播放中', style: TextStyle(color: Colors.white54, fontSize: AppTheme.metrics.fontSize15)),
                ],
              ),
            ),
          ),
        videoWidget,
        // 顶部滑动透传区（48px）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: AppTheme.metrics.kSpace48,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) => widget.onSwipeDelta(details.delta.dy),
            onVerticalDragEnd: (_) => widget.onSwipeEnd(),
          ),
        ),
        // 中间区域（避开底部控制栏）
        Positioned(
          top: AppTheme.metrics.kSpace48,
          left: 0,
          right: 0,
          bottom: controlsHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) => widget.onSwipeDelta(details.delta.dy),
            onVerticalDragEnd: (_) => widget.onSwipeEnd(),
          ),
        ),
      ],
    );
  }
}

// ── 视频播放速度按钮 ────────────────────────────────────────────────────────

class _VideoSpeedButton extends StatelessWidget {
  const _VideoSpeedButton({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.rate,
      initialData: player.state.rate,
      builder: (context, snapshot) {
        final rate = snapshot.data ?? 1.0;
        final label = (rate == rate.truncateToDouble()) ? '${rate.toInt()}x' : '${rate}x';
        return PopupMenuButton<double>(
          tooltip: '播放速度',
          color: Colors.black87,
          itemBuilder: (_) => [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
              .map(
                (r) => PopupMenuItem<double>(
                  value: r,
                  child: Text(
                    (r == r.truncateToDouble()) ? '${r.toInt()}x' : '${r}x',
                    style: TextStyle(
                      color: r == rate ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                ),
              )
              .toList(),
          onSelected: player.setRate,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace12),
            child: Text(label, style: TextStyle(color: Colors.white, fontSize: AppTheme.metrics.fontSize13)),
          ),
        );
      },
    );
  }
}

// ── 视频适应方式按钮（contain ↔ cover）─────────────────────────────────────

class _VideoFitButton extends StatelessWidget {
  const _VideoFitButton({required this.currentFit, required this.onToggle});
  final BoxFit currentFit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isCover = currentFit == BoxFit.cover;
    return IconButton(
      tooltip: isCover ? '适应屏幕' : '填充屏幕',
      icon: Icon(
        isCover ? Icons.fit_screen_rounded : Icons.crop_rounded,
        color: Colors.white,
        size: AppTheme.metrics.iconSize22,
      ),
      onPressed: onToggle,
    );
  }
}

// ── 视频音量按钮（点击静音/取消静音）──────────────────────────────────────

class _VideoVolumeButton extends StatelessWidget {
  const _VideoVolumeButton({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final vol = snapshot.data ?? 100.0;
        final icon = vol == 0
            ? Icons.volume_off_rounded
            : (vol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
        return IconButton(
          tooltip: vol == 0 ? '取消静音' : '静音',
          icon: Icon(icon, color: Colors.white, size: AppTheme.metrics.iconSize22),
          onPressed: () => player.setVolume(vol == 0 ? 100.0 : 0.0),
          onLongPress: () => _showVolumeSlider(context),
        );
      },
    );
  }

  void _showVolumeSlider(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) => Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace24, vertical: AppTheme.metrics.kSpace16),
        child: Row(
          children: [
            const Icon(Icons.volume_down_rounded, color: Colors.white70),
            Expanded(
              child: StreamBuilder<double>(
                stream: player.stream.volume,
                initialData: player.state.volume,
                builder: (context, snapshot) {
                  final vol = snapshot.data ?? 100.0;
                  return Slider(
                    value: vol.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    onChanged: player.setVolume,
                  );
                },
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
