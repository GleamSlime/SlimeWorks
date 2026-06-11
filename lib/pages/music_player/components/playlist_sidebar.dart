import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/pages/music_player/components/eq_panel.dart';

/// 播放列表侧边栏（桌面端左侧）
class PlaylistSidebar extends StatelessWidget {
  final MusicPlayerViewModel viewModel;

  const PlaylistSidebar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
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
          // 目录 + 播放列表
          Expanded(
            child: Obx(() {
              final subFolders = viewModel.currentSubFolders;
              final folderPlaylists = viewModel.currentFolderPlaylists;
              if (subFolders.isEmpty && folderPlaylists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '暂无内容',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      SizedBox(height: AppTheme.metrics.kSpace8),
                      TextButton.icon(
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 16,
                        ),
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
                itemCount: subFolders.length + folderPlaylists.length,
                itemBuilder: (context, index) {
                  // 先显示子目录，再显示播放列表
                  if (index < subFolders.length) {
                    final folder = subFolders[index];
                    return _FolderTile(
                      folder: folder,
                      onTap: () => viewModel.navigateToFolder(folder.id),
                      onRename: (name) =>
                          viewModel.renameFolder(folder.id, name),
                      onDelete: () => viewModel.deleteFolder(folder.id),
                    );
                  }
                  final playlist = folderPlaylists[index - subFolders.length];
                  final isSelected =
                      viewModel.currentPlaylistId.value == playlist.id;
                  return _PlaylistTile(
                    playlist: playlist,
                    isSelected: isSelected,
                    onTap: () => viewModel.selectPlaylist(playlist.id),
                    onRename: (name) =>
                        viewModel.renamePlaylist(playlist.id, name),
                    onDelete: () => viewModel.deletePlaylist(playlist.id),
                  );
                },
              );
            }),
          ),
          // 分隔线
          const Divider(height: 1),
          // 快捷操作
          Padding(
            padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.favorite_rounded, size: 18),
                  title: const Text('收藏'),
                  onTap: () => _showFavorites(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: const Text('最近播放'),
                  onTap: () => _showRecentPlayed(context),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.equalizer_rounded, size: 18),
                  title: const Text('均衡器'),
                  onTap: () => _showEqPanel(context),
                ),
              ],
            ),
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
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace2,
              ),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
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

  void _showEqPanel(BuildContext context) {
    showModalBottomSheet(context: context, builder: (ctx) => const EqPanel());
  }

  /// 显示收藏列表
  void _showFavorites(BuildContext context) async {
    await viewModel.loadFavorites();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.metrics.kSpace16),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: AppTheme.metrics.kSpace16),
              Row(
                children: [
                  Text('收藏', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Obx(() => Text(
                    '${viewModel.favoriteItems.length} 首',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  )),
                ],
              ),
              SizedBox(height: AppTheme.metrics.kSpace12),
              Obx(() {
                final items = viewModel.favoriteItems;
                if (items.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.favorite_border_rounded, size: 40, color: Theme.of(context).hintColor),
                          SizedBox(height: AppTheme.metrics.kSpace8),
                          Text('暂无收藏', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          )),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: items.map((item) => _MusicListTile(
                    item: item,
                    onTap: () {
                      // 将收藏列表设为当前播放列表并播放
                      final index = viewModel.currentItems.indexOf(item);
                      if (index >= 0) {
                        viewModel.playItem(index);
                      } else {
                        // 如果不在当前列表中，直接播放该文件
                        viewModel.currentItems.value = [item];
                        viewModel.playItem(0);
                      }
                      Navigator.pop(ctx);
                    },
                    onFavoriteTap: () => viewModel.toggleFavorite(item.id),
                  )).toList(),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示最近播放列表
  void _showRecentPlayed(BuildContext context) async {
    await viewModel.loadRecentPlayed();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.metrics.kSpace16),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: AppTheme.metrics.kSpace16),
              Row(
                children: [
                  Text('最近播放', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Obx(() => Text(
                    '${viewModel.recentRecords.length} 首',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  )),
                ],
              ),
              SizedBox(height: AppTheme.metrics.kSpace12),
              Obx(() {
                final records = viewModel.recentRecords;
                if (records.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded, size: 40, color: Theme.of(context).hintColor),
                          SizedBox(height: AppTheme.metrics.kSpace8),
                          Text('暂无播放记录', style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          )),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: records.map((record) {
                    // 从当前列表中查找歌曲信息
                    final musicItem = viewModel.currentItems.firstWhereOrNull(
                      (i) => i.id == record.musicId,
                    );
                    final title = musicItem?.title ?? '未知歌曲';
                    final artist = musicItem?.artist;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.music_note_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: artist != null
                          ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall)
                          : null,
                      trailing: Text(
                        _formatPlayTime(record.playedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      onTap: () {
                        // 在当前列表中查找并播放
                        final index = viewModel.currentItems.indexWhere((i) => i.id == record.musicId);
                        if (index >= 0) {
                          viewModel.playItem(index);
                        }
                        Navigator.pop(ctx);
                      },
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ),
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

  const _BreadcrumbChip({
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace4,
          vertical: 2,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).hintColor,
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
        queue.enqueue(
          audioFilePath: item.filePath,
          displayName: item.title,
        );
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加文件夹「${folder.name}」的音频到识别队列')),
    );
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
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
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.1),
      leading: Icon(
        playlist.isDefault
            ? Icons.queue_music_rounded
            : Icons.playlist_play_rounded,
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
      subtitle: Text(
        '${playlist.itemCount} 首',
        style: Theme.of(context).textTheme.bodySmall,
      ),
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
          if (!playlist.isDefault)
            const PopupMenuItem(value: 'delete', child: Text('删除')),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
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

  const _MusicListTile({
    required this.item,
    required this.onTap,
    required this.onFavoriteTap,
  });

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
          ? Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall)
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
