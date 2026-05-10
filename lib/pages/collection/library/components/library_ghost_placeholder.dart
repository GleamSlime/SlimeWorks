import 'dart:io';

import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';

/// 拖拽排序时在目标前方显示的半透明"幽灵"占位卡
class GhostPlaceholderCard extends StatefulWidget {
  final LibraryItem item;

  const GhostPlaceholderCard({super.key, required this.item});

  @override
  State<GhostPlaceholderCard> createState() => _GhostPlaceholderCardState();
}

class _GhostPlaceholderCardState extends State<GhostPlaceholderCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.item is LibraryBookItem) {
      final meta = (widget.item as LibraryBookItem).metadata;
      content = Stack(
        fit: StackFit.expand,
        children: [
          meta.coverPath != null && File(meta.coverPath!).existsSync()
              ? Image.file(File(meta.coverPath!), fit: BoxFit.cover)
              : Container(color: Theme.of(context).colorScheme.outline),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.all(scaleW(6)),
              color: Colors.black.withAlpha(100),
              child: Text(
                meta.title,
                style: TextStyle(color: Colors.white, fontSize: appMetrics.fontSize11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      );
    } else {
      final folder = (widget.item as LibraryFolderItem).folder;
      content = Container(
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_rounded, size: scaleW(40), color: Colors.blue.withAlpha(180)),
            SizedBox(height: scaleW(4)),
            Text(folder.name, style: TextStyle(fontSize: appMetrics.fontSize11), maxLines: 1),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _opacity,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: appMetrics.radius8,
          side: BorderSide(color: Theme.of(context).colorScheme.primary, width: scaleW(2)),
        ),
        child: Opacity(opacity: 0.5, child: content),
      ),
    );
  }
}
