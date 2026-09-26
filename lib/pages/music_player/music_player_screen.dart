import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
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
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 侧边栏宽度
///
/// 用 getter 而不是 const：scaleW 按当前窗口宽度折算，写死 220 的话窗口缩小侧边栏也不会跟着收。
double get _kSidebarWidth => scaleW(220);

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
          final s = AppSemantic.of(context);
          final m = AppTheme.metrics;
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: m.kSpace16,
              vertical: m.kSpace8,
            ),
            // 强调色容器：原来用 colorScheme.primaryContainer 是 fromSeed 派生出来的，
            // 不跟着 accent 主题色走，换主题色时这块会单独变色。
            color: s.accentContainer,
            child: Row(
              children: [
                // 有确定进度时显示确定进度条，否则转圈
                SizedBox(
                  width: m.iconSize16,
                  child: viewModel.importingProgress.value < 0
                      ? CircularProgressIndicator(
                          strokeWidth: scaleW(2),
                          color: s.accent,
                        )
                      : LinearProgressIndicator(
                          value: viewModel.importingProgress.value.clamp(0.0, 1.0),
                          backgroundColor: s.accent.withValues(alpha: 0.2),
                        ),
                ),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Text(
                    viewModel.importingStatus.value,
                    style: AppTextStyles.body(context).copyWith(color: s.accentText),
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
        onImportAsmr: () => _showAsmrImportDialog(context),
        onSettings: () => _showPlaylistSettings(context),
      );
    });
  }

  /// 歌曲列表
  ///
  /// 搜索栏常驻：空列表原先整块换成"暂无音乐 + 导入按钮"，把搜索框一起带走了，
  /// 于是搜不到结果时用户既改不了关键词，也看不到自己其实在搜索。
  Widget _buildSongList(BuildContext context) {
    final items = viewModel.filteredItems;
    final m = AppTheme.metrics;

    return Column(
      children: [
        // 搜索栏 + 操作按钮
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
          child: Row(
            children: [
              // 搜索
              Expanded(
                child: TextField(
                  onChanged: (v) => viewModel.searchQuery.value = v,
                  decoration: const InputDecoration(
                    hintText: '搜索歌曲...',
                    prefixIcon: DrawIcon(StrokeIcons.search),
                  ),
                ),
              ),
              SizedBox(width: m.kSpace8),
              ToolIconButton(
                icon: StrokeIcons.fileOpen,
                tooltip: '导入文件',
                onPressed: viewModel.pickAndImportFiles,
              ),
              ToolIconButton(
                icon: StrokeIcons.folderOpen,
                tooltip: '导入文件夹',
                onPressed: viewModel.pickAndImportFolder,
              ),
              ToolIconButton(
                icon: StrokeIcons.link,
                tooltip: 'ASMR链接导入',
                onPressed: () => _showAsmrImportDialog(context),
              ),
              ToolIconButton(
                icon: StrokeIcons.add,
                tooltip: '新建播放列表',
                onPressed: () => _showCreatePlaylistDialog(context),
              ),
            ],
          ),
        ),
        // 列表
        Expanded(
          child: items.isEmpty
              ? _buildEmptySongs(context)
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace16),
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
                      onRevealTap: () => viewModel.revealInFileManager(item.filePath),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptySongs(BuildContext context) {
    final m = AppTheme.metrics;
    // 搜索无结果和真的没导入过是两回事，共用一句"点击导入按钮添加"会让人以为列表被清空了。
    if (viewModel.searchQuery.value.trim().isNotEmpty) {
      return const EmptyState(
        icon: StrokeIcons.search,
        title: '未找到匹配的歌曲',
        description: '换个关键词试试',
      );
    }
    return EmptyState(
      icon: StrokeIcons.musicNote,
      title: '暂无音乐',
      description: '把音频文件直接拖进窗口，或用下面的按钮导入',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: m.kSpace8,
        runSpacing: m.kSpace8,
        children: [
          ElevatedButton.icon(
            onPressed: viewModel.pickAndImportFiles,
            icon: DrawIcon(StrokeIcons.fileOpen),
            label: const Text('选择文件'),
          ),
          ElevatedButton.icon(
            onPressed: viewModel.pickAndImportFolder,
            icon: DrawIcon(StrokeIcons.folderOpen),
            label: const Text('选择文件夹'),
          ),
          OutlinedButton.icon(
            onPressed: () => _showAsmrImportDialog(context),
            icon: DrawIcon(StrokeIcons.link),
            label: const Text('ASMR链接'),
          ),
        ],
      ),
    );
  }

  /// 拖拽导入覆盖层
  Widget _buildDragOverlay(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      // 内缩一圈再画描边：贴窗口边的描边会被 macOS 的圆角切掉，看着像渲染坏了。
      padding: EdgeInsets.all(m.kSpace10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: s.accent.withValues(alpha: 0.08),
          borderRadius: m.radiusPanel,
          border: Border.all(color: s.accent, width: scaleW(2)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DrawIcon(StrokeIcons.musicNote, size: m.iconSize64, color: s.accent),
              SizedBox(height: m.kSpace12),
              Text(
                '松开以导入音乐',
                style: AppTextStyles.sectionTitle(context).copyWith(color: s.accentText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放列表/文件夹设置
  void _showPlaylistSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final s = AppSemantic.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: DrawIcon(StrokeIcons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenamePlaylistDialog(context);
                },
              ),
              ListTile(
                leading: DrawIcon(StrokeIcons.image),
                title: const Text('更换封面'),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: DrawIcon(StrokeIcons.folder),
                title: const Text('移动到目录'),
                onTap: () => Navigator.pop(ctx),
              ),
              // 批量语音识别
              ListTile(
                leading: DrawIcon(StrokeIcons.recordVoiceOver),
                title: const Text('批量语音识别'),
                subtitle: Text(
                  '识别当前列表 ${viewModel.currentItems.length} 首歌曲',
                  style: AppTextStyles.caption(ctx),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  viewModel.transcribeAllItems();
                },
              ),
              const AppDivider(),
              // 危险项整行染色：混在一列普通操作里最容易被顺手点到。
              ListTile(
                leading: DrawIcon(StrokeIcons.deleteOutline, color: s.danger.color),
                title: Text('删除播放列表', style: TextStyle(color: s.danger.color)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
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
          decoration: const InputDecoration(hintText: '名称'),
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
          decoration: const InputDecoration(hintText: '播放列表名称'),
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

  /// ASMR 链接导入对话框
  void _showAsmrImportDialog(BuildContext context) {
    final urlController = TextEditingController();
    // 下载选项（本地下载模式默认开启）
    var downloadLocal = true;
    var remoteStream = false;
    var mp3 = true;
    var wav = false;

    void submit() {
      final url = urlController.text.trim();
      if (url.isEmpty) return;
      final formats = <String>{if (mp3) 'mp3', if (wav) 'wav'};
      Navigator.of(context).pop();
      viewModel.importAsmrLink(
        url,
        downloadLocal: downloadLocal,
        remoteStream: remoteStream,
        formats: formats,
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ASMR 链接导入'),
        content: StatefulBuilder(
          builder: (ctx, setState) => SizedBox(
            width: scaleW(420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动抓取作品信息：可下载到本地「下载/asmr」目录并导入，或直接导入远程流地址。',
                  style: AppTextStyles.caption(ctx),
                ),
                SizedBox(height: AppTheme.metrics.kSpace12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'ASMR 链接',
                    hintText: 'https://asmr.one/work/RJ01292783',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                // 下载方式
                CheckboxListTile(
                  value: downloadLocal,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('下载到本地'),
                  subtitle: const Text('音频保存到「下载/asmr」并扫描入库'),
                  onChanged: (v) => setState(() {
                    downloadLocal = v ?? false;
                    if (downloadLocal) remoteStream = false;
                  }),
                ),
                CheckboxListTile(
                  value: remoteStream,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('远程流地址'),
                  subtitle: const Text('仅导入可在线播放的流地址，不下载文件'),
                  onChanged: (v) => setState(() {
                    remoteStream = v ?? false;
                    if (remoteStream) downloadLocal = false;
                  }),
                ),
                // 下载格式（本地下载模式可选）
                if (downloadLocal) ...[
                  AppDivider(spacing: AppTheme.metrics.kSpace16),
                  Text(
                    '下载格式',
                    style: AppTextStyles.caption(ctx),
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: mp3,
                        onChanged: (v) => setState(() => mp3 = v ?? false),
                      ),
                      const Text('mp3'),
                      SizedBox(width: AppTheme.metrics.kSpace16),
                      Checkbox(
                        value: wav,
                        onChanged: (v) => setState(() => wav = v ?? false),
                      ),
                      const Text('wav'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton.icon(
            onPressed: submit,
            icon: DrawIcon(StrokeIcons.link, size: AppTheme.metrics.iconSize18),
            label: const Text('导入'),
          ),
        ],
      ),
    );
  }

  /// 显示均衡器
  void _showEqPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const EqPanel(),
    );
  }

  /// 收藏 / 最近播放共用的底部抽屉
  ///
  /// 这两个抽屉原先各写了一遍完整的 sheet（标题行、分割线、空态、行样式），
  /// 改一处就得记得改两处。这里只留差异：标题、图标、数据源和行内容。
  /// 数据源用回调传：抽屉里的 Obx 需要在弹开后继续跟随 Rx 变化。
  void _showTrackSheet<T>({
    required BuildContext context,
    required String title,
    required StrokeIcon icon,
    required String emptyTitle,
    required List<T> Function() items,
    required Widget Function(BuildContext context, T item) tileBuilder,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // 底色交给 bottomSheetTheme：这里再铺一层实心画布会把主题的浮层配色整个盖掉，抽屉因此不透。
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Obx(() {
          final list = items();
          final m = AppTheme.metrics;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.all(m.kSpace16),
                child: Row(
                  children: [
                    DrawIcon(icon, size: m.iconSize18, color: AppSemantic.of(ctx).accent),
                    SizedBox(width: m.kSpace8),
                    Text(title, style: AppTextStyles.sectionTitle(ctx)),
                    const Spacer(),
                    Text('${list.length} 首', style: AppTextStyles.caption(ctx)),
                  ],
                ),
              ),
              const AppDivider(),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(icon: icon, title: emptyTitle, compact: true)
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: list.length,
                        itemBuilder: (_, index) => tileBuilder(ctx, list[index]),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }

  /// 显示收藏列表
  void _showFavorites(BuildContext context) async {
    await viewModel.loadFavorites();
    if (!context.mounted) return;
    _showTrackSheet(
      context: context,
      title: '收藏',
      icon: StrokeIcons.favorite,
      emptyTitle: '暂无收藏',
      items: () => viewModel.favoriteItems,
      tileBuilder: (ctx, item) => _TrackTile(
        title: item.title,
        artist: item.artist,
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
      ),
    );
  }

  /// 显示最近播放
  void _showRecentPlayed(BuildContext context) async {
    await viewModel.loadRecentPlayed();
    if (!context.mounted) return;
    _showTrackSheet(
      context: context,
      title: '最近播放',
      icon: StrokeIcons.history,
      emptyTitle: '暂无播放记录',
      items: () => viewModel.recentRecords,
      tileBuilder: (ctx, record) {
        final musicItem = viewModel.currentItems.firstWhereOrNull(
          (i) => i.id == record.musicId,
        );
        return _TrackTile(
          title: musicItem?.title ?? '未知歌曲',
          artist: musicItem?.artist,
          onTap: () {
            Navigator.pop(ctx);
            final idx = viewModel.currentItems.indexWhere((i) => i.id == record.musicId);
            if (idx >= 0) viewModel.playItem(idx);
          },
        );
      },
    );
  }
}

/// 抽屉里的歌曲行
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.title, this.artist, this.onTap});

  final String title;
  final String? artist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: DrawIcon(StrokeIcons.musicNote, size: m.iconSize20, color: s.textTertiary),
      title: Text(
        title,
        style: AppTextStyles.rowTitle(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        artist ?? '未知艺术家',
        style: AppTextStyles.caption(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
  final VoidCallback onImportAsmr;
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
    required this.onImportAsmr,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return Container(
      padding: EdgeInsets.fromLTRB(m.kSpace24, m.kSpace20, m.kSpace24, m.kSpace16),
      decoration: BoxDecoration(
        // 整块不透明会把窗口磨砂彻底盖掉；渐变本身保留，只降到分区面板那一档。
        // 原来这里按 isDark 手写了两组十六进制色，换主题色时这块不会跟着变。
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [s.surface, s.surfaceSunken]
              .map((color) => color.withAlpha(WindowGlass.panelAlpha))
              .toList(),
        ),
        border: Border(bottom: BorderSide(color: s.hairline, width: scaleW(1))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          _buildCover(context),
          SizedBox(width: m.kSpace20),
          // 信息 + 操作
          Expanded(child: _buildInfo(context)),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final coverSize = scaleW(96);
    final hasCover = coverPath != null && File(coverPath!).existsSync();

    return GestureDetector(
      onTap: onSettings,
      child: Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          borderRadius: m.radiusCard,
          // 占位底色必须是比表面更暗的一档：surfaceContainerHighest 在亮色下比白卡片还亮，
          // 没封面的时候这里就是一片纯白，看不出是块可点的封面区域。
          color: s.surfaceSunken,
          boxShadow: s.elevation(Elevation.raised),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      color: s.surfaceSunken,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 装饰性音符
          DrawIcon(StrokeIcons.musicNote,
            size: size * 0.35,
            color: s.accent.withValues(alpha: 0.4),
          ),
          // 右下角设置图标
          Positioned(
            right: m.kSpace4,
            bottom: m.kSpace4,
            child: DrawIcon(StrokeIcons.settings,
              size: m.iconSize14,
              color: s.textTertiary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 名称
        Text(
          name,
          style: AppTextStyles.pageTitle(context),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: m.kSpace8),
        // 统计信息标签
        Wrap(
          spacing: m.kSpace12,
          runSpacing: m.kSpace4,
          children: [
            _InfoChip(icon: StrokeIcons.audiotrack, label: '$songCount 首'),
            if (playCount > 0)
              _InfoChip(icon: StrokeIcons.playCircleOutline, label: '$playCount 次播放'),
            if (author != null && author!.isNotEmpty)
              _InfoChip(icon: StrokeIcons.personOutline, label: author!),
            if (createdAt != null)
              _InfoChip(icon: StrokeIcons.calendarToday, label: _formatTimestamp(createdAt!)),
          ],
        ),
        if (tags != null && tags!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: m.kSpace8),
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace4,
              children: [
                for (final raw in tags!.split(','))
                  if (raw.trim().isNotEmpty) TagChip(label: raw.trim()),
              ],
            ),
          ),
        SizedBox(height: m.kSpace12),
        // 操作按钮
        // 按钮区用 Wrap 而不是 Row： Row + Spacer 在窗口变窄时会直接溢出报错。
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: m.kSpace8,
                runSpacing: m.kSpace8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 全部播放
                  ElevatedButton.icon(
                    onPressed: onPlayAll,
                    icon: DrawIcon(StrokeIcons.playArrow, size: m.iconSize20),
                    label: const Text('全部播放'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace16,
                        vertical: m.kSpace6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // 导入文件
                  OutlinedButton.icon(
                    onPressed: onImportFiles,
                    icon: DrawIcon(StrokeIcons.fileOpen, size: m.iconSize18),
                    label: const Text('导入文件'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace12,
                        vertical: m.kSpace6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // 导入文件夹
                  OutlinedButton.icon(
                    onPressed: onImportFolder,
                    icon: DrawIcon(StrokeIcons.folderOpen, size: m.iconSize18),
                    label: const Text('导入文件夹'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace12,
                        vertical: m.kSpace6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // ASMR 链接导入
                  OutlinedButton.icon(
                    onPressed: onImportAsmr,
                    icon: DrawIcon(StrokeIcons.link, size: m.iconSize18),
                    label: const Text('ASMR链接'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace12,
                        vertical: m.kSpace6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace8),
            // 设置
            IconButton(
              onPressed: onSettings,
              icon: DrawIcon(StrokeIcons.moreHoriz),
              tooltip: '设置',
              style: IconButton.styleFrom(backgroundColor: s.surfaceSunken),
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
  final StrokeIcon icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DrawIcon(icon, size: m.iconSize14, color: s.textTertiary),
        SizedBox(width: m.kSpace4),
        Text(label, style: AppTextStyles.caption(context)),
      ],
    );
  }
}

/// 音乐播放器顶部工具栏（收藏、最近播放、均衡器）
class _MusicPlayerToolbar extends StatelessWidget {
  final VoidCallback onFavorites;
  final VoidCallback onRecentPlayed;
  final VoidCallback onEqPanel;

  const _MusicPlayerToolbar({
    required this.onFavorites,
    required this.onRecentPlayed,
    required this.onEqPanel,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      children: [
        DesktopHeadToolsButton(
          icon: DrawIcon(StrokeIcons.favorite, size: m.iconSize16),
          size: m.iconSize32,
          onTap: onFavorites,
        ),
        DesktopHeadToolsButton(
          icon: DrawIcon(StrokeIcons.history, size: m.iconSize16),
          size: m.iconSize32,
          onTap: onRecentPlayed,
        ),
        DesktopHeadToolsButton(
          icon: DrawIcon(StrokeIcons.equalizer, size: m.iconSize16),
          size: m.iconSize32,
          onTap: onEqPanel,
        ),
      ],
    );
  }
}
