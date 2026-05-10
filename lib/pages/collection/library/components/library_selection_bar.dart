import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 多选状态时显示在底部的操作栏
class LibrarySelectionBar extends StatelessWidget {
  final NovelLibraryViewModel viewModel;

  const LibrarySelectionBar({super.key, required this.viewModel});

  void _confirmDelete(BuildContext context) {
    final count = viewModel.selectedIds.length;
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除已选中的 $count 个项目？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dlgCtx).colorScheme.error),
            onPressed: () {
              Navigator.pop(dlgCtx);
              viewModel.deleteSelected();
            },
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
  }

  void _showMoveFolderDialog(BuildContext context) async {
    final vm = viewModel;
    final contextFolderId = vm.currentFolderId.value;
    final List<NovelFolder> foldersToShow = contextFolderId != null
        ? vm.getChildFolders(contextFolderId)
        : vm.folders.where((f) => f.parentId == null).toList();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx2) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          if (contextFolderId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx2).pop('__ROOT__'),
              child: Row(
                children: [const Icon(Icons.home_outlined), SizedBox(width: AppTheme.metrics.kSpace8), const Text('移回根目录')],
              ),
            ),
          ...foldersToShow.map(
            (f) => SimpleDialogOption(
              onPressed: () => Navigator.of(ctx2).pop(f.id),
              child: Row(
                children: [
                  const Icon(Icons.folder_outlined),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Text(f.name),
                ],
              ),
            ),
          ),
          if (foldersToShow.isEmpty && contextFolderId == null)
            SimpleDialogOption(
              child: Text('暂无文件夹', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ),
        ],
      ),
    );
    if (result == null) return;
    await vm.moveSelectedToFolder(result == '__ROOT__' ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => _buildBar(context));
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final count = viewModel.selectedIds.length;

    final selectedNovels = viewModel.selectedIds
        .map((id) => viewModel.novels.firstWhereOrNull((n) => n.id == id))
        .whereType<NovelMetadata>()
        .toList();
    final allFavorited = selectedNovels.isNotEmpty && selectedNovels.every((n) => n.isFavorite);

    return Container(
      height: appMetrics.kSpace48 + 16,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(top: BorderSide(color: theme.dividerColor.withAlpha(30))),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: appMetrics.kSpace16,
          vertical: appMetrics.kSpace8,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: viewModel.toggleSelectAll,
              icon: Icon(
                viewModel.selectedIds.length == viewModel.filteredItems.length
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              tooltip: '全选',
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '已选 $count 项',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            // 收藏 / 取消收藏
            IconButton(
              onPressed: count > 0 && selectedNovels.isNotEmpty
                  ? () => viewModel.favoriteSelected()
                  : null,
              icon: Icon(
                allFavorited ? Icons.star : Icons.star_border,
                color: allFavorited ? Colors.amber : null,
              ),
              tooltip: allFavorited ? '取消收藏' : '加入收藏',
            ),
            // 移动到文件夹
            IconButton(
              onPressed: count > 0 && selectedNovels.isNotEmpty
                  ? () => _showMoveFolderDialog(context)
                  : null,
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: '移动到文件夹',
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            TextButton(onPressed: viewModel.exitSelection, child: const Text('取消')),
            SizedBox(width: AppTheme.metrics.kSpace8),
            FilledButton.icon(
              onPressed: count > 0 ? () => _confirmDelete(context) : null,
              icon: Icon(Icons.delete_outline, size: AppTheme.metrics.iconSize18),
              label: const Text('删除'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
