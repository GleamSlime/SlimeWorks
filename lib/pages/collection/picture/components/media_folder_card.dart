import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class MediaFolderCard extends StatefulWidget {
  const MediaFolderCard({
    super.key,
    required this.folder,
    required this.coverSource,
    required this.itemCount,
    required this.resourceCount,
    required this.totalSize,
    required this.typeLabel,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onRename,
    required this.onDelete,
    required this.isRemote,
    required this.nodeName,
    this.onTransfer,
    this.onPullToLocal,
    this.onDeleteNodeFiles,
    this.isLost = false,
  });

  final media_api.MediaFolder folder;
  final String? coverSource;

  /// 点开该文件夹能看到的卡片数（子文件夹 + 本层集合）
  final int itemCount;

  /// 子树内仍然存在的资源条数
  final int resourceCount;

  /// 子树内仍然存在的资源体积
  final BigInt totalSize;

  /// 卡片类型徽章：文件夹 / 同名分组 / 远程文件夹
  final String typeLabel;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool isRemote;
  final String? nodeName;
  final VoidCallback? onTransfer;
  final VoidCallback? onPullToLocal;
  final VoidCallback? onDeleteNodeFiles;
  final bool isLost;

  @override
  State<MediaFolderCard> createState() => _MediaFolderCardState();
}

class _MediaFolderCardState extends State<MediaFolderCard> {
  bool _hovering = false;

  Worker? _privacyWorker;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>() ? getIt.get<MediaPrefsService>() : null;
    if (prefs != null) {
      _privacyWorker = ever(prefs.privacyMode, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _privacyWorker?.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset globalPosition) async {
    final overlayState = Overlay.of(context);
    final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
    final localPos = overlayBox.globalToLocal(globalPosition);
    final overlaySize = overlayBox.size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx,
        localPos.dy,
        overlaySize.width - localPos.dx,
        overlaySize.height - localPos.dy,
      ),
      items: [
        GlassMenuItem<String>(
          value: 'rename',
          label: '重命名文件夹',
          icon: StrokeIcons.driveFileRenameOutline,
        ),
        if (widget.onTransfer != null)
          GlassMenuItem<String>(
            value: 'transfer',
            label: '转移集合到...',
            icon: StrokeIcons.driveFolderUpload,
          ),
        if (widget.isRemote && widget.onPullToLocal != null)
          GlassMenuItem<String>(
            value: 'pull_to_local',
            label: '拉取到本地',
            icon: StrokeIcons.download,
          ),
        if (PlatformUtil.isMobile)
          GlassMenuItem<String>(
            value: 'select',
            label: '进入多选',
            icon: StrokeIcons.checklist,
          ),
        const PopupMenuDivider(),
        if (widget.isRemote && widget.onDeleteNodeFiles != null)
          GlassMenuItem<String>(
            value: 'delete_node_files',
            label: '删除节点本地文件',
            icon: StrokeIcons.cloudOff,
            destructive: true,
          ),
        GlassMenuItem<String>(
          value: 'delete',
          label: '删除文件夹',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
        ),
      ],
    );
    if (action == 'rename') {
      widget.onRename();
    } else if (action == 'transfer') {
      widget.onTransfer?.call();
    } else if (action == 'pull_to_local') {
      widget.onPullToLocal?.call();
    } else if (action == 'delete_node_files') {
      widget.onDeleteNodeFiles?.call();
    } else if (action == 'delete') {
      widget.onDelete();
    } else if (action == 'select') {
      widget.onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: PlatformUtil.isMobile ? null : widget.onLongPress,
      onLongPressStart: PlatformUtil.isMobile
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: MediaCutoutCard(
          selected: widget.isSelected,
          hovered: _hovering,
          label: widget.typeLabel,
          // 「N 项」是点开能看到的卡片数，和正文里的「共 N 资源」两个口径，
          // 分放右上标签和正文正好各自说一件事
          tagLabel: '${widget.itemCount} 项',
          tagIcon: StrokeIcons.folder,
          title: widget.folder.name,
          body: widget.resourceCount > 0
              ? '共 ${widget.resourceCount} 资源'
              : '暂无资源',
          footIcon: widget.isRemote ? StrokeIcons.cloud : StrokeIcons.computer,
          footName: widget.isRemote ? (widget.nodeName ?? '远程节点') : '本机',
          footReadout: formatFileSize(widget.totalSize),
          media: MediaCardCover(
            source: widget.coverSource,
            placeholderIcon: StrokeIcons.folder,
            lostIcon: StrokeIcons.folderOff,
            isLost: widget.isLost,
          ),
          mediaOverlay: widget.isLost
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: appMetrics.kSpace8,
                      top: appMetrics.kSpace8,
                    ),
                    child: const LostBadge(),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
