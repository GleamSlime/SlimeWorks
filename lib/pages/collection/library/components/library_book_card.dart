import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/library/components/library_book_info_dialog.dart';
import 'package:slime_works/pages/collection/library/components/remote_novel_reader_dialog.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryBookCard extends StatefulWidget {
  final NovelMetadata metadata;
  final NovelLibraryViewModel viewModel;
  final bool isSelected;
  final bool isSelecting;

  const LibraryBookCard({
    super.key,
    required this.metadata,
    required this.viewModel,
    this.isSelected = false,
    this.isSelecting = false,
  });

  @override
  State<LibraryBookCard> createState() => _LibraryBookCardState();
}

class _LibraryBookCardState extends State<LibraryBookCard> {
  bool _hovering = false;

  void _onTagTap(String tag) {
    widget.viewModel.filterBySingleTag(tag);
  }

  void _onTap() {
    if (widget.isSelecting) {
      widget.viewModel.toggleSelection(widget.metadata.id);
      return;
    }
    if (widget.viewModel.isRemoteNovel(widget.metadata.id)) {
      _showRemoteReaderDialog(context);
      return;
    }
    NovelReaderRoute($extra: widget.metadata).go(context);
    widget.viewModel.loadNovels();
  }

  void _onLongPress() {
    if (!widget.isSelecting) {
      widget.viewModel.enterSelection(widget.metadata.id);
    }
  }

  // ── 右键菜单 ──────────────────────────────────────────────────────────────

  void _showContextMenu(BuildContext ctx, Offset globalPos) async {
    // 将全局坐标转换到 Overlay 的局部坐标系，避免 ScreenUtil 等变换导致偏移
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final localPos = overlay.globalToLocal(globalPos);
    final overlaySize = overlay.size;
    final meta = widget.metadata;
    final result = await showMenu<String>(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(localPos.dx, localPos.dy, 1, 1),
        Offset.zero & overlaySize,
      ),
      items: [
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: scaleW(18)),
              SizedBox(width: scaleW(8)),
              const Text('书籍信息'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: scaleW(18)),
              SizedBox(width: scaleW(8)),
              const Text('重命名'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'cover',
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: scaleW(18)),
              SizedBox(width: scaleW(8)),
              const Text('编辑封面'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                meta.isFavorite ? Icons.star : Icons.star_border,
                size: scaleW(18),
                color: meta.isFavorite ? Colors.amber : null,
              ),
              SizedBox(width: scaleW(8)),
              Text(meta.isFavorite ? '取消收藏' : '加入收藏'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'move',
          child: Row(
            children: [
              Icon(Icons.drive_file_move_outlined, size: scaleW(18)),
              SizedBox(width: scaleW(8)),
              const Text('移动到文件夹'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outlined,
                size: scaleW(18),
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(width: scaleW(8)),
              Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ],
    );
    if (!ctx.mounted) return;
    switch (result) {
      case 'info':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showInfoDialog(context);
        });
        break;
      case 'rename':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showRenameDialog(context);
        });
        break;
      case 'cover':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pickAndSetCover(context);
        });
        break;
      case 'favorite':
        await widget.viewModel.toggleFavorite(widget.metadata.id);
        break;
      case 'move':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) _showMoveFolderDialog(ctx);
        });
        break;
      case 'delete':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) _confirmDelete(ctx);
        });
        break;
    }
  }

  void _showRenameDialog(BuildContext ctx) {
    final controller = TextEditingController(text: widget.metadata.title);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        title: const Text('重命名书籍'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新的书名'),
          onSubmitted: (_) async {
            final title = controller.text.trim();
            if (ctx2.mounted) Navigator.of(ctx2).pop();
            await widget.viewModel.renameNovel(widget.metadata.id, title);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (ctx2.mounted) Navigator.of(ctx2).pop();
              await widget.viewModel.renameNovel(widget.metadata.id, title);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showMoveFolderDialog(BuildContext ctx) async {
    final vm = widget.viewModel;
    final currentFolderId = widget.metadata.folderId;
    // 如果当前在文件夹内，显示该文件夹的子文件夹；否则显示所有顶级文件夹
    final contextFolderId = vm.currentFolderId.value;
    final List<NovelFolder> foldersToShow = contextFolderId != null
        ? vm.getChildFolders(contextFolderId)
        : vm.folders.where((f) => f.parentId == null).toList();

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx2) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          if (currentFolderId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx2).pop('__ROOT__'),
              child: Row(
                children: [
                  const Icon(Icons.home_outlined),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  const Text('移回根目录'),
                ],
              ),
            ),
          ...foldersToShow
              .where((f) => f.id != currentFolderId)
              .map(
                (f) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx2).pop(f.id),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      SizedBox(width: AppTheme.metrics.kSpace8),
                      Text(f.name),
                    ],
                  ),
                ),
              ),
          if (foldersToShow.where((f) => f.id != currentFolderId).isEmpty &&
              currentFolderId == null)
            SimpleDialogOption(
              child: Text('暂无文件夹', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            ),
        ],
      ),
    );
    if (result == null) return;
    await vm.moveNovelToFolder(widget.metadata.id, result == '__ROOT__' ? null : result);
  }

  void _confirmDelete(BuildContext ctx) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx2) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定要删除《${widget.metadata.title}》吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: const Text('取消')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              Navigator.of(ctx2).pop();
              widget.viewModel.deleteNovel(widget.metadata.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ── 编辑封面 ───────────────────────────────────────────────────────────────

  Future<void> _pickAndSetCover(BuildContext ctx) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    await widget.viewModel.updateNovelCover(widget.metadata.id, path);
  }

  // ── 书籍信息弹层 ───────────────────────────────────────────────────────────

  void _showInfoDialog(BuildContext ctx) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dlgCtx) =>
          LibraryBookInfoDialog(metadata: widget.metadata, viewModel: widget.viewModel),
    );
  }

  void _showRemoteReaderDialog(BuildContext ctx) {
    final nodeId = widget.viewModel.getRemoteNodeId(widget.metadata.id);
    final nodeName = widget.viewModel.getNovelNodeName(widget.metadata.id);
    if (nodeId == null || nodeName == null) {
      return;
    }

    if (PlatformUtil.isMobile) {
      _pushBookOpenRoute(
        RemoteNovelReaderPage(metadata: widget.metadata, nodeId: nodeId, nodeName: nodeName),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dlgCtx) =>
          RemoteNovelReaderDialog(metadata: widget.metadata, nodeId: nodeId, nodeName: nodeName),
    );
  }

  void _pushBookOpenRoute(Widget page) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return Stack(
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0, end: 0.22).animate(curved),
                child: Container(color: Colors.black),
              ),
              ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
                child: FadeTransition(opacity: curved, child: child),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    const dur = Duration(milliseconds: 200);
    const curve = Curves.easeOut;

    return AnimatedScale(
      scale: _hovering ? 1.03 : 1.0,
      duration: dur,
      curve: curve,
      child: Card(
        elevation: _hovering ? 4 : 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: appMetrics.radius8,
          side: widget.isSelected ? BorderSide(color: accent, width: 2) : BorderSide.none,
        ),
        child: InkWell(
          onTap: _onTap,
          onLongPress: _onLongPress,
          onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant),
              child: Stack(
                children: [
                  // 封面作为整个卡片背景
                  if (widget.metadata.coverPath != null)
                    _buildCoverImage()
                  else
                    _buildDefaultCover(),

                  // 格式标签（右上角磨砂玻璃，hover 时缩放淡入）
                  if (!widget.isSelecting)
                    Positioned(
                      top: scaleW(8),
                      right: scaleW(8),
                      child: AnimatedOpacity(
                        opacity: _hovering ? 1.0 : 0.7,
                        duration: dur,
                        curve: curve,
                        child: AnimatedScale(
                          scale: _hovering ? 1.0 : 0.85,
                          duration: dur,
                          curve: curve,
                          child: ClipRRect(
                            borderRadius: appMetrics.radius12,
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                              child: Row(
                                spacing: appMetrics.kSpace2,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: scaleW(8),
                                      vertical: scaleW(4),
                                    ),
                                    color: _hovering
                                        ? Colors.black.withAlpha(120)
                                        : Colors.black.withAlpha(84),
                                    child: Text(
                                      formatFileSize(widget.metadata.fileSize),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: appMetrics.fontSize9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: scaleW(8),
                                      vertical: scaleW(4),
                                    ),
                                    color: _hovering
                                        ? Colors.black.withAlpha(120)
                                        : Colors.black.withAlpha(84),
                                    child: Text(
                                      widget.metadata.format.name.toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: appMetrics.fontSize9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 收藏图标（左上角）
                  if (!widget.isSelecting)
                    Positioned(
                      top: scaleW(8),
                      left: scaleW(8),
                      child: AnimatedOpacity(
                        opacity: (_hovering || PlatformUtil.isMobile)
                            ? 1.0
                            : (widget.metadata.isFavorite ? 0.9 : 0.0),
                        duration: dur,
                        curve: curve,
                        child: AnimatedScale(
                          scale: (_hovering || PlatformUtil.isMobile) ? 1.0 : 0.7,
                          duration: dur,
                          curve: curve,
                          child: GestureDetector(
                            onTap: () => widget.viewModel.toggleFavorite(widget.metadata.id),
                            child: ClipRRect(
                              borderRadius: appMetrics.radius12,
                              child: TweenAnimationBuilder<double>(
                                duration: dur,
                                curve: curve,
                                tween: Tween(
                                  begin: _hovering ? 8.0 : 0.0,
                                  end: _hovering ? 0.0 : 8.0,
                                ),
                                builder: (_, sigma, child) => BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                                  child: child,
                                ),
                                child: Container(
                                  padding: EdgeInsets.all(scaleW(4)),
                                  color: _hovering
                                      ? Colors.black.withAlpha(150)
                                      : Colors.transparent,
                                  child: Icon(
                                    widget.metadata.isFavorite
                                        ? Icons.star_sharp
                                        : Icons.star_border_sharp,
                                    color: widget.metadata.isFavorite
                                        ? Colors.amber
                                        : Colors.white70,
                                    size: scaleW(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: dur,
                      curve: curve,
                      height: _hovering ? scaleW(145) : scaleW(95),
                      clipBehavior: Clip.none,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 标签展示（进度条上方，前5个）
                          Positioned(
                            top: 0,
                            left: scaleW(8),
                            right: scaleW(8),
                            child: Align(
                              alignment: Alignment.topRight,
                              child: ClipRRect(
                                borderRadius: appMetrics.radius12,
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: scaleW(6),
                                      vertical: scaleW(2),
                                    ),
                                    decoration: BoxDecoration(
                                      color: _hovering
                                          ? Colors.black.withAlpha(120)
                                          : Colors.black.withAlpha(89),
                                      borderRadius: appMetrics.radius12,
                                    ),
                                    child: Builder(
                                      builder: (context) {
                                        final chapterCount = widget.viewModel.getNovelChapterCount(
                                          widget.metadata.id,
                                        );
                                        final displayTags = <String>[
                                          ...widget.metadata.tags.take(3),
                                          '章节 ${chapterCount ?? '--'}',
                                        ];

                                        return Wrap(
                                          spacing: scaleW(4),
                                          runSpacing: scaleW(2),
                                          alignment: WrapAlignment.end,
                                          children: displayTags
                                              .map(
                                                (tag) => GestureDetector(
                                                  onTap: tag.startsWith('章节 ')
                                                      ? null
                                                      : () => _onTagTap(tag),
                                                  child: Container(
                                                    padding: EdgeInsets.symmetric(
                                                      horizontal: scaleW(5),
                                                      vertical: scaleW(1),
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withAlpha(40),
                                                      borderRadius: appMetrics.radius8,
                                                    ),
                                                    child: Text(
                                                      tag,
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: appMetrics.fontSize9,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(growable: false),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 底部磨砂栏：hover 时通过高度动画展开 + 模糊渐清晰
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: TweenAnimationBuilder<double>(
                      duration: dur,
                      curve: curve,
                      tween: Tween(begin: _hovering ? 6.0 : 3.0, end: _hovering ? 3.0 : 6.0),
                      builder: (_, blurSigma, child) => ClipRRect(
                        borderRadius: BorderRadius.only(
                          bottomLeft: appMetrics.radius8.bottomLeft,
                          bottomRight: appMetrics.radius8.bottomRight,
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                          child: child,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: dur,
                        curve: curve,
                        height: _hovering ? scaleW(120) : scaleW(70),
                        color: _hovering ? Colors.black.withAlpha(120) : Colors.black.withAlpha(89),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 阅读进度条
                            if (widget.metadata.progress > 0)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: SizedBox(
                                  height: scaleW(4),
                                  child: LinearProgressIndicator(
                                    value: widget.metadata.progress,
                                    backgroundColor: Colors.black.withAlpha(38),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.greenAccent.withAlpha(180),
                                    ),
                                  ),
                                ),
                              ),

                            // 标题和作者
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: AnimatedSlide(
                                offset: _hovering ? Offset.zero : const Offset(0, 0.05),
                                duration: dur,
                                curve: curve,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: scaleW(8),
                                    vertical: scaleW(8),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.metadata.title,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: appMetrics.fontSize13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: scaleW(4)),
                                      Text(
                                        widget.metadata.author ?? '',
                                        style: TextStyle(
                                          fontSize: appMetrics.fontSize11,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (widget.viewModel.isRemoteNovel(widget.metadata.id)) ...[
                                        SizedBox(height: scaleW(4)),
                                        Text(
                                          '节点: ${widget.viewModel.getNovelNodeName(widget.metadata.id) ?? '未知'}',
                                          style: TextStyle(
                                            fontSize: appMetrics.fontSize9,
                                            color: Colors.lightBlueAccent,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // 额外信息（进度/格式），hover 时淡入滑入
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: AnimatedOpacity(
                                opacity: _hovering ? 1.0 : 0.0,
                                duration: dur,
                                curve: curve,
                                child: AnimatedSlide(
                                  offset: _hovering ? Offset.zero : const Offset(0, 0.3),
                                  duration: dur,
                                  curve: curve,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: scaleW(8),
                                      vertical: scaleW(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: scaleW(6),
                                            vertical: scaleW(2),
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withAlpha(20),
                                            borderRadius: appMetrics.radius10,
                                          ),
                                          child: Text(
                                            widget.metadata.format.toString(),
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: appMetrics.fontSize11,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: scaleW(8)),
                                        if (widget.metadata.progress > 0)
                                          Flexible(
                                            child: Text(
                                              '${(widget.metadata.progress * 100).toStringAsFixed(0)}% 阅读',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: appMetrics.fontSize11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 选中状态 overlay（右上角）
                            if (widget.isSelecting)
                              Positioned(
                                top: scaleW(6),
                                right: scaleW(6),
                                child: Container(
                                  width: scaleW(22),
                                  height: scaleW(22),
                                  decoration: BoxDecoration(
                                    color: widget.isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black.withAlpha(60),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: widget.isSelected
                                      ? Icon(
                                          Icons.check,
                                          size: appMetrics.fontSize13,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
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

  Widget _buildCoverImage() {
    final privacyOn = getIt.isRegistered<MediaPrefsService>()
        ? getIt<MediaPrefsService>().privacyMode.value
        : false;
    final blurSigma = getIt.isRegistered<MediaPrefsService>()
        ? getIt<MediaPrefsService>().privacyBlurSigma.value
        : 15.0;
    try {
      final coverPath = widget.metadata.coverPath;
      Widget coverWidget;
      if (coverPath != null && coverPath.startsWith('data:image/')) {
        final commaIndex = coverPath.indexOf(',');
        if (commaIndex > 0 && commaIndex < coverPath.length - 1) {
          final encoded = coverPath.substring(commaIndex + 1);
          final bytes = base64Decode(encoded);
          coverWidget = ClipRect(
            child: AnimatedScale(
              scale: _hovering ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Hero(
                tag: 'book_cover_${widget.metadata.id}',
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
          );
        } else {
          coverWidget = _buildDefaultCover();
        }
      } else if (widget.metadata.coverPath != null) {
        final file = File(widget.metadata.coverPath!);
        if (file.existsSync()) {
          coverWidget = ClipRect(
            child: AnimatedScale(
              scale: _hovering ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Hero(
                tag: 'book_cover_${widget.metadata.id}',
                child: Image.file(
                  file,
                  key: ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        } else {
          coverWidget = _buildDefaultCover();
        }
      } else {
        coverWidget = _buildDefaultCover();
      }

      if (privacyOn && widget.metadata.coverPath != null) {
        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              coverWidget,
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                  child: Container(color: Colors.transparent),
                ),
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
      return Positioned.fill(child: coverWidget);
    } catch (_) {}
    return Positioned.fill(child: _buildDefaultCover());
  }

  Widget _buildDefaultCover() {
    return Hero(
      tag: 'book_cover_${widget.metadata.id}',
      child: Container(
        color: Theme.of(context).colorScheme.outline,
        child: Center(
          child: Icon(Icons.book, size: scaleW(40), color: Colors.white70),
        ),
      ),
    );
  }
}
