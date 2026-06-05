import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
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
        border: Border(right: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
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
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => _showCreatePlaylistDialog(context),
                  tooltip: '新建播放列表',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 播放列表
          Expanded(
            child: Obx(() {
              final playlists = viewModel.playlists;
              if (playlists.isEmpty) {
                return Center(
                  child: Text(
                    '暂无播放列表',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                  ),
                );
              }
              return ListView.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
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
                  onTap: () => viewModel.loadFavorites(),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history_rounded, size: 18),
                  title: const Text('最近播放'),
                  onTap: () => viewModel.loadRecentPlayed(),
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

  void _showEqPanel(BuildContext context) {
    showModalBottomSheet(context: context, builder: (ctx) => const EqPanel());
  }
}

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
