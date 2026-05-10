import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_viewer_page.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 媒体集合详情层：显示当前打开集合内的瀑布流媒体网格。
///
/// 通过回调 [onViewerActiveChanged] 通知父页面媒体查看器的打开 / 关闭状态，
/// 以便桌面端的返回按钮能正确重定向到关闭查看器而非退出集合。
class CollectionDetailSection extends StatelessWidget {
  const CollectionDetailSection({
    super.key,
    required this.viewModel,
    required this.columnCount,
    required this.viewerActive,
    required this.onViewerActiveChanged,
  });

  final MediaLibraryViewModel viewModel;
  final int columnCount;

  /// 桌面端媒体查看器当前是否打开。
  final bool viewerActive;

  /// 查看器打开 / 关闭时回调，参数为新状态。
  final void Function(bool active) onViewerActiveChanged;

  @override
  Widget build(BuildContext context) {
    // 内部独立 Obx，让加载/条目变化只引发内部重建，避免外层 AnimatedSwitcher 多次闪烁。
    return Obx(() {
      final isLoading = viewModel.isLoadingItems.value;
      final sortedItems = viewModel.sortedCurrentItems;
      final collectionId = viewModel.currentCollectionId.value ?? '';
      final isRemote = viewModel.isRemoteCollection(collectionId);

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
      if (sortedItems.isEmpty) {
        return Center(
          child: Text('该集合暂无可预览媒体', style: Theme.of(context).textTheme.bodyMedium),
        );
      }

      return Stack(
        children: [
          MasonryMediaGrid(
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
                    scale: Tween<double>(begin: 0.93, end: 1.0).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                    ),
                    child: child,
                  ),
                ),
              );
              if (isMobile) {
                Navigator.of(context, rootNavigator: true).push(route);
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  onViewerActiveChanged(true);
                });
                Navigator.of(context).push(route).whenComplete(() {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onViewerActiveChanged(false);
                  });
                });
              }
            },
            onConfirmDelete: (item) => _confirmDeleteItemFile(context, item),
            onConfirmDeleteNodeLocalFile: isRemote
                ? (item) => _confirmDeleteNodeLocalItemFile(context, item)
                : null,
          ),
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

  Future<void> _confirmDeleteItemFile(
    BuildContext context,
    media_api.MediaItem item,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除文件',
      message: '确定要删除「${item.title}」吗？\n此操作不可恢复，文件将从磁盘永久删除。',
      confirmLabel: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteItemFile(item);
  }

  Future<void> _confirmDeleteNodeLocalItemFile(
    BuildContext context,
    media_api.MediaItem item,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点本地文件',
      message:
          '确定要删除节点上「${item.title}」的本地文件吗？\n'
          '此操作将从节点磁盘永久删除该文件，集合记录保留。',
      confirmLabel: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteRemoteItemLocalFile(item);
  }
}
