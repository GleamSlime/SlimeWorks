import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
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
    this.showOverlay = true,
    this.isLost = false,
    this.coverFallbackSource,
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

  /// 远程图片兜底原图 URL：缩略图 2s 未返回时临时改用原图充当封面。
  final String? coverFallbackSource;

  /// 是否显示叠加层（类型标签 + 标题栏）。
  final bool showOverlay;

  final bool isLost;

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

  Worker? _privacyWorker;

  // ── 远程缩略图 2s 超时兜底状态 ─────────────────────────────────────────
  // 缩略图请求后台继续生成；超时后临时切原图，生成完成再切回缩略图。
  bool _coverFallbackActive = false;
  bool _coverThumbReady = false;
  Timer? _coverFallbackTimer;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
    if (prefs != null) {
      _privacyWorker = ever(prefs.privacyMode, (_) {
        if (mounted) setState(() {});
      });
    }
    // 视频 tile：立即后台加载帧，提供默认封面（不等待 hover）
    if (_isVideo && widget.onRequestScrubFrames != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadScrubFrames());
    }
    // 音频 tile：立即后台提取嵌入封面
    if (_isAudio && widget.onRequestAudioCover != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAudioCover());
    }
    // 远程图片：预取缩略图并启动 2s 兜底计时
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCoverFallback());
  }

  @override
  void didUpdateWidget(MediaItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.coverFallbackSource != widget.coverFallbackSource) {
      _coverFallbackActive = false;
      _coverThumbReady = false;
      _coverFallbackTimer?.cancel();
      _coverFallbackTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCoverFallback());
    }
  }

  @override
  void dispose() {
    _coverFallbackTimer?.cancel();
    _privacyWorker?.dispose();
    super.dispose();
  }

  /// 远程缩略图可用兜底时：预取缩略图 + 启动超时计时。
  void _prepareCoverFallback() {
    if (!mounted) return;
    final src = widget.source;
    final fallback = widget.coverFallbackSource;
    // 仅远程缩略图 URL 且提供了不同于缩略图的原图 URL 时启用
    if (src == null || !src.startsWith('http') || fallback == null || fallback == src) {
      return;
    }
    _coverThumbReady = false;
    // 后台预取缩略图（不阻塞 UI），完成后切回缩略图
    precacheImage(NetworkImage(src), context)
        .then((_) {
          _coverFallbackTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _coverThumbReady = true;
            _coverFallbackActive = false;
          });
        })
        .catchError((_) {
          // 缩略图生成失败：直接改用原图兜底
          _coverFallbackTimer?.cancel();
          if (!mounted) return;
          setState(() => _coverFallbackActive = true);
        });
    // 2s 未就绪则临时采用原图
    _coverFallbackTimer?.cancel();
    _coverFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _coverThumbReady) return;
      setState(() => _coverFallbackActive = true);
    });
  }

  /// 计算实际展示的图片源：远程缩略图超时未返回时临时使用原图。
  String? _coverEffectiveSrc(String? src) {
    if (src == null || !src.startsWith('http')) return src;
    if (_coverThumbReady) return src;
    if (_coverFallbackActive) return widget.coverFallbackSource ?? src;
    return src;
  }

  bool get _isVideo => widget.item.kind == media_api.MediaKind.video;
  bool get _isAudio => widget.item.kind == media_api.MediaKind.audio;

  String? get _displaySource {
    if (_isVideo) {
      if (widget.onRequestScrubFrames == null) return widget.source;
      final frames = _scrubFrames;
      if (frames != null && frames.isNotEmpty) {
        if (_hovering) {
          final idx = (_hoverRatio * (frames.length - 1)).round().clamp(0, frames.length - 1);
          return frames[idx];
        }
        return frames[frames.length > 1 ? 1 : 0];
      }
      return null;
    }
    if (_isAudio) {
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

  Future<void> _showContextMenu(BuildContext context, Offset globalPosition) async {
    final hasActions =
        widget.onOpenFolder != null ||
        widget.onDeleteFile != null ||
        widget.onDeleteNodeLocalFile != null ||
        widget.onSaveToGallery != null;
    if (!hasActions) return;
    if (!mounted) return;
    // 将全局坐标换算为 Overlay 本地坐标，保证菜单在光标位置弹出（与 MediaCollectionCard 一致）
    final overlayBox = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final localPos = overlayBox.globalToLocal(globalPosition);
    final overlaySize = overlayBox.size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx,
        localPos.dy,
        overlaySize.width - localPos.dx,
        overlaySize.height - localPos.dy,
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
    final src = _coverEffectiveSrc(_displaySource);
    final showCoverAnyway = src != null && src.isNotEmpty && !widget.isLost;
    final privacyOn = getIt<MediaPrefsService>().privacyMode.value;
    final blurSigma = getIt<MediaPrefsService>().privacyBlurSigma.value;

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
                        ? (privacyOn
                              ? ClipRRect(
                                  borderRadius: BorderRadius.zero,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      src.startsWith('http')
                                          ? Image.network(src, fit: BoxFit.cover)
                                          : Image.file(
                                              File(src),
                                              fit: BoxFit.cover,
                                              cacheWidth: () {
                                                final w = getIt<MediaPrefsService>()
                                                    .localPreviewWidth
                                                    .value;
                                                return w > 0 ? w : null;
                                              }(),
                                            ),
                                      BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: blurSigma,
                                          sigmaY: blurSigma,
                                        ),
                                        child: Container(color: Colors.transparent),
                                      ),
                                      Center(
                                        child: Container(
                                          padding: EdgeInsets.all(appMetrics.kSpace6),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(120),
                                            borderRadius: AppTheme.metrics.radius999,
                                          ),
                                          child: Icon(
                                            Icons.lock_outline,
                                            size: appMetrics.iconSize16,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : src.startsWith('http')
                              ? Image.network(
                                  src,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Icon(
                                      _isAudio
                                          ? Icons.music_note_rounded
                                          : Icons.smart_display_rounded,
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
                if (widget.isLost)
                  Positioned.fill(
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
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: scaleW(44),
                              color: theme.colorScheme.primary.withAlpha(180),
                            ),
                          ),
                        ),
                        Positioned(
                          left: appMetrics.kSpace8,
                          top: appMetrics.kSpace8,
                          child: const LostBadge(),
                        ),
                      ],
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
                if (widget.showOverlay)
                  Positioned(
                    right: appMetrics.kSpace8,
                    top: appMetrics.kSpace8,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? appMetrics.kSpace6 : appMetrics.kSpace10,
                        vertical: isMobile ? appMetrics.kSpace3 : appMetrics.kSpace5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.item.kind == media_api.MediaKind.image
                                ? Icons.image_outlined
                                : widget.item.kind == media_api.MediaKind.audio
                                ? Icons.music_note_rounded
                                : Icons.play_circle_outline_rounded,
                            size: scaleW(10),
                            color: Colors.white.withAlpha(200),
                          ),
                          SizedBox(width: appMetrics.kSpace3),
                          Text(
                            widget.item.kind == media_api.MediaKind.image
                                ? '图片'
                                : widget.item.kind == media_api.MediaKind.audio
                                ? '音频'
                                : '视频',
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: appMetrics.fontSize9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.showOverlay)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom:
                        (_hovering && _isVideo && _scrubFrames != null && _scrubFrames!.isNotEmpty)
                        ? scaleW(3)
                        : 0,
                    child: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black.withAlpha(100)),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? appMetrics.kSpace8 : appMetrics.kSpace12,
                              vertical: isMobile ? appMetrics.kSpace4 : appMetrics.kSpace8,
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
                                      fontSize: isMobile
                                          ? appMetrics.fontSize9
                                          : appMetrics.fontSize12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
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
                                      fontSize: appMetrics.fontSize9,
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
