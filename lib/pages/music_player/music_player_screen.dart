import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/pages/music_player/components/music_list_item.dart';
import 'package:slime_works/pages/music_player/components/playlist_sidebar.dart';
import 'package:slime_works/pages/music_player/components/bottom_player_bar.dart';
import 'package:slime_works/pages/music_player/components/eq_panel.dart';
import 'package:slime_works/pages/music_player/components/immersive_player_screen.dart';

const _kSidebarWidth = 220.0;

class MusicPlayerScreen extends BasePage<MusicPlayerViewModel> {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends BasePageState<MusicPlayerViewModel, MusicPlayerScreen> {
  bool _isDraggingFiles = false;

  late final MusicPlayerViewModel _persistentViewModel = Get.put(
    MusicPlayerViewModel(),
    permanent: true,
  );

  @override
  MusicPlayerViewModel createViewModel() => _persistentViewModel;

  @override
  Widget buildContent(BuildContext context) {
    final isMobile = PlatformUtil.isMobile || getIt<DesktopScreenProvider>().isMobile.value;

    return ScreenChrome(
      data: _buildScreenChromeData(context, isMobile),
      child: Obx(() {
        // 沉浸式播放模式（全屏唱片机，覆盖整个页面）
        if (viewModel.isImmersiveMode.value) {
          return ImmersivePlayerScreen(viewModel: viewModel);
        }

        // 桌面端：左侧播放列表侧边栏 + 右侧主内容 + 底部播放栏
        if (!isMobile) {
          return DropTarget(
            onDragEntered: (_) => setState(() => _isDraggingFiles = true),
            onDragExited: (_) => setState(() => _isDraggingFiles = false),
            onDragDone: (detail) {
              setState(() => _isDraggingFiles = false);
              viewModel.importDroppedPaths(detail.files.map((f) => f.path).toList());
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          // 左侧播放列表
                          SizedBox(
                            width: _kSidebarWidth,
                            child: PlaylistSidebar(viewModel: viewModel),
                          ),
                          // 右侧主内容（文件夹信息 + 歌曲列表）
                          Expanded(child: _buildMainContent(context)),
                        ],
                      ),
                    ),
                    // 底部悬浮播放栏
                    BottomPlayerBar(viewModel: viewModel, onTapExpand: viewModel.enterImmersiveMode),
                  ],
                ),
                if (_isDraggingFiles)
                  Positioned.fill(child: IgnorePointer(child: _buildDragOverlay(context))),
              ],
            ),
          );
        }

        // 移动端：全屏布局，底部播放控制栏
        return Column(
          children: [
            Expanded(child: _buildMainContent(context)),
            BottomPlayerBar(viewModel: viewModel, onTapExpand: viewModel.enterImmersiveMode),
          ],
        );
      }),
    );
  }

  /// 构建 ScreenChromeData（顶部工具栏：收藏、最近播放、均衡器）
  ScreenChromeData _buildScreenChromeData(BuildContext context, bool isMobile) {
    final toolbar = _MusicPlayerToolbar(
      viewModel: viewModel,
      onFavorites: () => _showFavorites(context),
      onRecentPlayed: () => _showRecentPlayed(context),
      onEqPanel: () => _showEqPanel(context),
    );

    return ScreenChromeData(
      title: '音乐播放器',
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: toolbar,
    );
  }

  /// 主内容区域：文件夹信息卡片 + 歌曲列表
  Widget _buildMainContent(BuildContext context) {
    return Column(
      children: [
        // 文件夹/播放列表信息卡片
        _buildFolderInfoCard(context),
        // 导入状态提示
        Obx(() {
          if (!viewModel.isImporting.value && viewModel.importingStatus.value.isEmpty) {
            return const SizedBox.shrink();
          }
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace16,
              vertical: AppTheme.metrics.kSpace8,
            ),
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(width: AppTheme.metrics.kSpace12),
                Expanded(
                  child: Text(
                    viewModel.importingStatus.value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // 歌曲列表
        Expanded(child: _buildSongList(context)),
      ],
    );
  }

  /// 文件夹信息卡片（替代原来的唱片机区域）
  Widget _buildFolderInfoCard(BuildContext context) {
    return Obx(() {
      final playlistId = viewModel.currentPlaylistId.value;
      final playlists = viewModel.playlists;
      final currentPlaylist = playlists.firstWhereOrNull((p) => p.id == playlistId);
      final folderId = viewModel.currentFolderId.value;
      final folders = viewModel.folders;
      final currentFolder = folders.firstWhereOrNull((f) => f.id == folderId);

      // 决定展示主体：优先当前播放列表，否则当前目录
      final name = currentPlaylist?.name ?? currentFolder?.name ?? '全部音乐';
      // 封面：优先播放列表/文件夹封面，否则取第一首有封面的歌曲
      final coverPath = currentPlaylist?.coverPath
          ?? currentFolder?.coverPath
          ?? viewModel.currentItems.firstWhereOrNull((i) => i.coverPath != null && i.coverPath!.isNotEmpty)?.coverPath;
      final songCount = currentPlaylist?.itemCount.toInt() ?? viewModel.currentItems.length;
      final playCount = currentFolder?.playCount ?? 0;
      final author = currentFolder?.author;
      final tags = currentFolder?.tags;
      final createdAt = currentPlaylist != null
          ? currentPlaylist.createdAt
          : currentFolder?.createdAt;

      return _FolderInfoHeader(
        name: name,
        coverPath: coverPath,
        songCount: songCount,
        playCount: playCount,
        author: author,
        tags: tags,
        createdAt: createdAt,
        onPlayAll: songCount > 0 ? () => viewModel.playItem(0) : null,
        onImportFiles: viewModel.pickAndImportFiles,
        onImportFolder: viewModel.pickAndImportFolder,
        onSettings: () => _showPlaylistSettings(context),
      );
    });
  }

  /// 歌曲列表
  Widget _buildSongList(BuildContext context) {
    final items = viewModel.filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: AppTheme.metrics.iconSize48,
              color: Theme.of(context).hintColor,
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            Text(
              '暂无音乐，点击导入按钮添加',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: viewModel.pickAndImportFiles,
                  icon: const Icon(Icons.file_open_rounded),
                  label: const Text('选择文件'),
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                ElevatedButton.icon(
                  onPressed: viewModel.pickAndImportFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('选择文件夹'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 搜索栏 + 操作按钮
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace16,
            vertical: AppTheme.metrics.kSpace8,
          ),
          child: Row(
            children: [
              // 搜索
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索歌曲...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace8),
                    ),
                  ),
                  onChanged: (v) => viewModel.searchQuery.value = v,
                ),
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              IconButton(
                onPressed: viewModel.pickAndImportFiles,
                icon: const Icon(Icons.file_open_rounded),
                tooltip: '导入文件',
              ),
              IconButton(
                onPressed: viewModel.pickAndImportFolder,
                icon: const Icon(Icons.folder_open_rounded),
                tooltip: '导入文件夹',
              ),
              IconButton(
                onPressed: () => _showCreatePlaylistDialog(context),
                icon: const Icon(Icons.add_rounded),
                tooltip: '新建播放列表',
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isCurrent =
                  viewModel.currentIndex.value == viewModel.currentItems.indexOf(item);
              return MusicListItem(
                item: item,
                isCurrent: isCurrent,
                isPlaying: isCurrent && viewModel.isPlaying.value,
                onTap: () => viewModel.playItem(viewModel.currentItems.indexOf(item)),
                onFavoriteTap: () => viewModel.toggleFavorite(item.id),
                onDeleteTap: () => viewModel.deleteMusicItem(item.id),
                onTranscribeTap: () => viewModel.transcribeItem(item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 拖拽导入覆盖层
  Widget _buildDragOverlay(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: AppTheme.metrics.iconSize64,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            Text(
              '松开以导入音乐',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 播放列表/文件夹设置
  void _showPlaylistSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenamePlaylistDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('更换封面'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: const Text('移动到目录'),
              onTap: () => Navigator.pop(ctx),
            ),
            // 批量语音识别
            ListTile(
              leading: const Icon(Icons.record_voice_over_rounded),
              title: const Text('批量语音识别'),
              subtitle: Text(
                '识别当前列表 ${viewModel.currentItems.length} 首歌曲',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.pop(ctx);
                viewModel.transcribeAllItems();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除播放列表'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context) {
    final playlistId = viewModel.currentPlaylistId.value;
    if (playlistId == null) return;
    final playlist = viewModel.playlists.firstWhereOrNull((p) => p.id == playlistId);
    final nameController = TextEditingController(text: playlist?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) viewModel.renamePlaylist(playlistId, name);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 新建播放列表弹窗
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
              if (name.isNotEmpty) {
                viewModel.createPlaylist(name);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 显示均衡器
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.metrics.kSpace16)),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                child: Row(
                  children: [
                    Icon(Icons.favorite_rounded, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    Text('收藏', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Obx(() => Text(
                      '${viewModel.favoriteItems.length} 首',
                      style: Theme.of(context).textTheme.bodySmall,
                    )),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Obx(() => viewModel.favoriteItems.isEmpty
                    ? Center(
                        child: Text(
                          '暂无收藏',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: viewModel.favoriteItems.length,
                        itemBuilder: (_, index) {
                          final item = viewModel.favoriteItems[index];
                          return ListTile(
                            leading: const Icon(Icons.music_note_rounded, size: 20),
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              item.artist ?? '未知艺术家',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              // 在当前列表中查找并播放
                              final idx = viewModel.currentItems.indexWhere((i) => i.id == item.id);
                              if (idx >= 0) {
                                viewModel.playItem(idx);
                              } else {
                                viewModel.currentItems.value = [item];
                                viewModel.playItem(0);
                              }
                            },
                          );
                        },
                      )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示最近播放
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.metrics.kSpace16)),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    Text('最近播放', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Obx(() => Text(
                      '${viewModel.recentRecords.length} 首',
                      style: Theme.of(context).textTheme.bodySmall,
                    )),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Obx(() => viewModel.recentRecords.isEmpty
                    ? Center(
                        child: Text(
                          '暂无播放记录',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: viewModel.recentRecords.length,
                        itemBuilder: (_, index) {
                          final record = viewModel.recentRecords[index];
                          final musicItem = viewModel.currentItems.firstWhereOrNull(
                            (i) => i.id == record.musicId,
                          );
                          final title = musicItem?.title ?? '未知歌曲';
                          final artist = musicItem?.artist;
                          return ListTile(
                            leading: const Icon(Icons.music_note_rounded, size: 20),
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: artist != null
                                ? Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis)
                                : null,
                            onTap: () {
                              Navigator.pop(ctx);
                              final idx = viewModel.currentItems.indexWhere(
                                (i) => i.id == record.musicId,
                              );
                              if (idx >= 0) {
                                viewModel.playItem(idx);
                              }
                            },
                          );
                        },
                      )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// 文件夹信息头部卡片
// ─────────────────────────────────────────────────────────────────────────────
class _FolderInfoHeader extends StatelessWidget {
  final String name;
  final String? coverPath;
  final int songCount;
  final int playCount;
  final String? author;
  final String? tags;
  final int? createdAt;
  final VoidCallback? onPlayAll;
  final VoidCallback onImportFiles;
  final VoidCallback onImportFolder;
  final VoidCallback onSettings;

  const _FolderInfoHeader({
    required this.name,
    this.coverPath,
    required this.songCount,
    this.playCount = 0,
    this.author,
    this.tags,
    this.createdAt,
    this.onPlayAll,
    required this.onImportFiles,
    required this.onImportFolder,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTheme.metrics.kSpace24,
        AppTheme.metrics.kSpace20,
        AppTheme.metrics.kSpace24,
        AppTheme.metrics.kSpace16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF252523), const Color(0xFF1A1A18)]
              : [const Color(0xFFF5F5F3), const Color(0xFFEDEDEB)],
        ),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          _buildCover(context),
          SizedBox(width: AppTheme.metrics.kSpace20),
          // 信息 + 操作
          Expanded(child: _buildInfo(context)),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    const coverSize = 96.0;
    final hasCover = coverPath != null && File(coverPath!).existsSync();

    return GestureDetector(
      onTap: onSettings,
      child: Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: hasCover
            ? Image.file(
                File(coverPath!),
                fit: BoxFit.cover,
                width: coverSize,
                height: coverSize,
                errorBuilder: (_, _, _) => _buildDefaultCoverContent(context, coverSize),
              )
            : _buildDefaultCoverContent(context, coverSize),
      ),
    );
  }

  Widget _buildDefaultCoverContent(BuildContext context, double size) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 装饰性音符
          Icon(
            Icons.music_note_rounded,
            size: size * 0.35,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          ),
          // 右下角设置图标
          Positioned(
            right: 4,
            bottom: 4,
            child: Icon(
              Icons.settings_rounded,
              size: 14,
              color: Theme.of(context).hintColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 名称
        Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, height: 1.2),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        // 统计信息标签
        Wrap(
          spacing: AppTheme.metrics.kSpace8,
          runSpacing: AppTheme.metrics.kSpace4,
          children: [
            _InfoChip(icon: Icons.audiotrack_rounded, label: '$songCount 首'),
            if (playCount > 0)
              _InfoChip(icon: Icons.play_circle_outline_rounded, label: '$playCount 次播放'),
            if (author != null && author!.isNotEmpty)
              _InfoChip(icon: Icons.person_outline_rounded, label: author!),
            if (createdAt != null)
              _InfoChip(icon: Icons.calendar_today_rounded, label: _formatTimestamp(createdAt!)),
          ],
        ),
        if (tags != null && tags!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: AppTheme.metrics.kSpace4),
            child: Wrap(
              spacing: AppTheme.metrics.kSpace4,
              children: tags!.split(',').map((t) {
                final tag = t.trim();
                if (tag.isEmpty) return const SizedBox.shrink();
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.metrics.kSpace8,
                    vertical: AppTheme.metrics.kSpace2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace4),
                  ),
                  child: Text(
                    tag,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: AppTheme.metrics.fontSize10,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        SizedBox(height: AppTheme.metrics.kSpace12),
        // 操作按钮
        Row(
          children: [
            // 全部播放
            ElevatedButton.icon(
              onPressed: onPlayAll,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('全部播放'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace16,
                  vertical: AppTheme.metrics.kSpace6,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            SizedBox(width: AppTheme.metrics.kSpace8),
            // 导入文件
            OutlinedButton.icon(
              onPressed: onImportFiles,
              icon: const Icon(Icons.file_open_rounded, size: 18),
              label: const Text('导入文件'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace12,
                  vertical: AppTheme.metrics.kSpace6,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            SizedBox(width: AppTheme.metrics.kSpace8),
            // 导入文件夹
            OutlinedButton.icon(
              onPressed: onImportFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('导入文件夹'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace12,
                  vertical: AppTheme.metrics.kSpace6,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const Spacer(),
            // 设置
            IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: '设置',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTimestamp(int ts) {
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

/// 信息标签
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).hintColor),
        SizedBox(width: AppTheme.metrics.kSpace2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).hintColor,
            fontSize: AppTheme.metrics.fontSize11,
          ),
        ),
      ],
    );
  }
}

/// 音乐播放器顶部工具栏（收藏、最近播放、均衡器）
class _MusicPlayerToolbar extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  final VoidCallback onFavorites;
  final VoidCallback onRecentPlayed;
  final VoidCallback onEqPanel;

  const _MusicPlayerToolbar({
    required this.viewModel,
    required this.onFavorites,
    required this.onRecentPlayed,
    required this.onEqPanel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DesktopHeadToolsButton(
          icon: const Icon(Icons.favorite_rounded, size: 16),
          size: 32,
          onTap: onFavorites,
        ),
        DesktopHeadToolsButton(
          icon: const Icon(Icons.history_rounded, size: 16),
          size: 32,
          onTap: onRecentPlayed,
        ),
        DesktopHeadToolsButton(
          icon: const Icon(Icons.equalizer_rounded, size: 16),
          size: 32,
          onTap: onEqPanel,
        ),
      ],
    );
  }
}
