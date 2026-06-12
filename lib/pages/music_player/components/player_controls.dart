import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';

/// 播放控制按钮组
class PlayerControls extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  final bool compact;

  /// 统一图标颜色（沉浸式页面传白色）
  final Color? color;

  const PlayerControls({super.key, required this.viewModel, this.compact = false, this.color});

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);
    return _buildFull(context);
  }

  Widget _buildFull(BuildContext context) {
    return Obx(() {
      final playing = viewModel.isPlaying.value;
      final mode = viewModel.playMode.value;
      final position = viewModel.currentPositionMs.value;
      final duration = viewModel.durationMs.value;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  viewModel.formatDuration(position),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: duration > 0 ? position.clamp(0, duration).toDouble() : 0,
                    min: 0,
                    max: duration.toDouble(),
                    onChanged: (v) => viewModel.seekTo(v.toInt()),
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  viewModel.formatDuration(duration),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          SizedBox(height: AppTheme.metrics.kSpace4),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 播放模式
              IconButton(
                onPressed: viewModel.cyclePlayMode,
                icon: Icon(mode.icon, size: 20),
                tooltip: mode.label,
                color: mode != PlayerPlayMode.sequential
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              // 上一曲
              IconButton(
                onPressed: viewModel.playPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 28,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              // 播放/暂停
              IconButton(
                onPressed: viewModel.togglePlayPause,
                icon: Icon(
                  playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                ),
                iconSize: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              // 下一曲
              IconButton(
                onPressed: viewModel.playNext,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 28,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              // 收藏
              Obx(() {
                final item = viewModel.currentItem;
                final isFav = item?.isFavorite ?? false;
                return IconButton(
                  onPressed: item != null ? () => viewModel.toggleFavorite(item.id) : null,
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 20,
                    color: isFav ? Colors.redAccent : null,
                  ),
                );
              }),
            ],
          ),
        ],
      );
    });
  }

  Widget _buildCompact(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;
    return Obx(() {
      final playing = viewModel.isPlaying.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: viewModel.playPrevious,
            icon: const Icon(Icons.skip_previous_rounded, size: 38),
            color: iconColor,
          ),
          IconButton(
            onPressed: viewModel.togglePlayPause,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 48),
            color: iconColor,
          ),
          IconButton(
            onPressed: viewModel.playNext,
            icon: const Icon(Icons.skip_next_rounded, size: 38),
            color: iconColor,
          ),
        ],
      );
    });
  }
}
