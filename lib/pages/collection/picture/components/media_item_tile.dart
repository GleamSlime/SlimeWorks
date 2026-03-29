import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaItemTile extends StatefulWidget {
  const MediaItemTile({
    super.key,
    required this.item,
    required this.source,
    required this.onTap,
    this.onRequestScrubFrames,
    this.onOpenFolder,
    this.onDeleteFile,
    this.fixedHeight,
  });

  final media_api.MediaItem item;
  final String? source;
  final VoidCallback onTap;

  /// 仅本地视频提供：异步返回均匀分布的帧文件路径列表。
  final Future<List<String>> Function()? onRequestScrubFrames;

  /// 在文件管理器中显示该文件（本地）。
  final VoidCallback? onOpenFolder;

  /// 删除该文件（本地）。
  final VoidCallback? onDeleteFile;

  /// 瀑布流模式下由外部指定的固定高度（null = 填满格子）。
  final double? fixedHeight;

  @override
  State<MediaItemTile> createState() => _MediaItemTileState();
}

class _MediaItemTileState extends State<MediaItemTile> {
  bool _hovering = false;
  double _hoverRatio = 0.0;
  List<String>? _scrubFrames;
  bool _loadingFrames = false;

  bool get _isVideo => widget.item.kind == media_api.MediaKind.video;

  /// 视频：优先显示 scrub 帧；悬停时按比例选帧，非悬停时取第 2 帧（≈10s）作为默认封面。
  /// 非视频：直接返回 widget.source。
  String? get _displaySource {
    if (_isVideo) {
      final frames = _scrubFrames;
      if (frames != null && frames.isNotEmpty) {
        if (_hovering) {
          final idx = (_hoverRatio * (frames.length - 1)).round().clamp(0, frames.length - 1);
          return frames[idx];
        }
        // 默认封面：第 2 帧（约 10s 位置），若只有 1 帧则用第 1 帧
        return frames[frames.length > 1 ? 1 : 0];
      }
      return null; // 帧未就绪时显示占位图标，不尝试解码视频文件
    }
    return widget.source;
  }

  Future<void> _loadScrubFrames() async {
    if (_loadingFrames || _scrubFrames != null) return;
    if (widget.onRequestScrubFrames == null) return;
    setState(() => _loadingFrames = true);
    try {
      final frames = await widget.onRequestScrubFrames!();
      if (mounted)
        setState(() {
          _scrubFrames = frames;
          _loadingFrames = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingFrames = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // 视频 tile：立即后台加载帧，提供默认封面（不等待 hover）
    if (_isVideo && widget.onRequestScrubFrames != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadScrubFrames());
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    final overlaySize = overlay.size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        if (widget.onOpenFolder != null)
          const PopupMenuItem<String>(value: 'open_folder', child: Text('打开所在文件夹')),
        if (widget.onDeleteFile != null)
          const PopupMenuItem<String>(value: 'delete', child: Text('删除文件')),
      ],
    );
    if (!mounted) return;
    if (action == 'open_folder') widget.onOpenFolder?.call();
    if (action == 'delete') widget.onDeleteFile?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final src = _displaySource;
    // src 始终是 jpg 帧路径或 null（视频不再传入 .mp4 路径），或图片文件路径
    final showCoverAnyway = src != null && src.isNotEmpty;

    final tile = GestureDetector(
      onTap: widget.onTap,
      onSecondaryTapDown: (widget.onOpenFolder != null || widget.onDeleteFile != null)
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovering = true);
          // hover 时也确保帧已加载（initState 中已触发，此处为兜底）
          if (_isVideo && widget.onRequestScrubFrames != null) _loadScrubFrames();
        },
        onHover: (event) {
          if (!_isVideo || _scrubFrames == null || _scrubFrames!.isEmpty) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final ratio = (event.localPosition.dx / box.size.width).clamp(0.0, 1.0);
          final newIdx = (ratio * (_scrubFrames!.length - 1)).round();
          final curIdx = (_hoverRatio * (_scrubFrames!.length - 1)).round();
          if (newIdx != curIdx) setState(() => _hoverRatio = ratio);
        },
        onExit: (_) => setState(() {
          _hovering = false;
          _hoverRatio = 0.0;
        }),
        child: Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: appMetrics.radius8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surfaceContainerHighest,
                      theme.colorScheme.surfaceContainerLow,
                    ],
                  ),
                ),
                child: showCoverAnyway && src != null
                    ? (src.startsWith('http')
                          ? Image.network(src, fit: BoxFit.cover)
                          : Image.file(File(src), fit: BoxFit.cover))
                    : Center(
                        child: Icon(
                          Icons.smart_display_rounded,
                          size: scaleW(44),
                          color: theme.colorScheme.primary.withAlpha(180),
                        ),
                      ),
              ),
              // 悬停时视频进度条指示器
              if (_hovering && _isVideo && _scrubFrames != null && _scrubFrames!.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: _hoverRatio,
                    minHeight: scaleW(3),
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
              Positioned(
                right: appMetrics.kSpace8,
                top: appMetrics.kSpace8,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: appMetrics.kSpace8,
                    vertical: appMetrics.kSpace4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.item.kind == media_api.MediaKind.image ? '图片' : '视频',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: appMetrics.fontSize10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: (_hovering && _isVideo && _scrubFrames != null && _scrubFrames!.isNotEmpty)
                    ? scaleW(3)
                    : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withAlpha(132)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: appMetrics.kSpace10,
                      vertical: appMetrics.kSpace8,
                    ),
                    child: Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: appMetrics.fontSize12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.fixedHeight != null) {
      return SizedBox(height: widget.fixedHeight, child: tile);
    }
    return tile;
  }
}
