import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_library_item.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/pages/collection/picture/components/media_selection_bar.dart';
import 'package:slime_works/pages/collection/picture/components/media_viewer_page.dart';
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
  final GlobalKey _gridKey = GlobalKey();
  late final ScrollController _scrollController;
  late final MediaLibraryViewModel _persistentViewModel = Get.put(
    MediaLibraryViewModel(),
    permanent: true,
  );

  @override
  MediaLibraryViewModel createViewModel() => _persistentViewModel;

  Worker? _scrollRestoreWorker;

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
    return ScreenChromeData(
      title: viewModel.isInDetail ? viewModel.currentCollectionTitle : viewModel.currentBrowseTitle,
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: _PictureLibraryToolbar(
        viewModel: viewModel,
        onCreateFolder: () => _showCreateFolderDialog(),
        onScanFolder: () => _handleFolderAction(scanMode: true),
        onImportFolder: () => _handleFolderAction(scanMode: false),
        onRefresh: () async => viewModel.refreshAll(),
        onClearLibrary: () => _confirmClearLibrary(),
        onCreateSmartFolder: () => _showCreateSmartFolderDialog(),
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
      final items = viewModel.currentItems;
      final totalSize = items.fold(
        BigInt.zero,
        (sum, item) => sum + item.fileSize,
      );
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
            '集合内媒体 ${items.length} 项 · ${_formatBytes(totalSize)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final hasBreadcrumb =
        viewModel.currentFolderTrail.isNotEmpty || viewModel.currentSmartFolder != null;
    final hasNodes = viewModel.enabledRemoteNodes.isNotEmpty;
    if (!hasBreadcrumb && !hasNodes) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        appMetrics.kSpace16,
        appMetrics.kSpace4,
        appMetrics.kSpace16,
        appMetrics.kSpace4,
      ),
      child: Row(
        children: [
          if (hasBreadcrumb) Flexible(child: _buildBreadcrumb(context)),
          const Spacer(),
          if (hasNodes)
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
    final smartFolder = viewModel.currentSmartFolder;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              viewModel.exitToRoot();
            },
            child: const Text('媒体库'),
          ),
          // Regular folder trail
          for (int index = 0; index < trail.length; index++) ...[
            Icon(Icons.chevron_right_rounded, size: scaleW(18)),
            TextButton(
              onPressed: () => viewModel.enterFolder(trail[index].id),
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
                Text(
                  smartFolder.name,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
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

  // ── Smart Folder Dialogs ─────────────────────────────────────────────────

  Future<void> _showCreateSmartFolderDialog() async {
    // 确保文件夹列表是最新的
    await viewModel.loadFolders();
    // 快照为普通 List，避免 StatefulBuilder 不在 GetX 响应式上下文中无法正确读取 RxList
    final snapshotFolders = viewModel.folders.toList();
    final nameCtrl = TextEditingController();
    final patternCtrl = TextEditingController();
    final selectedFolderIds = <String>{}; // empty = 全部集合
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
                      decoration: const InputDecoration(
                        labelText: '文件夹名称',
                        hintText: '例：我的收藏',
                      ),
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
                    TextField(
                      controller: patternCtrl,
                      decoration: const InputDecoration(
                        labelText: '正则匹配规则（可选）',
                        hintText: '例：大名|别名|关键词',
                        helperText: '留空则显示目标文件夹内全部集合',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await viewModel.createSmartFolder(
                      nameCtrl.text,
                      patternCtrl.text,
                      targetFolderIds: selectedFolderIds.toList(),
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
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
                    TextField(
                      controller: patternCtrl,
                      decoration: const InputDecoration(
                        labelText: '正则匹配规则（可选）',
                        hintText: '例：大名|别名|关键词',
                        helperText: '留空则显示目标文件夹内全部集合',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await viewModel.editSmartFolder(
                      sf.id,
                      name: nameCtrl.text,
                      pattern: patternCtrl.text,
                      targetFolderIds: selectedFolderIds.toList(),
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
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除智能文件夹'),
          content: Text('确定删除"$name"？集合本身不受影响，仅删除此筛选规则。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteSmartFolder(id);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
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
              viewModel.enterFolder(folder.id);
            },
            onLongPress: () => viewModel.enterSelection(folder.id),
            onRename: () => _showRenameFolderDialog(folder.id, folder.name),
            onDelete: () => _confirmDeleteFolder(folder.id, folder.name),
          );
          if (viewModel.isRemoteFolder(folder.id)) return folderCard;
          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => !viewModel.isRemoteCollection(d.data),
            onAcceptWithDetails: (d) =>
                viewModel.moveCollectionToFolder(d.data, folder.id),
            builder: (ctx, candidateData, _) => _buildDropHighlight(
              ctx,
              highlighted: candidateData.isNotEmpty,
              child: folderCard,
            ),
          );
        }

        if (item is MediaLibrarySmartFolderItem) {
          final sf = item.smartFolder;
          final sfCard = SmartFolderCard(
            smartFolder: sf,
            coverSource: viewModel.buildSmartFolderCoverSource(sf),
            matchCount: viewModel.mergedCollections.where((c) => sf.matches(c)).length,
            isSelected: viewModel.selectedIds.contains(sf.id),
            onTap: () {
              if (viewModel.isSelecting.value) {
                viewModel.toggleSelection(sf.id);
                return;
              }
              viewModel.enterFolder(sf.id);
            },
            onLongPress: () => viewModel.enterSelection(sf.id),
            onRename: () => _showRenameSmartFolderDialog(sf.id, sf.name),
            onEdit: () => _showEditSmartFolderDialog(sf),
            onDelete: () => _confirmDeleteSmartFolder(sf.id, sf.name),
          );
          final targetId = sf.targetFolderId;
          if (targetId == null) return sfCard;
          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => !viewModel.isRemoteCollection(d.data),
            onAcceptWithDetails: (d) =>
                viewModel.moveCollectionToFolder(d.data, targetId),
            builder: (ctx, candidateData, _) => _buildDropHighlight(
              ctx,
              highlighted: candidateData.isNotEmpty,
              child: sfCard,
            ),
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
          onOpenFolder: () => _openFolderInExplorer(collection.folderPath),
          onDeleteFolder: viewModel.isRemoteCollection(collection.id)
              ? null
              : () => _confirmDeleteCollectionFolder(
                    collection.id,
                    collection.folderPath,
                    collection.title,
                  ),
        );
        // Local collections: draggable (to folder) + DragTarget (from other collections for reorder)
        if (viewModel.isRemoteCollection(collection.id)) return collectionCard;
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
          builder: (ctx, candidateData, _) => _buildDropHighlight(
            ctx,
            highlighted: candidateData.isNotEmpty,
            child: draggable,
          ),
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
          onRequestScrubFrames: (item.kind == media_api.MediaKind.video &&
                  !viewModel.isRemoteCollection(
                      viewModel.currentCollectionId.value ?? ''))
              ? () => viewModel.getVideoScrubFrames(item.filePath)
              : null,
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
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除文件夹失败: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

/// Stable toolbar widget - kept as a dedicated class so Flutter’s element
/// reconciliation reuses the same element across ScreenChromeData rebuilds,
/// preventing semantics-tree node-ID churn that causes AXTree errors on Windows.
class _PictureLibraryToolbar extends StatelessWidget {
  const _PictureLibraryToolbar({
    required this.viewModel,
    required this.onCreateFolder,
    required this.onScanFolder,
    required this.onImportFolder,
    required this.onRefresh,
    required this.onClearLibrary,
    required this.onCreateSmartFolder,
  });

  final MediaLibraryViewModel viewModel;
  final VoidCallback onCreateFolder;
  final VoidCallback onScanFolder;
  final VoidCallback onImportFolder;
  final VoidCallback onRefresh;
  final VoidCallback onClearLibrary;
  final VoidCallback onCreateSmartFolder;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isScanning = viewModel.isScanning.value;
      final statusText = viewModel.scanStatusText.value;
      final inDetail = viewModel.isInDetail;
      final showBack = inDetail || viewModel.currentFolderId.value != null;
      return ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace8,
          children: [
            // 扫描进度（opacity 不增删节点）
            AnimatedOpacity(
              opacity: isScanning ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !isScanning,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppTheme.metrics.kSpace8,
                  children: [
                    SizedBox(
                      width: AppTheme.metrics.kSpace20,
                      height: AppTheme.metrics.kSpace20,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                    AnimatedOpacity(
                      opacity: statusText.isNotEmpty ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        statusText.isNotEmpty ? statusText : ' ',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 操作按钮
            AnimatedOpacity(
              opacity: (!isScanning && !inDetail) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: isScanning || inDetail,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppTheme.metrics.kSpace8,
                  children: [
                    Tooltip(
                      message: '新建文件夹',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.create_new_folder_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onCreateFolder,
                      ),
                    ),
                    Tooltip(
                      message: '扫描文件夹',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.travel_explore_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onScanFolder,
                      ),
                    ),
                    Tooltip(
                      message: '导入文件夹',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.folder_open_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onImportFolder,
                      ),
                    ),
                    Tooltip(
                      message: '同步节点',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.cloud_sync_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onRefresh,
                      ),
                    ),
                    Tooltip(
                      message: '清空媒体库',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onClearLibrary,
                      ),
                    ),
                    Tooltip(
                      message: '新建智能文件夹',
                      child: DesktopHeadToolsButton(
                        icon: const Icon(Icons.auto_awesome_outlined),
                        size: AppTheme.metrics.kSpace40,
                        onTap: onCreateSmartFolder,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DesktopHeadToolsButton(
              icon: const Icon(Icons.refresh),
              size: AppTheme.metrics.kSpace40,
              onTap: onRefresh,
            ),
            // 返回按钮
            AnimatedOpacity(
              opacity: showBack ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !showBack,
                child: DesktopHeadToolsButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () {
                    if (inDetail) {
                      viewModel.exitCollection();
                    } else {
                      viewModel.exitFolder();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
