import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/pages/collection/picture/components/media_selection_bar.dart';
import 'package:slime_works/pages/collection/picture/components/media_viewer_page.dart';
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
  final GlobalKey _gridKey = GlobalKey();
  late final ScrollController _scrollController;
  late final MediaLibraryViewModel _persistentViewModel = Get.put(
    MediaLibraryViewModel(),
    permanent: true,
  );

  @override
  MediaLibraryViewModel createViewModel() => _persistentViewModel;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: viewModel.savedScrollOffset.value);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    return ScreenChromeData(
      title: viewModel.isInDetail ? viewModel.currentCollectionTitle : viewModel.currentBrowseTitle,
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: Row(
        spacing: AppTheme.metrics.kSpace8,
        children: [
          DesktopHeadToolsButton(
            icon: const Icon(Icons.refresh),
            size: AppTheme.metrics.kSpace40,
            onTap: () async {
              await viewModel.refreshAll();
            },
          ),
          if (viewModel.isInDetail || viewModel.currentFolderId.value != null)
            DesktopHeadToolsButton(
              icon: const Icon(Icons.arrow_back_rounded),
              size: AppTheme.metrics.kSpace40,
              onTap: () {
                if (viewModel.isInDetail) {
                  viewModel.exitCollection();
                } else {
                  viewModel.exitFolder();
                }
              },
            ),
        ],
      ),
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
          child: Obx(
            () => Column(
              children: [
                _buildActionBar(context),
                Expanded(
                  child: !viewModel.isInDetail
                      ? _buildBrowseGrid(context)
                      : _buildCollectionDetail(context),
                ),
                if (viewModel.isSelecting.value)
                  MediaSelectionBar(
                    selectedCount: viewModel.selectedIds.length,
                    onDelete: () => _confirmDeleteSelected(context),
                    onCancel: viewModel.exitSelection,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final inDetail = viewModel.isInDetail;
    if (inDetail) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          appMetrics.kSpace16,
          appMetrics.kSpace12,
          appMetrics.kSpace16,
          appMetrics.kSpace8,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '集合内媒体 ${viewModel.currentItems.length} 项',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        appMetrics.kSpace16,
        appMetrics.kSpace12,
        appMetrics.kSpace16,
        appMetrics.kSpace8,
      ),
      child: Wrap(
        spacing: appMetrics.kSpace12,
        runSpacing: appMetrics.kSpace8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (viewModel.currentFolderTrail.isNotEmpty) _buildBreadcrumb(context),
          FilledButton.icon(
            onPressed: () => _showCreateFolderDialog(),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('新建文件夹'),
          ),
          FilledButton.icon(
            onPressed: viewModel.isScanning.value
                ? null
                : () => _handleFolderAction(scanMode: true),
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('扫描文件夹'),
          ),
          OutlinedButton.icon(
            onPressed: viewModel.isScanning.value
                ? null
                : () => _handleFolderAction(scanMode: false),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('导入文件夹'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await viewModel.refreshAll();
            },
            icon: const Icon(Icons.cloud_sync_outlined),
            label: const Text('同步节点'),
          ),
          if (viewModel.enabledRemoteNodes.isNotEmpty)
            Text(
              '已连接节点 ${viewModel.enabledRemoteNodes.length} 个',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    final trail = viewModel.currentFolderTrail;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              viewModel.exitSelection();
              viewModel.currentFolderId.value = null;
            },
            child: const Text('媒体库'),
          ),
          for (int index = 0; index < trail.length; index++) ...[
            Icon(Icons.chevron_right_rounded, size: scaleW(18)),
            TextButton(
              onPressed: () => viewModel.enterFolder(trail[index].id),
              child: Text(trail[index].name),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleFolderAction({required bool scanMode}) async {
    final activeRemoteFolderId = viewModel.currentFolderId.value;
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
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '节点文件夹路径',
                      hintText: '/Users/demo/Pictures',
                    ),
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
        maxCrossAxisExtent: scaleW(250),
        childAspectRatio: 0.78,
        mainAxisSpacing: appMetrics.kSpace12,
        crossAxisSpacing: appMetrics.kSpace12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is MediaLibraryFolderItem) {
          final folder = item.folder;
          return MediaFolderCard(
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
              viewModel.enterFolder(folder.id);
            },
            onLongPress: () => viewModel.enterSelection(folder.id),
            onRename: () => _showRenameFolderDialog(folder.id, folder.name),
            onDelete: () => _confirmDeleteFolder(folder.id, folder.name),
          );
        }

        final collection = (item as MediaLibraryCollectionItem).collection;
        return MediaCollectionCard(
          collection: collection,
          coverSource: viewModel.buildCollectionCoverSource(collection),
          isSelected: viewModel.selectedIds.contains(collection.id),
          isSelecting: viewModel.isSelecting.value,
          isRemote: viewModel.isRemoteCollection(collection.id),
          nodeName: viewModel.getRemoteNodeName(collection.id),
          onTap: () {
            if (viewModel.isSelecting.value) {
              viewModel.toggleSelection(collection.id);
              return;
            }
            viewModel.enterCollection(collection.id);
          },
          onLongPress: () => viewModel.enterSelection(collection.id),
          onRename: () => _showRenameDialog(collection.id, collection.title),
          onDelete: () => _confirmDeleteSingle(collection.id, collection.title),
          onMove: () => _showMoveCollectionDialog(collection.id, collection.folderId),
        );
      },
    );

    if (Platform.isAndroid || Platform.isIOS) {
      return grid;
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
                painter: _SelectionBoxPainter(
                  start: _selectionBoxStart!,
                  end: _selectionBoxEnd!,
                  color: Theme.of(context).colorScheme.primary.withAlpha(48),
                  borderColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollectionDetail(BuildContext context) {
    if (viewModel.isLoadingItems.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.currentItems.isEmpty) {
      return Center(child: Text('该集合暂无可预览媒体', style: Theme.of(context).textTheme.bodyMedium));
    }

    return GridView.builder(
      padding: EdgeInsets.all(appMetrics.kSpace12),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: scaleW(220),
        childAspectRatio: 0.82,
        mainAxisSpacing: appMetrics.kSpace12,
        crossAxisSpacing: appMetrics.kSpace12,
      ),
      itemCount: viewModel.currentItems.length,
      itemBuilder: (context, index) {
        final item = viewModel.currentItems[index];
        final source = viewModel.buildMediaSource(item);
        return MediaItemTile(
          item: item,
          source: source,
          onTap: () {
            final collectionId = viewModel.currentCollectionId.value;
            if (collectionId == null) {
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MediaViewerPage(
                  items: viewModel.currentItems.toList(),
                  initialIndex: index,
                  collectionId: collectionId,
                  viewModel: viewModel,
                ),
              ),
            );
          },
        );
      },
    );
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
}

class _SelectionBoxPainter extends CustomPainter {
  const _SelectionBoxPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.borderColor,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scaleW(1.5);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SelectionBoxPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
