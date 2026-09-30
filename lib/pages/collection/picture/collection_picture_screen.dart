import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/dialogs/node_directory_picker.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
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
import 'package:slime_works/pages/collection/picture/components/selection_marquee.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/pages/collection/picture/components/picture_action_bar.dart';

part 'picture_screen_dialogs.dart';

const Loggers _logger = Loggers(name: '图片浏览');

class CollectionPictureScreen extends BasePage<MediaLibraryViewModel> {
  const CollectionPictureScreen({super.key});

  @override
  State<CollectionPictureScreen> createState() => _CollectionPictureScreenState();
}

class _CollectionPictureScreenState
    extends BasePageState<MediaLibraryViewModel, CollectionPictureScreen>
    with PictureScreenDialogs {
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
      // _logger.info('[Scroll] _onScroll: saved offset=${_scrollController.offset}');
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
      onRescanCollection: () => viewModel.rescanCollection(),
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
                  icon: DrawIcon(StrokeIcons.arrowBack),
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
      leading: PictureActionBar(
        viewModel: viewModel,
        isViewerActive: _viewerActive,
        detailColumnCount: _detailColumnCount,
        onColumnDecrement: () => setState(() => _detailColumnCount--),
        onColumnIncrement: () => setState(() => _detailColumnCount++),
        onExitCollection: _exitCollection,
        onExitFolder: _exitFolder,
        onExitToRoot: _exitToRoot,
        onEnterFolder: _enterFolder,
      ),
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: toolbar,
    );
  }

  /// 底部居中悬浮「清除搜索结果」按钮（相似查找激活时显示，点击清除筛选）。
  /// 返回 null 表示相似查找未激活，无需渲染。
  Widget? _similarClearOverlay(BuildContext context) {
    if (viewModel.similarSearchQuery.value.trim().isEmpty) return null;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: AppTheme.metrics.kSpace20,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: viewModel.clearSimilarSearch,
            borderRadius: AppTheme.metrics.radius999,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace16,
                vertical: AppTheme.metrics.kSpace8,
              ),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withAlpha(235),
                borderRadius: AppTheme.metrics.radius999,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DrawIcon(
                    StrokeIcons.close,
                    size: AppTheme.metrics.iconSize18,
                    color: scheme.onPrimaryContainer,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace6),
                  Text(
                    '清除搜索结果',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: AppTheme.metrics.fontSize13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              // ESC：优先退出多选；否则逐级返回上一级（集合 → 文件夹 → 根目录）
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (viewModel.isSelecting.value) {
                  viewModel.exitSelection();
                  return KeyEventResult.handled;
                }
                if (viewModel.isInDetail) {
                  _exitCollection();
                  return KeyEventResult.handled;
                }
                if (viewModel.currentFolderId.value != null) {
                  _exitFolder();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
              if (viewModel.isInDetail) {
                return KeyEventResult.ignored;
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
              // 鼠标悬停集合 + Delete：直接删除本地文件及文件夹（无需二次确认）
              if (event.logicalKey == LogicalKeyboardKey.delete && !viewModel.isSelecting.value) {
                final hovered = viewModel.hoveredLocalCollection();
                if (hovered != null) {
                  _deleteCollectionFolder(hovered.id, hovered.folderPath);
                  return KeyEventResult.handled;
                }
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
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.topLeft,
                        children: [...previousChildren, ?currentChild],
                      ),
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
                      onSelectUnfavorited: viewModel.selectUnfavoritedCollections,
                    ),
                ],
              );
              // 相似查找激活时的底部悬浮「清除搜索结果」按钮（null 表示未激活）
              final clearBtn = _similarClearOverlay(context);
              // 仅桌面端启用文件拖拽导入
              if (Platform.isAndroid || Platform.isIOS) {
                // 移动端：有内部导航层级时，在左边缘叠加一个右滑返回手势区域。
                // 补偿 PopScope 在 iOS CupertinoPage 中只拦截 Android 返回键的不足。
                if (!hasInternalBackLevel) {
                  return clearBtn == null ? body : Stack(children: [body, clearBtn]);
                }
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
                    ?clearBtn,
                  ],
                );
              }
              return DropTarget(
                onDragEntered: (_) => setState(() => _isDraggingFiles = true),
                onDragExited: (_) => setState(() => _isDraggingFiles = false),
                onDragDone: (detail) async {
                  setState(() => _isDraggingFiles = false);
                  // 与点击"导入文件夹"完全一致：先弹窗确认选项再导入
                  final options = await _showImportOptionsDialog();
                  if (options == null) return;
                  await viewModel.importDroppedPaths(
                    detail.files.map((f) => f.path).toList(),
                    generateThumbnails: options.$1,
                    preserveStructure: options.$2,
                  );
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
                                  DrawIcon(
                                    StrokeIcons.folderOpen,
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
                    ?clearBtn,
                  ],
                ),
              );
            }),
          ),
        ),
      );
    });
  }

  /// 浏览网格视图（首页列表 / 文件夹内列表），由 [MediaBrowseGridView] 实现。
  /// 桌面端外面包一层 [SelectionMarquee] 处理拖框多选（拖框不重建网格）；
  /// 移动端多选走长按进入，不需要框选层。
  Widget _buildBrowseGridWidget(BuildContext context) {
    final grid = MediaBrowseGridView(
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
      onOpenConfigDir: _openCollectionConfigDir,
    );
    final isMobile =
        PlatformUtil.isMobile || getIt<DesktopScreenProvider>().isMobile.value;
    if (isMobile) return grid;
    return SelectionMarquee(
      viewModel: viewModel,
      scrollController: _scrollController,
      child: grid,
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
        // 转场时得有一层底，否则新旧两页互相透出来。用和内容区同一档玻璃透明度，
        // 而不是 scaffoldBackgroundColor 的实心画布——后者会把整页的磨砂彻底盖掉。
        color: AppSemantic.of(context).canvas.withAlpha(WindowGlass.contentAlpha),
        child: SlideTransition(
          position: tween.animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
}
