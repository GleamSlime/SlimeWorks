import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

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

class _MediaViewerPageState extends State<MediaViewerPage> {
  late final PageController _pageController;
  int _currentIndex = 0;

  /// 累计滑动偏移，超阈值才翻页（避免误触）
  double _scrollAccum = 0.0;
  static const double _kScrollThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _jump(int delta) {
    final next = (_currentIndex + delta).clamp(0, widget.items.length - 1);
    if (next == _currentIndex) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// 触摸板 / 鼠标滚轮：离散事件直接翻页，触摸板累积翻页。
  void _handlePointerScroll(PointerScrollEvent event) {
    final dy = event.scrollDelta.dy;
    if (dy.abs() >= 100) {
      _scrollAccum = 0;
      _jump(dy > 0 ? 1 : -1);
      return;
    }
    _scrollAccum += dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      _jump(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  /// 子页面（图片 / 视频）反馈的垂直滑动偏移量，统一处理翻页逻辑。
  /// [dy] 正 = 手指向下 → 上一项；负 = 手指向上 → 下一项。
  void _handleSwipeDelta(double dy) {
    _scrollAccum -= dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      _jump(_scrollAccum > 0 ? 1 : -1);
      _scrollAccum = 0;
    }
  }

  /// 将当前图片保存到系统相册。
  Future<void> _saveCurrentItem(BuildContext context) async {
    final item = widget.items[_currentIndex];
    if (item.kind != media_api.MediaKind.image) return;
    // 保存时始终用原图（不传 isCover）
    final source = widget.viewModel.buildMediaSource(item, collectionId: widget.collectionId);
    if (source == null || source.isEmpty) return;

    // 最多请求 3 次权限
    const maxAttempts = 3;
    bool hasAccess = false;
    try {
      hasAccess = await Gal.hasAccess(toAlbum: true);
    } catch (_) {}
    for (int attempt = 0; !hasAccess && attempt < maxAttempts; attempt++) {
      try {
        hasAccess = await Gal.requestAccess(toAlbum: true);
      } catch (_) {}
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

    EasyLoading.show(status: '正在保存...');
    File? tmpFile;
    try {
      String localPath;
      if (source.startsWith('http')) {
        // 带 30s 超时，避免卡死
        final resp = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 30));
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
      // Gal.putImage 需在主线程调用，用 microtask 确保
      await Future.microtask(() => Gal.putImage(localPath));
      EasyLoading.showSuccess('已保存到相册');
    } catch (e) {
      EasyLoading.showError('保存失败: $e');
    } finally {
      tmpFile?.delete().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final isImage = item.kind == media_api.MediaKind.image;
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
            _jump(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _jump(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            // ── 全屏翻页器 ──────────────────────────────────────────────────
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) _handlePointerScroll(event);
              },
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.items.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  _scrollAccum = 0;
                },
                itemBuilder: (context, index) {
                  final currentItem = widget.items[index];
                  final source = widget.viewModel.buildMediaSource(
                    currentItem,
                    collectionId: widget.collectionId,
                  );
                  if (currentItem.kind == media_api.MediaKind.video) {
                    return _VideoPreview(
                      source: source,
                      onSwipeDelta: _handleSwipeDelta,
                      onSwipeEnd: () => _scrollAccum = 0,
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
                  );
                },
              ),
            ),

            // ── 左上角：玻璃返回按钮 ─────────────────────────────────────────
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 12,
              child: _GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '关闭预览',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),

            // ── 右下角：浮动操作菜单 ─────────────────────────────────────────
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GlassChip(label: '${_currentIndex + 1} / ${widget.items.length}'),
                  _FloatingActionMenu(
                    canGoPrev: _currentIndex > 0,
                    canGoNext: _currentIndex < widget.items.length - 1,
                    onSave: isImage ? () => _saveCurrentItem(context) : null,
                    onPrev: () => _jump(-1),
                    onNext: () => _jump(1),
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
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 42,
            height: 42,
            color: Colors.black.withOpacity(0.42),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 22),
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

// ── 玻璃计数标签 ────────────────────────────────────────────────────────────

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          color: Colors.black.withOpacity(0.42),
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
          for (final btn in actionBtns) ...[btn, const SizedBox(height: 10)],
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
  });

  final String source;

  /// 父级翻页 delta（dy 正 = 手指向下 = 上一项）
  final void Function(double dy) onSwipeDelta;
  final VoidCallback onSwipeEnd;

  /// 移动端长按时触发保存。
  final VoidCallback? onSave;

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
    if (!_isTransformed && d.pointerCount < 2) {
      // 未变换 + 单指：将焦点位移传给父级做翻页
      widget.onSwipeDelta(d.focalPointDelta.dy);
      return;
    }
    // 双指或已变换：更新缩放 / 旋转 / 位移
    final newScale = (_baseScale * d.scale).clamp(1.0, 8.0);
    final focalDx = d.localFocalPoint.dx - _startFocalX;
    final focalDy = d.localFocalPoint.dy - _startFocalY;
    setState(() {
      _scale = newScale;
      _rotation = _baseRotation + d.rotation;
      _offsetX = _baseOffsetX + focalDx;
      _offsetY = _baseOffsetY + focalDy;
    });
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
                final imgWidget = src.startsWith('http')
                    ? Image.network(
                        src,
                        fit: BoxFit.contain,
                        width: w,
                        height: h,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white38),
                        ),
                      )
                    : Image.file(
                        File(src),
                        fit: BoxFit.contain,
                        width: w,
                        height: h,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white38),
                        ),
                      );
                return Transform.translate(
                  offset: Offset(_offsetX, _offsetY),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateZ(_rotation)
                      ..scale(_scale),
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
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.zoom_out_map_rounded, size: 18),
                label: const Text('复原'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
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
  const _VideoPreview({required this.source, required this.onSwipeDelta, required this.onSwipeEnd});

  final String? source;
  final void Function(double dy) onSwipeDelta;
  final VoidCallback onSwipeEnd;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    if (source == null || source.isEmpty) return;
    _player = Player();
    _videoController = VideoController(_player!);
    final uri = source.startsWith('http') ? source : Uri.file(source).toString();
    _player!.open(Media(uri));
    _player!.setPlaylistMode(PlaylistMode.loop);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
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
    // 移动端平台视图会吸收所有触摸事件，用透明覆盖层（顶部）实现滑动翻页。
    // 底部 ~80px 保留给播放器控制栏，不覆盖。
    return Stack(
      children: [
        Video(controller: controller),
        // 顶部滑动区（48px），Flutter Widget 层在平台视图之上，可接收手势
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) => widget.onSwipeDelta(details.delta.dy),
            onVerticalDragEnd: (_) => widget.onSwipeEnd(),
          ),
        ),
        // 中间区域（避开底部控制栏 80px）也注册滑动手势
        Positioned(
          top: 48,
          left: 0,
          right: 0,
          bottom: 80,
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
