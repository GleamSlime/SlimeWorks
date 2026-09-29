import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/format.dart';
import 'package:slime_works/pages/collection/picture/components/lost_badge.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 智能文件夹卡
///
/// 从 StatelessWidget 改成 StatefulWidget：镂空样式靠悬停拉开层次（描边加深 +
/// 封面推近），这张卡原来一点悬停反馈都没有，和三张兄弟卡摆在一起像坏了。
class SmartFolderCard extends StatefulWidget {
  const SmartFolderCard({
    super.key,
    required this.smartFolder,
    required this.matchCount,
    required this.resourceCount,
    required this.totalSize,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.onRename,
    this.onEdit,
    this.onDelete,
    this.coverSource,
    this.onTransfer,
    this.nodeName,
    this.isLost = false,
  });

  final SmartFolder smartFolder;

  /// 命中的集合数
  final int matchCount;

  /// 命中集合内仍然存在的资源条数
  final int resourceCount;

  /// 命中集合内仍然存在的资源体积
  final BigInt totalSize;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? coverSource;
  final VoidCallback? onTransfer;

  /// 非空表示这是远程节点的智能文件夹，来源行显示节点名。
  final String? nodeName;

  final bool isLost;

  @override
  State<SmartFolderCard> createState() => _SmartFolderCardState();
}

class _SmartFolderCardState extends State<SmartFolderCard> {
  bool _hovering = false;

  Worker? _privacyWorker;

  @override
  void initState() {
    super.initState();
    final prefs = getIt.isRegistered<MediaPrefsService>()
        ? getIt.get<MediaPrefsService>()
        : null;
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
    if (!mounted) return;
    // 将全局坐标转为 Overlay 的本地坐标，正确处理侧边栏等布局偏移
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
        if (widget.onRename != null)
          GlassMenuItem<String>(
            value: 'rename',
            label: '重命名',
            icon: StrokeIcons.driveFileRenameOutline,
          ),
        if (widget.onEdit != null)
          GlassMenuItem<String>(
            value: 'edit',
            label: '编辑智能文件夹',
            icon: StrokeIcons.autoAwesome,
          ),
        if (widget.onTransfer != null)
          GlassMenuItem<String>(
            value: 'transfer',
            label: '转移集合到...',
            icon: StrokeIcons.driveFolderUpload,
          ),
        if (PlatformUtil.isMobile)
          GlassMenuItem<String>(
            value: 'select',
            label: '进入多选',
            icon: StrokeIcons.checklist,
          ),
        if (widget.onDelete != null) ...[
          const PopupMenuDivider(),
          GlassMenuItem<String>(
            value: 'delete',
            label: '删除智能文件夹',
            icon: StrokeIcons.deleteOutline,
            destructive: true,
          ),
        ],
      ],
    );
    if (!mounted) return;
    if (action == 'rename') {
      widget.onRename?.call();
    } else if (action == 'edit') {
      widget.onEdit?.call();
    } else if (action == 'transfer') {
      widget.onTransfer?.call();
    } else if (action == 'delete') {
      widget.onDelete?.call();
    } else if (action == 'select') {
      widget.onLongPress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sf = widget.smartFolder;
    final pattern = sf.effectivePattern;
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
          label: '智能文件夹',
          tagLabel: '${widget.matchCount} 项',
          tagIcon: StrokeIcons.category,
          title: sf.name,
          // 模式是这张卡的身份，占正文；没有模式（全量聚合）时才让位给资源摘要。
          // 命中集合里的资源条数不再上卡面：正文只有两行，体积已经说了「多少」。
          body: pattern.isNotEmpty
              ? pattern
              : (widget.resourceCount > 0
                    ? '共 ${widget.resourceCount} 资源'
                    : '暂无资源'),
          bodyMono: pattern.isNotEmpty,
          footIcon: widget.nodeName != null
              ? StrokeIcons.cloud
              : StrokeIcons.computer,
          footName: widget.nodeName ?? '本机',
          footReadout: formatFileSize(widget.totalSize),
          trailingIcon: StrokeIcons.edit,
          trailingOnTap: widget.onEdit,
          media: MediaCardCover(
            source: widget.coverSource,
            placeholderIcon: StrokeIcons.autoAwesome,
            lostIcon: StrokeIcons.brokenImage,
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
