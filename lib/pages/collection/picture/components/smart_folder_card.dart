import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/debug_image_size_badge.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';

class SmartFolderCard extends StatelessWidget {
  const SmartFolderCard({
    super.key,
    required this.smartFolder,
    required this.matchCount,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.onRename,
    this.onEdit,
    this.onDelete,
    this.coverSource,
    this.onTransfer,
    this.nodeName,
  });

  final SmartFolder smartFolder;
  final int matchCount;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? coverSource;
  final VoidCallback? onTransfer;

  /// 非空表示这是远程节点的智能文件夹，显示节点名 badge。
  final String? nodeName;

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
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
        if (onRename != null) const PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        if (onEdit != null) const PopupMenuItem<String>(value: 'edit', child: Text('编辑智能文件夹')),
        if (onTransfer != null)
          const PopupMenuItem<String>(value: 'transfer', child: Text('转移集合到...')),
        if (onDelete != null) const PopupMenuItem<String>(value: 'delete', child: Text('删除智能文件夹')),
        if (PlatformUtil.isMobile)
          const PopupMenuItem<String>(value: 'select', child: Text('进入多选')),
      ],
    );
    if (action == 'rename') {
      onRename?.call();
    } else if (action == 'edit') {
      onEdit?.call();
    } else if (action == 'transfer') {
      onTransfer?.call();
    } else if (action == 'delete') {
      onDelete?.call();
    } else if (action == 'select') {
      onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            // Background: cover image (if available) or gradient
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.tertiary.withAlpha(55),
                    theme.colorScheme.secondary.withAlpha(30),
                  ],
                ),
              ),
              child: (() {
                final src = coverSource;
                if (src != null && src.isNotEmpty) {
                  final cacheW = src.startsWith('http')
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
                      src.startsWith('http')
                          ? Image.network(
                              src,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const _SmartPlaceholder(),
                            )
                          : Image.file(
                              File(src),
                              fit: BoxFit.cover,
                              cacheWidth: cacheW,
                              errorBuilder: (_, __, ___) => const _SmartPlaceholder(),
                            ),
                      if (kDebugMode)
                        Positioned(right: 4, bottom: 4, child: DebugImageSizeBadge(src: src)),
                    ],
                  );
                }
                return Center(
                  child: Icon(
                    Icons.auto_awesome_outlined,
                    size: scaleW(54),
                    color: theme.colorScheme.tertiary.withAlpha(180),
                  ),
                );
              })(),
            ),
            // Bottom fade
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withAlpha(150)],
                ),
              ),
            ),
            // Match count badge (top-left)
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
                  '$matchCount 个集合',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: appMetrics.fontSize10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            // Smart badge (top-right): "正则" for local, node name for remote
            Positioned(
              right: appMetrics.kSpace10,
              top: appMetrics.kSpace10,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: appMetrics.kSpace8,
                  vertical: appMetrics.kSpace4,
                ),
                decoration: BoxDecoration(
                  color: nodeName != null
                      ? theme.colorScheme.secondaryContainer.withAlpha(220)
                      : theme.colorScheme.tertiaryContainer.withAlpha(220),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  nodeName ?? '正则',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: appMetrics.fontSize10,
                    fontWeight: FontWeight.w600,
                    color: nodeName != null
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ),
            // Title + pattern
            Positioned(
              left: appMetrics.kSpace12,
              right: appMetrics.kSpace12,
              bottom: appMetrics.kSpace12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    smartFolder.name,
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
                    smartFolder.regexPattern.isEmpty ? '全部集合' : smartFolder.regexPattern,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withAlpha(210),
                      fontSize: appMetrics.fontSize12,
                      fontFamily: smartFolder.regexPattern.isEmpty ? null : 'monospace',
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

class _SmartPlaceholder extends StatelessWidget {
  const _SmartPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.tertiary.withAlpha(42),
            theme.colorScheme.primary.withAlpha(28),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome_outlined,
          size: 48,
          color: theme.colorScheme.tertiary.withAlpha(150),
        ),
      ),
    );
  }
}
