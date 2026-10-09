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
import 'package:slime_works/core/widgets/app_text_field.dart';

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

  /// 正文按键层（Ctrl+A / Delete / ESC）的宿主节点。
  ///
  /// 必须显式持有并主动收回焦点：点搜索结果里的卡片时，搜索框会因 TapRegion 判定
  /// 「点到外面」而释放焦点，primary focus 退回最近的 FocusScopeNode。页面里的
  /// Focus 都挂在这个 scope 下面，按键派发只从 primary focus 往上走，于是 ESC
  /// 谁都送不到——表现就是「从搜索结果进集合/文件夹后 ESC 没反应，普通列表进的却正常」。
  final FocusNode _bodyFocusNode = FocusNode();

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
    // 焦点收回正文，ESC 才有地方送（见 _bodyFocusNode 注释）
    _bodyFocusNode.requestFocus();
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
    // 同上：从搜索结果点进来时焦点多半刚被搜索框释放，不收回来 ESC 就是死键
    _bodyFocusNode.requestFocus();
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
    _bodyFocusNode.dispose();
    super.dispose();
  }

  /// ESC 逐级返回：退出多选 → 退出集合 → 退出文件夹 → 交回上层。
  ///
  /// 为什么要单独一层挂在 chrome 控件上：工具栏和面包屑走 ScreenChrome 的 AppBar 槽，
  /// 与正文里那层 Focus 是兄弟而不是后代。焦点一旦落进搜索框或工具栏按钮，ESC 就再也
  /// 回不到正文，而 app 层的 DefaultTextEditingShortcuts 把 Escape 绑成「什么都不做并
  /// 停止冒泡」——于是从搜索结果点进集合后按 ESC 毫无反应。这一层拦住它。
  KeyEventResult _onEscapeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
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

  /// 给顶部 chrome 控件套 ESC 拦截层；不抢焦点，null 原样返回。
  Widget? _escLayer(Widget? child) => child == null
      ? null
      : Focus(canRequestFocus: false, onKeyEvent: _onEscapeKey, child: child);

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
        titleWidget: _escLayer(toolbar),
        leading: _escLayer(
          showBack
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
        ),
        toolbarHeight: AppTheme.metrics.kSpace48,
        // toolbar: toolbar,
      );
    }

    // 桌面端：leading 显示操作栏（面包屑/统计/排序），toolbar 显示图书馆快捷按钮
    return ScreenChromeData(
      title: viewModel.isInDetail ? viewModel.currentCollectionTitle : viewModel.currentBrowseTitle,
      leading: _escLayer(
        PictureActionBar(
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
      ),
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: _escLayer(toolbar),
    );
  }

  /// 底部居中悬浮「清除搜索结果」按钮（相似查找激活时显示，点击清除筛选）。
  /// 返回 null 表示相似查找未激活，无需渲染。
  Widget? _similarClearOverlay(BuildContext context) {
    if (viewModel.similarSearchQuery.value.trim().isEmpty) return null;
    final s = AppSemantic.of(context);
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
                color: s.accentContainer.withAlpha(235),
                borderRadius: AppTheme.metrics.radius999,
                boxShadow: [
                  BoxShadow(
                    color: s.shadowKey,
                    blurRadius: scaleW(12),
                    offset: Offset(0, scaleW(4)),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DrawIcon(
                    StrokeIcons.close,
                    size: AppTheme.metrics.iconSize18,
                    color: s.textPrimary,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace6),
                  Text(
                    '清除搜索结果',
                    style: AppTextStyles.role(
                      context,
                      fontSize: AppTheme.metrics.fontSize13,
                      color: s.textPrimary,
                      weight: FontWeight.w600,
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
            focusNode: _bodyFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) {
                return KeyEventResult.ignored;
              }
              // ESC：与顶部 chrome 共用同一套逐级返回逻辑（见 _onEscapeKey）
              if (_onEscapeKey(node, event) == KeyEventResult.handled) {
                return KeyEventResult.handled;
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
              final s = AppSemantic.of(context);
              final pageKey = _pageContentKey;
              final pageContent = !viewModel.isInDetail
                  ? _buildBrowseGridWidget(context)
                  : _buildCollectionDetailWidget(context);
              final body = Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppMotion.base,
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
                              color: s.accent.withAlpha(40),
                              border: Border.all(
                                color: s.accent,
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
                                    color: s.accent,
                                  ),
                                  SizedBox(height: AppTheme.metrics.kSpace12),
                                  Text(
                                    '松开以导入媒体',
                                    style: AppTextStyles.role(
                                      context,
                                      fontSize: AppTheme.metrics.fontSize14,
                                      color: s.accent,
                                      weight: FontWeight.bold,
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
          position: tween.animate(CurvedAnimation(parent: animation, curve: AppMotion.decelerate)),
          child: child,
        ),
      ),
    );
  }
}
