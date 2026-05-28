import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/debug_image_size_badge.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaFolderCard extends StatefulWidget {
  const MediaFolderCard({
    super.key,
    required this.folder,
    required this.coverSource,
    required this.collectionCount,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.isRemote,
    required this.nodeName,
    this.onTransfer,
    this.onPullToLocal,
    this.onDeleteNodeFiles,
    this.isLost = false,
  });

  final media_api.MediaFolder folder;
  final String? coverSource;
  final int collectionCount;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool isRemote;
  final String? nodeName;
  final VoidCallback? onTransfer;
  final VoidCallback? onPullToLocal;
  final VoidCallback? onDeleteNodeFiles;
  final bool isLost;

  @override
  State<MediaFolderCard> createState() => _MediaFolderCardState();
}

class _MediaFolderCardState extends State<MediaFolderCard> {
  bool _hovering = false;

  static const Duration _kAnimDur = Duration(milliseconds: 200);
  static const Curve _kAnimCurve = Curves.easeOut;

  Worker? _privacyWorker;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
    if (prefs != null) {
      _privacyWorker = ever(prefs.privacyMode, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _privacyWorker?.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
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
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名文件夹')),
        if (widget.onTransfer != null)
          const PopupMenuItem<String>(value: 'transfer', child: Text('转移集合到...')),
        if (widget.isRemote && widget.onPullToLocal != null)
          const PopupMenuItem<String>(value: 'pull_to_local', child: Text('拉取到本地')),
        if (widget.isRemote && widget.onDeleteNodeFiles != null)
          const PopupMenuItem<String>(value: 'delete_node_files', child: Text('删除节点本地文件')),
        const PopupMenuItem<String>(value: 'delete', child: Text('删除文件夹')),
        if (PlatformUtil.isMobile)
          const PopupMenuItem<String>(value: 'select', child: Text('进入多选')),
      ],
    );
    if (action == 'rename') {
      widget.onRename();
    } else if (action == 'transfer') {
      widget.onTransfer?.call();
    } else if (action == 'pull_to_local') {
      widget.onPullToLocal?.call();
    } else if (action == 'delete_node_files') {
      widget.onDeleteNodeFiles?.call();
    } else if (action == 'delete') {
      widget.onDelete();
    } else if (action == 'select') {
      widget.onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedCover = widget.coverSource;
    final hasCover = resolvedCover != null && resolvedCover.isNotEmpty;
    final privacyOn = getIt.isRegistered<MediaPrefsService>()
        ? getIt<MediaPrefsService>().privacyMode.value
        : false;
    final blurSigma = getIt.isRegistered<MediaPrefsService>()
        ? getIt<MediaPrefsService>().privacyBlurSigma.value
        : 15.0;
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
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Card(
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
                          theme.colorScheme.primary.withAlpha(44),
                          theme.colorScheme.secondary.withAlpha(26),
                        ],
                      ),
                    ),
                    child: hasCover && widget.isLost
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              const _FolderPlaceholder(),
                              Positioned(
                                left: AppTheme.metrics.kSpace8,
                                top: AppTheme.metrics.kSpace8,
                                child: LostBadge(),
                              ),
                            ],
                          )
                        : hasCover
                        ? (() {
                            final cacheW = resolvedCover.startsWith('http')
                                ? null
                                : () {
                                    final prefs = getIt.isRegistered<MediaPrefsService>()
                                        ? getIt.get<MediaPrefsService>()
                                        : null;
                                    final w = prefs?.localPreviewWidth.value ?? 480;
                                    return w > 0 ? w : null;
                                  }();
                            final image = resolvedCover.startsWith('http')
                                ? Image.network(
                                    resolvedCover,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const _FolderPlaceholder(),
                                  )
                                : Image.file(
                                    File(resolvedCover),
                                    fit: BoxFit.cover,
                                    cacheWidth: cacheW,
                                    errorBuilder: (_, _, _) => const _FolderPlaceholder(),
                                  );
                            if (privacyOn) {
                              return ClipRect(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    image,
                                    BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: blurSigma,
                                        sigmaY: blurSigma,
                                      ),
                                      child: Container(color: Colors.transparent),
                                    ),
                                    Center(
                                      child: Container(
                                        padding: EdgeInsets.all(AppTheme.metrics.kSpace6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(120),
                                          borderRadius: AppTheme.metrics.radius999,
                                        ),
                                        child: Icon(
                                          Icons.lock_outline,
                                          size: AppTheme.metrics.iconSize16,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                image,
                                if (kDebugMode)
                                  Positioned(
                                    right: AppTheme.metrics.kSpace4,
                                    bottom: AppTheme.metrics.kSpace4,
                                    child: DebugImageSizeBadge(src: resolvedCover),
                                  ),
                              ],
                            );
                          }())
                        : Center(
                            child: Icon(
                              Icons.folder_rounded,
                              size: scaleW(54),
                              color: theme.colorScheme.primary.withAlpha(180),
                            ),
                          ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withAlpha(150)],
                    ),
                  ),
                ),
                Positioned(
                  left: appMetrics.kSpace10,
                  top: appMetrics.kSpace10,
                  child: RepaintBoundary(
                    child: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: appMetrics.kSpace8,
                            vertical: appMetrics.kSpace4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(120),
                            borderRadius: AppTheme.metrics.radius999,
                          ),
                          child: Text(
                            '${widget.collectionCount} 个集合',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: appMetrics.fontSize9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.isRemote && widget.nodeName != null)
                  Positioned(
                    right: appMetrics.kSpace10,
                    top: appMetrics.kSpace10,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: appMetrics.kSpace8,
                        vertical: appMetrics.kSpace4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withAlpha(220),
                        borderRadius: AppTheme.metrics.radius999,
                      ),
                      child: Text(
                        widget.nodeName!,
                        style: TextStyle(
                          fontSize: appMetrics.fontSize9,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black.withAlpha(100)),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: appMetrics.kSpace10,
                            vertical: appMetrics.kSpace10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.folder.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: appMetrics.fontSize13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              SizedBox(height: appMetrics.kSpace4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: scaleW(12),
                                    color: Colors.white.withAlpha(180),
                                  ),
                                  SizedBox(width: appMetrics.kSpace4),
                                  Text(
                                    '${widget.collectionCount} 个集合',
                                    style: TextStyle(
                                      color: Colors.white.withAlpha(180),
                                      fontSize: appMetrics.fontSize9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
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
  }
}

class _FolderPlaceholder extends StatelessWidget {
  const _FolderPlaceholder();

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
      child: Center(
        child: Icon(
          Icons.folder_off_outlined,
          size: AppTheme.metrics.iconSize48,
          color: theme.colorScheme.primary.withAlpha(150),
        ),
      ),
    );
  }
}
