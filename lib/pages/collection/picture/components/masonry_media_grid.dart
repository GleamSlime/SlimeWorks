import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 将 items 分配到 [columnCount] 列（按当前累计高度平衡）。
  List<List<int>> _distributeColumns(double colWidth) {
    final cols = List.generate(widget.columnCount, (_) => <int>[]);
    final heights = List.filled(widget.columnCount, 0.0);
    for (int i = 0; i < widget.items.length; i++) {
      final src = widget.viewModel.buildMediaSource(widget.items[i], isCover: true);
      final ar = (src != null && src.isNotEmpty) ? (_aspectRatios[src] ?? 1.0) : 1.0;
      final h = colWidth / ar;
      // 放入最短的列
      int shortest = 0;
      for (int c = 1; c < widget.columnCount; c++) {
        if (heights[c] < heights[shortest]) shortest = c;
      }
      cols[shortest].add(i);
      heights[shortest] += h;
    }
    return cols;
  }

  Widget _buildTile(media_api.MediaItem item, int globalIndex, double colWidth) {
    // 缩略图走「远程封面清晰度」，预览全图需另行调用 buildMediaSource(isCover:false)
    final source = widget.viewModel.buildMediaSource(item, isCover: true);
    final isVideo = item.kind == media_api.MediaKind.video;
    final defaultAr = isVideo ? (16.0 / 9.0) : (3.0 / 5.0);
    final ar = (source != null && source.isNotEmpty)
        ? (_aspectRatios[source] ?? defaultAr)
        : defaultAr;
    final tileHeight = (colWidth / ar).clamp(60.0, colWidth * 2.5);

    // 非视频图片：首次渲染后异步解码真实宽高比
    if (!isVideo && source != null && source.isNotEmpty && !source.startsWith('http')) {
      if (!_aspectRatios.containsKey(source)) {
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
      onOpenFolder: widget.isRemote ? null : () => widget.viewModel.openItemInFolder(item),
      onDeleteFile: widget.isRemote ? null : () => widget.onConfirmDelete(item),
      // 移动端图片支持保存到相册（本地和远程均支持）
      onSaveToGallery: (PlatformUtil.isMobile && !isVideo)
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
    final isMobileRemote = PlatformUtil.isMobile && widget.isRemote;

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

    if (!isMobileRemote) return grid;

    return Stack(
      children: [
        grid,
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            heroTag: 'upload_media_fab',
            tooltip: '从相册上传图片到节点',
            onPressed: () => _pickAndUpload(context),
            child: const Icon(Icons.upload_rounded),
          ),
        ),
      ],
    );
  }

  /// 打开文件选择器，选图后上传到远程节点。
  Future<void> _pickAndUpload(BuildContext context) async {
    final nodeId = widget.viewModel.getRemoteNodeId(widget.collectionId);
    if (nodeId == null) return;

    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final nodeService = getIt<NodeSettingsService>();
    final rawCollId = widget.viewModel.getRemoteRawCollectionId(widget.collectionId);
    int success = 0;
    int fail = 0;

    EasyLoading.show(status: '正在上传 0 / ${result.files.length}...');
    for (int i = 0; i < result.files.length; i++) {
      final path = result.files[i].path;
      if (path == null) continue;
      EasyLoading.show(status: '正在上传 ${i + 1} / ${result.files.length}...');
      try {
        await nodeService.uploadMediaToNode(
          nodeId: nodeId,
          localPath: path,
          collectionId: rawCollId,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }

    if (fail == 0) {
      EasyLoading.showSuccess('已上传 $success 张');
    } else {
      EasyLoading.showError('上传完成：$success 成功，$fail 失败');
    }
    // 触发远程集合刷新
    await widget.viewModel.refreshRemoteCollections();
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
