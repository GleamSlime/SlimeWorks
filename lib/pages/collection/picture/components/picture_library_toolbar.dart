import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 图片库操作工具栏。
///
/// 在桌面端放置于 [ScreenChromeData.toolbar]（右侧），
/// 移动端同样放置于 [ScreenChromeData.toolbar]（AppBar 下方第二行）。
///
/// 当 [columnCount] 非 null 时表示处于移动端详情模式，
/// 工具栏会额外显示列数调节按钮和资源排序按钮。
/// 桌面端此二控件已由 `_buildActionBar` 的 `leading` 区域负责，
/// 因此传入 null 以避免重复。
class PictureLibraryToolbar extends StatelessWidget {
  const PictureLibraryToolbar({
    super.key,
    required this.viewModel,
    required this.onCreateFolder,
    required this.onScanFolder,
    required this.onImportFolder,
    required this.onRefresh,
    required this.onClearLibrary,
    required this.onCreateSmartFolder,
    this.columnCount,
    this.onColumnDecrement,
    this.onColumnIncrement,
  });

  final MediaLibraryViewModel viewModel;
  final VoidCallback onCreateFolder;
  final VoidCallback onScanFolder;
  final VoidCallback onImportFolder;
  final VoidCallback onRefresh;
  final VoidCallback onClearLibrary;
  final VoidCallback onCreateSmartFolder;

  /// 移动端详情模式当前列数；null 表示桌面模式（不显示列数控件）。
  final int? columnCount;

  /// 列数减少回调（移动端详情模式）。
  final VoidCallback? onColumnDecrement;

  /// 列数增加回调（移动端详情模式）。
  final VoidCallback? onColumnIncrement;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isScanning = viewModel.isScanning.value;
      final statusText = viewModel.scanStatusText.value;
      final inDetail = viewModel.isInDetail;
      // columnCount 非 null 表示移动端，需要在 toolbar 中显示列数 + 排序
      final showMobileDetailControls = columnCount != null && inDetail;
      final showMobileBrowseSortControl = columnCount != null && !inDetail;

      return ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace8,
          children: [
            // 扫描进度（opacity 不增删节点，避免 AX tree 闪烁）
            AnimatedOpacity(
              opacity: isScanning ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !isScanning,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppTheme.metrics.kSpace8,
                  children: [
                    SizedBox(
                      width: AppTheme.metrics.kSpace20,
                      height: AppTheme.metrics.kSpace20,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    AnimatedOpacity(
                      opacity: statusText.isNotEmpty ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        statusText.isNotEmpty ? statusText : ' ',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 浏览模式：图书馆操作按钮
            if (!isScanning && !inDetail)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: AppTheme.metrics.kSpace8,
                children: [
                  Tooltip(
                    message: '新建文件夹',
                    child: DesktopHeadToolsButton(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      size: AppTheme.metrics.kSpace40,
                      onTap: onCreateFolder,
                    ),
                  ),
                  Tooltip(
                    message: '扫描文件夹',
                    child: DesktopHeadToolsButton(
                      icon: const Icon(Icons.travel_explore_outlined),
                      size: AppTheme.metrics.kSpace40,
                      onTap: onScanFolder,
                    ),
                  ),
                  Tooltip(
                    message: '导入文件夹',
                    child: DesktopHeadToolsButton(
                      icon: const Icon(Icons.folder_open_outlined),
                      size: AppTheme.metrics.kSpace40,
                      onTap: onImportFolder,
                    ),
                  ),
                  Tooltip(
                    message: '清空媒体库',
                    child: DesktopHeadToolsButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      size: AppTheme.metrics.kSpace40,
                      onTap: onClearLibrary,
                    ),
                  ),
                  Tooltip(
                    message: '新建智能文件夹',
                    child: DesktopHeadToolsButton(
                      icon: const Icon(Icons.auto_awesome_outlined),
                      size: AppTheme.metrics.kSpace40,
                      onTap: onCreateSmartFolder,
                    ),
                  ),
                  Tooltip(
                    message: viewModel.showFavoritesOnly.value ? '显示全部' : '只显示收藏',
                    child: DesktopHeadToolsButton(
                      icon: Icon(
                        viewModel.showFavoritesOnly.value
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: viewModel.showFavoritesOnly.value ? Colors.redAccent : null,
                      ),
                      size: AppTheme.metrics.kSpace40,
                      onTap: () =>
                          viewModel.showFavoritesOnly.value = !viewModel.showFavoritesOnly.value,
                    ),
                  ),
                ],
              ),
            // 移动端浏览模式：集合排序按钮（桌面端此按钮在 leading 区域）
            if (showMobileBrowseSortControl)
              PopupMenuButton<CollectionSortOrder>(
                tooltip: '集合排序',
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort_rounded, size: scaleW(18)),
                    SizedBox(width: AppTheme.metrics.kSpace4),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: scaleW(72)),
                      child: Text(
                        viewModel.collectionSortOrder.value.label,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                onSelected: (v) => viewModel.collectionSortOrder.value = v,
                itemBuilder: (_) => CollectionSortOrder.values
                    .map(
                      (o) => PopupMenuItem<CollectionSortOrder>(
                        value: o,
                        child: Row(
                          children: [
                            if (viewModel.collectionSortOrder.value == o)
                              Icon(Icons.check_rounded, size: scaleW(16))
                            else
                              SizedBox(width: scaleW(16)),
                            SizedBox(width: AppTheme.metrics.kSpace8),
                            Text(o.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            // 移动端详情模式：列数调节 + 资源排序（桌面端此控件在 leading 区域）
            if (showMobileDetailControls) ...[
              Icon(Icons.grid_view_rounded, size: scaleW(16), color: Theme.of(context).hintColor),
              IconButton(
                icon: const Icon(Icons.remove_rounded),
                iconSize: scaleW(16),
                padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                tooltip: '减少列数',
                onPressed: (columnCount! > 1) ? onColumnDecrement : null,
              ),
              Text('$columnCount 列', style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                iconSize: scaleW(16),
                padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
                constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                tooltip: '增加列数',
                onPressed: (columnCount! < 10) ? onColumnIncrement : null,
              ),
              SizedBox(width: AppTheme.metrics.kSpace4),
              PopupMenuButton<MediaItemSortOrder>(
                tooltip: '排序',
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.sort_rounded, size: scaleW(18))],
                ),
                onSelected: (v) => viewModel.itemSortOrder.value = v,
                itemBuilder: (_) => MediaItemSortOrder.values
                    .map(
                      (o) => PopupMenuItem<MediaItemSortOrder>(
                        value: o,
                        child: Row(
                          children: [
                            if (viewModel.itemSortOrder.value == o)
                              Icon(Icons.check_rounded, size: scaleW(16))
                            else
                              SizedBox(width: scaleW(16)),
                            SizedBox(width: AppTheme.metrics.kSpace8),
                            Text(o.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            // 刷新/同步按钮（始终显示）
            DesktopHeadToolsButton(
              icon: const Icon(Icons.refresh),
              size: AppTheme.metrics.kSpace40,
              onTap: onRefresh,
            ),
          ],
        ),
      );
    });
  }
}
