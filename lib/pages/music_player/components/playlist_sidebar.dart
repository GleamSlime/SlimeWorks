import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/widgets/app_chips.dart';
import 'package:slime_works/core/widgets/empty_state.dart';
import 'package:slime_works/core/widgets/glass_menu.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 播放列表侧边栏（桌面端左侧）
class PlaylistSidebar extends StatelessWidget {
  final MusicPlayerViewModel viewModel;

  const PlaylistSidebar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.surface.withAlpha(WindowGlass.panelAlpha),
        // 原来只画右边一条描边却配了圆角：圆角处描边断开，看着像缺了一角。
        borderRadius: AppTheme.metrics.radius10,
        border: Border.all(color: s.hairline, width: scaleW(1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 操作按钮
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.metrics.kSpace16,
              AppTheme.metrics.kSpace16,
              AppTheme.metrics.kSpace8,
              AppTheme.metrics.kSpace8,
            ),
            child: Row(
              children: [
                Text('播放列表', style: AppTextStyles.cardTitle(context)),
                const Spacer(),
                // 新建子目录
                ToolIconButton(
                  icon: StrokeIcons.createNewFolder,
                  onPressed: () => _showCreateFolderDialog(context),
                  tooltip: '新建子目录',
                ),
                // 新建播放列表
                ToolIconButton(
                  icon: StrokeIcons.add,
                  onPressed: () => _showCreatePlaylistDialog(context),
                  tooltip: '新建播放列表',
                ),
              ],
            ),
          ),
          // 面包屑导航
          Obx(() => _buildBreadcrumb(context)),
          const AppDivider(),
          // 路径映射 + 目录 + 播放列表
          Expanded(
            child: Obx(() {
              // 只显示当前文件夹下的路径映射
              final currentFolderId = viewModel.currentFolderId.value;
              final mappings = viewModel.pathMappings
                  .where((m) => m.folderId == currentFolderId)
                  .toList();
              final subFolders = viewModel.currentSubFolders;
              final folderPlaylists = viewModel.currentFolderPlaylists;
              if (mappings.isEmpty && subFolders.isEmpty && folderPlaylists.isEmpty) {
                return EmptyState(
                  title: '暂无内容',
                  icon: StrokeIcons.folderOpen,
                  compact: true,
                  action: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: DrawIcon(StrokeIcons.createNewFolder,
                          size: AppTheme.metrics.iconSize16,
                        ),
                        label: const Text('新建子目录'),
                        onPressed: () => _showCreateFolderDialog(context),
                      ),
                      TextButton.icon(
                        icon: DrawIcon(StrokeIcons.add, size: AppTheme.metrics.iconSize16),
                        label: const Text('新建播放列表'),
                        onPressed: () => _showCreatePlaylistDialog(context),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: mappings.length + subFolders.length + folderPlaylists.length,
                itemBuilder: (context, index) {
                  // 先显示路径映射，再显示子目录，最后播放列表
                  if (index < mappings.length) {
                    final mapping = mappings[index];
                    return _PathMappingTile(
                      node: mapping,
                      onRemove: () => viewModel.removePathMapping(mapping.path),
                      onRefresh: () => viewModel.refreshPathMapping(mapping.path),
                    );
                  }
                  final adjustedIndex = index - mappings.length;
                  if (adjustedIndex < subFolders.length) {
                    final folder = subFolders[adjustedIndex];
                    return _FolderTile(
                      folder: folder,
                      onTap: () => viewModel.navigateToFolder(folder.id),
                      onRename: (name) => viewModel.renameFolder(folder.id, name),
                      onDelete: () => viewModel.deleteFolder(folder.id),
                    );
                  }
                  final playlist = folderPlaylists[adjustedIndex - subFolders.length];
                  final isSelected = viewModel.currentPlaylistId.value == playlist.id;
                  return _PlaylistTile(
                    playlist: playlist,
                    isSelected: isSelected,
                    onTap: () => viewModel.selectPlaylist(playlist.id),
                    onRename: (name) => viewModel.renamePlaylist(playlist.id, name),
                    onDelete: () => viewModel.deletePlaylist(playlist.id),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  /// 面包屑导航
  Widget _buildBreadcrumb(BuildContext context) {
    final breadcrumbs = viewModel.breadcrumbFolders;
    if (breadcrumbs.isEmpty && viewModel.currentFolderId.value == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8),
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 根级
          _BreadcrumbChip(
            label: '全部',
            onTap: () => viewModel.navigateToFolder(null),
            isActive: viewModel.currentFolderId.value == null,
          ),
          for (int i = 0; i < breadcrumbs.length; i++) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace2),
              child: DrawIcon(StrokeIcons.chevronRight,
                size: AppTheme.metrics.iconSize14,
                color: AppSemantic.of(context).textTertiary,
              ),
            ),
            _BreadcrumbChip(
              label: breadcrumbs[i].name,
              onTap: () => viewModel.navigateToFolder(breadcrumbs[i].id),
              isActive: i == breadcrumbs.length - 1,
            ),
          ],
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final nameController = TextEditingController(text: '新播放列表');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放列表'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '播放列表名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) viewModel.createPlaylist(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final nameController = TextEditingController(text: '新目录');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建子目录'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '目录名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) viewModel.createSubFolder(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 面包屑导航项
class _BreadcrumbChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _BreadcrumbChip({required this.label, required this.onTap, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace4,
          vertical: scaleW(2),
        ),
        child: Text(
          label,
          style: AppTextStyles.body(context).copyWith(
            color: isActive
                ? AppSemantic.of(context).accent
                : AppSemantic.of(context).textTertiary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 目录条目
class _FolderTile extends StatelessWidget {
  final music_api.FolderInfo folder;
  final VoidCallback onTap;
  final Function(String) onRename;
  final VoidCallback onDelete;

  const _FolderTile({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return ListTile(
      dense: true,
      leading: DrawIcon(StrokeIcons.folder,
        size: m.iconSize18,
        // 目录比播放列表低一档权重：同一层里靠饱和度区分，而不是靠字号。
        color: s.accent.withValues(alpha: 0.7),
      ),
      title: Text(
        folder.name,
        style: AppTextStyles.rowTitle(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: DrawIcon(StrokeIcons.moreVert, size: m.iconSize16),
        onSelected: (action) {
          switch (action) {
            case 'rename':
              _showRenameDialog(context);
              break;
            case 'delete':
              onDelete();
              break;
            case 'transcribe':
              _transcribeFolder(context);
              break;
          }
        },
        itemBuilder: (ctx) => [
          GlassMenuItem(
            value: 'transcribe',
            label: '批量语音识别',
            icon: StrokeIcons.graphicEq,
          ),
          GlassMenuItem(
            value: 'rename',
            label: '重命名',
            icon: StrokeIcons.driveFileRenameOutline,
          ),
          GlassMenuItem(
            value: 'delete',
            label: '删除',
            icon: StrokeIcons.deleteOutline,
            destructive: true,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  /// 批量识别文件夹下的所有音频
  void _transcribeFolder(BuildContext context) {
    final viewModel = Get.find<MusicPlayerViewModel>();
    final queue = getIt<TranscriptionTaskQueue>();
    // 获取该文件夹下所有播放列表的歌曲
    final folderPlaylists = viewModel.playlists.where((p) => p.folderId == folder.id);
    for (final playlist in folderPlaylists) {
      final items = music_api.getPlaylistItems(playlistId: playlist.id);
      for (final item in items) {
        queue.enqueue(audioFilePath: item.filePath, displayName: item.title);
      }
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已添加文件夹「${folder.name}」的音频到识别队列')));
  }

  void _showRenameDialog(BuildContext context) {
    final nameController = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名目录'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '目录名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) onRename(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 播放列表条目
class _PlaylistTile extends StatelessWidget {
  final music_api.Playlist playlist;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(String) onRename;
  final VoidCallback onDelete;

  const _PlaylistTile({
    required this.playlist,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return ListTile(
      dense: true,
      selected: isSelected,
      // 选中底用 accentContainer 而不是 primary@10% 手搓：这是全站的"选中"语言。
      selectedTileColor: s.accentContainer,
      leading: DrawIcon(
        playlist.isDefault ? StrokeIcons.queueMusic : StrokeIcons.playlistPlay,
        size: m.iconSize18,
        color: isSelected ? s.accent : null,
      ),
      title: Text(
        playlist.name,
        style: AppTextStyles.rowTitle(context).copyWith(
          color: isSelected ? s.accent : s.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.itemCount} 首',
        style: AppTextStyles.caption(context),
      ),
      trailing: PopupMenuButton<String>(
        icon: DrawIcon(StrokeIcons.moreVert, size: m.iconSize16),
        onSelected: (action) {
          switch (action) {
            case 'rename':
              _showRenameDialog(context);
              break;
            case 'delete':
              if (!playlist.isDefault) onDelete();
              break;
          }
        },
        itemBuilder: (ctx) => [
          GlassMenuItem(
            value: 'rename',
            label: '重命名',
            icon: StrokeIcons.driveFileRenameOutline,
          ),
          if (!playlist.isDefault)
            GlassMenuItem(
              value: 'delete',
              label: '删除',
              icon: StrokeIcons.deleteOutline,
              destructive: true,
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  void _showRenameDialog(BuildContext context) {
    final nameController = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '播放列表名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) onRename(name);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 路径映射条目（可展开的树形结构）
class _PathMappingTile extends StatefulWidget {
  final music_api.PathMappingNodeInfo node;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;

  const _PathMappingTile({required this.node, required this.onRemove, required this.onRefresh});

  @override
  State<_PathMappingTile> createState() => _PathMappingTileState();
}

class _PathMappingTileState extends State<_PathMappingTile> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 根节点标题行
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace12,
              vertical: AppTheme.metrics.kSpace8,
            ),
            child: Row(
              children: [
                DrawIcon(
                  _isExpanded ? StrokeIcons.expandMore : StrokeIcons.chevronRight,
                  size: m.iconSize18,
                  color: s.textTertiary,
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                DrawIcon(StrokeIcons.link,
                  size: m.iconSize16,
                  color: node.hasAudio ? s.accent : s.textTertiary,
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Expanded(
                  child: Text(
                    node.name,
                    style: AppTextStyles.rowTitle(context).copyWith(
                      fontSize: m.fontSize12,
                      color: node.hasAudio ? s.accent : s.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.hasAudio)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace4,
                      vertical: scaleW(1),
                    ),
                    decoration: BoxDecoration(
                      color: s.accentContainer,
                      borderRadius: m.radius4,
                    ),
                    child: Text(
                      '含音频',
                      style: AppTextStyles.overline(context).copyWith(
                        color: s.accentText,
                        fontSize: m.fontSize10,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                PopupMenuButton<String>(
                  icon: DrawIcon(StrokeIcons.moreVert, size: m.iconSize14, color: s.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: m.kSpace24,
                    minHeight: m.kSpace24,
                  ),
                  tooltip: '映射操作',
                  onSelected: (value) {
                    switch (value) {
                      case 'remove':
                        widget.onRemove();
                        break;
                      case 'open_folder':
                        Process.run('open', [widget.node.path]);
                        break;
                      case 'refresh':
                        widget.onRefresh();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    GlassMenuItem(
                      value: 'open_folder',
                      label: '打开文件夹所在位置',
                      icon: StrokeIcons.folderOpen,
                    ),
                    GlassMenuItem(
                      value: 'refresh',
                      label: '刷新映射',
                      icon: StrokeIcons.refresh,
                    ),
                    GlassMenuItem(
                      value: 'remove',
                      label: '移除映射',
                      icon: StrokeIcons.linkOff,
                      destructive: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 子节点树
        if (_isExpanded && node.children.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: AppTheme.metrics.kSpace16),
            child: _buildChildren(context, node.children, 0),
          ),
      ],
    );
  }

  Widget _buildChildren(BuildContext context, List<music_api.PathMappingNodeInfo> children, int depth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((child) => _PathMappingChildTile(node: child, depth: depth)).toList(),
    );
  }
}

/// 路径映射子节点
class _PathMappingChildTile extends StatefulWidget {
  final music_api.PathMappingNodeInfo node;
  final int depth;

  const _PathMappingChildTile({required this.node, required this.depth});

  @override
  State<_PathMappingChildTile> createState() => _PathMappingChildTileState();
}

class _PathMappingChildTileState extends State<_PathMappingChildTile> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isDir = node.nodeType == music_api.PathMappingNodeType.directory;
    final icon = _getIcon(node);
    final iconColor = _getIconColor(context, node);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isDir
              ? () => setState(() => _isExpanded = !_isExpanded)
              : () => _onFileTap(context),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace8,
              vertical: AppTheme.metrics.kSpace2,
            ),
            child: Row(
              children: [
                if (isDir)
                  DrawIcon(
                    _isExpanded ? StrokeIcons.expandMore : StrokeIcons.chevronRight,
                    size: AppTheme.metrics.iconSize14,
                    color: AppSemantic.of(context).textTertiary,
                  )
                else
                  SizedBox(width: AppTheme.metrics.iconSize14),
                SizedBox(width: AppTheme.metrics.kSpace4),
                DrawIcon(icon, size: AppTheme.metrics.iconSize14, color: iconColor),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Expanded(
                  child: Text(
                    node.name,
                    style: AppTextStyles.rowTitle(context).copyWith(
                      fontSize: AppTheme.metrics.fontSize12,
                      color: _getTextColor(context, node),
                      fontWeight: node.hasAudio ? FontWeight.w500 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.fileSize != null)
                  Text(
                    _formatFileSize(node.fileSize!),
                    style: AppTextStyles.caption(context).copyWith(
                      fontSize: AppTheme.metrics.fontSize10,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isDir && _isExpanded && node.children.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: AppTheme.metrics.kSpace12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: node.children
                  .map((child) => _PathMappingChildTile(node: child, depth: widget.depth + 1))
                  .toList(),
            ),
          ),
      ],
    );
  }

  StrokeIcon _getIcon(music_api.PathMappingNodeInfo node) {
    switch (node.nodeType) {
      case music_api.PathMappingNodeType.directory:
        return StrokeIcons.folder;
      case music_api.PathMappingNodeType.audioFile:
        return StrokeIcons.audiotrack;
      case music_api.PathMappingNodeType.imageFile:
        return StrokeIcons.image;
      case music_api.PathMappingNodeType.cueFile:
        return StrokeIcons.description;
      case music_api.PathMappingNodeType.otherFile:
        return StrokeIcons.insertDriveFile;
    }
  }

  Color _getIconColor(BuildContext context, music_api.PathMappingNodeInfo node) {
    final s = AppSemantic.of(context);
    switch (node.nodeType) {
      case music_api.PathMappingNodeType.directory:
        return s.accent.withValues(alpha: 0.7);
      case music_api.PathMappingNodeType.audioFile:
        return s.accent;
      case music_api.PathMappingNodeType.imageFile:
        // 图片/歌词的类型色走状态色族：裸 Colors.teal / Colors.orange 不随明暗，
        // 在暗色面板上就是一块刺眼的生色。
        return s.info.color;
      case music_api.PathMappingNodeType.cueFile:
        return s.warning.color;
      case music_api.PathMappingNodeType.otherFile:
        return s.textTertiary;
    }
  }

  Color? _getTextColor(BuildContext context, music_api.PathMappingNodeInfo node) {
    if (node.hasAudio || node.nodeType == music_api.PathMappingNodeType.audioFile) {
      return AppSemantic.of(context).accent;
    }
    return null;
  }

  String _formatFileSize(int bytes) {
    final b = bytes;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 点击文件时的预览操作
  void _onFileTap(BuildContext context) {
    final node = widget.node;
    switch (node.nodeType) {
      case music_api.PathMappingNodeType.imageFile:
        _previewImage(context, node);
        break;
      case music_api.PathMappingNodeType.cueFile:
        _previewCue(context, node);
        break;
      case music_api.PathMappingNodeType.audioFile:
        // 音频文件：用系统默认应用打开
        Process.run('open', [node.path]);
        break;
      default:
        // 其他文件：用系统默认应用打开
        Process.run('open', [node.path]);
        break;
    }
  }

  /// 预览图片
  void _previewImage(BuildContext context, music_api.PathMappingNodeInfo node) {
    final file = File(node.path);
    if (!file.existsSync()) return;
    final m = AppTheme.metrics;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(m.kSpace8),
              child: Row(
                children: [
                  DrawIcon(StrokeIcons.image,
                    size: m.iconSize16,
                    color: AppSemantic.of(context).info.color,
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: Text(
                      node.name,
                      style: AppTextStyles.cardTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: DrawIcon(StrokeIcons.close, size: m.iconSize18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(
                  padding: EdgeInsets.all(m.kSpace32),
                  child: Text('无法加载图片', style: AppTextStyles.body(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 预览 CUE 文件内容
  void _previewCue(BuildContext context, music_api.PathMappingNodeInfo node) {
    final file = File(node.path);
    if (!file.existsSync()) return;
    final content = file.readAsStringSync();
    final m = AppTheme.metrics;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: scaleW(480),
          height: scaleW(400),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(m.kSpace8),
                child: Row(
                  children: [
                    DrawIcon(StrokeIcons.description,
                      size: m.iconSize16,
                      color: AppSemantic.of(context).warning.color,
                    ),
                    SizedBox(width: m.kSpace8),
                    Expanded(
                      child: Text(
                        node.name,
                        style: AppTextStyles.cardTitle(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: DrawIcon(StrokeIcons.close, size: m.iconSize18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const AppDivider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(m.kSpace12),
                  child: SelectableText(content, style: AppTextStyles.mono(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
