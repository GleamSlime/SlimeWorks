part of 'media_viewer_page.dart';

// ── 图片预览 ───────────────────────────────────────────────────────────────

/// 图片预览页：
/// - 单指未缩放：上下滑触发翻页
/// - 单指已缩放/旋转：平移图片
/// - 双指：捏合缩放 + 旋转
/// - 双击：复原（重置缩放/旋转/位移）
/// - 长按：触发保存（移动端）
/// - 桌面端：Ctrl+滚轮缩放；缩放后直接滚轮继续缩放、鼠标拖拽平移
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.source,
    required this.onSwipeDelta,
    required this.onSwipeEnd,
    this.onSave,
    this.onZoomChanged,
    this.pageIndex = -1,
    this.wheelZoomNotifier,
  });

  final String source;

  /// 父级翻页 delta（dy 正 = 手指向下 = 上一项）
  final void Function(double dy) onSwipeDelta;
  final VoidCallback onSwipeEnd;

  /// 移动端长按时触发保存。
  final VoidCallback? onSave;

  /// 图片缩放状态变化时回调（true = 已缩放/变换，false = 恢复原样）。
  final void Function(bool isZoomed)? onZoomChanged;

  /// 本页在父级中的 index（用于识别滚轮缩放通知是否发给自己）。
  final int pageIndex;

  /// 父级滚轮缩放通知：(序号, 目标页 index, 鼠标位置, 滚轮 dy)。
  final ValueNotifier<(int, int, Offset, double)>? wheelZoomNotifier;

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

  // 当前布局尺寸（滚轮缩放以鼠标位置为锚点时需要）
  double _layoutW = 0.0;
  double _layoutH = 0.0;

  // 已处理的滚轮缩放通知序号（去重）
  int _lastWheelSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.wheelZoomNotifier?.addListener(_onWheelZoomRequest);
  }

  @override
  void didUpdateWidget(_ImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wheelZoomNotifier != widget.wheelZoomNotifier) {
      oldWidget.wheelZoomNotifier?.removeListener(_onWheelZoomRequest);
      widget.wheelZoomNotifier?.addListener(_onWheelZoomRequest);
    }
  }

  @override
  void dispose() {
    widget.wheelZoomNotifier?.removeListener(_onWheelZoomRequest);
    super.dispose();
  }

  /// 响应父级滚轮缩放通知：仅处理发往本页的事件。
  void _onWheelZoomRequest() {
    final v = widget.wheelZoomNotifier?.value;
    if (v == null) return;
    if (v.$2 != widget.pageIndex) return;
    if (v.$1 == _lastWheelSeq) return;
    _lastWheelSeq = v.$1;
    _zoomAtPointer(v.$3, v.$4);
  }

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
    if (isDesktop && d.pointerCount < 2) {
      // 桌面端鼠标拖拽：缩放状态下平移图片；未缩放时忽略（翻页由外层处理）
      if (_scale > 1.02) {
        setState(() {
          _offsetX += d.focalPointDelta.dx;
          _offsetY += d.focalPointDelta.dy;
        });
      }
      return;
    }

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
    if (!Platform.isAndroid && !Platform.isIOS) return;
    widget.onSwipeEnd();
  }

  // ── 桌面端鼠标滚轮缩放 ──────────────────────────────────────────────
  // 滚轮事件由父级 _handlePointerScroll 统一拦截（外层 Listener 独占指针信号），
  // 父级判定为缩放行为后经 wheelZoomNotifier 通知本页执行 _zoomAtPointer。

  /// 以鼠标位置为锚点缩放。dy < 0（滚轮向上）= 放大。
  /// 缩放回 1.0 时清除全部变换，滚轮恢复翻页行为。
  void _zoomAtPointer(Offset pos, double dy) {
    const step = 1.15;
    final raw = dy < 0 ? _scale * step : _scale / step;
    final newScale = raw.clamp(1.0, 8.0);
    if (newScale == _scale) {
      // 已在边界（继续缩小但已是 1.0）→ 直接复原
      if (_scale <= 1.0 && _isTransformed) _reset();
      return;
    }
    final wasZoomed = _isTransformed;
    if (newScale <= 1.0) {
      // 缩放回原始大小：清除全部变换，滚轮恢复翻页行为
      _reset();
      return;
    }
    // 锚点缩放：保持鼠标下的图像内容不动（变换 = 围绕中心缩放 + 平移）
    final k = newScale / _scale;
    final cx = _layoutW / 2;
    final cy = _layoutH / 2;
    setState(() {
      _offsetX = pos.dx - cx - (pos.dx - _offsetX - cx) * k;
      _offsetY = pos.dy - cy - (pos.dy - _offsetY - cy) * k;
      _scale = newScale;
    });
    final nowZoomed = _isTransformed;
    if (nowZoomed != wasZoomed) {
      widget.onZoomChanged?.call(nowZoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final src = widget.source;
    // 注意：不要在此处内嵌 Listener 拦截滚轮——指针信号由命中路径上先注册者独占，
    // 外层 Listener 永远先于内层收到，内层拦截不会生效。滚轮逻辑统一由父级处理。
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
                // 记录布局尺寸，供滚轮锚点缩放计算使用
                _layoutW = w;
                _layoutH = h;
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
                              color: s.onMediaSecondary,
                              strokeWidth: AppTheme.metrics.strokeEmphasis,
                            ),
                            SizedBox(height: AppTheme.metrics.kSpace12),
                            Text(
                              label,
                              // 深色查看器画面上的加载文字：白字固定不随明暗翻转
                              style: AppTextStyles.role(
                                context,
                                color: s.onMediaSecondary,
                                fontSize: AppTheme.metrics.fontSize11,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: AppTheme.metrics.iconSize64,
                        color: s.onMediaFaint,
                      ),
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
                          // 语义色取不到 const，这里丢掉 const
                          CircularProgressIndicator(color: s.onMediaSecondary, strokeWidth: AppTheme.metrics.strokeEmphasis),
                        ],
                      );
                    },
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: AppTheme.metrics.iconSize64,
                        color: s.onMediaFaint,
                      ),
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
        // 已变换时显示「重置缩放」按钮（缩放/旋转/平移后均可一键复原）
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
                    label: const Text('重置缩放'),
                    style: FilledButton.styleFrom(
                      backgroundColor: s.mediaStage.withAlpha(42),
                      foregroundColor: s.onMedia,
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

