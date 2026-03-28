import 'dart:io';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

class MediaItemTile extends StatelessWidget {
  const MediaItemTile({super.key, required this.item, required this.source, required this.onTap});

  final media_api.MediaItem item;
  final String? source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedSource = source;
    final hasPreview =
        item.kind == media_api.MediaKind.image &&
        resolvedSource != null &&
        resolvedSource.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: appMetrics.radius8),
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
              child: hasPreview
                  ? (resolvedSource.startsWith('http')
                        ? Image.network(resolvedSource, fit: BoxFit.cover)
                        : Image.file(File(resolvedSource), fit: BoxFit.cover))
                  : Center(
                      child: Icon(
                        Icons.smart_display_rounded,
                        size: scaleW(44),
                        color: theme.colorScheme.primary.withAlpha(180),
                      ),
                    ),
            ),
            Positioned(
              right: appMetrics.kSpace8,
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
                  item.kind == media_api.MediaKind.image ? '图片' : '视频',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: appMetrics.fontSize10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withAlpha(132)),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: appMetrics.kSpace10,
                    vertical: appMetrics.kSpace8,
                  ),
                  child: Text(
                    item.title,
                    maxLines: 2,
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
          ],
        ),
      ),
    );
  }
}
