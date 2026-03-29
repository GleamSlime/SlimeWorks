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
  });

  final media_api.MediaItem item;
  final String? source;
  final VoidCallback onTap;
  /// 仅本地视频提供：异步返回均匀分布的帧文件路径列表。
  final Future<List<String>> Function()? onRequestScrubFrames;

  @override
  State<MediaItemTile> createState() => _MediaItemTileState();
}

class _MediaItemTileState extends State<MediaItemTile> {
  bool _hovering = false;
  double _hoverRatio = 0.0;
  List<String>? _scrubFrames;
  bool _loadingFrames = false;

  bool get _isVideo => widget.item.kind == media_api.MediaKind.video;

  String? get _displaySource {
    if (_hovering && _isVideo && _scrubFrames != null && _scrubFrames!.isNotEmpty) {
      final idx = (_hoverRatio * (_scrubFrames!.length - 1)).round()
          .clamp(0, _scrubFrames!.length - 1);
      return _scrubFrames![idx];
    }
    return widget.source;
  }

  Future<void> _loadScrubFrames() async {
    if (_loadingFrames || _scrubFrames != null) return;
    if (widget.onRequestScrubFrames == null) return;
    setState(() => _loadingFrames = true);
    try {
      final frames = await widget.onRequestScrubFrames!();
      if (mounted) setState(() { _scrubFrames = frames; _loadingFrames = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFrames = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final src = _displaySource;
    final hasCover = src != null && src.isNotEmpty;
    final showCoverAnyway = hasCover && (
      !_isVideo ||
      (_scrubFrames != null && _scrubFrames!.isNotEmpty)
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovering = true);
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
        onExit: (_) => setState(() { _hovering = false; _hoverRatio = 0.0; }),
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
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
  }
}
