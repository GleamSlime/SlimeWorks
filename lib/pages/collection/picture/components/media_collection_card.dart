import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class MediaCollectionCard extends StatefulWidget {
  const MediaCollectionCard({
    super.key,
    required this.collection,
    required this.coverSource,
    required this.isSelected,
    required this.isSelecting,
    required this.isRemote,
    required this.nodeName,
    required this.resourceCount,
    required this.totalSize,
    required this.isFavorited,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onOpenFolder,
    required this.onToggleFavorite,
    this.onSimilarSearch,
    this.onOpenConfigDir,
    this.onDeleteFolder,
    this.onPullToLocal,
    this.onDeleteNodeFiles,
    this.hoverCoverSources,
    this.onHoverEnter,
    this.onRequestVideoFrame,
    this.isLost = false,
    this.displayTitle,
  });

  final media_api.MediaCollection collection;

  /// 同名集合分组内的区分性标题（父级目录名）；为 null 时显示集合原标题。
  final String? displayTitle;
  final String? coverSource;
  final bool isSelected;
  final bool isSelecting;
  final bool isRemote;
  final String? nodeName;

  /// 仍然存在的资源条数（失效资源不计）
  final int resourceCount;

  /// 仍然存在的资源体积
  final BigInt totalSize;
  final bool isFavorited;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onOpenFolder;
  final VoidCallback onToggleFavorite;

  /// 相似查找回调，为 null 时不显示「相似查找」菜单项。
  final VoidCallback? onSimilarSearch;

  /// 打开集合配置目录（.SlimeWorks）回调，为 null 时不显示该菜单项（远程集合无本地目录）。
  final VoidCallback? onOpenConfigDir;

  final VoidCallback? onDeleteFolder;

  /// 拉取集合文件到本地回调（仅远程集合时有意义）。
  final VoidCallback? onPullToLocal;

  /// 删除节点本地文件回调（仅远程集合时有意义）。
  final VoidCallback? onDeleteNodeFiles;

  /// 悬停预览封面列表，可为空或 null。
  final List<String?>? hoverCoverSources;

  /// 悬停进入时回调（如预加载视频帧）。
  final VoidCallback? onHoverEnter;

  /// 悬停时按水平比例 [fraction]∊[0,1] 实时请求视频帧路径。
  /// 返回 null 表示帧未就绪。
  final String? Function(double fraction)? onRequestVideoFrame;

  final bool isLost;

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

  Worker? _privacyWorker;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>()
        ? getIt.get<MediaPrefsService>()
        : null;
    if (prefs != null) {
      _privacyWorker = ever(prefs.privacyMode, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _privacyWorker?.dispose();
    _hoverTimer?.cancel();
    super.dispose();
  }

  /// 根据悬停/滑动位置返回当前应显示的封面路径。
  /// 优先级：实时视频帧 > hoverCoverSources > coverSource。
  String? _activeDisplaySource() {
    final isActive = (_hovering && _hoverPreviewActive) || _swipePreviewActive;
    if (!isActive) return widget.coverSource;
    if (_realtimeVideoFrame != null && _realtimeVideoFrame!.isNotEmpty) {
      return _realtimeVideoFrame;
    }
    final sources = widget.hoverCoverSources;
    if (sources == null || sources.isEmpty) return widget.coverSource;
    final fraction = _swipePreviewActive
        ? _swipeFraction
        : (_cardWidth > 0 ? (_hoverLocalX / _cardWidth).clamp(0.0, 1.0) : 0.0);
    final count = sources.length;
    final idx = count == 1
        ? 0
        : (fraction * (count - 1)).round().clamp(0, count - 1);
    final src = sources[idx];
    if (src != null && src.isNotEmpty) return src;
    for (int d = 1; d < count; d++) {
      final left = idx - d;
      final right = idx + d;
      if (left >= 0 && sources[left] != null && sources[left]!.isNotEmpty) {
        return sources[left];
      }
      if (right < count &&
          sources[right] != null &&
          sources[right]!.isNotEmpty) {
        return sources[right];
      }
    }
    return widget.coverSource;
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    if (!mounted) return;
    // 将全局坐标转为 Overlay 的本地坐标，正确处理侧边栏等布局偏移
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
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
        GlassMenuItem<String>(
          value: 'rename',
          label: '重命名集合',
          icon: StrokeIcons.driveFileRenameOutline,
        ),
        GlassMenuItem<String>(
          value: 'move',
          label: '移动到文件夹',
          icon: StrokeIcons.driveFileMove,
        ),
        if (!widget.isRemote)
          GlassMenuItem<String>(
            value: 'open_folder',
            label: '打开所在文件夹',
            icon: StrokeIcons.folderOpen,
          ),
        if (widget.isRemote)
          GlassMenuItem<String>(
            value: 'open_folder',
            label: '查看远程路径',
            icon: StrokeIcons.link,
          ),
        if (!widget.isRemote && widget.onOpenConfigDir != null)
          GlassMenuItem<String>(
            value: 'open_config_dir',
            label: '打开配置目录',
            icon: StrokeIcons.settingsSuggest,
          ),
        GlassMenuItem<String>(
          value: 'favorite',
          label: widget.isFavorited ? '取消收藏' : '收藏',
          icon: widget.isFavorited
              ? StrokeIcons.favorite
              : StrokeIcons.favoriteBorder,
        ),
        if (widget.onSimilarSearch != null)
          const PopupMenuItem<String>(value: 'similar', child: Text('相似查找')),
        if (widget.isRemote && widget.onPullToLocal != null)
          GlassMenuItem<String>(
            value: 'pull_to_local',
            label: '拉取到本地',
            icon: StrokeIcons.download,
          ),
        if (PlatformUtil.isMobile)
          GlassMenuItem<String>(
            value: 'select',
            label: '进入多选',
            icon: StrokeIcons.checklist,
          ),
        // 三个删除项统一收到最后，中间断一行：这条菜单十项、原来近 500 高，
        // 删除混在普通操作里最容易误点。
        const PopupMenuDivider(),
        GlassMenuItem<String>(
          value: 'delete',
          label: '删除集合',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
        ),
        if (widget.onDeleteFolder != null)
          GlassMenuItem<String>(
            value: 'delete_folder',
            label: '删除文件夹',
            icon: StrokeIcons.deleteSweep,
            destructive: true,
          ),
        if (widget.isRemote && widget.onDeleteNodeFiles != null)
          GlassMenuItem<String>(
            value: 'delete_node_files',
            label: '删除节点本地文件',
            icon: StrokeIcons.cloudOff,
            destructive: true,
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      widget.onRename();
    } else if (action == 'move') {
      widget.onMove();
    } else if (action == 'open_folder') {
      widget.onOpenFolder();
    } else if (action == 'open_config_dir') {
      widget.onOpenConfigDir?.call();
    } else if (action == 'favorite') {
      widget.onToggleFavorite();
    } else if (action == 'similar') {
      widget.onSimilarSearch?.call();
    } else if (action == 'pull_to_local') {
      widget.onPullToLocal?.call();
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
    final s = AppSemantic.of(context);
    final displaySource = _activeDisplaySource();
    final previewing =
        (_hovering && _hoverPreviewActive) || _swipePreviewActive;
    final timelineFraction = _cardWidth > 0
        ? (_swipePreviewActive
                  ? _swipeFraction
                  : _hoverLocalX / _cardWidth)
              .clamp(0.0, 1.0)
        : 0.0;
    // 时间线只在"真的在翻封面序列"时画；多选态下框选会打断它，不如不画
    final showTimeline =
        previewing &&
        !widget.isSelecting &&
        (widget.hoverCoverSources?.length ?? 0) > 1;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: PlatformUtil.isMobile ? null : widget.onLongPress,
      onLongPressStart: PlatformUtil.isMobile
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      // ── 移动端水平滑动预览 ──────────────────────────────────────────────
      onHorizontalDragStart:
          PlatformUtil.isMobile &&
              (widget.hoverCoverSources?.isNotEmpty ?? false)
          ? (d) {
              // 触发预取（对应鼠标 onHoverEnter）
              if (!_hoverPreviewActive) {
                _hoverPreviewActive = true;
                widget.onHoverEnter?.call();
              }
              setState(() {
                _swipePreviewActive = true;
                _swipeFraction = (d.localPosition.dx / _cardWidth).clamp(
                  0.0,
                  1.0,
                );
              });
            }
          : null,
      onHorizontalDragUpdate:
          PlatformUtil.isMobile &&
              (widget.hoverCoverSources?.isNotEmpty ?? false)
          ? (d) {
              if (!_swipePreviewActive) return;
              setState(() {
                _swipeFraction = (d.localPosition.dx / _cardWidth).clamp(
                  0.0,
                  1.0,
                );
              });
            }
          : null,
      onHorizontalDragEnd:
          PlatformUtil.isMobile &&
              (widget.hoverCoverSources?.isNotEmpty ?? false)
          ? (_) {
              setState(() => _swipePreviewActive = false);
            }
          : null,
      onHorizontalDragCancel:
          PlatformUtil.isMobile &&
              (widget.hoverCoverSources?.isNotEmpty ?? false)
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
          if (_hoverPreviewActive &&
              widget.onRequestVideoFrame != null &&
              _cardWidth > 0) {
            final fraction = (e.localPosition.dx / _cardWidth).clamp(
              0.0,
              1.0,
            );
            final frame = widget.onRequestVideoFrame!(fraction);
            if (frame != null && frame != _realtimeVideoFrame) {
              setState(() => _realtimeVideoFrame = frame);
            }
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            _cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
            return MediaCutoutCard(
              selected: widget.isSelected,
              hovered: _hovering || _swipePreviewActive,
              label: '集合',
              // 主读数走右上标签：条数是这一格最该被扫见的数
              tagLabel: '${widget.resourceCount} 项',
              tagIcon: StrokeIcons.photoLibrary,
              // 同名分组内的集合卡显示父级目录名（xxx/1/哈哈哈 → 1），组内才分得清来源
              title: widget.displayTitle ?? widget.collection.title,
              // 目录整条留给正文：以前它哪都没露，恰恰是找文件时最想要的
              body: widget.collection.folderPath,
              footIcon: widget.isRemote ? StrokeIcons.cloud : StrokeIcons.computer,
              footName: widget.isRemote ? (widget.nodeName ?? '远程节点') : '本机',
              footReadout: formatFileSize(widget.totalSize),
              trailingIcon: widget.isFavorited
                  ? StrokeIcons.favorite
                  : StrokeIcons.favoriteBorder,
              trailingOnTap: widget.onToggleFavorite,
              // 已收藏的要一直看得见，不能只在悬停时露一下
              trailingAtRest: widget.isFavorited,
              media: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                // 悬停翻封面时按图源换页，不做淡入淡出会变成硬切闪屏
                child: MediaCardCover(
                  key: ValueKey('${widget.collection.id}_$displaySource'),
                  source: displaySource,
                  placeholderIcon: StrokeIcons.collections,
                  lostIcon: StrokeIcons.brokenImage,
                  isLost: widget.isLost,
                ),
              ),
              mediaOverlay: (widget.isLost || showTimeline)
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (widget.isLost)
                          Positioned(
                            left: appMetrics.kSpace8,
                            top: appMetrics.kSpace8,
                            child: const LostBadge(),
                          ),
                        if (showTimeline)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: timelineFraction,
                              minHeight: scaleW(3),
                              backgroundColor: s.surface,
                              valueColor: AlwaysStoppedAnimation<Color>(s.accent),
                            ),
                          ),
                      ],
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}
