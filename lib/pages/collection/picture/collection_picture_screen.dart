import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/dialogs/node_directory_picker.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/pages/collection/picture/components/media_browse_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_detail.dart';
import 'package:slime_works/pages/collection/picture/components/media_selection_bar.dart';
import 'package:slime_works/pages/collection/picture/components/picture_library_toolbar.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';
const Loggers _logger = Loggers(name: '图片浏览');

class CollectionPictureScreen extends BasePage<MediaLibraryViewModel> {
  const CollectionPictureScreen({super.key});

  @override
  State<CollectionPictureScreen> createState() => _CollectionPictureScreenState();
}

class _CollectionPictureScreenState
    extends BasePageState<MediaLibraryViewModel, CollectionPictureScreen> {
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
    _logger.info(
      '[Scroll] _replaceScrollController START: hasClients=${_scrollController.hasClients}, offset=${_scrollController.hasClients ? _scrollController.offset : "N/A"}',
    );
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
      _logger.info(
        '[Scroll] _replaceScrollController: saved offset=${_scrollController.offset} to viewModel',
      );
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _logger.info(
      '[Scroll] _replaceScrollController END: new controller with initialScrollOffset=${_scrollController.initialScrollOffset}',
    );
  }

  void _enterFolder(String id) {
    // 关闭可能打开中的右键菜单
    Navigator.of(
      context,
      rootNavigator: false,
    ).popUntil((route) => route.settings.name != null || route.isFirst);
    setState(() => _navForward = true);
    _replaceScrollController();
    viewModel.enterFolder(id);
  }

  void _exitFolder() {
    Navigator.of(
      context,
      rootNavigator: false,
    ).popUntil((route) => route.settings.name != null || route.isFirst);
    setState(() => _navForward = false);
    _replaceScrollController();
    viewModel.exitFolder();
  }

  void _enterCollection(String id) {
    _logger.info(
      '[Scroll] _enterCollection START: id=$id, savedScrollOffset=${viewModel.savedScrollOffset.value}',
    );
    setState(() => _navForward = true);
    viewModel.enterCollection(id);
    _logger.info('[Scroll] _enterCollection END');
  }

  void _exitCollection() {
    _logger.info(
      '[Scroll] _exitCollection START: savedScrollOffset=${viewModel.savedScrollOffset.value}',
    );
    setState(() => _navForward = false);
    viewModel.exitCollection();
    _logger.info(
      '[Scroll] _exitCollection END: scrollRestoreTarget=${viewModel.scrollRestoreTarget.value}',
    );
  }

  void _exitToRoot() {
    setState(() => _navForward = false);
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

  @override
  void initState() {
    super.initState();
    final initialOffset = viewModel.savedScrollOffset.value;
    _logger.info(
      '[Scroll] initState: creating ScrollController with initialScrollOffset=$initialOffset',
    );
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
    _scrollController.addListener(_onScroll);
    // Consume scroll-restore signals emitted by the viewmodel on exitCollection / exitFolder
    _scrollRestoreWorker = ever<double?>(viewModel.scrollRestoreTarget, (offset) {
      _logger.info('[Scroll] _scrollRestoreWorker triggered: offset=$offset');
      if (offset == null) return;
      final scrollController = _scrollController;
      int attempts = 0;
      void performRestore() {
        attempts++;
        if (!mounted) {
          _logger.info('[Scroll] _scrollRestoreWorker: not mounted, abort');
          return;
        }
        _logger.info(
          '[Scroll] _scrollRestoreWorker attempt $attempts: hasClients=${scrollController.hasClients}, offset=$offset',
        );
        if (!scrollController.hasClients && attempts < 10) {
          WidgetsBinding.instance.addPostFrameCallback((_) => performRestore());
          return;
        }
        if (scrollController.hasClients) {
          final clamped = offset.clamp(
            scrollController.position.minScrollExtent,
            scrollController.position.maxScrollExtent,
          );
          _logger.info('[Scroll] _scrollRestoreWorker: jumpTo $clamped (from $offset)');
          scrollController.jumpTo(clamped);
          _logger.info(
            '[Scroll] _scrollRestoreWorker: after jumpTo, position=${scrollController.offset}',
          );
        }
        viewModel.scrollRestoreTarget.value = null;
        _logger.info('[Scroll] _scrollRestoreWorker: set scrollRestoreTarget=null');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => performRestore());
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
      _logger.info('[Scroll] _onScroll: saved offset=${_scrollController.offset}');
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
                    if (inDetail) {
                      _exitCollection();
                    } else {
                      _exitFolder();
                    }
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
    return Obx(() {
      // 当处于文件夹或集合内时，拦截系统返回手势（Android 返回键 / iOS 左划），
      // 退回到上一层浏览内容而非退出整个媒体库页面。
      final inFolder = viewModel.currentFolderId.value != null;
      final inCollection = viewModel.isInDetail;
      final hasInternalBackLevel = inFolder || inCollection;

      return PopScope(
        canPop: !hasInternalBackLevel,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (inCollection) {
              _exitCollection();
            } else if (inFolder) {
              _exitFolder();
            }
          }
        },
        child: ScreenChrome(
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
                  ? _buildBrowseGridWidget(context)
                  : _buildCollectionDetailWidget(context);
              final body = Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) {
                        return _AnimatedSwitcherWrapper(
                          animation: animation,
                          navForward: _navForward,
                          pageContentKey: _pageContentKey,
                          child: child,
                        );
                      },
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
              if (Platform.isAndroid || Platform.isIOS) {
                // 移动端：有内部导航层级时，在左边缘叠加一个右滑返回手势区域。
                // 补偿 PopScope 在 iOS CupertinoPage 中只拦截 Android 返回键的不足。
                if (!hasInternalBackLevel) return body;
                return Stack(
                  children: [
                    body,
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: AppTheme.metrics.kSpace24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragEnd: (details) {
                          if ((details.primaryVelocity ?? 0) > 200) {
                            if (inCollection) {
                              _exitCollection();
                            } else if (inFolder) {
                              _exitFolder();
                            }
                          }
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              }
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
                                    size: AppTheme.metrics.iconSize64,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  SizedBox(height: AppTheme.metrics.kSpace12),
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
    });
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
      // 在打开对话框前同步捕获原始文件夹 ID，确保即使对话框关闭后状态发生变化也能正确定位
      final rawFolderId = viewModel.getRemoteRawFolderId(activeRemoteFolderId);
      await _showNodeFolderDialog(
        scanMode: scanMode,
        fixedNodeId: nodeId,
        targetRawFolderId: rawFolderId,
      );
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      // 在打开文件选择器前同步捕获当前本地文件夹上下文，
      // 避免异步 scanFolder 内部读取响应式状态时因时序问题丢失文件夹归属。
      final localFolderId = viewModel.effectiveFolderId;
      if (scanMode) {
        await viewModel.scanFolder(localTargetFolderId: localFolderId);
      } else {
        await viewModel.importFolder(localTargetFolderId: localFolderId);
      }
      return;
    }

    if (viewModel.enabledRemoteNodes.isEmpty) {
      viewModel.showSnack('提示', '移动端请先配置可用节点');
      return;
    }
    await _showNodeFolderDialog(scanMode: scanMode);
  }

  Future<void> _showNodeFolderDialog({
    required bool scanMode,
    String? fixedNodeId,
    String? targetRawFolderId,
  }) async {
    if (viewModel.enabledRemoteNodes.isEmpty) {
      viewModel.showSnack('提示', '没有可用节点');
      return;
    }
    String selectedNodeId = fixedNodeId ?? viewModel.enabledRemoteNodes.first.id;
    // 当用户切换节点时，targetRawFolderId 失效（非当前文件夹的节点）
    String? activeTargetRawFolderId = targetRawFolderId;

    // 从 SharedPreferences 加载该节点上次使用的路径
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('node_scan_path_$selectedNodeId') ?? '';
    final controller = TextEditingController(text: savedPath);

    if (!mounted) return;
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
                      if (value == null) return;
                      setState(() {
                        selectedNodeId = value;
                        // 切换节点时：目标文件夹上下文失效，并加载该节点的历史路径
                        if (value != fixedNodeId) {
                          activeTargetRawFolderId = null;
                        } else {
                          activeTargetRawFolderId = targetRawFolderId;
                        }
                        final nodePath = prefs.getString('node_scan_path_$value') ?? '';
                        controller.text = nodePath;
                      });
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
                            final currentPath = controller.text.trim();
                            final picked = await showDialog<String>(
                              context: context,
                              builder: (_) => NodeDirectoryPicker(
                                nodeId: selectedNodeId,
                                nodeSettingsService: viewModel.nodeSettingsService,
                                initialPath: currentPath.isEmpty ? '/' : currentPath,
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
                final path = controller.text.trim();
                Navigator.of(context).pop();
                // 持久化本次选择的路径
                if (path.isNotEmpty) {
                  await prefs.setString('node_scan_path_$selectedNodeId', path);
                }
                if (scanMode) {
                  await viewModel.scanFolder(
                    nodeId: selectedNodeId,
                    folderPath: path,
                    targetRawFolderId: activeTargetRawFolderId,
                  );
                } else {
                  await viewModel.importFolder(
                    nodeId: selectedNodeId,
                    folderPath: path,
                    targetRawFolderId: activeTargetRawFolderId,
                  );
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
    await viewModel.loadFolders();
    if (!mounted) return;
    final snapshotFolders = viewModel.folders.toList();
    final nameCtrl = TextEditingController();
    final patternCtrl = TextEditingController();
    final selectedFolderIds = <String>{};
    var regexTarget = SmartFolderRegexTarget.collectionName;
    var fileTypeFilter = SmartFolderFileType.all;
    String? targetNodeId;
    final enabledNodes = viewModel.enabledRemoteNodes;
    final keywords = <String>[];
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
                    if (enabledNodes.isNotEmpty) ...[
                      SizedBox(height: appMetrics.kSpace12),
                      DropdownButtonFormField<String?>(
                        initialValue: targetNodeId,
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
                    if (targetNodeId == null) ...[
                      SizedBox(height: appMetrics.kSpace12),
                      const Text('目标文件夹（可多选，空选则匹配全部集合）'),
                      SizedBox(height: appMetrics.kSpace4),
                      if (snapshotFolders.isEmpty)
                        Text('（暂无文件夹）', style: TextStyle(color: Theme.of(context).colorScheme.outline))
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
                    _KeywordInputList(keywords: keywords, onChanged: () => setState(() {})),
                    SizedBox(height: appMetrics.kSpace8),
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
                      patternCtrl.text.trim(),
                      keywords: keywords,
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

  Future<void> _showEditSmartFolderDialog(SmartFolder sf, {bool isRemote = false}) async {
    await viewModel.loadFolders();
    if (!mounted) return;
    final snapshotFolders = viewModel.folders.toList();
    final nameCtrl = TextEditingController(text: sf.name);
    final patternCtrl = TextEditingController(text: sf.regexPattern);
    final selectedFolderIds = <String>{...sf.targetFolderIds};
    var regexTarget = sf.regexTarget;
    var fileTypeFilter = sf.fileTypeFilter;
    final keywords = <String>[...sf.keywords];
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
                      Text('（暂无文件夹）', style: TextStyle(color: Theme.of(context).colorScheme.outline))
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
                    _KeywordInputList(keywords: keywords, onChanged: () => setState(() {})),
                    SizedBox(height: appMetrics.kSpace8),
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
                    if (isRemote) {
                      await viewModel.editRemoteSmartFolder(
                        sf.id,
                        name: nameCtrl.text,
                        pattern: patternCtrl.text.trim(),
                        keywords: keywords,
                        targetFolderIds: selectedFolderIds.toList(),
                        regexTarget: regexTarget,
                        fileTypeFilter: fileTypeFilter,
                      );
                    } else {
                      await viewModel.editSmartFolder(
                        sf.id,
                        name: nameCtrl.text,
                        pattern: patternCtrl.text.trim(),
                        keywords: keywords,
                        targetFolderIds: selectedFolderIds.toList(),
                        regexTarget: regexTarget,
                        fileTypeFilter: fileTypeFilter,
                      );
                    }
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

  /// 确认删除远程节点上的智能文件夹。
  Future<void> _confirmDeleteRemoteSmartFolder(String id, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除远程智能文件夹',
      message: '确定删除节点上的"$name"？此操作将从节点上永久删除该筛选规则，集合本身不受影响。',
      confirmLabel: '删除',
    );
    if (confirmed) await viewModel.deleteRemoteSmartFolder(id);
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

  /// 浏览网格视图（首页列表 / 文件夹内列表），由 [MediaBrowseGridView] 实现。
  Widget _buildBrowseGridWidget(BuildContext context) {
    return MediaBrowseGridView(
      viewModel: viewModel,
      scrollController: _scrollController,
      onEnterFolder: _enterFolder,
      onEnterCollection: _enterCollection,
      onRenameFolderDialog: _showRenameFolderDialog,
      onConfirmDeleteFolder: _confirmDeleteFolder,
      onRenameSmartFolderDialog: _showRenameSmartFolderDialog,
      onEditSmartFolder: (sf, {bool isRemote = false}) =>
          _showEditSmartFolderDialog(sf, isRemote: isRemote),
      onDeleteSmartFolder: (id, name, {bool isRemote = false}) => isRemote
          ? _confirmDeleteRemoteSmartFolder(id, name)
          : _confirmDeleteSmartFolder(id, name),
      onRenameCollection: _showRenameDialog,
      onDeleteCollection: _confirmDeleteSingle,
      onMoveCollection: _showMoveCollectionDialog,
      onOpenFolder: (path, {bool isRemote = false}) =>
          isRemote ? _showRemotePathDialog(path) : _openFolderInExplorer(path),
      onDeleteCollectionFolder: (id, path, title) =>
          _confirmDeleteCollectionFolder(id, path, title),
      onDeleteNodeLocalFilesForFolder: _confirmDeleteNodeLocalFilesForFolder,
      onDeleteNodeLocalFilesForCollection: _confirmDeleteNodeLocalFilesForCollection,
    );
  }

  /// 集合详情视图（集合内的媒体列表），由 [MediaCollectionDetailView] 实现。
  Widget _buildCollectionDetailWidget(BuildContext context) {
    return MediaCollectionDetailView(
      viewModel: viewModel,
      columnCount: _detailColumnCount,
      onConfirmDelete: _confirmDeleteItemFile,
      onConfirmDeleteNodeLocalFile:
          viewModel.isRemoteCollection(viewModel.currentCollectionId.value ?? '')
          ? _confirmDeleteNodeLocalItemFile
          : null,
      onViewerStateChanged: (active) {
        if (mounted) setState(() => _viewerActive = active);
      },
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
      message:
          '确定要删除节点上「${item.title}」的本地文件吗？\n'
          '此操作将从节点磁盘永久删除该文件，集合记录保留。',
      confirmLabel: '删除',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteRemoteItemLocalFile(item);
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
          content: Text('确定从媒体库移除已选中的 ${viewModel.selectedIds.length} 个项目吗？原始文件不会被删除。'),
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
      message:
          '此操作将永久删除远程节点上"$folderName"文件夹内所有集合的本地文件，且不可恢复。\n\n'
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
      message:
          '此操作将永久删除远程节点上"$title"集合的本地文件，且不可恢复。\n\n'
          '集合数据库记录保留，仅删除物理文件。确定继续吗？',
      confirmLabel: '删除文件',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) await viewModel.deleteNodeLocalFilesForCollection(collectionId);
  }
}

class _KeywordInputList extends StatefulWidget {
  const _KeywordInputList({required this.keywords, required this.onChanged});

  final List<String> keywords;
  final VoidCallback onChanged;

  @override
  State<_KeywordInputList> createState() => _KeywordInputListState();
}

class _KeywordInputListState extends State<_KeywordInputList> {
  final _newKeywordCtrl = TextEditingController();

  void _addKeyword() {
    final text = _newKeywordCtrl.text.trim();
    if (text.isEmpty) return;
    widget.keywords.add(text);
    _newKeywordCtrl.clear();
    widget.onChanged();
  }

  void _removeKeyword(int index) {
    widget.keywords.removeAt(index);
    widget.onChanged();
  }

  @override
  void dispose() {
    _newKeywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关键词列表', style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: appMetrics.kSpace4),
        if (widget.keywords.isNotEmpty)
          Wrap(
            spacing: appMetrics.kSpace4,
            runSpacing: appMetrics.kSpace4,
            children: [
              for (int i = 0; i < widget.keywords.length; i++)
                Chip(
                  label: Text(widget.keywords[i]),
                  deleteIcon: Icon(Icons.close, size: AppTheme.metrics.iconSize16),
                  onDeleted: () => _removeKeyword(i),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newKeywordCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '输入关键词',
                  contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12, vertical: AppTheme.metrics.kSpace8),
                ),
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            SizedBox(width: appMetrics.kSpace4),
            IconButton(
              icon: Icon(Icons.add_circle_outline, size: AppTheme.metrics.iconSize20),
              onPressed: _addKeyword,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: AppTheme.metrics.kSpace32, minHeight: AppTheme.metrics.kSpace32),
            ),
          ],
        ),
        if (widget.keywords.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: appMetrics.kSpace4),
            child: Text(
              '等效正则：${widget.keywords.map((k) => RegExp.escape(k)).join('|')}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
      ],
    );
  }
}

class _AnimatedSwitcherWrapper extends StatelessWidget {
  const _AnimatedSwitcherWrapper({
    required this.animation,
    required this.navForward,
    required this.pageContentKey,
    required this.child,
  });

  final Animation<double> animation;
  final bool navForward;
  final String pageContentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isIncoming = (child.key as ValueKey<String>?)?.value == pageContentKey;
    final dir = navForward ? 1.0 : -1.0;
    final tween = isIncoming
        ? Tween<Offset>(begin: Offset(dir, 0), end: Offset.zero)
        : Tween<Offset>(begin: Offset.zero, end: Offset(-dir, 0));
    return ClipRect(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SlideTransition(
          position: tween.animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
}
