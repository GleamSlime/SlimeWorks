import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';

/// 底部悬浮播放控制栏（网易音乐风格）
///
/// 布局：顶部可拖动进度条 → 下方左封面+歌名信息 | 中播放控件 | 右功能按钮
class BottomPlayerBar extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  final VoidCallback? onTapExpand;

  const BottomPlayerBar({super.key, required this.viewModel, this.onTapExpand});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasItem = viewModel.currentIndex.value >= 0;
      if (!hasItem) return const SizedBox.shrink();

      return GestureDetector(
        onTap: onTapExpand,
        child: Container(
          height: 72,
          decoration: _buildBarDecoration(context),
          child: Column(
            children: [
              // 顶部进度条
              _buildProgressBar(context),
              // 下方内容区
              Expanded(child: _buildContentRow(context)),
            ],
          ),
        ),
      );
    });
  }

  /// 进度条（细条，可拖动）
  Widget _buildProgressBar(BuildContext context) {
    final position = viewModel.currentPositionMs.value;
    final duration = viewModel.durationMs.value;
    final progress = duration > 0 ? position / duration : 0.0;

    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onHorizontalDragUpdate: (details) {
              final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              viewModel.seekTo((ratio * duration).toInt());
            },
            child: Stack(
              children: [
                // 背景轨道
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                // 已播放进度
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(AppTheme.metrics.kSpace2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _buildBarDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1C) : const Color(0xFFFAFAFA),
      border: Border(
        top: BorderSide(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ],
    );
  }

  /// 内容行：左信息 | 中控件 | 右功能
  Widget _buildContentRow(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12),
      child: Row(
        children: [
          // 左侧：封面 + 歌曲信息
          Expanded(flex: 3, child: _buildSongInfo(context)),
          // 中间：播放控件
          Expanded(flex: 4, child: _buildPlayControls(context)),
          // 右侧：功能按钮
          Expanded(flex: 3, child: _buildRightActions(context)),
        ],
      ),
    );
  }

  /// 左侧歌曲信息
  Widget _buildSongInfo(BuildContext context) {
    final coverPath = viewModel.currentCoverPath.value;
    final title = viewModel.currentTitle.value;
    final artist = viewModel.currentArtist.value;

    return Row(
      children: [
        // 封面
        _buildCoverThumb(context, coverPath),
        SizedBox(width: AppTheme.metrics.kSpace10),
        // 歌名 + 艺术家
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title.isEmpty ? '未选择歌曲' : title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: AppTheme.metrics.fontSize13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (artist != null)
                Text(
                  artist,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontSize: AppTheme.metrics.fontSize11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverThumb(BuildContext context, String? coverPath) {
    const size = 44.0;
    if (coverPath != null && File(coverPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace6),
        child: Image.file(
          File(coverPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultCover(context, size),
        ),
      );
    }
    return _buildDefaultCover(context, size);
  }

  Widget _buildDefaultCover(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace6),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  /// 中间播放控件
  Widget _buildPlayControls(BuildContext context) {
    final playing = viewModel.isPlaying.value;
    final mode = viewModel.playMode.value;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放模式
        IconButton(
          onPressed: viewModel.cyclePlayMode,
          icon: Icon(mode.icon, size: 18),
          tooltip: mode.label,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: mode != PlayerPlayMode.sequential
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).hintColor,
        ),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 上一曲
        IconButton(
          onPressed: viewModel.playPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 播放/暂停
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary,
          ),
          child: IconButton(
            onPressed: viewModel.togglePlayPause,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            iconSize: 26,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 下一曲
        IconButton(
          onPressed: viewModel.playNext,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 收藏
        Obx(() {
          final item = viewModel.currentItem;
          final isFav = item?.isFavorite ?? false;
          return IconButton(
            onPressed: item != null ? () => viewModel.toggleFavorite(item.id) : null,
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 18,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            color: isFav ? Colors.redAccent : Theme.of(context).hintColor,
          );
        }),
      ],
    );
  }

  /// 右侧功能按钮
  Widget _buildRightActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 播放顺序指示
        Obx(() {
          final mode = viewModel.playMode.value;
          return _ActionChip(
            icon: mode.icon,
            label: mode.label,
            active: mode != PlayerPlayMode.sequential,
            onTap: viewModel.cyclePlayMode,
          );
        }),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 歌词
        Obx(() => _ActionChip(
          icon: Icons.lyrics_outlined,
          label: '歌词',
          active: viewModel.showLyricsPanel.value,
          onTap: viewModel.toggleLyricsPanel,
        )),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 音量
        _VolumePopup(viewModel: viewModel),
        SizedBox(width: AppTheme.metrics.kSpace4),
        // 播放列表
        IconButton(
          onPressed: () {
            // 切换侧边栏可见性（由主页面处理）
          },
          icon: const Icon(Icons.queue_music_rounded, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: Theme.of(context).hintColor,
          tooltip: '播放列表',
        ),
      ],
    );
  }
}

/// 功能小按钮（带激活态）
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor,
      ),
    );
  }
}

/// 音量弹出调节
class _VolumePopup extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  const _VolumePopup({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      icon: Obx(() => Icon(
        viewModel.volume.value == 0
            ? Icons.volume_off_rounded
            : viewModel.volume.value < 50
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
        size: 20,
        color: Theme.of(context).hintColor,
      )),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      position: PopupMenuPosition.over,
      itemBuilder: (ctx) => [
        PopupMenuItem<void>(
          enabled: false,
          height: 48,
          child: Obx(() => Row(
            children: [
              Icon(
                viewModel.volume.value == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_down_rounded,
                size: 18,
                color: Theme.of(context).hintColor,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: viewModel.volume.value.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (v) => viewModel.setVolume(v.toInt()),
                  ),
                ),
              ),
              SizedBox(width: AppTheme.metrics.kSpace4),
              SizedBox(
                width: 32,
                child: Text(
                  '${viewModel.volume.value}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }
}
