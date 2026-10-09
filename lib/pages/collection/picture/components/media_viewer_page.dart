import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
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

part 'media_viewer_glass.dart';
part 'media_viewer_image.dart';
part 'media_viewer_video.dart';
part 'media_viewer_mini.dart';

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
  static const double _kDragCommitFraction = 0.3;
  int _lastJumpTimeMs = 0;
  static const int _kJumpCooldownMs = 400;

  // ── 沉浸模式 ──────────────────────────────────────────────────────────────
  bool _uiVisible = true;
  Timer? _immersiveTimer;

  // ── 图片缩放状态（缩放时禁用外层翻页手势）────────────────────────────────
  bool _imageIsZoomed = false;
  bool _currentIsVideo = false;

  /// 鼠标中键是否处于按下状态（中键按住 + 滚轮 = 缩放模式）。
  bool _middleButtonHeld = false;
  static const Duration _kImmersiveDelay = Duration(seconds: 10);

  // ── 滚轮缩放通信 ───────────────────────────────────────────────────────
  // 外层 Listener 独占指针信号（框架规则：先注册者胜，命中遍历从根到叶），
  // 内层 Listener 永远收不到事件，因此缩放由外层判定后经此 Notifier 定向通知。
  // 元组含义：(序号, 目标页 index, 鼠标位置, 滚轮 dy)
  int _wheelZoomSeq = 0;
  final _wheelZoomNotifier = ValueNotifier<(int, int, Offset, double)>((0, -1, Offset.zero, 0));

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
    _currentIsVideo =
        widget.items[_currentIndex].kind == media_api.MediaKind.video ||
        widget.items[_currentIndex].kind == media_api.MediaKind.audio;
    _snapCtrl = AnimationController(vsync: this, duration: AppMotion.base);
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
    _wheelZoomNotifier.dispose();
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
      final pending = _pendingIndex;
      _imageIsZoomed = false;
      setState(() {
        if (pending != null) {
          _prevPageWidget = null;
          _currPageWidget = null;
          _nextPageWidget = null;
          _currentIndex = pending;
          _currentItemId = widget.items.isNotEmpty ? widget.items[_currentIndex].id : null;
          final kind = widget.items[_currentIndex].kind;
          _currentIsVideo = kind == media_api.MediaKind.video || kind == media_api.MediaKind.audio;
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
    debugPrint(
      '[MVP] _onDragStart horizontal=$horizontal, _snapAnimating=${_snapCtrl.isAnimating}, _currentIndex=$_currentIndex',
    );
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

    debugPrint(
      '[MVP] _onDragEnd velocity=$velocity, dragOffset=$_dragOffset, frac=$frac, next=$next, screenExtent=$screenExtent',
    );

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
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed;
    // 中键按下（以事件自身 buttons 兜底，防止 down/up 监听遗漏）
    final middleHeld = _middleButtonHeld || (event.buttons & kMiddleMouseButton) != 0;
    // 按住 Ctrl 或鼠标中键：禁用翻页；图片页时滚轮作为缩放（视频页无缩放，忽略）
    if (ctrlPressed || middleHeld) {
      if (!_currentIsVideo) _requestZoom(event);
      return;
    }
    // 图片已缩放：滚轮继续缩放，禁用翻页（直到重置缩放恢复 100%）
    if (!_currentIsVideo && _imageIsZoomed) {
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

  /// 将滚轮事件转发给当前页的 _ImageViewer 执行锚点缩放。
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

  // ── 子页面垂直滑动回调（图片缩放后用 onSwipeDelta 代替 drag）────────────

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

  Widget _buildPageContent(BuildContext context, int index, {bool isActive = true}) {
    if (index < 0 || index >= widget.items.length) {
      return const SizedBox.expand();
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final item = widget.items[index];
    final source = widget.viewModel.buildMediaSource(item, collectionId: widget.collectionId);
    // 临时调试：打印预览实际请求的图片地址，判断是否带 width 缩略参数
    if (item.kind == media_api.MediaKind.image) {
      debugPrint('[ViewerDebug] index=$index kind=${item.kind.name} source=$source remoteImageWidth=${widget.viewModel.mediaPrefs.remoteImageWidth.value}');
    }
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
        isActive: isActive,
        onDragStart: () => _onDragStart(horizontal: false),
        onDragUpdate: (dy) => _onDragUpdate(dy),
        onDragEnd: (velocity, screenExtent) => _onDragEnd(velocity, screenExtent),
        isAudio: item.kind == media_api.MediaKind.audio,
      );
    }
    if (source == null || source.isEmpty) {
      // 查看器画布固定深色，错误提示白字不随明暗翻转
      return Center(
        child: Text('无法加载图片', style: AppTextStyles.role(
          context,
          color: AppSemantic.of(context).onMedia,
          fontSize: AppTheme.metrics.fontSize13,
        )),
      );
    }
    return _ImageViewer(
      source: source,
      pageIndex: index,
      wheelZoomNotifier: _wheelZoomNotifier,
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
    final s = AppSemantic.of(context);
    final size = MediaQuery.sizeOf(context);
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final item = widget.items[_currentIndex];
    final isImage = item.kind == media_api.MediaKind.image;

    // 懒填充：只建还没构建的槽，已有的直接复用
    _currPageWidget ??= _buildPageContent(context, _currentIndex, isActive: true);
    if (_currentIndex > 0) {
      if (_prevPageWidget == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _prevPageWidget = _buildPageContent(context, _currentIndex - 1, isActive: false);
          });
        });
      }
    } else {
      _prevPageWidget = null;
    }
    if (_currentIndex < widget.items.length - 1) {
      if (_nextPageWidget == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _nextPageWidget = _buildPageContent(context, _currentIndex + 1, isActive: false);
          });
        });
      }
    } else {
      _nextPageWidget = null;
    }

    debugPrint(
      '[MVP] build() index=$_currentIndex, isDragging=$_isDragging, dragOffset=$_dragOffset, currType=${_currPageWidget?.runtimeType}, prevType=${_prevPageWidget?.runtimeType}, nextType=${_nextPageWidget?.runtimeType}',
    );

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
                  // 移动端：水平拖动（图片翻项；视频页改为内部水平拖动快进/快退）
                  onHorizontalDragStart: (isMobile && !_imageIsZoomed && !_currentIsVideo)
                      ? (_) => _onDragStart(horizontal: true)
                      : null,
                  onHorizontalDragUpdate: (isMobile && !_imageIsZoomed && !_currentIsVideo)
                      ? (d) => _onDragUpdate(d.delta.dx)
                      : null,
                  onHorizontalDragEnd: (isMobile && !_imageIsZoomed && !_currentIsVideo)
                      ? (d) => _onDragEnd(d.velocity.pixelsPerSecond.dx, size.width)
                      : null,
                  // 移动端：垂直拖动（图片缩放时禁用）
                  onVerticalDragStart: (isMobile && !_imageIsZoomed && !_currentIsVideo)
                      ? (_) => _onDragStart(horizontal: false)
                      : null,
                  onVerticalDragUpdate: (isMobile && !_imageIsZoomed && !_currentIsVideo)
                      ? (d) => _onDragUpdate(d.delta.dy)
                      : null,
                  onVerticalDragEnd: (isMobile && !_imageIsZoomed && !_currentIsVideo)
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

            // ── 右下角：浮动操作菜单（视频/音频页自带控制栏，隐藏以免遮挡）────
            if (!_currentIsVideo)
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
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: appMetrics.kSpace10,
                                vertical: appMetrics.kSpace10,
                              ),
                              // 深色玻璃标题条上的白字不随明暗翻转
                              color: s.immersivePanel,
                              child: Text(
                                widget.items[_currentIndex].title,
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
