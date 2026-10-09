import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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
      // 圆角/投影这里不再各写一份：popupMenuTheme 就是全站浮层的口径。
      items: [
        GlassMenuItem<void>(
          label: '重命名',
          icon: StrokeIcons.driveFileRenameOutline,
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) => _showRenameDialog(ctx)),
        ),
        GlassMenuItem<void>(
          label: '删除文件夹',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
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
        content: AppTextField(
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
            style: FilledButton.styleFrom(
              backgroundColor: AppSemantic.of(dlgCtx).danger.color,
            ),
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
    final s = AppSemantic.of(context);
    final accent = s.accent;
    // 拖放目标/文件夹身份统一走 info 这一族，和拖拽浮影、幽灵占位同色
    final dropTint = s.info.color;
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
                ? BorderSide(color: dropTint, width: scaleW(2))
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
                        ? [dropTint.withAlpha(60), dropTint.withAlpha(30)]
                        : [accent.withAlpha(40), accent.withAlpha(20)],
                  ),
                ),
                // Obx 包一层：隐私模式 / 伪封面开关一切换，封面格立刻重绘，不用等整页重建
                child: Obx(() {
                  final coverPaths = widget.viewModel.getFolderCovers(widget.folder.id);
                  final prefs = getIt.isRegistered<MediaPrefsService>()
                      ? getIt<MediaPrefsService>()
                      : null;
                  final fakeOn = prefs?.fakeCover.value ?? false;
                  final privacyOn = prefs?.privacyMode.value ?? false;
                  final blurSigma = prefs?.privacyBlurSigma.value ?? 15.0;
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
                                        // 九宫格里每格只有几十像素宽，按显示尺寸解码
                                        child: Image.file(
                                          coverFile,
                                          fit: BoxFit.cover,
                                          cacheWidth: 200,
                                        ),
                                      );
                                    }
                                  }
                                  return Expanded(
                                    child: Container(
                                      // 空位格用封面 chrome 的白洗在强调底上做混合
                                      color: Color.alphaBlend(s.onMedia.withAlpha(200), accent),
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
                                        child: Image.file(
                                          coverFile,
                                          fit: BoxFit.cover,
                                          cacheWidth: 200,
                                        ),
                                      );
                                    }
                                  }
                                  return Expanded(
                                    child: Container(
                                      // 空位格用封面 chrome 的白洗在强调底上做混合
                                      color: Color.alphaBlend(s.onMedia.withAlpha(200), accent),
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
                              // 走 scrim 的色底，两个 alpha 只是这条渐变的起收
                              colors: [s.scrim.withAlpha(100), s.scrim.withAlpha(180)],
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
                    // 伪封面：整块九宫格换成那张无害图片，真实封面连解码都不参与
                    if (fakeOn) return const FakeCover();
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
                                  color: s.scrim.withAlpha(120),
                                  borderRadius: AppTheme.metrics.radius999,
                                ),
                                child: DrawIcon(StrokeIcons.lockOutline,
                                  size: AppTheme.metrics.iconSize16,
                                  // 锁徽标压在封面 blur 上的深色圆底里，白档不随主题反转
                                  color: s.onMediaSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return grid;
                  }
                  // Obx 的构建器必须返回 Widget，原来 IIFE 返回 null 的位置换成空占位
                  return const SizedBox.shrink();
                }),
              ),

              // 文件夹内容（图标+名称），使用Column居中
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 文件夹图标
                    DrawIcon(StrokeIcons.folder,
                      size: scaleW(56),
                      // 常态白压在封面九宫格上，属媒体 chrome；悬停态仍走主题 info
                      color: widget.isBookHover
                          ? dropTint.withAlpha(220)
                          : s.onMedia.withAlpha(220),
                    ),
                    SizedBox(height: appMetrics.kSpace8),
                    // 文件夹名称 / 拖放提示
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace8),
                      child: _isEditing
                          ? AppTextField(
                              controller: _editController,
                              focusNode: _editFocusNode,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.role(
                                context,
                                fontSize: appMetrics.fontSize11,
                                weight: FontWeight.w600,
                                // 底恒白，字就必须恒深：吃主题字色会在暗档变成白字白底
                                color: s.onMediaInk,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                // 就地改名框恒为白底（压在封面上），不随主题反转
                                fillColor: s.onMedia,
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
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: appMetrics.fontSize11,
                                  weight: FontWeight.w600,
                                  // 悬停提示走主题 info，常态名压在封面上走恒白 chrome
                                  color: widget.isBookHover ? dropTint : s.onMedia,
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
                        style: AppTextStyles.role(
                          context,
                          fontSize: appMetrics.fontSize9,
                          color: s.onMedia.withAlpha(220),
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
                        color: s.scrim.withAlpha(60),
                        shape: BoxShape.circle,
                      ),
                      child: DrawIcon(StrokeIcons.moreVert,
                        // 圆盒是宽度族固定尺寸，符号也跟着走宽度族，否则字号滑杆一拉就顶出去
                        size: scaleW(13),
                        // 按钮底是封面之上的深色磨砂圈，图标走恒白 chrome
                        color: s.onMedia,
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
                      color: widget.isSelected ? accent : s.scrim.withAlpha(60),
                      shape: BoxShape.circle,
                      // 选中环压在封面 art 上，白环不随主题反转
                      border: Border.all(color: s.onMedia, width: scaleW(2)),
                    ),
                    child: widget.isSelected
                        // 勾压在强调底上，明暗两档要跟着反相
                        ? DrawIcon(StrokeIcons.check, size: scaleW(13), color: s.accentOn)
                        : null,
                  ),
                ),

              // Hover 遮罩（封面图上的白色水洗提亮，不随主题反转）
              if (_hovering && !widget.isSelecting && !widget.isBookHover)
                Container(decoration: BoxDecoration(color: s.onMedia.withAlpha(10))),

              // 拖放入文件夹时的半透明高亮遮罩
              if (widget.isBookHover)
                Container(
                  decoration: BoxDecoration(color: dropTint.withAlpha(20)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
