import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder_card.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 媒体库浏览网格（首页 / 文件夹内列表）
///
/// 展示文件夹、智能文件夹、集合卡片；同时处理桌面端框选和拖拽逻辑。
class MediaBrowseGridView extends StatefulWidget {
  final MediaLibraryViewModel viewModel;

  /// 滚动控制器（由父页面管理生命周期）
  final ScrollController scrollController;

  // ── 导航回调 ──────────────────────────────────────────────────────────────
  final void Function(String id) onEnterFolder;
  final void Function(String id) onEnterCollection;

  // ── 文件夹操作回调 ────────────────────────────────────────────────────────
  final void Function(String id, String name) onRenameFolderDialog;
  final void Function(String id, String name) onConfirmDeleteFolder;

  // ── 智能文件夹操作回调 ────────────────────────────────────────────────────
  final void Function(String id, String name) onRenameSmartFolderDialog;
  final void Function(SmartFolder sf, {bool isRemote}) onEditSmartFolder;

  /// [isRemote] 为 true 时调用远程删除，否则本地删除
  final void Function(String id, String name, {bool isRemote})
  onDeleteSmartFolder;

  // ── 集合操作回调 ──────────────────────────────────────────────────────────
  final void Function(String id, String title) onRenameCollection;
  final void Function(String id, String title) onDeleteCollection;
  final void Function(String id, String? folderId) onMoveCollection;

  /// [isRemote] true 则显示路径弹窗，false 则打开本地文件夹
  final void Function(String path, {bool isRemote}) onOpenFolder;
  final void Function(String id, String path, String title)
  onDeleteCollectionFolder;
  final void Function(String id, String name) onDeleteNodeLocalFilesForFolder;
  final void Function(String id, String title)
  onDeleteNodeLocalFilesForCollection;

  /// 打开集合配置目录（集合目录下的 .SlimeWorks）回调，传入集合的文件夹路径。
  final void Function(String collectionFolderPath) onOpenConfigDir;

  const MediaBrowseGridView({
    super.key,
    required this.viewModel,
    required this.scrollController,
    required this.onEnterFolder,
    required this.onEnterCollection,
    required this.onRenameFolderDialog,
    required this.onConfirmDeleteFolder,
    required this.onRenameSmartFolderDialog,
    required this.onEditSmartFolder,
    required this.onDeleteSmartFolder,
    required this.onRenameCollection,
    required this.onDeleteCollection,
    required this.onMoveCollection,
    required this.onOpenFolder,
    required this.onDeleteCollectionFolder,
    required this.onDeleteNodeLocalFilesForFolder,
    required this.onDeleteNodeLocalFilesForCollection,
    required this.onOpenConfigDir,
  });

  @override
  State<MediaBrowseGridView> createState() => _MediaBrowseGridViewState();
}

class _MediaBrowseGridViewState extends State<MediaBrowseGridView> {
  /// 框选起点（桌面端）
  Offset? _selectionBoxStart;

  /// 框选终点（桌面端）
  Offset? _selectionBoxEnd;

  /// 网格的 RenderBox key，用于框选坐标计算
  final GlobalKey _gridKey = GlobalKey();

  MediaLibraryViewModel get vm => widget.viewModel;

  // ── 拖拽高亮辅助 ──────────────────────────────────────────────────────────

  Widget _buildDropHighlight(
    BuildContext context, {
    required bool highlighted,
    required Widget child,
  }) {
    if (!highlighted) return child;
    final color = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: appMetrics.radiusCard,
                border: Border.all(color: color, width: scaleW(3)),
                color: color.withAlpha(40),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 桌面端框选 ────────────────────────────────────────────────────────────

  /// 网格实际排出的列数与格宽
  ///
  /// 复刻 [SliverGridDelegateWithMaxCrossAxisExtent] 的取整方式（含 [MediaCutoutGeometry]
  /// 的格宽上限与 kSpace12 内边距），让 delegate 和框选命中用同一份数：
  /// 两边各写一份字面量时窗口一窄就差出一列，选中样式会落到隔壁卡片上。
  (int columns, double cellWidth) _gridColumns(double viewportWidth) {
    final spacing = appMetrics.kSpace12;
    final gridWidth = viewportWidth - 2 * spacing;
    if (gridWidth <= 0) return (0, 0);
    final columns = math.max(
      1,
      (gridWidth / (MediaCutoutGeometry.maxCellWidth + spacing)).ceil(),
    );
    final usable = math.max(0.0, gridWidth - spacing * (columns - 1));
    return (columns, usable / columns);
  }

  void _updateSelectionByBox() {
    if (_selectionBoxStart == null || _selectionBoxEnd == null) return;
    final selectionRect = Rect.fromPoints(
      _selectionBoxStart!,
      _selectionBoxEnd!,
    );
    final gridRenderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridRenderBox == null) return;

    final items = vm.visibleItems;
    final newSelection = <String>{};
    // 列数与格宽走同一条公式（见 [_gridColumns]）：这里是拿来判命中的矩形，
    // 和 delegate 差一列就会选中隔壁那张卡。
    final (crossAxisCount, itemWidth) = _gridColumns(gridRenderBox.size.width);
    if (crossAxisCount <= 0) return;

    final spacing = appMetrics.kSpace12;
    final padding = appMetrics.kSpace12;
    final itemHeight = itemWidth / MediaCutoutGeometry.aspectFor(itemWidth);

    for (int index = 0; index < items.length; index++) {
      final row = index ~/ crossAxisCount;
      final column = index % crossAxisCount;
      final left = padding + column * (itemWidth + spacing);
      final top = padding + row * (itemHeight + spacing);
      final itemRect = Rect.fromLTWH(left, top, itemWidth, itemHeight);
      if (selectionRect.overlaps(itemRect)) {
        newSelection.add(items[index].id);
      }
    }

    if (newSelection.isEmpty) {
      vm.exitSelection();
      return;
    }
    vm.isSelecting.value = true;
    vm.selectedIds.assignAll(newSelection);
  }

  // ── 卡片构建 ──────────────────────────────────────────────────────────────

  Widget _buildCard(BuildContext context, MediaLibraryItem item) {
    return Obx(() {
      if (item is MediaLibraryFolderItem) {
        return _buildFolderCard(context, item.folder);
      }
      if (item is MediaLibrarySmartFolderItem) {
        return _buildSmartFolderCard(context, item.smartFolder);
      }
      return _buildCollectionCard(
        context,
        (item as MediaLibraryCollectionItem).collection,
      );
    });
  }

  Widget _buildFolderCard(BuildContext context, folder) {
    // 同名集合分组是虚拟文件夹：不支持重命名/删除/迁移，也不接受拖放。
    final isDupGroup = vm.isDupGroup(folder.id);
    final isRemoteFolder = vm.isRemoteFolder(folder.id);
    final summary = vm.folderSummary(folder.id);
    final folderCard = MediaFolderCard(
      folder: folder,
      coverSource: vm.buildFolderCoverSource(folder),
      itemCount: summary.childCards,
      resourceCount: summary.resources,
      totalSize: summary.size,
      typeLabel: isDupGroup
          ? '同名分组'
          : isRemoteFolder
          ? '远程文件夹'
          : '文件夹',
      isSelected: vm.selectedIds.contains(folder.id),
      isRemote: isRemoteFolder,
      nodeName: vm.getRemoteFolderNodeName(folder.id),
      isLost: isDupGroup ? false : vm.checkFolderLost(folder),
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(folder.id);
          return;
        }
        widget.onEnterFolder(folder.id);
      },
      onLongPress: () => vm.enterSelection(folder.id),
      onRename: isDupGroup
          ? () => vm.showSnack('提示', '同名集合分组为自动聚合的虚拟文件夹，不支持重命名')
          : () => widget.onRenameFolderDialog(folder.id, folder.name),
      onDelete: isDupGroup
          ? () => vm.showSnack('提示', '同名集合分组为自动聚合的虚拟文件夹，不支持删除')
          : () => widget.onConfirmDeleteFolder(folder.id, folder.name),
      onTransfer: vm.isRemoteFolder(folder.id) || isDupGroup
          ? null
          : () => vm.transferFolderCollections(folderId: folder.id),
      onPullToLocal: vm.isRemoteFolder(folder.id)
          ? () => vm.pullRemoteFolderToLocal(folder.id)
          : null,
      onDeleteNodeFiles: vm.isRemoteFolder(folder.id)
          ? () => widget.onDeleteNodeLocalFilesForFolder(folder.id, folder.name)
          : null,
    );
    if (vm.isRemoteFolder(folder.id) || isDupGroup) return folderCard;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !vm.isRemoteCollection(d.data),
      onAcceptWithDetails: (d) => vm.moveCollectionToFolder(d.data, folder.id),
      builder: (ctx, candidateData, _) => _buildDropHighlight(
        ctx,
        highlighted: candidateData.isNotEmpty,
        child: folderCard,
      ),
    );
  }

  Widget _buildSmartFolderCard(BuildContext context, SmartFolder sf) {
    final isRemoteSf = vm.isRemoteSmartFolder(sf.id);
    final nodeId = vm.remoteSmartFolderNodeId(sf.id);
    final nodeName = nodeId != null
        ? (vm.nodeSettingsService.getNodeById(nodeId)?.name ?? nodeId)
        : null;
    final sfResources = vm.smartFolderResources(sf);
    final sfCard = SmartFolderCard(
      smartFolder: sf,
      coverSource: vm.buildSmartFolderCoverSource(sf),
      matchCount: vm.collectionsMatchingSmartFolder(sf).length,
      resourceCount: sfResources.count,
      totalSize: sfResources.size,
      isSelected: vm.selectedIds.contains(sf.id),
      nodeName: nodeName,
      isLost: vm.checkSmartFolderLost(sf),
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(sf.id);
          return;
        }
        widget.onEnterFolder(sf.id);
      },
      onLongPress: () => vm.enterSelection(sf.id),
      onRename: isRemoteSf
          ? null
          : () => widget.onRenameSmartFolderDialog(sf.id, sf.name),
      onEdit: () => widget.onEditSmartFolder(sf, isRemote: isRemoteSf),
      onDelete: () =>
          widget.onDeleteSmartFolder(sf.id, sf.name, isRemote: isRemoteSf),
      onTransfer: isRemoteSf
          ? null
          : () => vm.transferFolderCollections(smartFolderId: sf.id),
    );
    if (isRemoteSf) return sfCard;
    final targetId = sf.targetFolderIds.length == 1
        ? sf.targetFolderIds.first
        : null;
    if (targetId == null) return sfCard;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !vm.isRemoteCollection(d.data),
      onAcceptWithDetails: (d) => vm.moveCollectionToFolder(d.data, targetId),
      builder: (ctx, candidateData, _) => _buildDropHighlight(
        ctx,
        highlighted: candidateData.isNotEmpty,
        child: sfCard,
      ),
    );
  }

  Widget _buildCollectionCard(BuildContext context, collection) {
    final live = vm.collectionResources(collection);
    final card = MediaCollectionCard(
      collection: collection,
      coverSource: vm.buildCollectionCoverSource(collection),
      isSelected: vm.selectedIds.contains(collection.id),
      isSelecting: vm.isSelecting.value,
      isRemote: vm.isRemoteCollection(collection.id),
      nodeName: vm.getRemoteNodeName(collection.id),
      resourceCount: live.count,
      totalSize: live.size,
      isFavorited: vm.isFavorite(collection.id),
      isLost: vm.checkCollectionLost(collection),
      hoverCoverSources: vm.isRemoteCollection(collection.id)
          ? null
          : vm.buildCollectionHoverSources(collection),
      onHoverEnter: vm.isRemoteCollection(collection.id)
          ? null
          : () => vm.prefetchCollectionVideoFrames(collection.id),
      onRequestVideoFrame: vm.isRemoteCollection(collection.id)
          ? null
          : (fraction) =>
                vm.getCollectionVideoFrameAtFraction(collection.id, fraction),
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(collection.id);
          return;
        }
        widget.onEnterCollection(collection.id);
      },
      onLongPress: () => vm.enterSelection(collection.id),
      onRename: () =>
          widget.onRenameCollection(collection.id, collection.title),
      onDelete: () =>
          widget.onDeleteCollection(collection.id, collection.title),
      onMove: () => widget.onMoveCollection(collection.id, collection.folderId),
      onOpenFolder: vm.isRemoteCollection(collection.id)
          ? () => widget.onOpenFolder(collection.folderPath, isRemote: true)
          : () => widget.onOpenFolder(collection.folderPath, isRemote: false),
      onOpenConfigDir: vm.isRemoteCollection(collection.id)
          ? null
          : () => widget.onOpenConfigDir(collection.folderPath),
      onDeleteFolder: vm.isRemoteCollection(collection.id)
          ? null
          : () => widget.onDeleteCollectionFolder(
              collection.id,
              collection.folderPath,
              collection.title,
            ),
      onPullToLocal: vm.isRemoteCollection(collection.id)
          ? () => vm.pullRemoteCollectionToLocal(collection.id)
          : null,
      onDeleteNodeFiles: vm.isRemoteCollection(collection.id)
          ? () => widget.onDeleteNodeLocalFilesForCollection(
              collection.id,
              collection.title,
            )
          : null,
      onToggleFavorite: () => vm.toggleFavorite(collection.id),
      onSimilarSearch: () => vm.startSimilarSearch(collection),
    );

    // 追踪鼠标悬停状态（供 Delete 快捷键定位当前悬停的集合）
    final collectionCard = MouseRegion(
      onEnter: (_) => vm.hoveredCollectionId.value = collection.id,
      onExit: (_) {
        if (vm.hoveredCollectionId.value == collection.id) {
          vm.hoveredCollectionId.value = null;
        }
      },
      child: card,
    );

    if (vm.isRemoteCollection(collection.id)) return collectionCard;

    // 仅综合排序模式下启用拖拽重排序
    final isCombinedSort =
        vm.collectionSortOrder.value == CollectionSortOrder.combinedSort;
    if (!isCombinedSort) return collectionCard;

    final draggable = Draggable<String>(
      data: collection.id,
      feedback: Material(
        // canvasColor 现为透明，拖拽浮影需要自己铺底
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: appMetrics.radius8,
        child: SizedBox(
          width: scaleW(160),
          height: scaleW(60),
          child: Padding(
            padding: EdgeInsets.all(appMetrics.kSpace12),
            child: Text(
              collection.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: collectionCard),
      child: collectionCard,
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != collection.id &&
          !vm.isRemoteCollection(d.data) &&
          vm.mergedCollections.any((c) => c.id == d.data),
      onAcceptWithDetails: (d) => vm.reorderCollection(d.data, collection.id),
      builder: (ctx, candidateData, _) => _buildDropHighlight(
        ctx,
        highlighted: candidateData.isNotEmpty,
        child: draggable,
      ),
    );
  }

  // ── 构建主体 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = vm.visibleItems;
      if (items.isEmpty) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isRoot = vm.currentFolderId.value == null;
        return Center(
          child: Container(
            padding: EdgeInsets.all(appMetrics.kSpace32),
            margin: EdgeInsets.symmetric(horizontal: appMetrics.kSpace24),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.background2 : LightColors.background1,
              borderRadius: appMetrics.radius16,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withValues(alpha: isDark ? 0.2 : 0.08),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: appMetrics.radius16,
                  ),
                  child: DrawIcon(StrokeIcons.permMedia,
                    size: scaleW(36),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(height: appMetrics.kSpace20),
                Text(
                  isRoot ? '媒体库为空' : '当前文件夹为空',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: appMetrics.kSpace8),
                Text(
                  isRoot ? '使用上方操作按钮导入集合' : '拖拽或导入媒体到此处',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // 镂空卡是「定高文字区 + 比例封面」，卡片总高得按真实格宽反推，
      // 所以这里先量一次宽度，再把它同时喂给 delegate 和框选命中。
      final grid = LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = _gridColumns(constraints.maxWidth).$2;
          return GridView.builder(
            key: _gridKey,
            controller: widget.scrollController,
            padding: EdgeInsets.all(appMetrics.kSpace12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: MediaCutoutGeometry.maxCellWidth,
              childAspectRatio: MediaCutoutGeometry.aspectFor(cellWidth),
              mainAxisSpacing: appMetrics.kSpace12,
              crossAxisSpacing: appMetrics.kSpace12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              // 以集合/文件夹 id 作为 Element key：排序或拖拽重排后卡片按身份复用，
              // 否则按索引匹配会让选中态、封面等 State 错位到别的卡片上。
              // 注意：这里不再包 Cue.onMount → Actor 入场动画。每次 Obx 重建网格时，
              // 若卡片重新挂载会触发 mounted 动画风暴（60fps × 每卡 15ms 错峰），
              // 引发大量 _firstBuild，最终导致 UI 线程被拖死（Lost connection to device）。
              return KeyedSubtree(
                key: ValueKey(item.id),
                child: _buildCard(context, item),
              );
            },
          );
        },
      );

      // 远程节点加载进度条（顶部细条）
      final loadingIndicator = Obx(
        () => vm.isLoadingRemote.value
            ? const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              )
            : const SizedBox.shrink(),
      );

      // 移动端：仅显示网格 + 加载指示
      if (Platform.isAndroid || Platform.isIOS) {
        return Stack(children: [grid, loadingIndicator]);
      }

      // 桌面端：支持框选
      return GestureDetector(
        onPanStart: (details) {
          setState(() {
            _selectionBoxStart = details.localPosition;
            _selectionBoxEnd = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() => _selectionBoxEnd = details.localPosition);
          _updateSelectionByBox();
        },
        onPanEnd: (_) {
          setState(() {
            _selectionBoxStart = null;
            _selectionBoxEnd = null;
          });
        },
        child: Stack(
          children: [
            grid,
            if (_selectionBoxStart != null && _selectionBoxEnd != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: SelectionBoxPainter(
                    start: _selectionBoxStart!,
                    end: _selectionBoxEnd!,
                    color: Theme.of(context).colorScheme.primary.withAlpha(48),
                    borderColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            loadingIndicator,
          ],
        ),
      );
    });
  }
}
