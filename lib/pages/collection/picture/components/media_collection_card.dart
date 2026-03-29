import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaCollectionCard extends StatefulWidget {
  const MediaCollectionCard({
    super.key,
    required this.collection,
    required this.coverSource,
    required this.isSelected,
    required this.isSelecting,
    required this.isRemote,
    required this.nodeName,
    required this.totalSize,
    required this.isFavorited,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onOpenFolder,
    required this.onToggleFavorite,
    this.onDeleteFolder,
    this.hoverCoverSources,
    this.onHoverEnter,
    this.onRequestVideoFrame,
  });

  final media_api.MediaCollection collection;
  final String? coverSource;
  final bool isSelected;
  final bool isSelecting;
  final bool isRemote;
  final String? nodeName;
  final BigInt totalSize;
  final bool isFavorited;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onOpenFolder;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onDeleteFolder;

  /// 悬停预览封面列表，可为空或 null。
  final List<String?>? hoverCoverSources;

  /// 悬停进入时回调（如预加载视频帧）。
  final VoidCallback? onHoverEnter;

  /// 悬停时按水平比例 [fraction]∊[0,1] 实时请求视频帧路径。
  /// 返回 null 表示帧未就绪。
  final String? Function(double fraction)? onRequestVideoFrame;

  @override
  State<MediaCollectionCard> createState() => _MediaCollectionCardState();
}

class _MediaCollectionCardState extends State<MediaCollectionCard> {
  bool _hovering = false;
  double _hoverLocalX = 0;
  double _cardWidth = 1;
  /// 实时视频帧（优先级最高）。
  String? _realtimeVideoFrame;
  /// 悬停进入 3s 后才触发预取的计时器。
  Timer? _hoverTimer;
  /// 3s 阈值是否已达到（预取已触发）。
  bool _hoverPreviewActive = false;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  static String _formatBytes(BigInt bytes) {
    final d = bytes.toDouble();
    if (d < 1024) return '${d.toStringAsFixed(0)} B';
    if (d < 1024 * 1024) return '${(d / 1024).toStringAsFixed(1)} KB';
    if (d < 1024 * 1024 * 1024) return '${(d / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(d / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 根据悬停位置返回当前应显示的封面路径。
  /// 优先级：实时视频帧 > hoverCoverSources > coverSource。
  String? _activeDisplaySource() {
    if (!_hovering) return widget.coverSource;
    // 实时视频帧优先
    if (_realtimeVideoFrame != null && _realtimeVideoFrame!.isNotEmpty) {
      return _realtimeVideoFrame;
    }
    final sources = widget.hoverCoverSources;
    if (sources == null || sources.isEmpty) return widget.coverSource;
    final fraction = _cardWidth > 0 ? (_hoverLocalX / _cardWidth).clamp(0.0, 1.0) : 0.0;
    final count = sources.length;
    // count==1 时 index 恒为 0；index 随 fraction 线性增大
    final idx = count == 1 ? 0 : (fraction * (count - 1)).round().clamp(0, count - 1);
    final src = sources[idx];
    if (src != null && src.isNotEmpty) return src;
    // 当前 slot 为视频且尚无封面，向两侧找最近有效帧
    for (int d = 1; d < count; d++) {
      final left = idx - d;
      final right = idx + d;
      if (left >= 0 && sources[left] != null && sources[left]!.isNotEmpty) return sources[left];
      if (right < count && sources[right] != null && sources[right]!.isNotEmpty) return sources[right];
    }
    return widget.coverSource;
  }

  Widget _buildCoverContent(String? src, ThemeData theme) {
    if (src == null || src.isEmpty) {
      return Center(
        child: Icon(
          Icons.collections_outlined,
          size: scaleW(48),
          color: theme.colorScheme.primary.withAlpha(180),
        ),
      );
    }
    return src.startsWith('http')
        ? Image.network(src, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
        : Image.file(File(src), fit: BoxFit.cover, width: double.infinity, height: double.infinity);
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(globalPosition);
    final overlaySize = overlay.size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPosition.dx, localPosition.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名集合')),
        const PopupMenuItem<String>(value: 'move', child: Text('移动到文件夹')),
        const PopupMenuItem<String>(value: 'open_folder', child: Text('打开所在文件夹')),
        PopupMenuItem<String>(value: 'favorite', child: Text(widget.isFavorited ? '取消收藏' : '收藏')),
        const PopupMenuItem<String>(value: 'delete', child: Text('删除集合')),
        if (widget.onDeleteFolder != null)
          const PopupMenuItem<String>(value: 'delete_folder', child: Text('删除文件夹')),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') widget.onRename();
    else if (action == 'move') widget.onMove();
    else if (action == 'open_folder') widget.onOpenFolder();
    else if (action == 'favorite') widget.onToggleFavorite();
    else if (action == 'delete') widget.onDelete();
    else if (action == 'delete_folder') widget.onDeleteFolder?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displaySource = _activeDisplaySource();

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
            onEnter: (_) {
              setState(() => _hovering = true);
              // 3s 后触发预取：届时才调用 onHoverEnter（避免一进来就拉满 CPU）
              _hoverTimer?.cancel();
              _hoverPreviewActive = false;
              _hoverTimer = Timer(const Duration(seconds: 3), () {
                if (!mounted) return;
                setState(() => _hoverPreviewActive = true);
                widget.onHoverEnter?.call();
              });
            },
            onExit: (_) {
              _hoverTimer?.cancel();
              _hoverTimer = null;
              setState(() {
                _hovering = false;
                _hoverLocalX = 0;
                _realtimeVideoFrame = null;
                _hoverPreviewActive = false;
              });
            },
            onHover: (e) {
              setState(() => _hoverLocalX = e.localPosition.dx);
              // 实时视频帧取样（仅在 3s 阈值达到后才请求）
              if (_hoverPreviewActive &&
                  widget.onRequestVideoFrame != null &&
                  _cardWidth > 0) {
                final fraction = (e.localPosition.dx / _cardWidth).clamp(0.0, 1.0);
                final frame = widget.onRequestVideoFrame!(fraction);
                if (frame != null && frame != _realtimeVideoFrame) {
                  setState(() => _realtimeVideoFrame = frame);
                }
              }
            },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
            return Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: appMetrics.radius8,
                side: widget.isSelected
                    ? BorderSide(color: theme.colorScheme.primary, width: scaleW(2))
                    : BorderSide.none,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 封面区域（固定 4:3 比例） ─────────────────────────────
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primary.withAlpha(42),
                                theme.colorScheme.secondary.withAlpha(28),
                              ],
                            ),
                          ),
                          child: ClipRect(
                            child: AnimatedScale(
                              scale: _hovering ? 1.05 : 1.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 120),
                                // 以 widget.coverSource 作为动画切换 key，而不是 displaySource
                                // 避免悬停预览帧切换时产生重复 Key 异常
                                child: KeyedSubtree(
                                  key: ValueKey(widget.coverSource),
                                  child: _buildCoverContent(displaySource, theme),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 数量/大小 badge
                        Positioned(
                          left: appMetrics.kSpace8,
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
                              '${widget.collection.itemCount} 项 · ${_formatBytes(widget.totalSize)}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: appMetrics.fontSize10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // 远程节点名
                        if (widget.isRemote && widget.nodeName != null)
                          Positioned(
                            right: appMetrics.kSpace8,
                            top: appMetrics.kSpace8,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: appMetrics.kSpace8,
                                vertical: appMetrics.kSpace4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withAlpha(220),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.nodeName!,
                                style: TextStyle(
                                  fontSize: appMetrics.fontSize10,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        // 收藏按钮
                        if (!widget.isRemote)
                          Positioned(
                            right: appMetrics.kSpace4,
                            top: appMetrics.kSpace4,
                            child: GestureDetector(
                              onTap: widget.onToggleFavorite,
                              child: Container(
                                padding: EdgeInsets.all(appMetrics.kSpace4),
                                decoration: const BoxDecoration(
                                  color: Colors.black38,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.isFavorited
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: widget.isFavorited ? Colors.redAccent : Colors.white70,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        // 悬停时显示进度条
                        if (_hovering &&
                            !widget.isSelecting &&
                            widget.hoverCoverSources != null &&
                            widget.hoverCoverSources!.length > 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: _cardWidth > 0 ? (_hoverLocalX / _cardWidth).clamp(0.0, 1.0) : 0,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          ),
                        // 展开图标
                        if (_hovering && !widget.isSelecting)
                          Positioned(
                            right: appMetrics.kSpace8,
                            bottom: appMetrics.kSpace8,
                            child: Container(
                              padding: EdgeInsets.all(appMetrics.kSpace8),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(96),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.open_in_full, color: Colors.white, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── 标题区域 ─────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      appMetrics.kSpace12,
                      appMetrics.kSpace8,
                      appMetrics.kSpace12,
                      appMetrics.kSpace8,
                    ),
                    child: Text(
                      widget.collection.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}


