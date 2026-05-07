import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaItemTile extends StatefulWidget {
  const MediaItemTile({
    super.key,
    required this.item,
    required this.source,
    required this.onTap,
    this.onRequestScrubFrames,
    this.onRequestAudioCover,
    this.onOpenFolder,
    this.onDeleteFile,
    this.onDeleteNodeLocalFile,
    this.deleteNodeLocalFileLabel,
    this.onSaveToGallery,
    this.fixedHeight,
  });

  final media_api.MediaItem item;
  final String? source;
  final VoidCallback onTap;

  /// 仅本地视频提供：异步返回均匀分布的帧文件路径列表。
  final Future<List<String>> Function()? onRequestScrubFrames;

  /// 仅本地音频提供：异步返回提取出的嵌入专辑封面缩略图路径。
  final Future<String?> Function()? onRequestAudioCover;

  /// 在文件管理器中显示该文件（本地）。
  final VoidCallback? onOpenFolder;

  /// 删除该文件（本地）。
  final VoidCallback? onDeleteFile;

  /// 删除节点本地文件（远程资源）。
  final VoidCallback? onDeleteNodeLocalFile;

  /// 节点本地文件删除按钮的文案，默认为「删除节点本地文件」。
  final String? deleteNodeLocalFileLabel;

  /// 保存图片到相册（移动端）。
  final VoidCallback? onSaveToGallery;

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
  String? _audioCoverPath;
  bool _loadingAudioCover = false;

  static const Duration _kAnimDur = Duration(milliseconds: 200);
  static const Curve _kAnimCurve = Curves.easeOut;

  bool get _isVideo => widget.item.kind == media_api.MediaKind.video;
  bool get _isAudio => widget.item.kind == media_api.MediaKind.audio;

  /// 视频：优先显示 scrub 帧；悬停时按比例选帧，非悬停时取第 2 帧（≈10s）作为默认封面。
  /// 音频：显示已提取的嵌入专辑封面，无封面时返回 null（显示音符图标）。
  /// 非视频/音频：直接返回 widget.source。
  String? get _displaySource {
    if (_isVideo) {
      // 远程视频没有 scrub 帧回调，直接使用预先构建好的封面 URL（mode=cover）
      if (widget.onRequestScrubFrames == null) return widget.source;
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
    if (_isAudio) {
      // 远程音频：直接用预构建 URL；本地音频：用异步提取的封面路径
      if (widget.onRequestAudioCover == null) return widget.source;
      return _audioCoverPath;
    }
    return widget.source;
  }

  Future<void> _loadScrubFrames() async {
    if (_loadingFrames || _scrubFrames != null) return;
    if (widget.onRequestScrubFrames == null) return;
    setState(() => _loadingFrames = true);
    try {
      final frames = await widget.onRequestScrubFrames!();
      if (mounted) {
        setState(() {
          _scrubFrames = frames;
          _loadingFrames = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFrames = false);
    }
  }

  Future<void> _loadAudioCover() async {
    if (_loadingAudioCover || _audioCoverPath != null) return;
    if (widget.onRequestAudioCover == null) return;
    setState(() => _loadingAudioCover = true);
    try {
      final path = await widget.onRequestAudioCover!();
      if (mounted) {
        setState(() {
          _audioCoverPath = path;
          _loadingAudioCover = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAudioCover = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // 视频 tile：立即后台加载帧，提供默认封面（不等待 hover）
    if (_isVideo && widget.onRequestScrubFrames != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadScrubFrames());
    }
    // 音频 tile：立即后台提取嵌入封面
    if (_isAudio && widget.onRequestAudioCover != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAudioCover());
    }
  }

  Future<void> _showContextMenu(BuildContext context, Offset globalPosition) async {
    final hasActions =
        widget.onOpenFolder != null ||
        widget.onDeleteFile != null ||
        widget.onDeleteNodeLocalFile != null ||
        widget.onSaveToGallery != null;
    if (!hasActions) return;
    if (!mounted) return;
    final screenSize = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        screenSize.width - globalPosition.dx,
        screenSize.height - globalPosition.dy,
      ),
      items: [
        if (widget.onOpenFolder != null)
          const PopupMenuItem<String>(value: 'open_folder', child: Text('打开所在文件夹')),
        if (widget.onSaveToGallery != null)
          const PopupMenuItem<String>(value: 'save', child: Text('保存到相册')),
        if (widget.onDeleteFile != null)
          const PopupMenuItem<String>(value: 'delete', child: Text('删除本地文件')),
        if (widget.onDeleteNodeLocalFile != null)
          PopupMenuItem<String>(
            value: 'delete_node_local',
            child: Text(widget.deleteNodeLocalFileLabel ?? '删除节点本地文件'),
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'open_folder') widget.onOpenFolder?.call();
    if (action == 'save') widget.onSaveToGallery?.call();
    if (action == 'delete') widget.onDeleteFile?.call();
    if (action == 'delete_node_local') widget.onDeleteNodeLocalFile?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final src = _displaySource;
    // src 始终是 jpg 帧路径或 null（视频不再传入 .mp4 路径），或图片文件路径
    final showCoverAnyway = src != null && src.isNotEmpty;

    final hasMenuActions =
        widget.onOpenFolder != null ||
        widget.onDeleteFile != null ||
        widget.onDeleteNodeLocalFile != null ||
        widget.onSaveToGallery != null;
    final tile = AnimatedScale(
      scale: _hovering ? 1.03 : 1.0,
      duration: _kAnimDur,
      curve: _kAnimCurve,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: hasMenuActions
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
        onLongPressStart: (PlatformUtil.isMobile && hasMenuActions)
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
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
          onExit: (_) => setState(() {
            _hovering = false;
            _hoverRatio = 0.0;
          }),
          child: Card(
            elevation: _hovering ? 4 : 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: appMetrics.radius8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedScale(
                  scale: _hovering ? 1.05 : 1.0,
                  duration: _kAnimDur,
                  curve: _kAnimCurve,
                  child: DecoratedBox(
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
                    child: showCoverAnyway
                        ? (src.startsWith('http')
                              ? Image.network(
                                  src,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Icon(
                                      _isAudio ? Icons.music_note_rounded : Icons.smart_display_rounded,
                                      size: scaleW(44),
                                      color: theme.colorScheme.primary.withAlpha(180),
                                    ),
                                  ),
                                )
                              : Image.file(
                                  File(src),
                                  fit: BoxFit.cover,
                                  cacheWidth: () {
                                    final w = getIt<MediaPrefsService>().localPreviewWidth.value;
                                    return w > 0 ? w : null;
                                  }(),
                                ))
                        : Center(
                            child: Icon(
                              _isAudio ? Icons.music_note_rounded : Icons.smart_display_rounded,
                              size: scaleW(44),
                              color: theme.colorScheme.primary.withAlpha(180),
                            ),
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
                    horizontal: appMetrics.kSpace16,
                    vertical: appMetrics.kSpace8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(120),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.item.kind == media_api.MediaKind.image
                        ? '图片'
                        : widget.item.kind == media_api.MediaKind.audio
                        ? '音频'
                        : '视频',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: appMetrics.fontSize14,
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
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black.withAlpha(132)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: appMetrics.kSpace16,
                          vertical: appMetrics.kSpace8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                widget.item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: appMetrics.fontSize18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if ((_isAudio || _isVideo) &&
                                widget.item.durationMs != null &&
                                widget.item.durationMs! > BigInt.zero) ...[
                              SizedBox(width: appMetrics.kSpace4),
                              Text(
                                _formatDuration(widget.item.durationMs!),
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: appMetrics.fontSize10,
                                ),
                              ),
                            ],
                          ],
                        ),
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
    );
    if (widget.fixedHeight != null) {
      return SizedBox(height: widget.fixedHeight, child: tile);
    }
    return tile;
  }

  /// 将毫秒格式化为 M:SS 或 H:MM:SS 字符串。
  static String _formatDuration(BigInt ms) {
    final total = (ms.toInt() ~/ 1000).clamp(0, 359999); // max 99:59:59
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
