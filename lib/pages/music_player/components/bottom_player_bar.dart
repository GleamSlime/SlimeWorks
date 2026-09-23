import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_chips.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
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
          height: scaleW(72),
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
      height: scaleW(3),
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
                Positioned.fill(
                  child: ColoredBox(color: AppSemantic.of(context).border),
                ),
                // 已播放进度
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: AppSemantic.of(context).accent,
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
    final s = AppSemantic.of(context);
    return BoxDecoration(
      // 播放条压在列表之上，整块实心就把整窗的磨砂截断了；浮层档透明度，
      // 上面还有内容区的底色兜着，文字对比度不受影响。
      color: s.surfaceRaised.withAlpha(WindowGlass.overlayAlpha),
      border: Border(top: BorderSide(color: s.hairline, width: scaleW(1))),
      // 投影朝上：这条是贴在窗口底边的停靠栏，向下的影子落在窗口外等于没有。
      boxShadow: [
        for (final shadow in s.elevation(Elevation.floating))
          shadow.copyWith(offset: Offset(shadow.offset.dx, -shadow.offset.dy.abs())),
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
                style: AppTextStyles.cardTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (artist != null)
                Text(
                  artist,
                  style: AppTextStyles.caption(context),
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
    final size = scaleW(44);
    if (coverPath != null && File(coverPath).existsSync()) {
      return ClipRRect(
        borderRadius: AppTheme.metrics.radius6,
        child: Image.file(
          File(coverPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildDefaultCover(context, size),
        ),
      );
    }
    return _buildDefaultCover(context, size);
  }

  Widget _buildDefaultCover(BuildContext context, double size) {
    final s = AppSemantic.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 占位底必须比卡片更暗：这里原来是 surfaceRaised（亮色下就是白），
        // 压在白色播放条上等于一块看不见的空白。
        color: s.surfaceSunken,
        borderRadius: AppTheme.metrics.radius6,
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: s.textTertiary,
      ),
    );
  }

  /// 中间播放控件
  Widget _buildPlayControls(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final playing = viewModel.isPlaying.value;
    final mode = viewModel.playMode.value;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放模式
        IconButton(
          onPressed: viewModel.cyclePlayMode,
          icon: Icon(mode.icon, size: m.iconSize18),
          tooltip: mode.label,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: m.kSpace32,
            minHeight: m.kSpace32,
          ),
          color: mode != PlayerPlayMode.sequential ? s.accent : s.textTertiary,
        ),
        SizedBox(width: m.kSpace4),
        // 上一曲
        IconButton(
          onPressed: viewModel.playPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: m.iconSize22,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: scaleW(36),
            minHeight: scaleW(36),
          ),
        ),
        SizedBox(width: m.kSpace4),
        // 播放/暂停
        IconButton(
          onPressed: viewModel.togglePlayPause,
          icon: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          iconSize: scaleW(26),
          // 底色必须走 styleFrom 而不是外面套一个圆形 Container：Container 在
          // InkWell 之下，涟漪会方形溢出圆钮，圆形底也吃不到按压反馈。
          style: IconButton.styleFrom(
            backgroundColor: s.accent,
            foregroundColor: s.accentOn,
            padding: EdgeInsets.zero,
            minimumSize: Size(scaleW(40), scaleW(40)),
            shape: const CircleBorder(),
          ),
        ),
        SizedBox(width: m.kSpace4),
        // 下一曲
        IconButton(
          onPressed: viewModel.playNext,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: m.iconSize22,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: scaleW(36),
            minHeight: scaleW(36),
          ),
        ),
        SizedBox(width: m.kSpace4),
        // 收藏
        Obx(() {
          final item = viewModel.currentItem;
          final isFav = item?.isFavorite ?? false;
          return IconButton(
            onPressed: item != null ? () => viewModel.toggleFavorite(item.id) : null,
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: m.iconSize18,
            ),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: m.kSpace32,
              minHeight: m.kSpace32,
            ),
            // 收藏是"选中"，不是"危险"：用强调色，和全站选中态一个口径。
            color: isFav ? s.accent : s.textTertiary,
          );
        }),
      ],
    );
  }

  /// 右侧功能按钮
  Widget _buildRightActions(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 播放顺序指示
        Obx(() {
          final mode = viewModel.playMode.value;
          return ToolIconButton(
            icon: mode.icon,
            tooltip: mode.label,
            selected: mode != PlayerPlayMode.sequential,
            onPressed: viewModel.cyclePlayMode,
          );
        }),
        SizedBox(width: m.kSpace4),
        // 歌词
        Obx(() => ToolIconButton(
          icon: Icons.lyrics_outlined,
          tooltip: '歌词',
          selected: viewModel.showLyricsPanel.value,
          onPressed: viewModel.toggleLyricsPanel,
        )),
        SizedBox(width: m.kSpace4),
        // 音量
        _VolumePopup(viewModel: viewModel),
        SizedBox(width: m.kSpace4),
        // 播放列表
        ToolIconButton(
          icon: Icons.queue_music_rounded,
          tooltip: '播放列表',
          onPressed: () {
            // 切换侧边栏可见性（由主页面处理）
          },
        ),
      ],
    );
  }
}

/// 音量弹出调节
class _VolumePopup extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  const _VolumePopup({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return PopupMenuButton<void>(
      icon: Obx(() {
        final v = viewModel.volume.value;
        return Icon(
          v == 0
              ? Icons.volume_off_rounded
              : v < 50
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded,
          size: m.iconSize20,
          color: s.textTertiary,
        );
      }),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: m.kSpace32,
        minHeight: m.kSpace32,
      ),
      position: PopupMenuPosition.over,
      itemBuilder: (ctx) => [
        // 菜单里塞控件：这条必须是 enabled:false，否则点滑块会直接关掉整个菜单。
        PopupMenuItem<void>(
          enabled: false,
          height: scaleW(34),
          child: Obx(() => Row(
            children: [
              Icon(
                viewModel.volume.value == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_down_rounded,
                size: m.iconSize18,
                color: s.textTertiary,
              ),
              SizedBox(width: m.kSpace8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: scaleW(3),
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: m.kSpace6,
                    ),
                  ),
                  child: Slider(
                    value: viewModel.volume.value.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (v) => viewModel.setVolume(v.toInt()),
                  ),
                ),
              ),
              SizedBox(width: m.kSpace4),
              SizedBox(
                width: m.kSpace32,
                child: Text(
                  '${viewModel.volume.value}',
                  style: AppTextStyles.caption(context),
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
