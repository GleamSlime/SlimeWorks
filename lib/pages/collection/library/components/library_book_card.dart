import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/pages/collection/library/components/library_book_info_dialog.dart';
import 'package:slime_works/pages/collection/library/components/remote_novel_reader_dialog.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

class LibraryBookCard extends StatefulWidget {
  final NovelMetadata metadata;
  final NovelLibraryViewModel viewModel;
  final bool isSelected;
  final bool isSelecting;
  final bool isLost;

  const LibraryBookCard({
    super.key,
    required this.metadata,
    required this.viewModel,
    this.isSelected = false,
    this.isSelecting = false,
    this.isLost = false,
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
        GlassMenuItem<String>(
          value: 'info',
          label: '书籍信息',
          icon: StrokeIcons.infoOutline,
        ),
        GlassMenuItem<String>(
          value: 'rename',
          label: '重命名',
          icon: StrokeIcons.edit,
        ),
        GlassMenuItem<String>(
          value: 'cover',
          label: '编辑封面',
          icon: StrokeIcons.image,
        ),
        GlassMenuItem<String>(
          value: 'favorite',
          label: meta.isFavorite ? '取消收藏' : '加入收藏',
          icon: meta.isFavorite ? StrokeIcons.star : StrokeIcons.starBorder,
        ),
        GlassMenuItem<String>(
          value: 'move',
          label: '移动到文件夹',
          icon: StrokeIcons.driveFileMove,
        ),
        const PopupMenuDivider(),
        GlassMenuItem<String>(
          value: 'delete',
          label: '删除',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
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
        content: AppTextField(
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
                  DrawIcon(StrokeIcons.home),
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
                      DrawIcon(StrokeIcons.folder),
                      SizedBox(width: AppTheme.metrics.kSpace8),
                      Text(f.name),
                    ],
                  ),
                ),
              ),
          if (foldersToShow.where((f) => f.id != currentFolderId).isEmpty &&
              currentFolderId == null)
            SimpleDialogOption(
              child: Text(
                '暂无文件夹',
                style: AppTextStyles.role(
                  context,
                  fontSize: AppTheme.metrics.fontSize13,
                  color: AppSemantic.of(context).textTertiary,
                ),
              ),
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
            style: TextButton.styleFrom(
              foregroundColor: AppSemantic.of(context).danger.color,
            ),
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
    final s = AppSemantic.of(context);
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        // 页面转场：进场 slow、退场取相邻的 base 一档
        transitionDuration: AppMotion.slow,
        reverseTransitionDuration: AppMotion.base,
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return Stack(
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0, end: 0.22).animate(curved),
                child: Container(color: s.scrim),
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
    final s = AppSemantic.of(context);
    // 卡片所有动效都由 hover 驱动，属反馈类，只允许取 ≤160ms 那一档
    const dur = AppMotion.fast;
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
          side: widget.isSelected ? BorderSide(color: s.accent, width: 2) : BorderSide.none,
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
              decoration: BoxDecoration(color: s.hairline),
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
                                        ? s.scrim.withAlpha(120)
                                        : s.scrim.withAlpha(84),
                                    child: Text(
                                      formatFileSize(widget.metadata.fileSize),
                                      // 压在封面 art 上的白字，明暗两档都不反转
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: appMetrics.fontSize9,
                                        weight: FontWeight.bold,
                                        color: s.onMedia,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: scaleW(8),
                                      vertical: scaleW(4),
                                    ),
                                    color: _hovering
                                        ? s.scrim.withAlpha(120)
                                        : s.scrim.withAlpha(84),
                                    child: Text(
                                      widget.metadata.format.name.toUpperCase(),
                                      // 同为封面 art 上的恒白 chrome
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: appMetrics.fontSize9,
                                        weight: FontWeight.bold,
                                        color: s.onMedia,
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
                                      ? s.scrim.withAlpha(150)
                                      : Colors.transparent,
                                  child: DrawIcon(
                                    widget.metadata.isFavorite
                                        ? StrokeIcons.star
                                        : StrokeIcons.starBorder,
                                    color: widget.metadata.isFavorite
                                        ? s.warning.color
                                        : s.onMediaSecondary,
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
                                          ? s.scrim.withAlpha(120)
                                          : s.scrim.withAlpha(89),
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
                                                      // 标签药丸底：封面上的白色水洗，alpha 沿用原值
                                                      color: s.onMedia.withAlpha(40),
                                                      borderRadius: appMetrics.radius8,
                                                    ),
                                                    child: Text(
                                                      tag,
                                                      style: AppTextStyles.role(
                                                        context,
                                                        fontSize: appMetrics.fontSize9,
                                                        weight: FontWeight.w500,
                                                        color: s.onMedia,
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
                        color: _hovering ? s.scrim.withAlpha(120) : s.scrim.withAlpha(89),
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
                                    backgroundColor: s.scrim.withAlpha(38),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      s.success.color.withAlpha(180),
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
                                        style: AppTextStyles.role(
                                          context,
                                          fontSize: appMetrics.fontSize13,
                                          weight: FontWeight.bold,
                                          color: s.onMedia,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: scaleW(4)),
                                      Text(
                                        widget.metadata.author ?? '',
                                        style: AppTextStyles.role(
                                          context,
                                          fontSize: appMetrics.fontSize11,
                                          color: s.onMediaSecondary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (widget.viewModel.isRemoteNovel(widget.metadata.id)) ...[
                                        SizedBox(height: scaleW(4)),
                                        Text(
                                          '节点: ${widget.viewModel.getNovelNodeName(widget.metadata.id) ?? '未知'}',
                                          // 远程节点属提示类，走 info 而不是随手挑一个浅蓝
                                          style: AppTextStyles.role(
                                            context,
                                            fontSize: appMetrics.fontSize9,
                                            color: s.info.color,
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
                                            // 同理：封面磨砂栏上的白色水洗小底
                                            color: s.onMedia.withAlpha(20),
                                            borderRadius: appMetrics.radius10,
                                          ),
                                          child: Text(
                                            widget.metadata.format.toString(),
                                            style: AppTextStyles.role(
                                              context,
                                              fontSize: appMetrics.fontSize11,
                                              color: s.onMediaSecondary,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: scaleW(8)),
                                        if (widget.metadata.progress > 0)
                                          Flexible(
                                            child: Text(
                                              '${(widget.metadata.progress * 100).toStringAsFixed(0)}% 阅读',
                                              style: AppTextStyles.role(
                                                context,
                                                fontSize: appMetrics.fontSize11,
                                                color: s.onMediaSecondary,
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
                                        ? s.accent
                                        : s.scrim.withAlpha(60),
                                    shape: BoxShape.circle,
                                    // 选中圆点压在封面 art 上，那圈白环不随主题反转
                                    border: Border.all(color: s.onMedia, width: scaleW(2)),
                                  ),
                                  child: widget.isSelected
                                      ? DrawIcon(StrokeIcons.check,
                                          size: scaleW(13),
                                          color: s.accentOn,
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

  /// 封面区：伪封面 > 隐私高斯模糊 > 真实封面
  ///
  /// 整块包在 Obx 里，隐私模式/伪封面任一开关一切换这里就重绘，不用等整个网格重建。
  Widget _buildCoverImage() => Obx(_coverImage);

  Widget _coverImage() {
    // 偏好项必须在任何提前 return 之前读一遍：Obx 本次构建没读到一个 Rx 会直接抛
    // "improper use of Obx"，丢失封面那条分支正好一个都不读。
    final prefs = getIt.isRegistered<MediaPrefsService>()
        ? getIt<MediaPrefsService>()
        : null;
    final fakeOn = prefs?.fakeCover.value ?? false;
    final privacyOn = prefs?.privacyMode.value ?? false;
    final blurSigma = prefs?.privacyBlurSigma.value ?? 15.0;
    // 网格封面按预览宽度解码，避免每张原图（可达数 MB）整幅进内存
    final previewWidth = prefs?.localPreviewWidth.value ?? 480;
    final cacheWidth = previewWidth > 0 ? previewWidth : null;
    if (widget.isLost && widget.metadata.coverPath != null) {
      return Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildDefaultCover(),
            Positioned(
              left: AppTheme.metrics.kSpace8,
              top: AppTheme.metrics.kSpace8,
              child: LostBadge(),
            ),
          ],
        ),
      );
    }
    // 伪封面排在真实封面之前：直接换成那张无害图片，真实封面连解码都不参与
    if (fakeOn && widget.metadata.coverPath != null) {
      return Positioned.fill(child: const FakeCover());
    }
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
              duration: AppMotion.fast,
              curve: Curves.easeOut,
              child: Hero(
                tag: 'book_cover_${widget.metadata.id}',
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                ),
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
              duration: AppMotion.fast,
              curve: Curves.easeOut,
              child: Hero(
                tag: 'book_cover_${widget.metadata.id}',
                child: Image.file(
                  file,
                  key: ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}'),
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
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
                    color: AppSemantic.of(context).scrim.withAlpha(120),
                    borderRadius: AppTheme.metrics.radius999,
                  ),
                  child: DrawIcon(StrokeIcons.lockOutline,
                    size: AppTheme.metrics.iconSize16,
                    // 隐私锁徽标压在封面 blur 之上的深色圆底里，白字档同理不反转
                    color: AppSemantic.of(context).onMediaSecondary,
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
        color: AppSemantic.of(context).border,
        child: Center(
          // 这是占位封面，本身要压得住 art 上的白字，所以图标走媒体 chrome 档而非主题语义色
          child: DrawIcon(
            StrokeIcons.book,
            size: scaleW(40),
            color: AppSemantic.of(context).onMediaSecondary,
          ),
        ),
      ),
    );
  }
}
