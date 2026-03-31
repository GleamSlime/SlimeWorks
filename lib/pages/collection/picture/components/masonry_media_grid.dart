import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
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
  });

  final List<media_api.MediaItem> items;
  final String collectionId;
  final bool isRemote;
  final MediaLibraryViewModel viewModel;
  final int columnCount;
  final void Function(int index) onOpenViewer;
  final Future<void> Function(media_api.MediaItem) onConfirmDelete;

  @override
  State<MasonryMediaGrid> createState() => MasonryMediaGridState();
}

class MasonryMediaGridState extends State<MasonryMediaGrid> {
  final _scrollController = ScrollController();
  // 缓存每张已加载图片的宽高比，key 为 source
  final Map<String, double> _aspectRatios = {};

  /// 当前已渲染的 item 数量（逐行递增，产生横向加载效果）。
  int _visibleCount = 0;

  /// 初始按行逐帧展开的最大行数；超过后一次性加载剩余全部。
  static const int _kInitialRevealRows = 12;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(MasonryMediaGrid old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length ||
        old.columnCount != widget.columnCount) {
      _visibleCount = 0;
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    if (widget.items.isEmpty) {
      if (mounted) setState(() => _visibleCount = 0);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(_revealNextBatch);
  }

  void _revealNextBatch([_]) {
    if (!mounted) return;
    final total = widget.items.length;
    if (_visibleCount >= total) return;
    final n = widget.columnCount;
    final threshold = n * _kInitialRevealRows;
    if (_visibleCount < threshold) {
      setState(() => _visibleCount = (_visibleCount + n).clamp(0, total));
      if (_visibleCount < total) {
        WidgetsBinding.instance.addPostFrameCallback(_revealNextBatch);
      }
    } else {
      setState(() => _visibleCount = total);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    // 缩略图走「远程封面清晰度」，预览全图需另行调用 buildMediaSource(isCover:false)
    final source = widget.viewModel.buildMediaSource(item, isCover: true);
    final isVideo = item.kind == media_api.MediaKind.video;
    final isAudio = item.kind == media_api.MediaKind.audio;
    final defaultAr = (3.0 / 5.0);

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

    return MediaItemTile(
      key: ValueKey(item.id),
      item: item,
      source: source,
      fixedHeight: tileHeight,
      onTap: () => widget.onOpenViewer(globalIndex),
      onRequestScrubFrames: (isVideo && !widget.isRemote)
          ? () => widget.viewModel.getVideoScrubFrames(item.filePath)
          : null,
      onRequestAudioCover: (isAudio && !widget.isRemote)
          ? () => widget.viewModel.getAudioCoverSource(item.filePath)
          : null,
      onOpenFolder: widget.isRemote ? null : () => widget.viewModel.openItemInFolder(item),
      onDeleteFile: widget.isRemote ? null : () => widget.onConfirmDelete(item),
      // 移动端图片支持保存到相册（本地和远程均支持）
      onSaveToGallery: (PlatformUtil.isMobile && !isVideo && !isAudio)
          ? () => saveToGallery(context, source)
          : null,
    );
  }

  void _resolveAspectRatio(String source, File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
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
        final resp = await http.get(Uri.parse(source));
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
                        _buildTile(widget.items[columns[c][i]], columns[c][i], colWidth),
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
