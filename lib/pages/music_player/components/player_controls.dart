import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
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
                width: m.kSpace40,
                child: Text(
                  viewModel.formatDuration(position),
                  style: AppTextStyles.caption(context),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: scaleW(3),
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: m.kSpace6,
                    ),
                    overlayShape: RoundSliderOverlayShape(
                      overlayRadius: m.kSpace12,
                    ),
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
                width: m.kSpace40,
                child: Text(
                  viewModel.formatDuration(duration),
                  style: AppTextStyles.caption(context),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          SizedBox(height: m.kSpace4),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 播放模式
              IconButton(
                onPressed: viewModel.cyclePlayMode,
                icon: DrawIcon(mode.icon, size: m.iconSize20),
                tooltip: mode.label,
                color: mode != PlayerPlayMode.sequential ? s.accent : null,
              ),
              SizedBox(width: m.kSpace8),
              // 上一曲
              IconButton(
                onPressed: viewModel.playPrevious,
                icon: DrawIcon(StrokeIcons.skipPrevious),
                iconSize: m.iconSize28,
              ),
              SizedBox(width: m.kSpace8),
              // 播放/暂停
              IconButton(
                onPressed: viewModel.togglePlayPause,
                icon: DrawIcon(
                  playing ? StrokeIcons.pauseCircleFilled : StrokeIcons.playCircleFilled,
                ),
                iconSize: m.iconSize40,
                color: s.accent,
              ),
              SizedBox(width: m.kSpace8),
              // 下一曲
              IconButton(
                onPressed: viewModel.playNext,
                icon: DrawIcon(StrokeIcons.skipNext),
                iconSize: m.iconSize28,
              ),
              SizedBox(width: m.kSpace8),
              // 收藏
              Obx(() {
                final item = viewModel.currentItem;
                final isFav = item?.isFavorite ?? false;
                return IconButton(
                  onPressed: item != null ? () => viewModel.toggleFavorite(item.id) : null,
                  icon: DrawIcon(
                    isFav ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
                    size: m.iconSize20,
                    // 收藏是"选中"，用强调色；原来的 Colors.redAccent 不在状态色体系里。
                    color: isFav ? s.accent : null,
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
    final m = AppTheme.metrics;
    final iconColor = color ?? AppSemantic.of(context).accent;
    return Obx(() {
      final playing = viewModel.isPlaying.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: viewModel.playPrevious,
            icon: DrawIcon(StrokeIcons.skipPrevious, size: scaleW(38)),
            color: iconColor,
          ),
          IconButton(
            onPressed: viewModel.togglePlayPause,
            icon: DrawIcon(playing ? StrokeIcons.pause : StrokeIcons.playArrow, size: m.iconSize48),
            color: iconColor,
          ),
          IconButton(
            onPressed: viewModel.playNext,
            icon: DrawIcon(StrokeIcons.skipNext, size: scaleW(38)),
            color: iconColor,
          ),
        ],
      );
    });
  }
}
