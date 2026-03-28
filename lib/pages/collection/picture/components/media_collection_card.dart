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
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
  });

  final media_api.MediaCollection collection;
  final String? coverSource;
  final bool isSelected;
  final bool isSelecting;
  final bool isRemote;
  final String? nodeName;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;

  @override
  State<MediaCollectionCard> createState() => _MediaCollectionCardState();
}

class _MediaCollectionCardState extends State<MediaCollectionCard> {
  bool _hovering = false;

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
        PopupMenuItem<String>(value: 'rename', child: Text('重命名集合')),
        PopupMenuItem<String>(value: 'move', child: Text('移动到文件夹')),
        PopupMenuItem<String>(value: 'delete', child: Text('从媒体库移除')),
      ],
    );
    if (!mounted) {
      return;
    }
    if (action == 'rename') {
      widget.onRename();
    } else if (action == 'move') {
      widget.onMove();
    } else if (action == 'delete') {
      widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverSource = widget.coverSource;
    final hasCover = coverSource != null && coverSource.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Card(
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
              Expanded(
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
                      child: hasCover
                          ? (coverSource.startsWith('http')
                                ? Image.network(coverSource, fit: BoxFit.cover)
                                : Image.file(File(coverSource), fit: BoxFit.cover))
                          : Center(
                              child: Icon(
                                Icons.collections_outlined,
                                size: scaleW(48),
                                color: theme.colorScheme.primary.withAlpha(180),
                              ),
                            ),
                    ),
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
                          '${widget.collection.itemCount} 项',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: appMetrics.fontSize10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
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
              Padding(
                padding: EdgeInsets.fromLTRB(
                  appMetrics.kSpace12,
                  appMetrics.kSpace10,
                  appMetrics.kSpace12,
                  appMetrics.kSpace12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.collection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: appMetrics.kSpace8),
                    Text(
                      widget.collection.folderPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
