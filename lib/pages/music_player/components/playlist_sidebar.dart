import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';

/// 播放列表侧边栏（桌面端左侧）
class PlaylistSidebar extends StatelessWidget {
  final MusicPlayerViewModel viewModel;

  const PlaylistSidebar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
        borderRadius: AppTheme.metrics.radius10,
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
                Text(
                  '播放列表',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // 新建子目录
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed: () => _showCreateFolderDialog(context),
                  tooltip: '新建子目录',
                ),
                // 新建播放列表
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => _showCreatePlaylistDialog(context),
                  tooltip: '新建播放列表',
                ),
              ],
            ),
          ),
          // 面包屑导航
          Obx(() => _buildBreadcrumb(context)),
          const Divider(height: 1),
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
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '暂无内容',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                      ),
                      SizedBox(height: AppTheme.metrics.kSpace8),
                      TextButton.icon(
                        icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                        label: const Text('新建子目录'),
                        onPressed: () => _showCreateFolderDialog(context),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 16),
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
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: Theme.of(context).hintColor,
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

  /// 格式化播放时间
  String _formatPlayTime(int? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
      if (diff.inDays < 1) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
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
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace4, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
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
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.folder_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, size: 16),
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
          const PopupMenuItem(value: 'transcribe', child: Text('批量语音识别')),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
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
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      leading: Icon(
        playlist.isDefault ? Icons.queue_music_rounded : Icons.playlist_play_rounded,
        size: 18,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        playlist.name,
        style: TextStyle(
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${playlist.itemCount} 首', style: Theme.of(context).textTheme.bodySmall),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, size: 16),
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
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          if (!playlist.isDefault) const PopupMenuItem(value: 'delete', child: Text('删除')),
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

/// 收藏列表中的音乐条目
class _MusicListTile extends StatelessWidget {
  final music_api.MusicItem item;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const _MusicListTile({required this.item, required this.onTap, required this.onFavoriteTap});

  @override
  Widget build(BuildContext context) {
    final isFav = item.isFavorite;
    return ListTile(
      dense: true,
      leading: Icon(
        Icons.music_note_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.artist != null
          ? Text(
              item.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: IconButton(
        icon: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: isFav ? Colors.redAccent : null,
        ),
        onPressed: onFavoriteTap,
      ),
      onTap: onTap,
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
                Icon(
                  _isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: Theme.of(context).hintColor,
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Icon(
                  Icons.link_rounded,
                  size: 16,
                  color: node.hasAudio
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Expanded(
                  child: Text(
                    node.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: node.hasAudio
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.hasAudio)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace4),
                    ),
                    child: Text(
                      '含音频',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 14, color: Theme.of(context).hintColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
                    const PopupMenuItem(value: 'open_folder', child: Text('打开文件夹所在位置')),
                    const PopupMenuItem(value: 'refresh', child: Text('刷新映射')),
                    const PopupMenuItem(value: 'remove', child: Text('移除映射')),
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
                  Icon(
                    _isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                    size: 14,
                    color: Theme.of(context).hintColor,
                  )
                else
                  SizedBox(width: 14),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Icon(icon, size: 14, color: iconColor),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Expanded(
                  child: Text(
                    node.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _getTextColor(context, node),
                      fontWeight: node.hasAudio ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.fileSize != null)
                  Text(
                    _formatFileSize(node.fileSize!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).hintColor,
                      fontSize: 10,
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

  IconData _getIcon(music_api.PathMappingNodeInfo node) {
    switch (node.nodeType) {
      case music_api.PathMappingNodeType.directory:
        return Icons.folder_rounded;
      case music_api.PathMappingNodeType.audioFile:
        return Icons.audiotrack_rounded;
      case music_api.PathMappingNodeType.imageFile:
        return Icons.image_rounded;
      case music_api.PathMappingNodeType.cueFile:
        return Icons.description_rounded;
      case music_api.PathMappingNodeType.otherFile:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getIconColor(BuildContext context, music_api.PathMappingNodeInfo node) {
    switch (node.nodeType) {
      case music_api.PathMappingNodeType.directory:
        return Theme.of(context).colorScheme.primary.withValues(alpha: 0.7);
      case music_api.PathMappingNodeType.audioFile:
        return Theme.of(context).colorScheme.primary;
      case music_api.PathMappingNodeType.imageFile:
        return Colors.teal;
      case music_api.PathMappingNodeType.cueFile:
        return Colors.orange;
      case music_api.PathMappingNodeType.otherFile:
        return Theme.of(context).hintColor;
    }
  }

  Color? _getTextColor(BuildContext context, music_api.PathMappingNodeInfo node) {
    if (node.hasAudio || node.nodeType == music_api.PathMappingNodeType.audioFile) {
      return Theme.of(context).colorScheme.primary;
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
              child: Row(
                children: [
                  Icon(Icons.image_rounded, size: 16, color: Colors.teal),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Text(
                      node.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
                  child: Text('无法加载图片', style: Theme.of(context).textTheme.bodyMedium),
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 480,
          height: 400,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
                child: Row(
                  children: [
                    Icon(Icons.description_rounded, size: 16, color: Colors.orange),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    Expanded(
                      child: Text(
                        node.name,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                  child: SelectableText(
                    content,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
