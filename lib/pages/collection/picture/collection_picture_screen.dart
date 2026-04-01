import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/dialogs/node_directory_picker.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/media_selection_bar.dart';
import 'package:slime_works/pages/collection/picture/components/media_viewer_page.dart';
import 'package:slime_works/pages/collection/picture/components/picture_library_toolbar.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder_card.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

class CollectionPictureScreen extends BasePage<MediaLibraryViewModel> {
  const CollectionPictureScreen({super.key});

  @override
  State<CollectionPictureScreen> createState() => _CollectionPictureScreenState();
}

class _CollectionPictureScreenState
    extends BasePageState<MediaLibraryViewModel, CollectionPictureScreen> {
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  // 每次导航时重新生成，确保 AnimatedSwitcher 过渡期间新旧页有不同 GlobalKey
  GlobalKey _gridKey = GlobalKey();
  int _detailColumnCount = 3;
  // 同样每次导航时重建，避免 AnimatedSwitcher 过渡期间两个 GridView 同时 attach 同一个 controller
  late ScrollController _scrollController;

  /// 文件/文件夹正被拖入窗口（桌面端）。
  bool _isDraggingFiles = false;

  /// true when MediaViewerPage is pushed on top; used to redirect the back
  /// button in the action bar to close the viewer instead of exiting the collection.
  bool _viewerActive = false;

  /// 导航方向：true = 向前（进入子页），false = 向后（返回上级）。
  bool _navForward = true;

  late final MediaLibraryViewModel _persistentViewModel = Get.put(
    MediaLibraryViewModel(),
    permanent: true,
  );

  @override
  MediaLibraryViewModel createViewModel() => _persistentViewModel;

  Worker? _scrollRestoreWorker;

  // ── 导航包装方法（同时设置动画方向） ─────────────────────────────────────

  /// 导航时重建 [_scrollController]，并同步保存当前滚动位置到 viewModel。
  void _replaceScrollController() {
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _enterFolder(String id) {
    setState(() {
      _navForward = true;
      _gridKey = GlobalKey();
    });
    _replaceScrollController();
    viewModel.enterFolder(id);
  }

  void _exitFolder() {
    setState(() {
      _navForward = false;
      _gridKey = GlobalKey();
    });
    _replaceScrollController();
    viewModel.exitFolder();
  }

  void _enterCollection(String id) {
    setState(() {
      _navForward = true;
      _gridKey = GlobalKey();
    });
    _replaceScrollController();
    viewModel.enterCollection(id);
  }

  void _exitCollection() {
    setState(() {
      _navForward = false;
      _gridKey = GlobalKey();
    });
    _replaceScrollController();
    viewModel.exitCollection();
  }

  void _exitToRoot() {
    setState(() {
      _navForward = false;
      _gridKey = GlobalKey();
    });
    _replaceScrollController();
    viewModel.exitToRoot();
  }

  /// 当前页面内容的唯一标识 key（切换时触发 AnimatedSwitcher 动画）。
  String get _pageContentKey {
    final folderId = viewModel.currentFolderId.value ?? 'root';
    final collectionId = viewModel.currentCollectionId.value;
    if (collectionId != null) return 'detail_$collectionId';
    return 'browse_$folderId';
  }

  /// 方向感知的滑动切换过渡效果。
  Widget _buildPageTransition(Widget child, Animation<double> animation) {
    final isIncoming = (child.key as ValueKey<String>?)?.value == _pageContentKey;
    final dir = _navForward ? 1.0 : -1.0;
    final tween = isIncoming
        ? Tween<Offset>(begin: Offset(dir, 0), end: Offset.zero)
        : Tween<Offset>(begin: Offset.zero, end: Offset(-dir, 0));
    return ClipRect(
      child: SlideTransition(
        position: tween.animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: viewModel.savedScrollOffset.value);
    _scrollController.addListener(_onScroll);
    // Consume scroll-restore signals emitted by the viewmodel on exitCollection / exitFolder
    _scrollRestoreWorker = ever<double?>(viewModel.scrollRestoreTarget, (offset) {
      if (offset == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final clamped = offset.clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.jumpTo(clamped);
        }
        viewModel.scrollRestoreTarget.value = null;
      });
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    _scrollRestoreWorker?.dispose();
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    final isMobile = PlatformUtil.isMobile || getIt<DesktopScreenProvider>().isMobile.value;
    // PictureLibraryToolbar：移动端传入 columnCount 以启用移动端控件（排序+列数调节）。
    // 桌面端传 null，对应控件由 leading 区域的 _buildActionBar 负责。
    final toolbar = PictureLibraryToolbar(
      viewModel: viewModel,
      onCreateFolder: () => _showCreateFolderDialog(),
      onScanFolder: () => _handleFolderAction(scanMode: true),
      onImportFolder: () => _handleFolderAction(scanMode: false),
      onRefresh: () async => viewModel.refreshAll(),
      onClearLibrary: () => _confirmClearLibrary(),
      onCreateSmartFolder: () => _showCreateSmartFolderDialog(),
      columnCount: isMobile ? _detailColumnCount : null,
      onColumnDecrement: isMobile && viewModel.isInDetail && _detailColumnCount > 1
          ? () => setState(() => _detailColumnCount--)
          : null,
      onColumnIncrement: isMobile && viewModel.isInDetail && _detailColumnCount < 10
          ? () => setState(() => _detailColumnCount++)
          : null,
      onUpload:
          (isMobile &&
              viewModel.isInDetail &&
              viewModel.isRemoteCollection(viewModel.currentCollectionId.value ?? ''))
          ? () => viewModel.uploadMediaToCurrentCollection()
          : null,
    );

    if (isMobile) {
      // 移动端：将操作控件放入 toolbar 二级行，AppBar 只保留标题和返回键。
      // 这样避免了 leading 区域挤占导致的视觉重叠问题。
      final inDetail = viewModel.isInDetail;
      final showBack = inDetail || viewModel.currentFolderId.value != null;
      return ScreenChromeData(
        // title: inDetail ? viewModel.currentCollectionTitle : viewModel.currentBrowseTitle,
        titleWidget: toolbar,
        leading: showBack
            ? SizedBox(
                width: AppTheme.metrics.kSpace48,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () {
                    if (inDetail)
                      _exitCollection();
                    else
                      _exitFolder();
                  },
                ),
              )
            : null,
        toolbarHeight: AppTheme.metrics.kSpace48,
        // toolbar: toolbar,
      );
    }

    // 桌面端：leading 显示操作栏（面包屑/统计/排序），toolbar 显示图书馆快捷按钮
    return ScreenChromeData(
      title: viewModel.isInDetail ? viewModel.currentCollectionTitle : viewModel.currentBrowseTitle,
      leading: _buildActionBar(context),
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: toolbar,
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return Obx(
      () => ScreenChrome(
        data: _buildScreenChromeData(context),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || viewModel.isInDetail) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape && viewModel.isSelecting.value) {
              viewModel.exitSelection();
              return KeyEventResult.handled;
            }
            if ((HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed) &&
                event.logicalKey == LogicalKeyboardKey.keyA) {
              if (!viewModel.isSelecting.value) {
                viewModel.isSelecting.value = true;
              }
              viewModel.toggleSelectAll();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.delete &&
                viewModel.isSelecting.value &&
                viewModel.selectedIds.isNotEmpty) {
              _confirmDeleteSelected(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Obx(() {
            final pageKey = _pageContentKey;
            final pageContent = !viewModel.isInDetail
                ? _buildBrowseGrid(context)
                : _buildCollectionDetail(context);
            final body = Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) {
                      // 每个过渡子 widget 加实色背景，防止滑动期间透出底层内容
                      return ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: _buildPageTransition(child, animation),
                      );
                    },
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren.map((c) => Positioned.fill(child: c)),
                        if (currentChild != null) Positioned.fill(child: currentChild),
                      ],
                    ),
                    child: KeyedSubtree(key: ValueKey(pageKey), child: pageContent),
                  ),
                ),
                if (viewModel.isSelecting.value)
                  MediaSelectionBar(
                    selectedCount: viewModel.selectedIds.length,
                    onDelete: () => _confirmDeleteSelected(context),
                    onCancel: viewModel.exitSelection,
                  ),
              ],
            );
            // 仅桌面端启用文件拖拽导入
            if (Platform.isAndroid || Platform.isIOS) return body;
            return DropTarget(
              onDragEntered: (_) => setState(() => _isDraggingFiles = true),
              onDragExited: (_) => setState(() => _isDraggingFiles = false),
              onDragDone: (detail) {
                setState(() => _isDraggingFiles = false);
                viewModel.importDroppedPaths(detail.files.map((f) => f.path).toList());
              },
              child: Stack(
                children: [
                  body,
                  if (_isDraggingFiles)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withAlpha(40),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_open_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '松开以导入媒体',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
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
                      icon: const Icon(Icons.arrow_back_rounded),
                      size: AppTheme.metrics.kSpace40,
                      onTap: () {
                        if (_viewerActive) {
                          Navigator.of(context).maybePop();
                        } else if (inDetail) {
                          _exitCollection();
                        } else {
                          _exitFolder();
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
                    Icon(
                      Icons.grid_view_rounded,
                      size: scaleW(16),
                      color: Theme.of(context).hintColor,
                    ),
                    SizedBox(width: appMetrics.kSpace4),
                    IconButton(
                      icon: const Icon(Icons.remove_rounded),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '减少列数',
                      onPressed: _detailColumnCount > 1
                          ? () => setState(() => _detailColumnCount--)
                          : null,
                    ),
                    Text('$_detailColumnCount 列', style: Theme.of(context).textTheme.bodySmall),
                    IconButton(
                      icon: const Icon(Icons.add_rounded),
                      iconSize: scaleW(16),
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      constraints: BoxConstraints(minWidth: scaleW(28), minHeight: scaleW(28)),
                      tooltip: '增加列数',
                      onPressed: _detailColumnCount < 10
                          ? () => setState(() => _detailColumnCount++)
                          : null,
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
              // 右侧：节点数小标签 + 集合排序按钮，整体作为刚性块不溢出
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
                      // 集合排序按钮（浏览层：根目录、文件夹内、智能文件夹均显示）
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
                  ), // Row
                ), // ConstrainedBox
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
              _exitToRoot();
            },
            child: const Text('媒体库'),
          ),
          // Regular folder trail
          for (int index = 0; index < trail.length; index++) ...[
            Icon(Icons.chevron_right_rounded, size: scaleW(18)),
            TextButton(
              onPressed: () => _enterFolder(trail[index].id),
              child: Text(trail[index].name),
            ),
          ],
          // Smart folder in trail (always root-level, no further sub-path)
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

  Future<void> _handleFolderAction({required bool scanMode}) async {
    final activeRemoteFolderId = viewModel.currentFolderId.value;

    // 当在小智能文件夹（无目标文件夹）中操作扫描，集合会被导入到根目录而非当前文件夹→拦截并提示
    if (activeRemoteFolderId != null &&
        viewModel.isSmartFolder(activeRemoteFolderId) &&
        viewModel.effectiveFolderId == null) {
      viewModel.showSnack('提示', '该智能文件夹未关联实际目录，请先进入一个普通文件夹再执行扫描');
      return;
    }

    if (activeRemoteFolderId != null && viewModel.isRemoteFolder(activeRemoteFolderId)) {
      final nodeId = viewModel.getRemoteFolderNodeId(activeRemoteFolderId);
      if (nodeId == null) {
        viewModel.showSnack('错误', '远程文件夹映射不存在');
        return;
      }
      await _showNodeFolderDialog(scanMode: scanMode, fixedNodeId: nodeId);
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      if (scanMode) {
        await viewModel.scanFolder();
      } else {
        await viewModel.importFolder();
      }
      return;
    }

    if (viewModel.enabledRemoteNodes.isEmpty) {
      viewModel.showSnack('提示', '移动端请先配置可用节点');
      return;
    }
    await _showNodeFolderDialog(scanMode: scanMode);
  }

  Future<void> _showNodeFolderDialog({required bool scanMode, String? fixedNodeId}) async {
    String selectedNodeId = fixedNodeId ?? viewModel.enabledRemoteNodes.first.id;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(scanMode ? '节点扫描文件夹' : '节点导入文件夹'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fixedNodeId == null)
                    DropdownButtonFormField<String>(
                      initialValue: selectedNodeId,
                      decoration: const InputDecoration(labelText: '目标节点'),
                      items: viewModel.enabledRemoteNodes
                          .map(
                            (node) =>
                                DropdownMenuItem<String>(value: node.id, child: Text(node.name)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => selectedNodeId = value);
                      },
                    ),
                  SizedBox(height: appMetrics.kSpace12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: '节点文件夹路径',
                            hintText: '/Users/demo/Pictures',
                          ),
                        ),
                      ),
                      SizedBox(width: appMetrics.kSpace8),
                      Tooltip(
                        message: '浏览节点目录',
                        child: IconButton(
                          icon: const Icon(Icons.folder_open_rounded),
                          onPressed: () async {
                            final picked = await showDialog<String>(
                              context: context,
                              builder: (_) => NodeDirectoryPicker(
                                nodeId: selectedNodeId,
                                nodeSettingsService: viewModel.nodeSettingsService,
                                initialPath: controller.text.trim().isEmpty
                                    ? '/'
                                    : controller.text.trim(),
                              ),
                            );
                            if (picked != null) {
                              setState(() => controller.text = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                if (scanMode) {
                  await viewModel.scanFolder(nodeId: selectedNodeId, folderPath: controller.text);
                } else {
                  await viewModel.importFolder(nodeId: selectedNodeId, folderPath: controller.text);
                }
              },
              child: const Text('执行'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final currentFolderId = viewModel.currentFolderId.value;
    final inFolder = currentFolderId != null;
    final allowLocalRoot = !Platform.isAndroid && !Platform.isIOS;
    if (!inFolder && !allowLocalRoot && viewModel.enabledRemoteNodes.isEmpty) {
      viewModel.showSnack('提示', '当前没有可用节点，无法创建远程文件夹');
      return;
    }
    String target = allowLocalRoot
        ? '__local__'
        : (viewModel.enabledRemoteNodes.firstOrNull?.id ?? '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建媒体文件夹'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!inFolder && viewModel.enabledRemoteNodes.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: target,
                      decoration: const InputDecoration(labelText: '创建位置'),
                      items: [
                        if (allowLocalRoot)
                          const DropdownMenuItem<String>(value: '__local__', child: Text('本地媒体库')),
                        ...viewModel.enabledRemoteNodes.map(
                          (node) =>
                              DropdownMenuItem<String>(value: node.id, child: Text(node.name)),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => target = value);
                        }
                      },
                    ),
                  if (!inFolder && viewModel.enabledRemoteNodes.isNotEmpty)
                    SizedBox(height: appMetrics.kSpace12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '输入文件夹名称'),
                    onSubmitted: (_) async {
                      Navigator.of(context).pop();
                      await viewModel.createFolderWithName(
                        controller.text,
                        targetNodeId: !inFolder && target != '__local__' ? target : null,
                      );
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.createFolderWithName(
                  controller.text,
                  targetNodeId: !inFolder && target != '__local__' ? target : null,
                );
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  // ── Smart Folder Dialogs ─────────────────────────────────────────────────

  Future<void> _showCreateSmartFolderDialog() async {
    // 确保文件夹列表是最新的
    await viewModel.loadFolders();
    // 快照为普通 List，避免 StatefulBuilder 不在 GetX 响应式上下文中无法正确读取 RxList
    final snapshotFolders = viewModel.folders.toList();
    final nameCtrl = TextEditingController();
    final patternCtrl = TextEditingController();
    final selectedFolderIds = <String>{}; // empty = 全部集合
    var regexTarget = SmartFolderRegexTarget.collectionName;
    var fileTypeFilter = SmartFolderFileType.all;
    // 目标节点：null = 本机，非空 = 指定远程节点
    String? targetNodeId;
    final enabledNodes = viewModel.enabledRemoteNodes;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('新建智能文件夹'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '文件夹名称', hintText: '例：我的收藏'),
                    ),
                    // 远程节点选择（有可用节点时显示）
                    if (enabledNodes.isNotEmpty) ...[
                      SizedBox(height: appMetrics.kSpace12),
                      DropdownButtonFormField<String?>(
                        value: targetNodeId,
                        decoration: const InputDecoration(labelText: '创建位置'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('本机')),
                          ...enabledNodes.map(
                            (node) =>
                                DropdownMenuItem<String?>(value: node.id, child: Text(node.name)),
                          ),
                        ],
                        onChanged: (v) => setState(() => targetNodeId = v),
                      ),
                    ],
                    // 本机模式才显示目标文件夹选择（远程节点无法引用本机文件夹ID）
                    if (targetNodeId == null) ...[
                      SizedBox(height: appMetrics.kSpace12),
                      const Text('目标文件夹（可多选，空选则匹配全部集合）'),
                      SizedBox(height: appMetrics.kSpace4),
                      if (snapshotFolders.isEmpty)
                        const Text('（暂无文件夹）', style: TextStyle(color: Colors.grey))
                      else
                        Wrap(
                          spacing: appMetrics.kSpace8,
                          runSpacing: appMetrics.kSpace4,
                          children: [
                            for (final f in snapshotFolders)
                              FilterChip(
                                label: Text(f.name),
                                selected: selectedFolderIds.contains(f.id),
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    selectedFolderIds.add(f.id);
                                  } else {
                                    selectedFolderIds.remove(f.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                    ],
                    SizedBox(height: appMetrics.kSpace12),
                    // 正则匹配目标
                    const Text('正则匹配目标'),
                    SizedBox(height: appMetrics.kSpace4),
                    SegmentedButton<SmartFolderRegexTarget>(
                      segments: SmartFolderRegexTarget.values
                          .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                          .toList(),
                      selected: {regexTarget},
                      onSelectionChanged: (s) => setState(() => regexTarget = s.first),
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                    // 文件类型过滤（仅匹配文件名时显示）
                    if (regexTarget == SmartFolderRegexTarget.fileName) ...[
                      SizedBox(height: appMetrics.kSpace8),
                      const Text('文件类型'),
                      SizedBox(height: appMetrics.kSpace4),
                      SegmentedButton<SmartFolderFileType>(
                        segments: SmartFolderFileType.values
                            .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                            .toList(),
                        selected: {fileTypeFilter},
                        onSelectionChanged: (s) => setState(() => fileTypeFilter = s.first),
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      ),
                    ],
                    SizedBox(height: appMetrics.kSpace12),
                    TextField(
                      controller: patternCtrl,
                      decoration: InputDecoration(
                        labelText: '正则匹配规则（可选）',
                        hintText: '例：大名|别名|关键词',
                        helperText: regexTarget == SmartFolderRegexTarget.fileName
                            ? '留空则显示目标文件夹内符合文件类型的全部集合'
                            : '留空则显示目标文件夹内全部集合',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await viewModel.createSmartFolder(
                      nameCtrl.text,
                      patternCtrl.text,
                      targetFolderIds: selectedFolderIds.toList(),
                      regexTarget: regexTarget,
                      fileTypeFilter: fileTypeFilter,
                      targetNodeId: targetNodeId,
                    );
                  },
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRenameSmartFolderDialog(String id, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名智能文件夹'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: '新名称'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.renameSmartFolder(id, ctrl.text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditSmartFolderDialog(SmartFolder sf) async {
    // 确保文件夹列表是最新的
    await viewModel.loadFolders();
    // 快照为普通 List，避免 StatefulBuilder 不在 GetX 响应式上下文中无法正确读取 RxList
    final snapshotFolders = viewModel.folders.toList();
    final nameCtrl = TextEditingController(text: sf.name);
    final patternCtrl = TextEditingController(text: sf.regexPattern);
    final selectedFolderIds = <String>{...sf.targetFolderIds};
    var regexTarget = sf.regexTarget;
    var fileTypeFilter = sf.fileTypeFilter;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('编辑智能文件夹'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '文件夹名称'),
                    ),
                    SizedBox(height: appMetrics.kSpace12),
                    const Text('目标文件夹（可多选，空选则匹配全部集合）'),
                    SizedBox(height: appMetrics.kSpace4),
                    if (snapshotFolders.isEmpty)
                      const Text('（暂无文件夹）', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(
                        spacing: appMetrics.kSpace8,
                        runSpacing: appMetrics.kSpace4,
                        children: [
                          for (final f in snapshotFolders)
                            FilterChip(
                              label: Text(f.name),
                              selected: selectedFolderIds.contains(f.id),
                              onSelected: (v) => setState(() {
                                if (v) {
                                  selectedFolderIds.add(f.id);
                                } else {
                                  selectedFolderIds.remove(f.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    SizedBox(height: appMetrics.kSpace12),
                    // 正则匹配目标
                    const Text('正则匹配目标'),
                    SizedBox(height: appMetrics.kSpace4),
                    SegmentedButton<SmartFolderRegexTarget>(
                      segments: SmartFolderRegexTarget.values
                          .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                          .toList(),
                      selected: {regexTarget},
                      onSelectionChanged: (s) => setState(() => regexTarget = s.first),
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    ),
                    // 文件类型过滤（仅匹配文件名时显示）
                    if (regexTarget == SmartFolderRegexTarget.fileName) ...[
                      SizedBox(height: appMetrics.kSpace8),
                      const Text('文件类型'),
                      SizedBox(height: appMetrics.kSpace4),
                      SegmentedButton<SmartFolderFileType>(
                        segments: SmartFolderFileType.values
                            .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                            .toList(),
                        selected: {fileTypeFilter},
                        onSelectionChanged: (s) => setState(() => fileTypeFilter = s.first),
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      ),
                    ],
                    SizedBox(height: appMetrics.kSpace12),
                    TextField(
                      controller: patternCtrl,
                      decoration: InputDecoration(
                        labelText: '正则匹配规则（可选）',
                        hintText: '例：大名|别名|关键词',
                        helperText: regexTarget == SmartFolderRegexTarget.fileName
                            ? '留空则显示目标文件夹内符合文件类型的全部集合'
                            : '留空则显示目标文件夹内全部集合',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await viewModel.editSmartFolder(
                      sf.id,
                      name: nameCtrl.text,
                      pattern: patternCtrl.text,
                      targetFolderIds: selectedFolderIds.toList(),
                      regexTarget: regexTarget,
                      fileTypeFilter: fileTypeFilter,
                    );
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteSmartFolder(String id, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除智能文件夹',
      message: '确定删除"$name"？集合本身不受影响，仅删除此筛选规则。',
      confirmLabel: '删除',
    );
    if (confirmed) await viewModel.deleteSmartFolder(id);
  }

  /// 显示远程节点集合的路径信息（不可本地打开，仅供参考）。
  void _showRemotePathDialog(String remotePath) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('远程路径'),
        content: SelectableText(
          remotePath,
          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
      ),
    );
  }

  void _openFolderInExplorer(String folderPath) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer.exe', [folderPath]);
      } else if (Platform.isMacOS) {
        Process.run('open', [folderPath]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [folderPath]);
      }
    } catch (e) {
      viewModel.showSnack('错误', '打开文件夹失败: $e');
    }
  }

  static String _formatBytes(BigInt bytes) {
    final d = bytes.toDouble();
    if (d < 1024) return '${d.toStringAsFixed(0)} B';
    if (d < 1024 * 1024) return '${(d / 1024).toStringAsFixed(1)} KB';
    if (d < 1024 * 1024 * 1024) return '${(d / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(d / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Wraps [child] in a colored overlay ring when a draggable is hovering over it.
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

  Widget _buildBrowseGrid(BuildContext context) {
    final items = viewModel.visibleItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.perm_media_outlined, size: scaleW(64), color: Theme.of(context).hintColor),
            SizedBox(height: appMetrics.kSpace12),
            Text(
              viewModel.currentFolderId.value == null ? '媒体库为空，使用上方操作导入集合' : '当前文件夹为空',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final grid = GridView.builder(
      key: _gridKey,
      controller: _scrollController,
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
        if (item is MediaLibraryFolderItem) {
          final folder = item.folder;
          final folderCard = MediaFolderCard(
            folder: folder,
            coverSource: viewModel.buildFolderCoverSource(folder),
            collectionCount: viewModel.collectionCountInFolder(folder.id),
            isSelected: viewModel.selectedIds.contains(folder.id),
            isRemote: viewModel.isRemoteFolder(folder.id),
            nodeName: viewModel.getRemoteFolderNodeName(folder.id),
            onTap: () {
              if (viewModel.isSelecting.value) {
                viewModel.toggleSelection(folder.id);
                return;
              }
              _enterFolder(folder.id);
            },
            onLongPress: () => viewModel.enterSelection(folder.id),
            onRename: () => _showRenameFolderDialog(folder.id, folder.name),
            onDelete: () => _confirmDeleteFolder(folder.id, folder.name),
            onTransfer: viewModel.isRemoteFolder(folder.id)
                ? null
                : () => viewModel.transferFolderCollections(folderId: folder.id),
            onPullToLocal: viewModel.isRemoteFolder(folder.id)
                ? () => viewModel.pullRemoteFolderToLocal(folder.id)
                : null,
            onDeleteNodeFiles: viewModel.isRemoteFolder(folder.id)
                ? () => _confirmDeleteNodeLocalFilesForFolder(folder.id, folder.name)
                : null,
          );
          if (viewModel.isRemoteFolder(folder.id)) return folderCard;
          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => !viewModel.isRemoteCollection(d.data),
            onAcceptWithDetails: (d) => viewModel.moveCollectionToFolder(d.data, folder.id),
            builder: (ctx, candidateData, _) =>
                _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: folderCard),
          );
        }

        if (item is MediaLibrarySmartFolderItem) {
          final sf = item.smartFolder;
          final isRemoteSf = viewModel.isRemoteSmartFolder(sf.id);
          final nodeId = viewModel.remoteSmartFolderNodeId(sf.id);
          final nodeName = nodeId != null
              ? (viewModel.nodeSettingsService.getNodeById(nodeId)?.name ?? nodeId)
              : null;
          final sfCard = SmartFolderCard(
            smartFolder: sf,
            coverSource: viewModel.buildSmartFolderCoverSource(sf),
            matchCount: viewModel.mergedCollections
                .where((c) => viewModel.collectionMatchesSmartFolder(sf, c))
                .length,
            isSelected: viewModel.selectedIds.contains(sf.id),
            nodeName: nodeName,
            onTap: () {
              if (viewModel.isSelecting.value) {
                viewModel.toggleSelection(sf.id);
                return;
              }
              _enterFolder(sf.id);
            },
            onLongPress: () => viewModel.enterSelection(sf.id),
            // 远程智能文件夹不允许本地编辑/删除/转移
            onRename: isRemoteSf ? null : () => _showRenameSmartFolderDialog(sf.id, sf.name),
            onEdit: isRemoteSf ? null : () => _showEditSmartFolderDialog(sf),
            onDelete: isRemoteSf ? null : () => _confirmDeleteSmartFolder(sf.id, sf.name),
            onTransfer: isRemoteSf
                ? null
                : () => viewModel.transferFolderCollections(smartFolderId: sf.id),
          );
          if (isRemoteSf) return sfCard;
          final targetId = sf.targetFolderIds.length == 1 ? sf.targetFolderIds.first : null;
          if (targetId == null) return sfCard;
          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => !viewModel.isRemoteCollection(d.data),
            onAcceptWithDetails: (d) => viewModel.moveCollectionToFolder(d.data, targetId),
            builder: (ctx, candidateData, _) =>
                _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: sfCard),
          );
        }

        final collection = (item as MediaLibraryCollectionItem).collection;
        final collectionCard = MediaCollectionCard(
          collection: collection,
          coverSource: viewModel.buildCollectionCoverSource(collection),
          isSelected: viewModel.selectedIds.contains(collection.id),
          isSelecting: viewModel.isSelecting.value,
          isRemote: viewModel.isRemoteCollection(collection.id),
          nodeName: viewModel.getRemoteNodeName(collection.id),
          totalSize: viewModel.getCollectionTotalSize(collection.id),
          isFavorited: viewModel.isFavorite(collection.id),
          hoverCoverSources: viewModel.isRemoteCollection(collection.id)
              ? null
              : viewModel.buildCollectionHoverSources(collection),
          onHoverEnter: viewModel.isRemoteCollection(collection.id)
              ? null
              : () => viewModel.prefetchCollectionVideoFrames(collection.id),
          onRequestVideoFrame: viewModel.isRemoteCollection(collection.id)
              ? null
              : (fraction) => viewModel.getCollectionVideoFrameAtFraction(collection.id, fraction),
          onTap: () {
            if (viewModel.isSelecting.value) {
              viewModel.toggleSelection(collection.id);
              return;
            }
            _enterCollection(collection.id);
          },
          onLongPress: () => viewModel.enterSelection(collection.id),
          onRename: () => _showRenameDialog(collection.id, collection.title),
          onDelete: () => _confirmDeleteSingle(collection.id, collection.title),
          onMove: () => _showMoveCollectionDialog(collection.id, collection.folderId),
          onOpenFolder: viewModel.isRemoteCollection(collection.id)
              ? () => _showRemotePathDialog(collection.folderPath)
              : () => _openFolderInExplorer(collection.folderPath),
          onDeleteFolder: viewModel.isRemoteCollection(collection.id)
              ? null
              : () => _confirmDeleteCollectionFolder(
                  collection.id,
                  collection.folderPath,
                  collection.title,
                ),
          onDeleteNodeFiles: viewModel.isRemoteCollection(collection.id)
              ? () => _confirmDeleteNodeLocalFilesForCollection(collection.id, collection.title)
              : null,
          onToggleFavorite: () => viewModel.toggleFavorite(collection.id),
        );
        // Local collections: draggable (to folder) + DragTarget (from other collections for reorder)
        // 仅在「综合排序」模式下启用拖拽重排序
        if (viewModel.isRemoteCollection(collection.id)) return collectionCard;
        final isCombinedSort =
            viewModel.collectionSortOrder.value == CollectionSortOrder.combinedSort;
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
              !viewModel.isRemoteCollection(d.data) &&
              viewModel.mergedCollections.any((c) => c.id == d.data),
          onAcceptWithDetails: (d) => viewModel.reorderCollection(d.data, collection.id),
          builder: (ctx, candidateData, _) =>
              _buildDropHighlight(ctx, highlighted: candidateData.isNotEmpty, child: draggable),
        );
      },
    );

    if (Platform.isAndroid || Platform.isIOS) {
      return Stack(
        children: [
          grid,
          // 远程节点异步加载中时，顶部显示一个细小的进度条
          Obx(
            () => viewModel.isLoadingRemote.value
                ? const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }

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
          // 远程节点异步加载中时，顶部细进度条
          Obx(
            () => viewModel.isLoadingRemote.value
                ? const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionDetail(BuildContext context) {
    final isLoading = viewModel.isLoadingItems.value;
    if (viewModel.currentItems.isEmpty && isLoading) {
      // 远程集合：显示带百分比的圆形进度环
      final collectionId = viewModel.currentCollectionId.value ?? '';
      if (viewModel.isRemoteCollection(collectionId)) {
        return Obx(() {
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
                const SizedBox(height: 12),
                Text('正在加载远程资源…', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        });
      }
      // 本地集合：普通 spinner
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.currentItems.isEmpty) {
      return Center(child: Text('该集合暂无可预览媒体', style: Theme.of(context).textTheme.bodyMedium));
    }

    final collectionId = viewModel.currentCollectionId.value ?? '';
    final isRemote = viewModel.isRemoteCollection(collectionId);
    final sortedItems = viewModel.sortedCurrentItems;

    return Stack(
      children: [
        MasonryMediaGrid(
          items: sortedItems,
          collectionId: collectionId,
          isRemote: isRemote,
          viewModel: viewModel,
          columnCount: _detailColumnCount,
          lastViewedItemId: viewModel.lastViewedItemId.value,
          onOpenViewer: (index) {
            if (collectionId.isEmpty) return;
            // 记录当前预览的资源 ID，返回后高亮并滚动到该位置
            if (index >= 0 && index < sortedItems.length) {
              viewModel.lastViewedItemId.value = sortedItems[index].id;
            }
            final isMobile = Platform.isAndroid || Platform.isIOS;
            // 自定义淡入放大过渡动画 — opaque:true 防止动画期间透出底层内容
            final route = PageRouteBuilder<void>(
              opaque: true,
              barrierColor: Colors.black,
              pageBuilder: (_, __, ___) => MediaViewerPage(
                items: sortedItems,
                initialIndex: index,
                collectionId: collectionId,
                viewModel: viewModel,
              ),
              transitionDuration: const Duration(milliseconds: 280),
              reverseTransitionDuration: const Duration(milliseconds: 240),
              transitionsBuilder: (_, animation, __, child) => FadeTransition(
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
              // 移动端：推到根 Navigator，使预览页覆盖整个 AppBar/chrome 层。
              Navigator.of(context, rootNavigator: true).push(route);
            } else {
              // 桌面端：推到内层 Navigator，并记录 _viewerActive 以重定向操作栏返回按钮。
              // 用 addPostFrameCallback 延迟 setState，避免在 push 帧内触发
              // _dependents.isEmpty 断言。
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _viewerActive = true);
              });
              Navigator.of(context).push(route).whenComplete(() {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _viewerActive = false);
                });
              });
            }
          },
          onConfirmDelete: _confirmDeleteItemFile,
          onConfirmDeleteNodeLocalFile: isRemote ? _confirmDeleteNodeLocalItemFile : null,
        ),
        // 有数据但仍在加载更多时，顶部显示细进度条（不阻塞内容交互）
        if (isLoading)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }

  Future<void> _confirmDeleteItemFile(media_api.MediaItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除文件',
      message: '确定要删除「${item.title}」吗？\n此操作不可恢复，文件将从磁盘永久删除。',
      confirmLabel: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteItemFile(item);
  }

  Future<void> _confirmDeleteNodeLocalItemFile(media_api.MediaItem item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点本地文件',
      message: '确定要删除节点上「${item.title}」的本地文件吗？\n'
          '此操作将从节点磁盘永久删除该文件，集合记录保留。',
      confirmLabel: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteRemoteItemLocalFile(item);
  }

  void _updateSelectionByBox() {
    if (_selectionBoxStart == null || _selectionBoxEnd == null) {
      return;
    }

    final selectionRect = Rect.fromPoints(_selectionBoxStart!, _selectionBoxEnd!);
    final gridRenderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridRenderBox == null) {
      return;
    }

    final items = viewModel.visibleItems;
    final newSelection = <String>{};
    final maxCrossAxisExtent = scaleW(250);
    final spacing = appMetrics.kSpace12;
    final padding = appMetrics.kSpace12;
    final gridWidth = gridRenderBox.size.width - 2 * padding;
    final crossAxisCount = (gridWidth / (maxCrossAxisExtent + spacing)).floor();
    if (crossAxisCount <= 0) {
      return;
    }
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
      viewModel.exitSelection();
      return;
    }
    viewModel.isSelecting.value = true;
    viewModel.selectedIds.assignAll(newSelection);
  }

  Future<void> _showRenameDialog(String collectionId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名集合'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入新的集合名称'),
            onSubmitted: (_) async {
              Navigator.of(context).pop();
              await viewModel.renameCollection(collectionId, controller.text);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.renameCollection(collectionId, controller.text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showRenameFolderDialog(String folderId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名文件夹'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入新的文件夹名称'),
            onSubmitted: (_) async {
              Navigator.of(context).pop();
              await viewModel.renameFolder(folderId, controller.text);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.renameFolder(folderId, controller.text);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMoveCollectionDialog(String collectionId, String? currentFolderId) async {
    String? selectedFolderId = currentFolderId;
    final availableFolders = viewModel.getAvailableFoldersForCollection(collectionId);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移动到文件夹'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return DropdownButtonFormField<String?>(
                initialValue: selectedFolderId,
                decoration: const InputDecoration(labelText: '目标位置'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('根目录')),
                  ...availableFolders.map(
                    (folder) =>
                        DropdownMenuItem<String?>(value: folder.id, child: Text(folder.name)),
                  ),
                ],
                onChanged: (value) => setState(() => selectedFolderId = value),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.moveCollectionToFolder(collectionId, selectedFolderId);
              },
              child: const Text('移动'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClearLibrary() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空媒体库'),
          content: const Text('将删除所有本地集合和文件夹记录。原始文件不会被删除，但扫描/导入记录全部清除。确定继续吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.clearLocalLibrary();
              },
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteSingle(String collectionId, String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移除媒体集合'),
          content: Text('确定将“$title”从媒体库中移除吗？不会删除原始文件。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteCollection(collectionId);
              },
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteFolder(String folderId, String title) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除媒体文件夹'),
          content: Text('确定删除“$title”吗？文件夹内集合会移动到上一级目录。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteFolder(folderId);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  /// 确认删除集合对应的本地文件夹（永久删除物理目录）
  Future<void> _confirmDeleteCollectionFolder(
    String collectionId,
    String folderPath,
    String title,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除本地文件夹'),
          content: Text(
            '确定删除“$title”对应的本地文件夹吗？\n'
            '路径：$folderPath\n\n'
            '此操作不可撤销，将永久删除该目录及其内全部文件。',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteCollectionFolder(collectionId, folderPath);
              },
              child: const Text('永久删除'),
            ),
          ],
        );
      },
    );
  }

  /// 删除物理目录并从媒体库移除集合记录
  Future<void> _deleteCollectionFolder(String collectionId, String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await viewModel.deleteCollection(collectionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除文件夹失败: $e'), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('批量删除媒体项目'),
          content: Text('确定删除已选中的 ${viewModel.selectedIds.length} 个项目吗？集合不会删除原始文件。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteSelectedItems();
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteNodeLocalFilesForFolder(String folderId, String folderName) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点本地文件',
      message: '此操作将永久删除远程节点上"$folderName"文件夹内所有集合的本地文件，且不可恢复。\n\n'
          '集合数据库记录保留，仅删除物理文件。确定继续吗？',
      confirmLabel: '删除文件',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteNodeLocalFilesForFolder(folderId);
  }

  Future<void> _confirmDeleteNodeLocalFilesForCollection(String collectionId, String title) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除节点本地文件',
      message: '此操作将永久删除远程节点上"$title"集合的本地文件，且不可恢复。\n\n'
          '集合数据库记录保留，仅删除物理文件。确定继续吗？',
      confirmLabel: '删除文件',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteNodeLocalFilesForCollection(collectionId);
  }
}
