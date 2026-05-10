import 'dart:io';

import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder_card.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

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
  final void Function(String id, String name, {bool isRemote}) onDeleteSmartFolder;

  // ── 集合操作回调 ──────────────────────────────────────────────────────────
  final void Function(String id, String title) onRenameCollection;
  final void Function(String id, String title) onDeleteCollection;
  final void Function(String id, String? folderId) onMoveCollection;

  /// [isRemote] true 则显示路径弹窗，false 则打开本地文件夹
  final void Function(String path, {bool isRemote}) onOpenFolder;
  final void Function(String id, String path, String title) onDeleteCollectionFolder;
  final void Function(String id, String name) onDeleteNodeLocalFilesForFolder;
  final void Function(String id, String title) onDeleteNodeLocalFilesForCollection;

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
                borderRadius: appMetrics.radius8,
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

  void _updateSelectionByBox() {
    if (_selectionBoxStart == null || _selectionBoxEnd == null) return;
    final selectionRect = Rect.fromPoints(_selectionBoxStart!, _selectionBoxEnd!);
    final gridRenderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridRenderBox == null) return;

    final items = vm.visibleItems;
    final newSelection = <String>{};
    final maxCrossAxisExtent = scaleW(250);
    final spacing = appMetrics.kSpace12;
    final padding = appMetrics.kSpace12;
    final gridWidth = gridRenderBox.size.width - 2 * padding;
    final crossAxisCount = (gridWidth / (maxCrossAxisExtent + spacing)).floor();
    if (crossAxisCount <= 0) return;

    final itemWidth = (gridWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
    final itemHeight = itemWidth / 0.78;

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
      return _buildCollectionCard(context, (item as MediaLibraryCollectionItem).collection);
    });
  }

  Widget _buildFolderCard(BuildContext context, folder) {
    final folderCard = MediaFolderCard(
      folder: folder,
      coverSource: vm.buildFolderCoverSource(folder),
      collectionCount: vm.collectionCountInFolder(folder.id),
      isSelected: vm.selectedIds.contains(folder.id),
      isRemote: vm.isRemoteFolder(folder.id),
      nodeName: vm.getRemoteFolderNodeName(folder.id),
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(folder.id);
          return;
        }
        widget.onEnterFolder(folder.id);
      },
      onLongPress: () => vm.enterSelection(folder.id),
      onRename: () => widget.onRenameFolderDialog(folder.id, folder.name),
      onDelete: () => widget.onConfirmDeleteFolder(folder.id, folder.name),
      onTransfer: vm.isRemoteFolder(folder.id)
          ? null
          : () => vm.transferFolderCollections(folderId: folder.id),
      onPullToLocal: vm.isRemoteFolder(folder.id)
          ? () => vm.pullRemoteFolderToLocal(folder.id)
          : null,
      onDeleteNodeFiles: vm.isRemoteFolder(folder.id)
          ? () => widget.onDeleteNodeLocalFilesForFolder(folder.id, folder.name)
          : null,
    );
    if (vm.isRemoteFolder(folder.id)) return folderCard;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !vm.isRemoteCollection(d.data),
      onAcceptWithDetails: (d) => vm.moveCollectionToFolder(d.data, folder.id),
      builder: (ctx, candidateData, _) =>
          _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: folderCard),
    );
  }

  Widget _buildSmartFolderCard(BuildContext context, SmartFolder sf) {
    final isRemoteSf = vm.isRemoteSmartFolder(sf.id);
    final nodeId = vm.remoteSmartFolderNodeId(sf.id);
    final nodeName = nodeId != null
        ? (vm.nodeSettingsService.getNodeById(nodeId)?.name ?? nodeId)
        : null;
    final sfCard = SmartFolderCard(
      smartFolder: sf,
      coverSource: vm.buildSmartFolderCoverSource(sf),
      matchCount: vm.mergedCollections.where((c) => vm.collectionMatchesSmartFolder(sf, c)).length,
      isSelected: vm.selectedIds.contains(sf.id),
      nodeName: nodeName,
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(sf.id);
          return;
        }
        widget.onEnterFolder(sf.id);
      },
      onLongPress: () => vm.enterSelection(sf.id),
      onRename: isRemoteSf ? null : () => widget.onRenameSmartFolderDialog(sf.id, sf.name),
      onEdit: () => widget.onEditSmartFolder(sf, isRemote: isRemoteSf),
      onDelete: () => widget.onDeleteSmartFolder(sf.id, sf.name, isRemote: isRemoteSf),
      onTransfer: isRemoteSf ? null : () => vm.transferFolderCollections(smartFolderId: sf.id),
    );
    if (isRemoteSf) return sfCard;
    final targetId = sf.targetFolderIds.length == 1 ? sf.targetFolderIds.first : null;
    if (targetId == null) return sfCard;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !vm.isRemoteCollection(d.data),
      onAcceptWithDetails: (d) => vm.moveCollectionToFolder(d.data, targetId),
      builder: (ctx, candidateData, _) =>
          _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: sfCard),
    );
  }

  Widget _buildCollectionCard(BuildContext context, collection) {
    final collectionCard = MediaCollectionCard(
      collection: collection,
      coverSource: vm.buildCollectionCoverSource(collection),
      isSelected: vm.selectedIds.contains(collection.id),
      isSelecting: vm.isSelecting.value,
      isRemote: vm.isRemoteCollection(collection.id),
      nodeName: vm.getRemoteNodeName(collection.id),
      totalSize: vm.getCollectionTotalSize(collection.id),
      isFavorited: vm.isFavorite(collection.id),
      hoverCoverSources: vm.isRemoteCollection(collection.id)
          ? null
          : vm.buildCollectionHoverSources(collection),
      onHoverEnter: vm.isRemoteCollection(collection.id)
          ? null
          : () => vm.prefetchCollectionVideoFrames(collection.id),
      onRequestVideoFrame: vm.isRemoteCollection(collection.id)
          ? null
          : (fraction) => vm.getCollectionVideoFrameAtFraction(collection.id, fraction),
      onTap: () {
        if (vm.isSelecting.value) {
          vm.toggleSelection(collection.id);
          return;
        }
        widget.onEnterCollection(collection.id);
      },
      onLongPress: () => vm.enterSelection(collection.id),
      onRename: () => widget.onRenameCollection(collection.id, collection.title),
      onDelete: () => widget.onDeleteCollection(collection.id, collection.title),
      onMove: () => widget.onMoveCollection(collection.id, collection.folderId),
      onOpenFolder: vm.isRemoteCollection(collection.id)
          ? () => widget.onOpenFolder(collection.folderPath, isRemote: true)
          : () => widget.onOpenFolder(collection.folderPath, isRemote: false),
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
          ? () => widget.onDeleteNodeLocalFilesForCollection(collection.id, collection.title)
          : null,
      onToggleFavorite: () => vm.toggleFavorite(collection.id),
    );

    if (vm.isRemoteCollection(collection.id)) return collectionCard;

    // 仅综合排序模式下启用拖拽重排序
    final isCombinedSort = vm.collectionSortOrder.value == CollectionSortOrder.combinedSort;
    if (!isCombinedSort) return collectionCard;

    final draggable = Draggable<String>(
      data: collection.id,
      feedback: Material(
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
      builder: (ctx, candidateData, _) =>
          _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: draggable),
    );
  }

  // ── 构建主体 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = vm.visibleItems;
      if (items.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.perm_media_outlined, size: scaleW(64), color: Theme.of(context).hintColor),
              SizedBox(height: appMetrics.kSpace12),
              Text(
                vm.currentFolderId.value == null ? '媒体库为空，使用上方操作导入集合' : '当前文件夹为空',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      }

      final grid = GridView.builder(
        key: _gridKey,
        controller: widget.scrollController,
        padding: EdgeInsets.all(appMetrics.kSpace12),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: scaleW(220),
          childAspectRatio: 0.68,
          mainAxisSpacing: appMetrics.kSpace12,
          crossAxisSpacing: appMetrics.kSpace12,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          // 前 40 项加入场动画，超出部分跳过以免卡顿
          final delay = index < 40 ? index * 15 : 0;
          return Cue.onMount(
            motion: const .smooth(),
            child: Actor(
              delay: Duration(milliseconds: delay),
              acts: [const .fadeIn(), const .slideY(from: 0.12)],
              child: _buildCard(context, item),
            ),
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
