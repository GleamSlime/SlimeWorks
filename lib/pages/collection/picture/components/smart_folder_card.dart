import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';

class SmartFolderCard extends StatelessWidget {
  const SmartFolderCard({
    super.key,
    required this.smartFolder,
    required this.matchCount,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onEdit,
    required this.onDelete,
    this.coverSource,
  });

  final SmartFolder smartFolder;
  final int matchCount;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? coverSource;

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
      items: const [
        PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
        PopupMenuItem<String>(value: 'edit', child: Text('编辑智能文件夹')),
        PopupMenuItem<String>(value: 'delete', child: Text('删除智能文件夹')),
      ],
    );
    if (action == 'rename') {
      onRename();
    } else if (action == 'edit') {
      onEdit();
    } else if (action == 'delete') {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  return src.startsWith('http')
                      ? Image.network(src, fit: BoxFit.cover)
                      : Image.file(File(src), fit: BoxFit.cover);
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
            // Smart badge (top-right)
            Positioned(
              right: appMetrics.kSpace10,
              top: appMetrics.kSpace10,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: appMetrics.kSpace8,
                  vertical: appMetrics.kSpace4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withAlpha(220),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '正则',
                  style: TextStyle(
                    fontSize: appMetrics.fontSize10,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onTertiaryContainer,
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
                    smartFolder.regexPattern.isEmpty
                        ? '全部集合'
                        : smartFolder.regexPattern,
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
