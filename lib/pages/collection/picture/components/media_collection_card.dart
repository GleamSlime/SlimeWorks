import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/debug_image_size_badge.dart';
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
    this.onDeleteNodeFiles,
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

  /// 删除节点本地文件回调（仅远程集合时有意义）。
  final VoidCallback? onDeleteNodeFiles;

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

  // ── 移动端滑动预览状态 ──────────────────────────────────────────────────────
  /// 移动端是否处于滑动预览激活状态。
  bool _swipePreviewActive = false;

  /// 滑动预览当前进度 [0,1]，映射到 hoverCoverSources 索引。
  double _swipeFraction = 0.5;

  static const Duration _kAnimDur = Duration(milliseconds: 200);
  static const Curve _kAnimCurve = Curves.easeOut;

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

  /// 根据悬停/滑动位置返回当前应显示的封面路径。
  /// 优先级：实时视频帧 > hoverCoverSources > coverSource。
  String? _activeDisplaySource() {
    final isActive = _hovering || _swipePreviewActive;
    if (!isActive) return widget.coverSource;
    // 实时视频帧优先
    if (_realtimeVideoFrame != null && _realtimeVideoFrame!.isNotEmpty) {
      return _realtimeVideoFrame;
    }
    final sources = widget.hoverCoverSources;
    if (sources == null || sources.isEmpty) return widget.coverSource;
    final fraction = _swipePreviewActive
        ? _swipeFraction
        : (_cardWidth > 0 ? (_hoverLocalX / _cardWidth).clamp(0.0, 1.0) : 0.0);
    final count = sources.length;
    final idx = count == 1 ? 0 : (fraction * (count - 1)).round().clamp(0, count - 1);
    final src = sources[idx];
    if (src != null && src.isNotEmpty) return src;
    // 当前 slot 无封面，向两侧找最近有效帧
    for (int d = 1; d < count; d++) {
      final left = idx - d;
      final right = idx + d;
      if (left >= 0 && sources[left] != null && sources[left]!.isNotEmpty) return sources[left];
      if (right < count && sources[right] != null && sources[right]!.isNotEmpty) {
        return sources[right];
      }
    }
    return widget.coverSource;
  }

  Widget _buildCoverImage(String? src, ThemeData theme) {
    if (src == null || src.isEmpty) {
      return _CollectionPlaceholder(icon: Icons.collections_outlined);
    }
    final cacheW = () {
      if (src.startsWith('http')) return null;
      final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
      final w = prefs?.localPreviewWidth.value ?? 480;
      return w > 0 ? w : null;
    }();
    return Stack(
      fit: StackFit.expand,
      children: [
        src.startsWith('http')
            ? Image.network(
                src,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) =>
                    _CollectionPlaceholder(icon: Icons.broken_image_outlined),
              )
            : Image.file(
                File(src),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: cacheW,
                errorBuilder: (_, __, ___) =>
                    _CollectionPlaceholder(icon: Icons.broken_image_outlined),
              ),
        if (kDebugMode) Positioned(right: 4, bottom: 4, child: DebugImageSizeBadge(src: src)),
      ],
    );
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
        if (!widget.isRemote)
          const PopupMenuItem<String>(value: 'open_folder', child: Text('打开所在文件夹')),
        if (widget.isRemote)
          const PopupMenuItem<String>(value: 'open_folder', child: Text('查看远程路径')),
        PopupMenuItem<String>(value: 'favorite', child: Text(widget.isFavorited ? '取消收藏' : '收藏')),
        const PopupMenuItem<String>(value: 'delete', child: Text('删除集合')),
        if (widget.onDeleteFolder != null)
          const PopupMenuItem<String>(value: 'delete_folder', child: Text('删除文件夹')),
        if (widget.isRemote && widget.onDeleteNodeFiles != null)
          const PopupMenuItem<String>(value: 'delete_node_files', child: Text('删除节点本地文件')),
        if (PlatformUtil.isMobile)
          const PopupMenuItem<String>(value: 'select', child: Text('进入多选')),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      widget.onRename();
    } else if (action == 'move') {
      widget.onMove();
    } else if (action == 'open_folder') {
      widget.onOpenFolder();
    } else if (action == 'favorite') {
      widget.onToggleFavorite();
    } else if (action == 'delete') {
      widget.onDelete();
    } else if (action == 'delete_folder') {
      widget.onDeleteFolder?.call();
    } else if (action == 'delete_node_files') {
      widget.onDeleteNodeFiles?.call();
    } else if (action == 'select') {
      widget.onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displaySource = _activeDisplaySource();

    return AnimatedScale(
      scale: _hovering ? 1.03 : 1.0,
      duration: _kAnimDur,
      curve: _kAnimCurve,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: PlatformUtil.isMobile ? null : widget.onLongPress,
        onLongPressStart: PlatformUtil.isMobile
            ? (details) => _showContextMenu(context, details.globalPosition)
            : null,
        onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
        // ── 移动端水平滑动预览 ──────────────────────────────────────────────
        onHorizontalDragStart:
            PlatformUtil.isMobile && (widget.hoverCoverSources?.isNotEmpty ?? false)
            ? (d) {
                // 触发预取（对应鼠标 onHoverEnter）
                if (!_hoverPreviewActive) {
                  _hoverPreviewActive = true;
                  widget.onHoverEnter?.call();
                }
                setState(() {
                  _swipePreviewActive = true;
                  _swipeFraction = (d.localPosition.dx / _cardWidth).clamp(0.0, 1.0);
                });
              }
            : null,
        onHorizontalDragUpdate:
            PlatformUtil.isMobile && (widget.hoverCoverSources?.isNotEmpty ?? false)
            ? (d) {
                if (!_swipePreviewActive) return;
                setState(() {
                  _swipeFraction = (d.localPosition.dx / _cardWidth).clamp(0.0, 1.0);
                });
              }
            : null,
        onHorizontalDragEnd:
            PlatformUtil.isMobile && (widget.hoverCoverSources?.isNotEmpty ?? false)
            ? (_) {
                setState(() => _swipePreviewActive = false);
              }
            : null,
        onHorizontalDragCancel:
            PlatformUtil.isMobile && (widget.hoverCoverSources?.isNotEmpty ?? false)
            ? () {
                setState(() => _swipePreviewActive = false);
              }
            : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _hovering = true);
            // 3s 后触发预取，避免进入就拉满 CPU
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
            if (_hoverPreviewActive && widget.onRequestVideoFrame != null && _cardWidth > 0) {
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
                elevation: _hovering ? 4 : 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: appMetrics.radius8,
                  side: widget.isSelected
                      ? BorderSide(color: theme.colorScheme.primary, width: scaleW(2))
                      : BorderSide.none,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── 全封面背景图（hover/swipe 时微缩放）────────────────
                    AnimatedScale(
                      scale: (_hovering || _swipePreviewActive) ? 1.05 : 1.0,
                      duration: _kAnimDur,
                      curve: _kAnimCurve,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        child: KeyedSubtree(
                          key: ValueKey(displaySource),
                          child: _buildCoverImage(displaySource, theme),
                        ),
                      ),
                    ),

                    // ── 数量/大小 badge
                    Positioned(
                      left: appMetrics.kSpace8,
                      top: appMetrics.kSpace8,
                      child: AnimatedOpacity(
                        opacity: _hovering ? 1.0 : 0.75,
                        duration: _kAnimDur,
                        curve: _kAnimCurve,
                        child: AnimatedScale(
                          scale: _hovering ? 1.0 : 0.88,
                          duration: _kAnimDur,
                          curve: _kAnimCurve,
                          child: ClipRRect(
                            borderRadius: appMetrics.radius12,
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: appMetrics.kSpace8,
                                  vertical: appMetrics.kSpace4,
                                ),
                                color: _hovering
                                    ? Colors.black.withAlpha(130)
                                    : Colors.black.withAlpha(90),
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
                          ),
                        ),
                      ),
                    ),

                    // ── 远程节点名 badge（右上角）────────────────────────
                    if (widget.isRemote && widget.nodeName != null)
                      Positioned(
                        right: appMetrics.kSpace8,
                        top: appMetrics.kSpace8,
                        child: ClipRRect(
                          borderRadius: appMetrics.radius12,
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: appMetrics.kSpace8,
                                vertical: appMetrics.kSpace4,
                              ),
                              color: theme.colorScheme.primaryContainer.withAlpha(200),
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
                        ),
                      ),

                    // ── 收藏按钮（本地：右上角；远程：左下角避开节点名 badge）
                    Positioned(
                      right: widget.isRemote ? null : appMetrics.kSpace8,
                      left: widget.isRemote ? appMetrics.kSpace8 : null,
                      top: widget.isRemote ? null : appMetrics.kSpace8,
                      bottom: widget.isRemote ? appMetrics.kSpace40 : null,
                      child: AnimatedOpacity(
                        opacity: (_hovering || PlatformUtil.isMobile)
                            ? 1.0
                            : (widget.isFavorited ? 0.9 : 0.0),
                        duration: _kAnimDur,
                        curve: _kAnimCurve,
                        child: AnimatedScale(
                          scale: (_hovering || PlatformUtil.isMobile) ? 1.0 : 0.7,
                          duration: _kAnimDur,
                          curve: _kAnimCurve,
                          child: GestureDetector(
                            onTap: widget.onToggleFavorite,
                            child: ClipRRect(
                              borderRadius: appMetrics.radius12,
                              child: TweenAnimationBuilder<double>(
                                duration: _kAnimDur,
                                curve: _kAnimCurve,
                                tween: Tween(
                                  begin: _hovering ? 8.0 : 0.0,
                                  end: _hovering ? 0.0 : 8.0,
                                ),
                                builder: (_, sigma, child) => BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                                  child: child,
                                ),
                                child: Container(
                                  padding: EdgeInsets.all(appMetrics.kSpace4),
                                  color: _hovering
                                      ? Colors.black.withAlpha(150)
                                      : Colors.transparent,
                                  child: Icon(
                                    widget.isFavorited
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: widget.isFavorited ? Colors.redAccent : Colors.white70,
                                    size: scaleW(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── 悬停预览进度条————————————————————————————
                    if ((_hovering || _swipePreviewActive) &&
                        !widget.isSelecting &&
                        widget.hoverCoverSources != null &&
                        widget.hoverCoverSources!.length > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: _swipePreviewActive
                              ? _swipeFraction
                              : (_cardWidth > 0 ? (_hoverLocalX / _cardWidth).clamp(0.0, 1.0) : 0),
                          minHeight: scaleW(3),
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),

                    // ── 底部磨砂标题栏（hover 时高度扩展）───────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: TweenAnimationBuilder<double>(
                        duration: _kAnimDur,
                        curve: _kAnimCurve,
                        tween: Tween(begin: _hovering ? 4.0 : 3.0, end: _hovering ? 3.0 : 4.0),
                        builder: (_, blurSigma, child) => ClipRRect(
                          borderRadius: BorderRadius.only(
                            bottomLeft: appMetrics.radius8.bottomLeft,
                            bottomRight: appMetrics.radius8.bottomRight,
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                            child: child,
                          ),
                        ),
                        child: AnimatedContainer(
                          duration: _kAnimDur,
                          curve: _kAnimCurve,
                          color: _hovering
                              ? Colors.black.withAlpha(140)
                              : Colors.black.withAlpha(100),
                          padding: EdgeInsets.symmetric(
                            horizontal: appMetrics.kSpace8,
                            vertical: appMetrics.kSpace8,
                          ),
                          child: AnimatedSlide(
                            offset: _hovering ? Offset.zero : const Offset(0, 0.05),
                            duration: _kAnimDur,
                            curve: _kAnimCurve,
                            child: Text(
                              widget.collection.title,
                              maxLines: _hovering ? 5 : 4,
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
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 集合/文件夹封面为空或加载失败时显示的默认占位图标。
class _CollectionPlaceholder extends StatelessWidget {
  const _CollectionPlaceholder({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
      child: Center(child: Icon(icon, size: 48, color: theme.colorScheme.primary.withAlpha(150))),
    );
  }
}
