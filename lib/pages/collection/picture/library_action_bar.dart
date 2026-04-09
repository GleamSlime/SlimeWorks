import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 桌面端媒体库操作栏（面包屑 / 统计 / 列数调节 / 排序）。
/// 仅桌面端的 [ScreenChromeData.leading] 使用，移动端不显示该组件。
class LibraryActionBar extends StatelessWidget {
  const LibraryActionBar({
    super.key,
    required this.viewModel,
    required this.columnCount,
    required this.viewerActive,
    required this.onBack,
    this.onColumnDecrement,
    this.onColumnIncrement,
  });

  final MediaLibraryViewModel viewModel;
  final int columnCount;

  /// 桌面端"媒体查看器"是否打开（影响返回按钮行为）。
  final bool viewerActive;

  /// 返回 / 关闭查看器回调。
  final VoidCallback onBack;

  final VoidCallback? onColumnDecrement;
  final VoidCallback? onColumnIncrement;

  @override
  Widget build(BuildContext context) {
    final inDetail = viewModel.isInDetail;
    final showBack = inDetail || viewModel.currentFolderId.value != null;

    if (inDetail) {
      final items = viewModel.currentItems;
      final totalSize = items.fold(BigInt.zero, (sum, item) => sum + item.fileSize);
      return LayoutBuilder(
        builder: (context, constraints) {
          final hasBoundedWidth = constraints.hasBoundedWidth;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              appMetrics.kSpace16,
              appMetrics.kSpace8,
              appMetrics.kSpace8,
              appMetrics.kSpace4,
            ),
            child: Row(
              mainAxisSize: hasBoundedWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                AnimatedOpacity(
                  opacity: showBack ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !showBack,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      iconSize: scaleW(18),
                      padding: EdgeInsets.all(appMetrics.kSpace8),
                      constraints: BoxConstraints(
                        minWidth: appMetrics.kSpace40,
                        minHeight: appMetrics.kSpace40,
                      ),
                      onPressed: onBack,
                    ),
                  ),
                ),
                SizedBox(width: appMetrics.kSpace8),
                Flexible(
                  child: Text(
                    '集合内媒体 ${items.length} 项 · ${_formatBytes(totalSize)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasBoundedWidth) const Spacer(),
                if (!hasBoundedWidth) SizedBox(width: appMetrics.kSpace8),
                // 列数调节
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.grid_view_rounded, size: scaleW(16), color: Theme.of(context).hintColor),
                    SizedBox(width: appMetrics.kSpace4),
                    IconButton(
                      icon: const Icon(Icons.remove_rounded),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '减少列数',
                      onPressed: onColumnDecrement,
                    ),
                    Text('$columnCount 列', style: Theme.of(context).textTheme.bodySmall),
                    IconButton(
                      icon: const Icon(Icons.add_rounded),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '增加列数',
                      onPressed: onColumnIncrement,
                    ),
                  ],
                ),
                SizedBox(width: appMetrics.kSpace4),
                // 排序按钮
                PopupMenuButton<MediaItemSortOrder>(
                  tooltip: '排序',
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, size: scaleW(18)),
                      SizedBox(width: appMetrics.kSpace4),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: scaleW(72)),
                        child: Text(
                          viewModel.itemSortOrder.value.label,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
                              SizedBox(width: appMetrics.kSpace8),
                              Text(o.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          );
        },
      );
    }

    // 浏览模式：面包屑 + 集合排序
    final hasBreadcrumb =
        viewModel.currentFolderTrail.isNotEmpty || viewModel.currentSmartFolder != null;
    final hasNodes = viewModel.enabledRemoteNodes.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            appMetrics.kSpace16,
            appMetrics.kSpace4,
            appMetrics.kSpace8,
            appMetrics.kSpace4,
          ),
          child: Row(
            mainAxisSize: hasBoundedWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (hasBreadcrumb) Flexible(child: _buildBreadcrumb(context, viewModel, onBack)),
              if (!hasBreadcrumb && hasNodes)
                Flexible(
                  child: Text(
                    '已连接节点 ${viewModel.enabledRemoteNodes.length} 个',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (hasBoundedWidth) const Spacer(),
              if (!hasBoundedWidth) SizedBox(width: appMetrics.kSpace8),
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasBreadcrumb && hasNodes) ...[
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: scaleW(80)),
                          child: Text(
                            '已连接节点 ${viewModel.enabledRemoteNodes.length} 个',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: appMetrics.kSpace8),
                      ],
                      PopupMenuButton<CollectionSortOrder>(
                        tooltip: '集合排序',
                        icon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort_rounded, size: scaleW(18)),
                            SizedBox(width: appMetrics.kSpace4),
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
                                    SizedBox(width: appMetrics.kSpace8),
                                    Text(o.label),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _buildBreadcrumb(
  BuildContext context,
  MediaLibraryViewModel viewModel,
  VoidCallback onExitToRoot,
) {
  final trail = viewModel.currentFolderTrail;
  final smartFolder = viewModel.currentSmartFolder;
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onExitToRoot, child: const Text('媒体库')),
        for (int index = 0; index < trail.length; index++) ...[
          Icon(Icons.chevron_right_rounded, size: scaleW(18)),
          TextButton(
            onPressed: () => viewModel.enterFolder(trail[index].id),
            child: Text(trail[index].name),
          ),
        ],
        if (smartFolder != null) ...[
          Icon(Icons.chevron_right_rounded, size: scaleW(18)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, size: scaleW(14)),
              SizedBox(width: appMetrics.kSpace4),
              Text(smartFolder.name, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ],
    ),
  );
}

String _formatBytes(BigInt bytes) {
  final d = bytes.toDouble();
  if (d < 1024) return '${d.toStringAsFixed(0)} B';
  if (d < 1024 * 1024) return '${(d / 1024).toStringAsFixed(1)} KB';
  if (d < 1024 * 1024 * 1024) return '${(d / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(d / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
