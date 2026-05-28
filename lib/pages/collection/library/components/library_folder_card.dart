import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryFolderCard extends StatefulWidget {
  final NovelFolder folder;
  final NovelLibraryViewModel viewModel;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  /// 当前有书籍被拖拽悬停在此文件夹上
  final bool isBookHover;
  final bool isLost;

  const LibraryFolderCard({
    super.key,
    required this.folder,
    required this.viewModel,
    required this.isSelected,
    required this.isSelecting,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onTap,
    this.isBookHover = false,
    this.isLost = false,
  });

  @override
  State<LibraryFolderCard> createState() => _LibraryFolderCardState();
}

class _LibraryFolderCardState extends State<LibraryFolderCard> {
  bool _hovering = false;
  bool _isEditing = false;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;

  bool get _isRemoteVirtualFolder => widget.folder.id.startsWith('remote-folder:');

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
    _editFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _editFocusNode.removeListener(_onFocusChange);
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_editFocusNode.hasFocus && _isEditing) {
      _saveRename();
    }
  }

  void _startEditing() {
    if (widget.isSelecting || _isRemoteVirtualFolder) return;
    setState(() {
      _isEditing = true;
      _editController.text = widget.folder.name;
    });
    // 延迟聚焦以确保TextField已构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _saveRename() {
    final newName = _editController.text.trim();
    setState(() => _isEditing = false);
    if (newName.isNotEmpty && newName != widget.folder.name) {
      widget.viewModel.renameFolder(widget.folder.id, newName);
    }
  }

  /// 在鼠标位置弹出菜单
  void _showContextMenu(BuildContext ctx, Offset globalPos) {
    if (_isRemoteVirtualFolder) {
      return;
    }
    // 先尝试关闭可能存在的菜单，再打开新的菜单（避免多个菜单同时存在）
    try {
      Navigator.of(ctx).maybePop();
    } catch (_) {}
    // 将全局坐标转换到 Overlay 局部坐标系，避免 ScreenUtil 变换造成右偏
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final localPos = overlay.globalToLocal(globalPos);
    final overlaySize = overlay.size;
    showMenu(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPos.dx, localPos.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: appMetrics.radius8),
      items: [
        PopupMenuItem(
          padding: EdgeInsets.symmetric(
            horizontal: appMetrics.kSpace12,
            vertical: appMetrics.kSpace4,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline, size: appMetrics.fontSize15),
                SizedBox(width: appMetrics.kSpace12),
                const Text('重命名'),
              ],
            ),
          ),
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => _showRenameDialog(ctx)),
        ),
        PopupMenuItem(
          padding: EdgeInsets.symmetric(
            horizontal: appMetrics.kSpace12,
            vertical: appMetrics.kSpace4,
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: appMetrics.fontSize15,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                SizedBox(width: appMetrics.kSpace12),
                Text('删除文件夹', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ),
          ),
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => _confirmDelete(ctx)),
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext ctx) {
    final controller = TextEditingController(text: widget.folder.name);
    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入文件夹名称', border: OutlineInputBorder()),
          onSubmitted: (_) => _doRename(dlgCtx, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          FilledButton(
            onPressed: () => _doRename(dlgCtx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _doRename(BuildContext dlgCtx, String name) {
    if (name.isEmpty) return;
    Navigator.pop(dlgCtx);
    widget.viewModel.renameFolder(widget.folder.id, name);
  }

  void _confirmDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: const Text('是否同时删除文件夹内的所有书籍？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(dlgCtx);
              widget.viewModel.deleteFolder(widget.folder.id);
            },
            child: const Text('仅删除文件夹'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dlgCtx).colorScheme.error),
            onPressed: () {
              Navigator.pop(dlgCtx);
              widget.viewModel.deleteFolderWithNovels(widget.folder.id);
            },
            child: const Text('删除文件夹及书籍'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final folderBookCount = widget.viewModel.getFolderNovelCount(widget.folder.id);

    return GestureDetector(
      onTap: widget.isSelecting || _isEditing ? null : widget.onTap,
      onLongPress: _isEditing || _isRemoteVirtualFolder ? null : widget.onLongPress,
      onSecondaryTapDown: _isEditing || _isRemoteVirtualFolder
          ? null
          : (d) => _showContextMenu(context, d.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: appMetrics.radius8,
            side: widget.isSelected
                ? BorderSide(color: accent, width: scaleW(2))
                : widget.isBookHover
                ? BorderSide(color: theme.colorScheme.tertiary, width: scaleW(2))
                : BorderSide.none,
          ),
          child: Stack(
            children: [
              // 背景渐变或封面图片
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isBookHover
                        ? [
                            theme.colorScheme.tertiary.withAlpha(60),
                            theme.colorScheme.tertiary.withAlpha(30),
                          ]
                        : [accent.withAlpha(40), accent.withAlpha(20)],
                  ),
                ),
                child: () {
                  final coverPaths = widget.viewModel.getFolderCovers(widget.folder.id);
                  final privacyOn = getIt.isRegistered<MediaPrefsService>()
                      ? getIt<MediaPrefsService>().privacyMode.value
                      : false;
                  final blurSigma = getIt.isRegistered<MediaPrefsService>()
                      ? getIt<MediaPrefsService>().privacyBlurSigma.value
                      : 15.0;
                  if (!widget.isBookHover && coverPaths.isNotEmpty) {
                    final grid = Stack(
                      fit: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: List.generate(3, (col) {
                                  final idx = col;
                                  if (idx < coverPaths.length) {
                                    final coverFile = File(coverPaths[idx]);
                                    if (coverFile.existsSync()) {
                                      return Expanded(
                                        child: Image.file(coverFile, fit: BoxFit.cover),
                                      );
                                    }
                                  }
                                  return Expanded(
                                    child: Container(
                                      color: Color.alphaBlend(Colors.white.withAlpha(200), accent),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: List.generate(3, (col) {
                                  final idx = 3 + col;
                                  if (idx < coverPaths.length) {
                                    final coverFile = File(coverPaths[idx]);
                                    if (coverFile.existsSync()) {
                                      return Expanded(
                                        child: Image.file(coverFile, fit: BoxFit.cover),
                                      );
                                    }
                                  }
                                  return Expanded(
                                    child: Container(
                                      color: Color.alphaBlend(Colors.white.withAlpha(200), accent),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withAlpha(100), Colors.black.withAlpha(180)],
                            ),
                          ),
                        ),
                      ],
                    );
                    if (widget.isLost) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          grid,
                          Positioned(
                            left: AppTheme.metrics.kSpace8,
                            top: AppTheme.metrics.kSpace8,
                            child: LostBadge(),
                          ),
                        ],
                      );
                    }
                    if (privacyOn) {
                      return ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            grid,
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                              child: Container(color: Colors.transparent),
                            ),
                            Center(
                              child: Container(
                                padding: EdgeInsets.all(AppTheme.metrics.kSpace6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(120),
                                  borderRadius: AppTheme.metrics.radius999,
                                ),
                                child: Icon(
                                  Icons.lock_outline,
                                  size: AppTheme.metrics.iconSize16,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return grid;
                  }
                  return null;
                }(),
              ),

              // 文件夹内容（图标+名称），使用Column居中
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 文件夹图标
                    Icon(
                      Icons.folder_rounded,
                      size: scaleW(56),
                      color: widget.isBookHover
                          ? theme.colorScheme.tertiary.withAlpha(220)
                          : Colors.white.withAlpha(220),
                    ),
                    SizedBox(height: appMetrics.kSpace8),
                    // 文件夹名称 / 拖放提示
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace8),
                      child: _isEditing
                          ? TextField(
                              controller: _editController,
                              focusNode: _editFocusNode,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: appMetrics.fontSize11,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: appMetrics.radius4,
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: appMetrics.kSpace4,
                                  vertical: appMetrics.kSpace4,
                                ),
                              ),
                              onSubmitted: (_) => _saveRename(),
                            )
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.isSelecting || widget.isBookHover
                                  ? null
                                  : () {}, // 空handler阻止事件冒泡到外层
                              onDoubleTap: widget.isSelecting || widget.isBookHover
                                  ? null
                                  : _startEditing,
                              child: Text(
                                widget.isBookHover ? '放入此文件夹' : widget.folder.name,
                                style: TextStyle(
                                  fontSize: appMetrics.fontSize11,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isBookHover
                                      ? theme.colorScheme.tertiary
                                      : Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                    ),
                    if (!_isEditing && !widget.isBookHover) ...[
                      SizedBox(height: appMetrics.kSpace4),
                      Text(
                        '$folderBookCount 本',
                        style: TextStyle(
                          fontSize: appMetrics.fontSize9,
                          color: Colors.white.withAlpha(220),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Hover 右上角操作按钮（非选择模式）
              if (_hovering &&
                  !widget.isSelecting &&
                  !widget.isBookHover &&
                  !_isRemoteVirtualFolder)
                Positioned(
                  top: appMetrics.kSpace4,
                  right: appMetrics.kSpace4,
                  child: Listener(
                    // 用 Listener 而非 GestureDetector，绕过 Draggable 的手势竞争
                    onPointerDown: (e) => _showContextMenu(context, e.position),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: EdgeInsets.all(appMetrics.kSpace4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(60),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.more_vert,
                        size: appMetrics.fontSize13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              // 选中状态 overlay（右上角）
              if (widget.isSelecting)
                Positioned(
                  top: appMetrics.kSpace4 + scaleW(2),
                  right: appMetrics.kSpace4 + scaleW(2),
                  child: Container(
                    width: scaleW(22),
                    height: scaleW(22),
                    decoration: BoxDecoration(
                      color: widget.isSelected ? accent : Colors.black.withAlpha(60),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: scaleW(2)),
                    ),
                    child: widget.isSelected
                        ? Icon(Icons.check, size: appMetrics.fontSize13, color: Colors.white)
                        : null,
                  ),
                ),

              // Hover 遮罩
              if (_hovering && !widget.isSelecting && !widget.isBookHover)
                Container(decoration: BoxDecoration(color: Colors.white.withAlpha(10))),

              // 拖放入文件夹时的半透明高亮遮罩
              if (widget.isBookHover)
                Container(
                  decoration: BoxDecoration(color: theme.colorScheme.tertiary.withAlpha(20)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
