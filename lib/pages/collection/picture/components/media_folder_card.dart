import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/debug_image_size_badge.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaFolderCard extends StatelessWidget {
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
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名文件夹')),
        if (onTransfer != null)
          const PopupMenuItem<String>(value: 'transfer', child: Text('转移集合到...')),
        const PopupMenuItem<String>(value: 'delete', child: Text('删除文件夹')),
        if (PlatformUtil.isMobile)
          const PopupMenuItem<String>(value: 'select', child: Text('进入多选')),
      ],
    );
    if (action == 'rename') {
      onRename();
    } else if (action == 'transfer') {
      onTransfer?.call();
    } else if (action == 'delete') {
      onDelete();
    } else if (action == 'select') {
      onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedCover = coverSource;
    final hasCover = resolvedCover != null && resolvedCover.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      onLongPress: PlatformUtil.isMobile ? null : onLongPress,
      onLongPressStart: PlatformUtil.isMobile
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: appMetrics.radius8,
          side: isSelected
              ? BorderSide(color: theme.colorScheme.primary, width: scaleW(2))
              : BorderSide.none,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
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
              child: hasCover
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
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          resolvedCover.startsWith('http')
                              ? Image.network(resolvedCover, fit: BoxFit.cover)
                              : Image.file(
                                  File(resolvedCover),
                                  fit: BoxFit.cover,
                                  cacheWidth: cacheW,
                                ),
                          if (kDebugMode)
                            Positioned(
                              right: 4,
                              bottom: 4,
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
                  '$collectionCount 个集合',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: appMetrics.fontSize10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (isRemote && nodeName != null)
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
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    nodeName!,
                    style: TextStyle(
                      fontSize: appMetrics.fontSize10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: appMetrics.kSpace12,
              right: appMetrics.kSpace12,
              bottom: appMetrics.kSpace12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: appMetrics.fontSize16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: appMetrics.kSpace4),
                  Text(
                    '点击进入文件夹',
                    style: TextStyle(
                      color: Colors.white.withAlpha(210),
                      fontSize: appMetrics.fontSize12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
