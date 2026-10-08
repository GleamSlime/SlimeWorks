import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
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
/// 展示文件夹、智能文件夹、集合卡片。
///
/// 性能架构（与旧「外层大 Obx + 每卡一个 Obx」的区别）：
/// - 数据层：build 里的唯一 Obx 只订阅 [MediaLibraryViewModel.visibleVersion]，
///   派生列表 / 卡片数据快照均命中 VM 侧缓存，Rx 变化收敛为一次重建；
/// - 选择层：每张卡用 ListenableBuilder 只订阅自己的选中通知器
///   （selectionOf）+ isSelecting，选择变化时 diff 通知，只重建真正变化的卡；
/// - 框选：桌面端由外层 SelectionMarquee 包裹（拖框不重建本网格）。
///
/// 入场动画：导航切换（本组件随 AnimatedSwitcher 的 pageKey 换层重建 State）
/// 时逐行渐进展开 + 每卡一次淡入上浮（TweenAnimationBuilder，按 id 复用不重播）；
/// 数据变更（远程加载/重排序/选中）只改 itemCount，不重播动画。
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
  MediaLibraryViewModel get vm => widget.viewModel;

  // ── 逐行展开（入场动画会话） ────────────────────────────────────────────────

  /// 当前已展开渲染的 item 数量（每步 +1 行）。
  int _visibleCount = 0;

  /// 逐行展开的定时器。用 Timer 而非 addPostFrameCallback 驱动后续批次，
  /// 避免在 build/layout 阶段触发 setState（瀑布流网格已验证的同款模式）。
  Timer? _revealTimer;

  /// 上一帧的条目总数，用于区分「条目新增」与「条目减少」两种数据变更。
  int _lastItemCount = 0;

  /// 渐进展开覆盖的最大行数；超过后一次性展开剩余全部。
  static const int _kInitialRevealRows = 12;

  /// LayoutBuilder 实测列数缓存（reveal 步长按行推进用）。
  int _lastColumns = 0;

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  /// 启动入场展开会话。
  ///
  /// 滚动位置恢复目标存在时（initialScrollOffset > 0 或 scrollRestoreTarget 非空）
  /// 直接一次性全量展开：渐进展开会让 maxScrollExtent 短暂偏小，
  /// 恢复的 jumpTo 会被 clamp 在错误位置。
  void _scheduleReveal() {
    _revealTimer?.cancel();
    final total = vm.visibleItems.length;
    _lastItemCount = total;
    if (total <= 0) return;
    if (widget.scrollController.initialScrollOffset > 0 ||
        vm.scrollRestoreTarget.value != null) {
      _visibleCount = total;
      return;
    }
    // 首批先直接给 2 行内容（列数未知时按 8 项兜底），保证第一帧不空白；
    // 之后每 16ms（≈1 帧）展开一行，走 Timer 避免打断 layout pipeline。
    final step = _lastColumns > 0 ? _lastColumns * 2 : 8;
    _visibleCount = math.min(step, total);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealNextBatch();
    });
  }

  void _revealNextBatch() {
    if (!mounted) return;
    final total = vm.visibleItems.length;
    if (_visibleCount >= total) return;
    // 恢复信号中途到达：立即全量，保证 jumpTo 有完整的 maxScrollExtent
    if (vm.scrollRestoreTarget.value != null) {
      setState(() => _visibleCount = total);
      return;
    }
    final step = _lastColumns > 0 ? _lastColumns : 8;
    final threshold = step * _kInitialRevealRows;
    if (_visibleCount < threshold) {
      setState(() => _visibleCount = math.min(_visibleCount + step, total));
      if (_visibleCount < total) {
        // 16ms ≈ 1 frame；Timer 在事件循环中触发，不会打断 build/layout pipeline
        _revealTimer = Timer(const Duration(milliseconds: 16), _revealNextBatch);
      }
    } else {
      setState(() => _visibleCount = total);
    }
  }

  // ── 拖拽高亮辅助 ──────────────────────────────────────────────────────────

  Widget _buildDropHighlight(
    BuildContext context, {
    required bool highlighted,
    required Widget child,
  }) {
    if (!highlighted) return child;
    final color = AppSemantic.of(context).accent;
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

  // ── 卡片构建 ──────────────────────────────────────────────────────────────

  /// 卡片外壳：订阅「自己的选中通知器 + 选择模式」，
  /// 选择变化只重建这一张卡（替代旧结构每卡一个 Obx 全量重查）。
  /// isSelecting 是 RxBool 不实现 Listenable，订阅的是 VM 侧的常驻代理。
  Widget _buildCard(BuildContext context, MediaLibraryItem item) {
    final selection = vm.selectionOf(item.id);
    return ListenableBuilder(
      listenable: Listenable.merge([selection, vm.isSelectingProxy]),
      builder: (context, _) {
        final isSelected = selection.value;
        final data = vm.browseCardData(item);
        if (item is MediaLibraryFolderItem) {
          return _buildFolderCard(context, item.folder, data, isSelected);
        }
        if (item is MediaLibrarySmartFolderItem) {
          return _buildSmartFolderCard(
            context,
            item.smartFolder,
            data,
            isSelected,
          );
        }
        return _buildCollectionCard(
          context,
          (item as MediaLibraryCollectionItem).collection,
          data,
          isSelected,
        );
      },
    );
  }

  Widget _buildFolderCard(
    BuildContext context,
    folder,
    BrowseCardData data,
    bool isSelected,
  ) {
    // 同名集合分组是虚拟文件夹：不支持重命名/删除/迁移，也不接受拖放。
    final isDupGroup = vm.isDupGroup(folder.id);
    final isRemoteFolder = data.isRemote;
    final folderCard = MediaFolderCard(
      folder: folder,
      coverSource: data.coverSource,
      itemCount: data.childCount,
      resourceCount: data.resourceCount,
      totalSize: data.totalSize,
      typeLabel: isDupGroup
          ? '同名分组'
          : isRemoteFolder
          ? '远程文件夹'
          : '文件夹',
      isSelected: isSelected,
      isRemote: isRemoteFolder,
      nodeName: data.nodeName,
      isLost: data.isLost,
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
      onTransfer: isRemoteFolder || isDupGroup
          ? null
          : () => vm.transferFolderCollections(folderId: folder.id),
      onPullToLocal: isRemoteFolder
          ? () => vm.pullRemoteFolderToLocal(folder.id)
          : null,
      onDeleteNodeFiles: isRemoteFolder
          ? () => widget.onDeleteNodeLocalFilesForFolder(folder.id, folder.name)
          : null,
    );
    if (isRemoteFolder || isDupGroup) return folderCard;
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

  Widget _buildSmartFolderCard(
    BuildContext context,
    SmartFolder sf,
    BrowseCardData data,
    bool isSelected,
  ) {
    final isRemoteSf = data.isRemote;
    final sfCard = SmartFolderCard(
      smartFolder: sf,
      coverSource: data.coverSource,
      matchCount: data.matchCount,
      resourceCount: data.resourceCount,
      totalSize: data.totalSize,
      isSelected: isSelected,
      nodeName: data.nodeName,
      isLost: data.isLost,
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

  Widget _buildCollectionCard(
    BuildContext context,
    collection,
    BrowseCardData data,
    bool isSelected,
  ) {
    final isRemote = data.isRemote;
    final card = MediaCollectionCard(
      collection: collection,
      coverSource: data.coverSource,
      isSelected: isSelected,
      isSelecting: vm.isSelecting.value,
      isRemote: isRemote,
      nodeName: data.nodeName,
      resourceCount: data.resourceCount,
      totalSize: data.totalSize,
      isFavorited: data.isFavorited,
      isLost: data.isLost,
      displayTitle: data.displayTitle,
      hoverCoverSources: isRemote
          ? null
          : vm.buildCollectionHoverSources(collection),
      onHoverEnter: isRemote
          ? null
          : () => vm.prefetchCollectionVideoFrames(collection.id),
      onRequestVideoFrame: isRemote
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
      onOpenFolder: isRemote
          ? () => widget.onOpenFolder(collection.folderPath, isRemote: true)
          : () => widget.onOpenFolder(collection.folderPath, isRemote: false),
      onOpenConfigDir: isRemote
          ? null
          : () => widget.onOpenConfigDir(collection.folderPath),
      onDeleteFolder: isRemote
          ? null
          : () => widget.onDeleteCollectionFolder(
              collection.id,
              collection.folderPath,
              collection.title,
            ),
      onPullToLocal: isRemote
          ? () => vm.pullRemoteCollectionToLocal(collection.id)
          : null,
      onDeleteNodeFiles: isRemote
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

    if (isRemote) return collectionCard;

    // 仅综合排序模式下启用拖拽重排序
    final isCombinedSort =
        vm.collectionSortOrder.value == CollectionSortOrder.combinedSort;
    if (!isCombinedSort) return collectionCard;

    final draggable = Draggable<String>(
      data: collection.id,
      feedback: Material(
        // canvasColor 现为透明，拖拽浮影需要自己铺底
        color: AppSemantic.of(context).surface,
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
              style: AppTextStyles.body(context),
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
      // 唯一数据订阅面：visibleVersion 推进 = 派生输入变化，重建一次网格
      vm.visibleVersion.value;
      final items = vm.visibleItems;
      if (items.isEmpty) {
        return _buildEmptyPlaceholder(context);
      }

      // 数据变更同步 reveal 进度（build 期间只改字段不 setState，本次 build 直接生效）：
      // 条目新增 → postFrame 继续展开（不重置进度、不重播已入场的卡）；
      // 条目减少 → 收缩到新总数。
      if (items.length != _lastItemCount) {
        if (items.length > _lastItemCount) {
          final wasFullyRevealed = _visibleCount >= _lastItemCount;
          _lastItemCount = items.length;
          if (wasFullyRevealed && _visibleCount < items.length) {
            // 新一批数据到达：继续渐进展开剩余条目
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _revealNextBatch();
            });
          }
        } else {
          _lastItemCount = items.length;
          if (_visibleCount > items.length) {
            _visibleCount = items.length;
          }
        }
      }

      // 镂空卡是「定高文字区 + 比例封面」，卡片总高得按真实格宽反推，
      // 所以这里先量一次宽度，再把它同时喂给 delegate（框选命中走同源的
      // MediaCutoutGeometry.gridColumnsFor）。
      final grid = LayoutBuilder(
        builder: (context, constraints) {
          final (columns, cellWidth) = MediaCutoutGeometry.gridColumnsFor(
            constraints.maxWidth,
          );
          // 实测列数缓存：reveal 步长按「整行」推进，避免列数变化后步长失真
          _lastColumns = columns;
          return GridView.builder(
            controller: widget.scrollController,
            padding: EdgeInsets.all(appMetrics.kSpace12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: MediaCutoutGeometry.maxCellWidth,
              childAspectRatio: MediaCutoutGeometry.aspectFor(cellWidth),
              mainAxisSpacing: appMetrics.kSpace12,
              crossAxisSpacing: appMetrics.kSpace12,
            ),
            itemCount: math.min(_visibleCount, items.length),
            itemBuilder: (context, index) {
              final item = items[index];
              // 以集合/文件夹 id 作为 Element key：排序或拖拽重排后卡片按身份复用，
              // 否则按索引匹配会让选中态、封面等 State 错位到别的卡片上。
              return KeyedSubtree(
                key: ValueKey(item.id),
                // 入场动画：首次插入播一次淡入+上浮（render 层 Opacity/Transform，
                // 无常驻 ticker）；Element 按 id 复用时 tween 相同不重播——
                // 数据刷新/重排序/选中变化都不会重播动画。
                // 注意 anim key 必须用 id 而非 index：按 index 会在排序后错位重播，
                // 历史上 Cue.onMount 按挂载播动画 + Obx 全网格重建的「动画风暴」
                // 就是这样把 UI 线程拖死的（Lost connection to device）。
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('anim_${item.id}'),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: AppMotion.emphasis,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, AppMotion.travelLarge * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: _buildCard(context, item),
                ),
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

      // 框选（桌面端）由外层 SelectionMarquee 包裹处理，这里只负责网格本体。
      return Stack(children: [grid, loadingIndicator]);
    });
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    final s = AppSemantic.of(context);
    final isRoot = vm.currentFolderId.value == null;
    return Center(
      child: Container(
        padding: EdgeInsets.all(appMetrics.kSpace32),
        margin: EdgeInsets.symmetric(horizontal: appMetrics.kSpace24),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: appMetrics.radius16,
          boxShadow: [
            BoxShadow(
              color: s.shadowKey,
              blurRadius: scaleW(16),
              offset: Offset(0, scaleW(6)),
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
                color: s.accent.withValues(alpha: 0.12),
                borderRadius: appMetrics.radius16,
              ),
              child: DrawIcon(StrokeIcons.permMedia,
                size: scaleW(36),
                color: s.accent,
              ),
            ),
            SizedBox(height: appMetrics.kSpace20),
            Text(
              isRoot ? '媒体库为空' : '当前文件夹为空',
              style: AppTextStyles.role(context,
                fontSize: appMetrics.fontSize14,
                color: s.textPrimary.withValues(alpha: 0.7),
                weight: FontWeight.w600,
              ),
            ),
            SizedBox(height: appMetrics.kSpace8),
            Text(
              isRoot ? '使用上方操作按钮导入集合' : '拖拽或导入媒体到此处',
              style: AppTextStyles.role(context,
                fontSize: appMetrics.fontSize12,
                color: s.textPrimary.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
