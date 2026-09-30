part of 'collection_picture_screen.dart';

/// 媒体库页面的全部弹窗与确认流程，从主 State 拆出（约 1200 行）。
///
/// mixin 挂到 _CollectionPictureScreenState 上，共享同一库的导入与私有成员；
/// 只依赖 BasePageState 提供的 viewModel / context / mounted / setState，
/// 不触碰主 State 的滚动控制器等导航字段——主 State 与弹窗职责彻底分开。
mixin PictureScreenDialogs
    on BasePageState<MediaLibraryViewModel, CollectionPictureScreen> {
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
        // 导入前弹出增强选项（全量缩略图 / 按原始目录导入）
        final options = await _showImportOptionsDialog();
        if (options == null) return;
        await viewModel.importFolder(
          localTargetFolderId: localFolderId,
          generateThumbnails: options.$1,
          preserveStructure: options.$2,
        );
      }
      return;
    }

    if (viewModel.enabledRemoteNodes.isEmpty) {
      viewModel.showSnack('提示', '移动端请先配置可用节点');
      return;
    }
    await _showNodeFolderDialog(scanMode: scanMode);
  }

  /// 本地导入前的增强选项弹窗，返回 (全量生成缩略图, 按原始目录导入)；取消返回 null。
  Future<(bool, bool)?> _showImportOptionsDialog() async {
    bool generateThumbnails = false;
    bool preserveStructure = false;
    return showDialog<(bool, bool)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入文件夹选项'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('导入后全文件生成缩略图'),
                    subtitle: const Text('导入的媒体自动加入缩略图生成队列'),
                    value: generateThumbnails,
                    onChanged: (v) => setState(() => generateThumbnails = v ?? false),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('按原始目录导入'),
                    subtitle: const Text('按导入目录创建文件夹层级，集合仍按资源父目录创建'),
                    value: preserveStructure,
                    onChanged: (v) => setState(() => preserveStructure = v ?? false),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((generateThumbnails, preserveStructure)),
              child: const Text('选择文件夹'),
            ),
          ],
        );
      },
    );
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
    // 导入增强选项（仅导入模式显示）
    bool generateThumbnails = false;
    bool preserveStructure = false;

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
                          icon: DrawIcon(StrokeIcons.folderOpen),
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
                  if (!scanMode) ...[
                    SizedBox(height: appMetrics.kSpace12),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('导入后全文件生成缩略图'),
                      subtitle: const Text('导入的媒体自动加入缩略图生成队列'),
                      value: generateThumbnails,
                      onChanged: (v) => setState(() => generateThumbnails = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('按原始目录导入'),
                      subtitle: const Text('按导入目录创建文件夹层级，集合仍按资源父目录创建'),
                      value: preserveStructure,
                      onChanged: (v) => setState(() => preserveStructure = v ?? false),
                    ),
                  ],
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
                    generateThumbnails: generateThumbnails,
                    preserveStructure: preserveStructure,
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
    // 如果当前正在浏览远程节点的文件夹，默认创建到该节点
    final currentFolderIdValue = viewModel.currentFolderId.value;
    String? targetNodeId;
    if (currentFolderIdValue != null && viewModel.isRemoteFolder(currentFolderIdValue)) {
      targetNodeId = viewModel.getRemoteFolderNodeId(currentFolderIdValue);
    }
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
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(Platform.isAndroid || Platform.isIOS ? '本机（无本地库）' : '本机'),
                          ),
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
                        Text(
                          '（暂无文件夹）',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        )
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
                      Text(
                        '（暂无文件夹）',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      )
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

  /// 打开集合配置目录（.SlimeWorks）。
  /// 缓存目录按 `<资源父目录>/.SlimeWorks` 规则创建，不一定位于集合根目录，
  /// 因此先搜索整个集合目录树；均未命中时在集合根目录创建后再打开，
  /// 保证导入后无论是否生成过缩略图都能打开。
  void _openCollectionConfigDir(String collectionFolderPath) {
    final dir = media_api.ensureCollectionConfigDir(rootDir: collectionFolderPath);
    if (dir == null) {
      viewModel.showSnack('无法打开配置目录', '集合目录不存在或无法创建 .SlimeWorks 目录：\n$collectionFolderPath');
      return;
    }
    _openFolderInExplorer(dir);
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
    // 层级化平铺（DFS）：一级/二级/三级文件夹均可选，缩进区分层级。
    // availableFolders 已按名称排序，同级文件夹保持名称有序。
    final flat = <(media_api.MediaFolder, int)>[];
    final visited = <String>{};
    void walk(String? parentId, int depth) {
      for (final folder in availableFolders) {
        if (folder.parentId != parentId || visited.contains(folder.id)) {
          continue;
        }
        visited.add(folder.id);
        flat.add((folder, depth));
        walk(folder.id, depth + 1);
      }
    }

    walk(null, 0);
    // 兜底：parentId 无法对应到列表内文件夹的（如远程节点映射）平铺到一级展示
    for (final folder in availableFolders) {
      if (!visited.contains(folder.id)) {
        flat.add((folder, 0));
      }
    }
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
                  ...flat.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.$1.id,
                      // 下拉项处于无界宽度约束，不能用 Flexible/Expanded，
                      // 改用 mainAxisSize.min + 限宽文本防溢出。
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: AppTheme.metrics.kSpace16 * entry.$2),
                          DrawIcon(
                            StrokeIcons.folder,
                            size: scaleW(16),
                            color: Theme.of(context).hintColor,
                          ),
                          SizedBox(width: AppTheme.metrics.kSpace4),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: scaleW(280)),
                            child: Text(entry.$1.name, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
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
    bool clearAppCache = true;
    bool clearResourceCache = true;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('清空媒体库'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('将删除所有本地集合和文件夹记录。原始文件不会被删除，但扫描/导入记录全部清除。'),
                  const SizedBox(height: 12),
                  const Text('可选清除磁盘上的缩略图缓存：', style: TextStyle(fontSize: 13)),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: clearAppCache,
                    onChanged: (v) => setState(() => clearAppCache = v ?? true),
                    title: const Text('清除应用缓存目录缩略图', style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      'library/media/thumbnails/',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: clearResourceCache,
                    onChanged: (v) => setState(() => clearResourceCache = v ?? true),
                    title: const Text(
                      '清除各资源目录 .SlimeWorks/tmp 缩略图',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await viewModel.clearLocalLibrary(
                      clearAppThumbnailCache: clearAppCache,
                      clearResourceThumbnailCache: clearResourceCache,
                    );
                  },
                  child: const Text('清空'),
                ),
              ],
            );
          },
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
    // 远程文件夹：保持原有确认逻辑（节点端默认将集合移到上一级）
    if (viewModel.isRemoteFolder(folderId)) {
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
      return;
    }

    // 文件夹内没有任何集合：不弹窗直接删除
    if (viewModel.collectionCountInFolder(folderId) == 0) {
      await viewModel.deleteFolder(folderId);
      return;
    }

    // 文件夹内有集合：由用户选择处理方式
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除媒体文件夹'),
          content: Text(
            '确定删除“$title”吗？\n文件夹内包含 ${viewModel.collectionCountInFolder(folderId)} 个集合，请选择处理方式：',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteFolder(folderId);
              },
              child: const Text('移到上一级'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await viewModel.deleteFolderWithCollections(folderId);
              },
              child: const Text('直接全部删除(不删原文件)'),
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
          '同时清理各集合目录内的 .SlimeWorks 缓存目录；被清空的集合目录会一并删除（不波及上级目录），'
          '对应集合记录随之移除。确定继续吗？',
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
          '同时清理该集合目录内的 .SlimeWorks 缓存目录；被清空的集合目录会一并删除（不波及上级目录），'
          '对应集合记录随之移除。确定继续吗？',
      confirmLabel: '删除文件',
      confirmColor: Theme.of(context).colorScheme.error,
    );
    if (confirmed) {
      await viewModel.deleteNodeLocalFilesForCollection(collectionId);
    }
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
                  deleteIcon: DrawIcon(StrokeIcons.close, size: AppTheme.metrics.iconSize16),
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppTheme.metrics.kSpace12,
                    vertical: AppTheme.metrics.kSpace8,
                  ),
                ),
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            SizedBox(width: appMetrics.kSpace4),
            IconButton(
              icon: DrawIcon(StrokeIcons.addCircleOutline, size: AppTheme.metrics.iconSize20),
              onPressed: _addKeyword,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: AppTheme.metrics.kSpace32,
                minHeight: AppTheme.metrics.kSpace32,
              ),
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
