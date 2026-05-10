import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 瀑布流（Masonry）媒体网格。
/// 将 [items] 均匀分配到 [columnCount] 列，每个 tile 高度由图片自然宽高比决定；
/// 图片加载前按默认比例占位，加载完成后刷新实际宽高比。
class MasonryMediaGrid extends StatefulWidget {
  const MasonryMediaGrid({
    super.key,
    required this.items,
    required this.collectionId,
    required this.isRemote,
    required this.viewModel,
    required this.columnCount,
    required this.onOpenViewer,
    required this.onConfirmDelete,
    this.onConfirmDeleteNodeLocalFile,
    this.lastViewedItemId,
    this.scrollController,
  });

  final List<media_api.MediaItem> items;
  final String collectionId;
  final bool isRemote;
  final MediaLibraryViewModel viewModel;
  final int columnCount;
  final void Function(int index) onOpenViewer;
  final Future<void> Function(media_api.MediaItem) onConfirmDelete;

  final Future<void> Function(media_api.MediaItem)? onConfirmDeleteNodeLocalFile;

  final String? lastViewedItemId;

  final ScrollController? scrollController;

  @override
  State<MasonryMediaGrid> createState() => MasonryMediaGridState();
}

class MasonryMediaGridState extends State<MasonryMediaGrid> {
  ScrollController? _internalScrollController;
  ScrollController get _scrollController =>
      widget.scrollController ?? (_internalScrollController ??= ScrollController());
  // 缓存每张已加载图片的宽高比，key 为 source
  final Map<String, double> _aspectRatios = {};

  /// 每个 tile 的 GlobalKey（key = item.id），用于滚动定位。
  final Map<String, GlobalKey> _itemKeys = {};

  /// 高亮消退的定时器。
  Timer? _highlightTimer;

  /// 当前需要高亮的 item ID（从 lastViewedItemId 初始化，显示后自动清除）。
  String? _highlightId;

  /// 当前已渲染的 item 数量（逐行递增，产生横向加载效果）。
  int _visibleCount = 0;

  /// 逐行展开的定时器。使用 Timer 而非 addPostFrameCallback 来避免在
  /// LayoutBuilder 的 layout 阶段中触发 setState，导致重复 key 等异常。
  Timer? _revealTimer;

  /// 初始按行逐帧展开的最大行数；超过后一次性加载剩余全部。
  static const int _kInitialRevealRows = 12;

  StreamSubscription<bool>? _overlaySub;

  @override
  void initState() {
    super.initState();
    _highlightId = widget.lastViewedItemId;
    _scheduleReveal();
    _overlaySub = widget.viewModel.showMediaOverlay.listen((_) {
      if (mounted) setState(() {});
    });
    if (_highlightId != null) {
      // 等待首批 tiles 渲染后滚动到高亮项，并在 2.5s 后消退高亮
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlighted();
        _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _highlightId = null);
          widget.viewModel.lastViewedItemId.value = null;
        });
      });
    }
  }

  @override
  void didUpdateWidget(MasonryMediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部传入新的高亮 ID（如从Viewer返回后重建 widget）
    if (widget.lastViewedItemId != null &&
        widget.lastViewedItemId != oldWidget.lastViewedItemId &&
        widget.lastViewedItemId != _highlightId) {
      _highlightTimer?.cancel();
      setState(() => _highlightId = widget.lastViewedItemId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlighted();
        _highlightTimer = Timer(const Duration(milliseconds: 25000), () {
          if (mounted) setState(() => _highlightId = null);
          widget.viewModel.lastViewedItemId.value = null;
        });
      });
    }
    if (oldWidget.collectionId != widget.collectionId ||
        oldWidget.columnCount != widget.columnCount) {
      // 切换了集合或列数变化：先立即显示前几行（避免空白闪烁），再继续逐行展开动画
      _revealTimer?.cancel();
      _itemKeys.clear();
      final initialCount = widget.items.isEmpty
          ? 0
          : (widget.columnCount * 2).clamp(0, widget.items.length);
      setState(() => _visibleCount = initialCount);
      // 下一帧继续展开剩余内容
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealNextBatch();
      });
    } else if (_visibleCount < widget.items.length) {
      // 同一集合内条目增加（如分页加载）：继续展示，不重置
      _revealTimer?.cancel();
      _scheduleReveal();
      // 清理已不在列表中的 GlobalKey
      final currentIds = widget.items.map((i) => i.id).toSet();
      _itemKeys.removeWhere((id, _) => !currentIds.contains(id));
    } else if (oldWidget.items.length > widget.items.length) {
      // 条目减少（删除）：直接收缩，清理缓存
      final currentIds = widget.items.map((i) => i.id).toSet();
      _itemKeys.removeWhere((id, _) => !currentIds.contains(id));
    }
  }

  void _scrollToHighlighted() {
    final id = _highlightId;
    if (id == null) return;
    final key = _itemKeys[id];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 400));
  }

  void _scheduleReveal() {
    _revealTimer?.cancel();
    if (widget.items.isEmpty) {
      if (mounted) setState(() => _visibleCount = 0);
      return;
    }
    // 首批用 postFrameCallback 保证第一帧可见，后续用 Timer 避免在 layout 阶段 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealNextBatch();
    });
  }

  void _revealNextBatch() {
    if (!mounted) return;
    final total = widget.items.length;
    if (_visibleCount >= total) return;
    final n = widget.columnCount;
    final threshold = n * _kInitialRevealRows;
    if (_visibleCount < threshold) {
      setState(() => _visibleCount = (_visibleCount + n).clamp(0, total));
      if (_visibleCount < total) {
        // 16ms ≈ 1 frame；Timer 在事件循环中触发，不会打断 build/layout pipeline
        _revealTimer = Timer(const Duration(milliseconds: 16), _revealNextBatch);
      }
    } else {
      setState(() => _visibleCount = total);
    }
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    _revealTimer?.cancel();
    _highlightTimer?.cancel();
    _internalScrollController?.dispose();
    super.dispose();
  }

  /// 将 items 分配到 [columnCount] 列，使用交错（round-robin）策略。
  /// 仅分配 [_visibleCount] 个 items，实现逐行展开的横向加载效果。
  List<List<int>> _distributeColumns(double colWidth) {
    final cols = List.generate(widget.columnCount, (_) => <int>[]);
    final visible = _visibleCount.clamp(0, widget.items.length);
    for (int i = 0; i < visible; i++) {
      cols[i % widget.columnCount].add(i);
    }
    return cols;
  }

  Widget _buildTile(media_api.MediaItem item, int globalIndex, double colWidth) {
    // 注册 GlobalKey 以便 scrollToHighlighted 定位
    final tileKey = _itemKeys.putIfAbsent(item.id, GlobalKey.new);

    final source = widget.viewModel.buildMediaSource(item, isCover: true);
    final fullSource = widget.viewModel.buildMediaSource(item);
    final isVideo = item.kind == media_api.MediaKind.video;
    final isAudio = item.kind == media_api.MediaKind.audio;
    const defaultAr = (3.0 / 5.0);

    // 优先使用 MediaItem 中已有的宽高字段（扫描时由 Rust 填入），避免在 build() 阶段
    // 同步读取图片文件来解码尺寸（会导致"一列一列"的加载顺序问题）。
    double ar;
    if (source != null && source.isNotEmpty && _aspectRatios.containsKey(source)) {
      ar = _aspectRatios[source]!;
    } else if (item.width != null && item.height != null && item.height! > 0) {
      ar = item.width! / item.height!;
      // 立即缓存，下次直接命中
      if (source != null && source.isNotEmpty) {
        _aspectRatios[source] = ar.clamp(0.3, 3.0);
      }
    } else {
      ar = defaultAr;
    }
    final tileHeight = (colWidth / ar).clamp(60.0, colWidth * 2.5);

    // 仅对本地非视频且没有已知尺寸的 items 才异步解码真实宽高比（兜底）。
    // 音频封面由 _audioCoverPath 异步返回，不从 source(原始音频文件)解码宽高比。
    if (!isVideo && !isAudio && source != null && source.isNotEmpty && !source.startsWith('http')) {
      if (!_aspectRatios.containsKey(source) &&
          (item.width == null || item.height == null || item.height == 0)) {
        _resolveAspectRatio(source, File(source));
      }
    }

    final isHighlighted = item.id == _highlightId;
    final tile = MediaItemTile(
      key: tileKey,
      item: item,
      source: source,
      fixedHeight: tileHeight,
      showOverlay: widget.viewModel.showMediaOverlay.value,
      onTap: () => widget.onOpenViewer(globalIndex),
      onRequestScrubFrames: (isVideo && !widget.isRemote)
          ? () => widget.viewModel.getVideoScrubFrames(item.filePath)
          : null,
      // 远程音频：widget.source 已经是 mode=cover URL，onRequestAudioCover 置 null
      // 令 _displaySource 直接返回 source，无需额外异步；本地音频走 ffmpeg 提取路径。
      onRequestAudioCover: isAudio
          ? (widget.isRemote ? null : () => widget.viewModel.getAudioCoverSource(item.filePath))
          : null,
      onOpenFolder: widget.isRemote ? null : () => widget.viewModel.openItemInFolder(item),
      onDeleteFile: widget.isRemote ? null : () => widget.onConfirmDelete(item),
      onDeleteNodeLocalFile: widget.isRemote
          ? () => widget.onConfirmDeleteNodeLocalFile?.call(item)
          : null,
      deleteNodeLocalFileLabel: widget.isRemote ? '删除节点本地文件' : null,
      // 移动端图片支持保存到相册（本地和远程均支持）
      onSaveToGallery: (PlatformUtil.isMobile && !isVideo && !isAudio)
          ? () => saveToGallery(context, fullSource)
          : null,
    );

    if (!isHighlighted) return tile;
    // 高亮边框（主色 0.5 不透明度）
    return Stack(
      children: [
        tile,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isHighlighted ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(scaleW(11)),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 带入场动画（淡入 + 向上滑入）的 tile 包装器。
  /// 每次 tile 首次插入 widget 树时，TweenAnimationBuilder 会从 0→1 播放一次。
  Widget _buildAnimatedTile(media_api.MediaItem item, int globalIndex, double colWidth) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('anim_$globalIndex'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 28 * (1 - value)), child: child),
      ),
      child: _buildTile(item, globalIndex, colWidth),
    );
  }

  void _resolveAspectRatio(String source, File file) async {
    try {
      final bytes = await file.openRead(0, 65536).expand((c) => c).toList();
      final bytesU8 = Uint8List.fromList(bytes);
      final codec = await ui.instantiateImageCodec(bytesU8);
      final frame = await codec.getNextFrame();
      final ar = frame.image.width / frame.image.height;
      frame.image.dispose();
      if (mounted && ar > 0 && !_aspectRatios.containsKey(source)) {
        setState(() => _aspectRatios[source] = ar.clamp(0.3, 3.0));
      }
    } catch (_) {}
  }

  /// 将图片保存到系统相册（支持本地路径和远程 HTTP URL）。
  static Future<void> saveToGallery(BuildContext context, String? source) async {
    if (source == null || source.isEmpty) return;
    // 最多请求 3 次权限
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
        // 保留原始扩展名，部分平台按扩展名识别图片格式
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
    final crossAxisCount = widget.columnCount;
    final padding = AppTheme.metrics.kSpace12;
    final spacing = AppTheme.metrics.kSpace8;

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final colWidth =
            (constraints.maxWidth - 2 * padding - (crossAxisCount - 1) * spacing) / crossAxisCount;
        final columns = _distributeColumns(colWidth);

        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int c = 0; c < crossAxisCount; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < columns[c].length; i++) ...[
                        if (i > 0) SizedBox(height: spacing),
                        _buildAnimatedTile(widget.items[columns[c][i]], columns[c][i], colWidth),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );

    return grid;
  }
}

/// 框选矩形绘制器，用于桌面端拖拽多选。
class SelectionBoxPainter extends CustomPainter {
  const SelectionBoxPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.borderColor,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scaleW(1.5);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SelectionBoxPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
