import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 桌面端顶栏操作区（ScreenChrome.leading 注入）：
/// 详情模式 = 返回按钮 + 集合内统计 + 列数调节 + 条目排序；
/// 浏览模式 = 面包屑/节点数提示 + 集合排序。
///
/// 从 collection_picture_screen 拆出。响应式语义变化：
/// 旧实现随 screen 的外层大 Obx 重建（一处 Rx 变化 = 整页重建），
/// 这里内部自持 Obx——面包屑/排序/统计的变化只重建本操作栏。
class PictureActionBar extends StatelessWidget {
  const PictureActionBar({
    super.key,
    required this.viewModel,
    required this.isViewerActive,
    required this.detailColumnCount,
    required this.onColumnDecrement,
    required this.onColumnIncrement,
    required this.onExitCollection,
    required this.onExitFolder,
    required this.onExitToRoot,
    required this.onEnterFolder,
  });

  final MediaLibraryViewModel viewModel;

  /// true 表示 MediaViewerPage 压在页面栈顶，返回按钮改为关闭查看器。
  final bool isViewerActive;

  /// 详情页网格列数（由 screen 持有，本栏只展示与回调增减）。
  final int detailColumnCount;
  final VoidCallback onColumnDecrement;
  final VoidCallback onColumnIncrement;

  final VoidCallback onExitCollection;
  final VoidCallback onExitFolder;
  final VoidCallback onExitToRoot;
  final void Function(String id) onEnterFolder;

  @override
  Widget build(BuildContext context) {
    return Obx(() => _buildActionBar(context));
  }

  Widget _buildActionBar(BuildContext context) {
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
                // 返回按钮（左侧）
                // When MediaViewerPage is on top (_viewerActive), this button closes
                // the viewer instead of exiting the collection — avoids a second back
                // button being visible inside MediaViewerPage at the same time.
                AnimatedOpacity(
                  opacity: showBack ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !showBack,
                    child: DesktopHeadToolsButton(
                      icon: DrawIcon(StrokeIcons.arrowBack),
                      size: AppTheme.metrics.kSpace40,
                      onTap: () {
                        if (isViewerActive) {
                          Navigator.of(context).maybePop();
                        } else if (inDetail) {
                          onExitCollection();
                        } else {
                          onExitFolder();
                        }
                      },
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
                    DrawIcon(
                      StrokeIcons.gridView,
                      size: scaleW(16),
                      color: Theme.of(context).hintColor,
                    ),
                    SizedBox(width: appMetrics.kSpace4),
                    IconButton(
                      icon: DrawIcon(StrokeIcons.remove),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '减少列数',
                      onPressed: detailColumnCount > 1 ? onColumnDecrement : null,
                    ),
                    Text('$detailColumnCount 列', style: Theme.of(context).textTheme.bodySmall),
                    IconButton(
                      icon: DrawIcon(StrokeIcons.add),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '增加列数',
                      onPressed: detailColumnCount < 10 ? onColumnIncrement : null,
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
                      DrawIcon(StrokeIcons.sort, size: scaleW(18)),
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
                        (o) => GlassMenuItem<MediaItemSortOrder>(
                          value: o,
                          label: o.label,
                          selected: viewModel.itemSortOrder.value == o,
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
        viewModel.currentFolderTrail.isNotEmpty ||
        viewModel.currentSmartFolder != null ||
        viewModel.isInDupGroup;
    final hasNodes = viewModel.enabledRemoteNodes.isNotEmpty;

    // 使用 LayoutBuilder 判断宽度是否有界，避免在 AppBar.leading 等无界父容器中使用
    // Spacer 导致 RenderFlex 宽度约束异常
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
              // 左侧：面包屑 (带文件夹时) 或节点数提示 (纯根目录时)
              if (hasBreadcrumb) Flexible(child: _buildBreadcrumb(context)),
              if (!hasBreadcrumb && hasNodes)
                Flexible(
                  child: Text(
                    '已连接节点 ${viewModel.enabledRemoteNodes.length} 个',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // 将左侧内容推到最左，右侧控件紧靠右边
              if (hasBoundedWidth) const Spacer(),
              if (!hasBoundedWidth) SizedBox(width: appMetrics.kSpace8),
              // 右侧：节点数小标签 + 集合排序按钮，整体作为刚性块不溢出（不加宽度上限，避免窄约束下内部 Row 溢出）
              Flexible(
                flex: 0,
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
                    // 集合排序按钮（浏览层：根目录、文件夹内、智能文件夹均显示）
                    PopupMenuButton<CollectionSortOrder>(
                      tooltip: '集合排序',
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DrawIcon(StrokeIcons.sort, size: scaleW(18)),
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
                            (o) => GlassMenuItem<CollectionSortOrder>(
                              value: o,
                              label: o.label,
                              selected: viewModel.collectionSortOrder.value == o,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ), // Row
              ), // Flexible
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    final trail = viewModel.currentFolderTrail;
    final smartFolder = viewModel.currentSmartFolder;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              onExitToRoot();
            },
            child: const Text('媒体库'),
          ),
          // Regular folder trail
          for (int index = 0; index < trail.length; index++) ...[
            DrawIcon(StrokeIcons.chevronRight, size: scaleW(18)),
            TextButton(
              onPressed: () => onEnterFolder(trail[index].id),
              child: Text(trail[index].name),
            ),
          ],
          // 同名集合分组标题段（虚拟分组，面包屑末段，不可点击）
          if (viewModel.currentDupGroupTitle != null) ...[
            DrawIcon(StrokeIcons.chevronRight, size: scaleW(18)),
            Text(viewModel.currentDupGroupTitle!, style: Theme.of(context).textTheme.labelMedium),
          ],
          // Smart folder in trail (always root-level, no further sub-path)
          if (smartFolder != null) ...[
            DrawIcon(StrokeIcons.chevronRight, size: scaleW(18)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DrawIcon(StrokeIcons.autoAwesome, size: scaleW(14)),
                SizedBox(width: appMetrics.kSpace4),
                Text(smartFolder.name, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 体积格式化（B/KB/MB/GB），详情模式统计文本专用。
String _formatBytes(BigInt bytes) {
  final d = bytes.toDouble();
  if (d < 1024) return '${d.toStringAsFixed(0)} B';
  if (d < 1024 * 1024) return '${(d / 1024).toStringAsFixed(1)} KB';
  if (d < 1024 * 1024 * 1024) {
    return '${(d / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(d / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
