import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/pages/collection/picture/components/media_viewer_page.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 媒体集合详情视图（集合内的媒体列表）
///
/// 负责展示集合内的 [MediaItem] 瀑布流，以及打开 [MediaViewerPage] 预览。
class MediaCollectionDetailView extends StatelessWidget {
  final MediaLibraryViewModel viewModel;

  /// 瀑布流列数
  final int columnCount;

  /// 确认删除条目（本地集合）
  final Future<void> Function(media_api.MediaItem item) onConfirmDelete;

  /// 确认删除节点本地文件（远程集合）；null 表示当前集合不支持
  final Future<void> Function(media_api.MediaItem item)? onConfirmDeleteNodeLocalFile;

  /// 查看器打开/关闭时回调（桌面端用于重定向操作栏返回按钮）
  final void Function(bool isActive)? onViewerStateChanged;

  const MediaCollectionDetailView({
    super.key,
    required this.viewModel,
    required this.columnCount,
    required this.onConfirmDelete,
    this.onConfirmDeleteNodeLocalFile,
    this.onViewerStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 独立 Obx：加载 / 条目变化时仅内部重建，不触发外层 AnimatedSwitcher 闪烁
    return Obx(() {
      final isLoading = viewModel.isLoadingItems.value;
      final sortedItems = viewModel.sortedCurrentItems;
      final collectionId = viewModel.currentCollectionId.value ?? '';
      final isRemote = viewModel.isRemoteCollection(collectionId);

      // ── 加载中且无数据 ────────────────────────────────────────────────────
      if (sortedItems.isEmpty && isLoading) {
        if (isRemote) {
          final progress = viewModel.itemLoadProgress.value;
          final percent = progress != null ? '${(progress * 100).toInt()}%' : null;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(value: progress, strokeWidth: 5),
                      if (percent != null)
                        Text(percent, style: Theme.of(context).textTheme.labelMedium),
                    ],
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace12),
                Text('正在加载远程资源…', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      }

      // ── 空集合 ────────────────────────────────────────────────────────────
      if (sortedItems.isEmpty) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Center(
          child: Container(
            padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
            margin: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace24),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.background2 : LightColors.background1,
              borderRadius: AppTheme.metrics.radius16,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: scaleW(72),
                  height: scaleW(72),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: AppTheme.metrics.radius16,
                  ),
                  child: Icon(
                    Icons.collections_outlined,
                    size: scaleW(36),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace20),
                Text(
                  '该集合暂无可预览媒体',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                Text(
                  '导入文件后即可在此浏览',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // ── 瀑布流/网格布局切换 ───────────────────────────────────────────────────
      final useMasonry = viewModel.useMasonryGrid.value;
      final gridWidget = useMasonry
          ? MasonryMediaGrid(
              key: ValueKey('masonry_$collectionId'),
              items: sortedItems,
              collectionId: collectionId,
              isRemote: isRemote,
              viewModel: viewModel,
              columnCount: columnCount,
              lastViewedItemId: viewModel.lastViewedItemId.value,
              onOpenViewer: (index) {
                if (collectionId.isEmpty) return;
                if (index >= 0 && index < sortedItems.length) {
                  viewModel.lastViewedItemId.value = sortedItems[index].id;
                }
                final isMobile = Platform.isAndroid || Platform.isIOS;
                final route = PageRouteBuilder<void>(
                  opaque: true,
                  barrierColor: Colors.black,
                  pageBuilder: (_, _, _) => MediaViewerPage(
                    items: sortedItems,
                    initialIndex: index,
                    collectionId: collectionId,
                    viewModel: viewModel,
                  ),
                  transitionDuration: const Duration(milliseconds: 280),
                  reverseTransitionDuration: const Duration(milliseconds: 240),
                  transitionsBuilder: (_, animation, _, child) => FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.93,
                        end: 1.0,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  ),
                );
                if (isMobile) {
                  Navigator.of(context, rootNavigator: true).push(route);
                } else {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onViewerStateChanged?.call(true);
                  });
                  Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      onViewerStateChanged?.call(false);
                    });
                  });
                }
              },
              onConfirmDelete: onConfirmDelete,
              onConfirmDeleteNodeLocalFile: isRemote ? onConfirmDeleteNodeLocalFile : null,
            )
          : GridView.builder(
              key: ValueKey('grid_$collectionId'),
              padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                mainAxisSpacing: AppTheme.metrics.kSpace12,
                crossAxisSpacing: AppTheme.metrics.kSpace12,
                childAspectRatio: 0.75,
              ),
              itemCount: sortedItems.length,
              itemBuilder: (context, index) {
                final item = sortedItems[index];
                final source = viewModel.buildMediaSource(item, isCover: true);
                final fullSource = viewModel.buildMediaSource(item);
                return MediaItemTile(
                  key: ValueKey(item.id),
                  item: item,
                  source: source,
                  coverFallbackSource: viewModel.buildRemoteOriginalMediaSource(
                    item,
                    collectionId: collectionId,
                  ),
                  showOverlay: viewModel.showMediaOverlay.value,
                  isLost: viewModel.checkItemLost(item),
                  onSaveToGallery: (PlatformUtil.isMobile && item.kind == media_api.MediaKind.image)
                      ? () => MasonryMediaGridState.saveToGallery(context, fullSource)
                      : null,
                  onTap: () {
                    if (collectionId.isEmpty) return;
                    viewModel.lastViewedItemId.value = item.id;
                    final isMobile = Platform.isAndroid || Platform.isIOS;
                    final route = PageRouteBuilder<void>(
                      opaque: true,
                      barrierColor: Colors.black,
                      pageBuilder: (_, _, _) => MediaViewerPage(
                        items: sortedItems,
                        initialIndex: index,
                        collectionId: collectionId,
                        viewModel: viewModel,
                      ),
                      transitionDuration: const Duration(milliseconds: 280),
                      reverseTransitionDuration: const Duration(milliseconds: 240),
                      transitionsBuilder: (_, animation, _, child) => FadeTransition(
                        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.93,
                            end: 1.0,
                          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                          child: child,
                        ),
                      ),
                    );
                    if (isMobile) {
                      Navigator.of(context, rootNavigator: true).push(route);
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        onViewerStateChanged?.call(true);
                      });
                      Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onViewerStateChanged?.call(false);
                        });
                      });
                    }
                  },
                  onDeleteFile: isRemote ? null : () => onConfirmDelete(item),
                  onDeleteNodeLocalFile: isRemote
                      ? () => onConfirmDeleteNodeLocalFile?.call(item)
                      : null,
                );
              },
            );

      // ── 瀑布流 + 进度条 ───────────────────────────────────────────────────
      return Stack(
        children: [
          gridWidget,
          // 有数据但仍在加载更多时，顶部细进度条
          if (isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    });
  }
}
