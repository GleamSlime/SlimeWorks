import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/pages/music_player/components/vinyl_disc_animation.dart';
import 'package:slime_works/pages/music_player/components/player_controls.dart';

/// 沉浸式播放器页面（全屏唱片机）
///
/// 点击底部播放栏展开，无侧边栏，专注播放体验
class ImmersivePlayerScreen extends StatelessWidget {
  final MusicPlayerViewModel viewModel;

  const ImmersivePlayerScreen({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final coverPath = viewModel.currentCoverPath.value;
      final title = viewModel.currentTitle.value;
      final artist = viewModel.currentArtist.value;
      final album = viewModel.currentAlbum.value;
      final playing = viewModel.isPlaying.value;

      return Stack(
        fit: StackFit.expand,
        children: [
          // 半透明黑色高斯模糊背景
          Positioned.fill(
            child: _BlurredBackground(coverPath: coverPath),
          ),
          // 内容
          SafeArea(
            child: Column(
              children: [
                // 顶部工具栏
                _buildTopBar(context),
                // 中间唱片机区域（白色背景）
                Expanded(child: _buildVinylArea(context, coverPath, playing)),
                // 底部信息 + 控制区
                _buildBottomArea(context, title, artist, album),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 顶部工具栏
  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            onPressed: viewModel.exitImmersiveMode,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            iconSize: 28,
            color: Colors.white,
            tooltip: '收起',
          ),
          const Spacer(),
          // 更多操作
          IconButton(
            onPressed: () {
              _showMoreOptions(context);
            },
            icon: const Icon(Icons.more_vert_rounded),
            color: Colors.white,
            tooltip: '更多',
          ),
        ],
      ),
    );
  }

  /// 中间唱片机区域（白色背景）
  Widget _buildVinylArea(BuildContext context, String? coverPath, bool playing) {
    return Center(
      child: Container(
        width: 320,
        height: 320,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: VinylDiscAnimation(
            coverPath: coverPath,
            isPlaying: playing,
            size: 260,
          ),
        ),
      ),
    );
  }

  /// 底部信息 + 控制区
  Widget _buildBottomArea(BuildContext context, String title, String? artist, String? album) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 歌曲信息
          Text(
            title.isEmpty ? '未选择歌曲' : title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (artist != null || album != null)
            Padding(
              padding: EdgeInsets.only(top: AppTheme.metrics.kSpace8),
              child: Text(
                [if (artist != null) artist, if (album != null) album].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          SizedBox(height: AppTheme.metrics.kSpace24),
          // 进度条
          _buildProgressBar(context),
          SizedBox(height: AppTheme.metrics.kSpace16),
          // 播放控制（紧凑模式：仅上一首/播放/下一首，白色图标）
          PlayerControls(viewModel: viewModel, compact: true, color: Colors.white),
          SizedBox(height: AppTheme.metrics.kSpace16),
          // 底部功能按钮
          _buildBottomActions(context),
          SizedBox(height: AppTheme.metrics.kSpace16),
        ],
      ),
    );
  }

  /// 进度条
  Widget _buildProgressBar(BuildContext context) {
    return Obx(() {
      final position = viewModel.currentPositionMs.value;
      final duration = viewModel.durationMs.value;

      return Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              viewModel.formatDuration(position),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.white.withValues(alpha: 0.9),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: Colors.white,
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
            width: 48,
            child: Text(
              viewModel.formatDuration(duration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    });
  }

  /// 底部功能按钮
  Widget _buildBottomActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 播放模式
        Obx(() {
          final mode = viewModel.playMode.value;
          return _ActionButton(
            icon: mode.icon,
            label: mode.label,
            active: mode != PlayerPlayMode.sequential,
            onTap: viewModel.cyclePlayMode,
          );
        }),
        // 收藏
        Obx(() {
          final item = viewModel.currentItem;
          final isFav = item?.isFavorite ?? false;
          return _ActionButton(
            icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            label: '收藏',
            active: isFav,
            onTap: item != null ? () => viewModel.toggleFavorite(item.id) : null,
            activeColor: Colors.redAccent,
          );
        }),
        // 歌词
        Obx(() => _ActionButton(
          icon: Icons.lyrics_outlined,
          label: '歌词',
          active: viewModel.showLyricsPanel.value,
          onTap: viewModel.toggleLyricsPanel,
        )),
        // 均衡器
        _ActionButton(
          icon: Icons.equalizer_rounded,
          label: '均衡器',
          onTap: () => _showEqPanel(context),
        ),
        // 音量
        _VolumeSlider(viewModel: viewModel),
      ],
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('分享'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('添加到播放列表'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('歌曲信息'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showEqPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
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
              Text(
                '均衡器',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: AppTheme.metrics.kSpace16),
              // 均衡器内容（简化版）
              _EqSliders(viewModel: viewModel),
            ],
          ),
        ),
      ),
    );
  }
}

/// 半透明黑色高斯模糊背景
class _BlurredBackground extends StatelessWidget {
  final String? coverPath;
  const _BlurredBackground({this.coverPath});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面模糊层（如果有封面）
        if (coverPath != null && File(coverPath!).existsSync())
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Image.file(
              File(coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        // 半透明黑色遮罩
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// 功能按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color? activeColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? (activeColor ?? Theme.of(context).colorScheme.primary)
        : Colors.white.withValues(alpha: 0.7);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 24),
          color: color,
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: AppTheme.metrics.fontSize10,
          ),
        ),
      ],
    );
  }
}

/// 音量滑块
class _VolumeSlider extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  const _VolumeSlider({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final vol = viewModel.volume.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => viewModel.setVolume(vol > 0 ? 0 : 100),
            icon: Icon(
              vol == 0
                  ? Icons.volume_off_rounded
                  : vol < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 24,
            ),
            color: Colors.white.withValues(alpha: 0.7),
          ),
          Text(
            '音量',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: AppTheme.metrics.fontSize10,
            ),
          ),
        ],
      );
    });
  }
}

/// 均衡器滑块组（沉浸式播放器内使用）
class _EqSliders extends StatefulWidget {
  final MusicPlayerViewModel viewModel;
  const _EqSliders({required this.viewModel});

  @override
  State<_EqSliders> createState() => _EqSlidersState();
}

class _EqSlidersState extends State<_EqSliders> {
  /// 本地管理的频段增益值，不受 Obx 重建影响
  late List<double> _bands;

  /// 当前选中的预设 ID（本地缓存，用于检测切换）
  String? _lastPresetId;

  @override
  void initState() {
    super.initState();
    _bands = List.filled(10, 0.0);
    // 打开时加载均衡器预设
    widget.viewModel.loadEqPresets();
  }

  /// 从预设同步 bands 到本地状态
  void _syncBandsFromPreset(music_api.EqualizerPresetInfo? preset) {
    for (int i = 0; i < 10; i++) {
      _bands[i] = preset != null && i < preset.bands.length
          ? preset.bands[i]
          : 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    const freqLabels = ['32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

    return Obx(() {
      final presets = widget.viewModel.eqPresets;
      final currentId = widget.viewModel.currentEqPresetId.value;

      // 检测预设切换，从预设同步 bands
      if (currentId != _lastPresetId) {
        _lastPresetId = currentId;
        music_api.EqualizerPresetInfo? currentPreset;
        if (currentId != null) {
          for (final p in presets) {
            if (p.id == currentId) {
              currentPreset = p;
              break;
            }
          }
        }
        _syncBandsFromPreset(currentPreset);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 预设选择
          if (presets.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presets.length,
                separatorBuilder: (_, __) => SizedBox(width: AppTheme.metrics.kSpace8),
                itemBuilder: (context, index) {
                  final preset = presets[index];
                  final isSelected = preset.id == currentId;
                  return ChoiceChip(
                    label: Text(preset.name),
                    selected: isSelected,
                    onSelected: (_) {
                      widget.viewModel.currentEqPresetId.value = preset.id;
                    },
                  );
                },
              ),
            ),
          SizedBox(height: AppTheme.metrics.kSpace12),
          SizedBox(
            height: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(10, (i) {
                return Column(
                  children: [
                    Text(
                      '${_bands[i] > 0 ? "+" : ""}${_bands[i].toStringAsFixed(1)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            activeTrackColor: Colors.white.withValues(alpha: 0.9),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _bands[i].clamp(-12.0, 12.0),
                            min: -12,
                            max: 12,
                            divisions: 24,
                            onChanged: (v) {
                              setState(() {
                                _bands[i] = v;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    Text(
                      freqLabels[i],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      );
    });
  }
}
