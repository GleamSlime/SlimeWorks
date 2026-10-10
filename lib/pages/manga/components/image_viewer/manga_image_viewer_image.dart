part of 'manga_image_viewer_page.dart';

// ── 漫画页放大预览 ─────────────────────────────────────────────────────────
//
/// 单页预览：
/// - 单指未缩放：上下滑触发翻页
/// - 单指已缩放/旋转：平移图片
/// - 双指：捏合缩放 + 旋转
/// - 双击：复原（重置缩放/旋转/位移）
/// - 长按：触发保存（移动端）
/// - 桌面端：Ctrl+滚轮缩放；缩放后直接滚轮继续缩放、鼠标拖拽平移
class _MangaPageViewer extends StatefulWidget {
  const _MangaPageViewer({
    required this.image,
    required this.onSwipeDelta,
    required this.onSwipeEnd,
    this.onSave,
    this.onZoomChanged,
    this.pageIndex = -1,
    this.wheelZoomNotifier,
  });

  final MangaImage image;

  /// 父级翻页 delta（dy 正 = 手指向下 = 上一页）
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
  State<_MangaPageViewer> createState() => _MangaPageViewerState();
}

class _MangaPageViewerState extends State<_MangaPageViewer> {
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

  // 当前布局尺寸（滚轮缩放以鼠标位置为锚点时需要）
  double _layoutW = 0.0;
  double _layoutH = 0.0;

  // 已处理的滚轮缩放通知序号（去重）
  int _lastWheelSeq = 0;

  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = getIt<MangaService>().fetchImageBytes(widget.image);
    widget.wheelZoomNotifier?.addListener(_onWheelZoomRequest);
  }

  /// 重新发起图片字节请求（加载失败后的重试）
  void _reload() {
    setState(() {
      _future = getIt<MangaService>().fetchImageBytes(widget.image);
    });
  }

  @override
  void didUpdateWidget(_MangaPageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path ||
        oldWidget.image.fileServer != widget.image.fileServer) {
      _future = getIt<MangaService>().fetchImageBytes(widget.image);
    }
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
    // 桌面端触摸板会同时产生 PointerScrollEvent（外层 Listener 捕获）和
    // pointerCount==0 的 PointerPanZoomUpdateEvent（走到这里），
    // 两处都处理会重复缩放，故桌面端此处只认双指手势。
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

    // 双指但没有真实的缩放/旋转变化，那是翻页滑动，不是图片变换
    final isScrollSwipe =
        d.pointerCount >= 2 &&
        (d.scale - 1.0).abs() < 0.03 &&
        d.rotation.abs() < 0.05 &&
        !_isTransformed;
    if (!_isTransformed && d.pointerCount < 2 || isScrollSwipe) {
      widget.onSwipeDelta(d.focalPointDelta.dy);
      return;
    }

    // 已变换或真实的捏合/旋转 —— 更新变换
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
                return Transform.translate(
                  offset: Offset(_offsetX, _offsetY),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..rotateZ(_rotation)
                      ..scaleByDouble(_scale, _scale, 1.0, 1.0),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: FutureBuilder<Uint8List>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return Center(
                              child: MangaProgressRing(
                                size: AppTheme.metrics.kSpace44,
                                color: s.onMediaSecondary,
                              ),
                            );
                          }
                          if (snapshot.hasError || !snapshot.hasData) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.broken_image_outlined,
                                    size: AppTheme.metrics.iconSize64,
                                    color: s.onMediaFaint,
                                  ),
                                  SizedBox(height: AppTheme.metrics.kSpace12),
                                  TextButton.icon(
                                    // 黑色舞台上的重试按钮：前景色固定为白
                                    style: TextButton.styleFrom(
                                      foregroundColor: s.onMediaSecondary,
                                    ),
                                    onPressed: _reload,
                                    icon: Icon(
                                      Icons.refresh,
                                      size: AppTheme.metrics.iconSize16,
                                    ),
                                    label: const Text('重试'),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            width: w,
                            height: h,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded || frame != null) return child;
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  child,
                                  CircularProgressIndicator(
                                    color: s.onMediaSecondary,
                                    strokeWidth: AppTheme.metrics.strokeEmphasis,
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
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
                  filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
                  child: FilledButton.icon(
                    onPressed: _reset,
                    icon: Icon(
                      Icons.zoom_out_map_rounded,
                      size: AppTheme.metrics.iconSize18,
                    ),
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
