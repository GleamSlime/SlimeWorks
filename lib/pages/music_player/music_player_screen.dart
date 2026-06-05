import 'dart:io';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/pages/music_player/components/vinyl_disc_animation.dart';
import 'package:slime_works/pages/music_player/components/music_list_item.dart';
import 'package:slime_works/pages/music_player/components/playlist_sidebar.dart';
import 'package:slime_works/pages/music_player/components/player_controls.dart';

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

    return Obx(() {
      // 桌面端：左侧播放列表侧边栏 + 右侧主内容
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
              Row(
                children: [
                  // 左侧播放列表
                  SizedBox(
                    width: _kSidebarWidth,
                    child: PlaylistSidebar(viewModel: viewModel),
                  ),
                  // 右侧主内容（唱片机 + 歌曲列表）
                  Expanded(child: _buildMainContent(context, isMobile: false)),
                ],
              ),
              if (_isDraggingFiles)
                Positioned.fill(child: IgnorePointer(child: _buildDragOverlay(context))),
            ],
          ),
        );
      }

      // 移动端：全屏布局，底部固定播放控制栏
      return Column(
        children: [
          Expanded(child: _buildMainContent(context, isMobile: true)),
          _buildMobilePlayerBar(context),
        ],
      );
    });
  }

  /// 主内容区域：唱片机动效 + 歌曲列表
  Widget _buildMainContent(BuildContext context, {required bool isMobile}) {
    final coverPath = viewModel.currentCoverPath.value;

    return Container(
      // 封面背景模糊效果（网易音乐风格）
      decoration: coverPath != null && File(coverPath).existsSync()
          ? BoxDecoration(
              image: DecorationImage(
                image: FileImage(File(coverPath)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.6),
                  BlendMode.dstATop,
                ),
              ),
            )
          : null,
      child: Container(
        // 二次模糊遮罩
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.85),
        child: Column(
          children: [
            // 唱片机播放动效区域
            if (!isMobile) SizedBox(height: 280, child: _buildVinylSection(context)),
            if (isMobile) SizedBox(height: 200, child: _buildVinylSection(context)),
            // 导入状态提示
            Obx(() {
              if (!viewModel.isImporting.value && viewModel.importingStatus.value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
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
        ),
      ),
    );
  }

  /// 唱片机播放动效区域
  Widget _buildVinylSection(BuildContext context) {
    final coverPath = viewModel.currentCoverPath.value;
    final title = viewModel.currentTitle.value;
    final artist = viewModel.currentArtist.value;
    final album = viewModel.currentAlbum.value;
    final playing = viewModel.isPlaying.value;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 封面背景模糊层
        if (coverPath != null && File(coverPath).existsSync())
          Positioned.fill(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Image.file(
                  File(coverPath),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
        // 内容
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 唱片机动效
                VinylDiscAnimation(coverPath: coverPath, isPlaying: playing, size: 160),
                SizedBox(width: appMetrics.kSpace24),
                // 歌曲信息 + 控制按钮
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.isEmpty ? '未选择歌曲' : title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (artist != null)
                        Padding(
                          padding: EdgeInsets.only(top: appMetrics.kSpace4),
                          child: Text(
                            artist,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (album != null)
                        Padding(
                          padding: EdgeInsets.only(top: appMetrics.kSpace2),
                          child: Text(
                            album,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).hintColor.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      SizedBox(height: appMetrics.kSpace12),
                      // 播放控制按钮
                      PlayerControls(viewModel: viewModel, compact: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
              size: appMetrics.iconSize48,
              color: Theme.of(context).hintColor,
            ),
            SizedBox(height: appMetrics.kSpace12),
            Text(
              '暂无音乐，点击导入按钮添加',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            ),
            SizedBox(height: appMetrics.kSpace12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: viewModel.pickAndImportFiles,
                  icon: const Icon(Icons.file_open_rounded),
                  label: const Text('选择文件'),
                ),
                SizedBox(width: appMetrics.kSpace8),
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
            horizontal: appMetrics.kSpace16,
            vertical: appMetrics.kSpace8,
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
                      borderRadius: BorderRadius.circular(appMetrics.kSpace8),
                    ),
                  ),
                  onChanged: (v) => viewModel.searchQuery.value = v,
                ),
              ),
              SizedBox(width: appMetrics.kSpace8),
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
            padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace16),
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
              );
            },
          ),
        ),
      ],
    );
  }

  /// 移动端底部播放控制栏
  Widget _buildMobilePlayerBar(BuildContext context) {
    final title = viewModel.currentTitle.value;
    final artist = viewModel.currentArtist.value;
    final coverPath = viewModel.currentCoverPath.value;
    final playing = viewModel.isPlaying.value;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          // 封面缩略图
          if (coverPath != null && File(coverPath).existsSync())
            Padding(
              padding: EdgeInsets.all(appMetrics.kSpace8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(appMetrics.kSpace4),
                child: Image.file(File(coverPath), width: 48, height: 48, fit: BoxFit.cover),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(appMetrics.kSpace8),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(appMetrics.kSpace4),
                ),
                child: const Icon(Icons.music_note_rounded, size: 24),
              ),
            ),
          // 歌曲信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title.isEmpty ? '未选择歌曲' : title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist != null)
                  Text(
                    artist,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // 控制按钮
          IconButton(
            onPressed: viewModel.playPrevious,
            icon: const Icon(Icons.skip_previous_rounded, size: 28),
          ),
          IconButton(
            onPressed: viewModel.togglePlayPause,
            icon: Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          IconButton(
            onPressed: viewModel.playNext,
            icon: const Icon(Icons.skip_next_rounded, size: 28),
          ),
        ],
      ),
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
              size: appMetrics.iconSize64,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: appMetrics.kSpace12),
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
}
