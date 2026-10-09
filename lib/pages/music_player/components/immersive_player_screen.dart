import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';
import 'package:slime_works/pages/music_player/components/eq_panel.dart';
import 'package:slime_works/pages/music_player/components/vinyl_disc_animation.dart';
import 'package:slime_works/pages/music_player/components/player_controls.dart';
import 'package:slime_works/pages/music_player/components/waveform_seek_bar.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 沉浸式页面画在封面模糊层上，底色恒为深色，所以这一页的文字/轨道色不走主题语义色：
/// 语义色（textSecondary 等）是按"压在浅色表面上"设计的，放到深色 art 上会直接看不见。
/// 这里把原先散落的二十多处 `Colors.white.withValues(alpha: x)` 收成一套档位，
/// 保证同一层信息在页面各处是同一个白度。
///
/// 档位全部从媒体 chrome 令牌取（DESIGN §2.7）：逐字节对上命名档的就用命名档
/// （primary→`onMedia`、muted→`onMediaSecondary`、hairline→`immersiveBorder`、
/// panel→`scrim`），对不上的（80%/40%/90%/30% 白）按原像素写算式，
/// 不往邻近档靠——收编是治理，改了渲染像素就算失败。
/// 之所以是"由 [AppSemantic] 构造出来的实例"而不是 static const 一族：
/// 取色入口必须留在 `s.` 上，业务侧不需要知道这族不跟主题走。
final class _OnArt {
  const _OnArt(this._s);

  final AppSemantic _s;

  /// 主字/主图标（恒白）
  Color get primary => _s.onMedia;

  /// 80%，图标与需要分量的文字
  Color get secondary => _s.onMedia.withValues(alpha: .8);

  /// 70%，说明文字与未选中态
  Color get muted => _s.onMediaSecondary;

  /// 40%，歌词的未播放行
  Color get faint => _s.onMedia.withValues(alpha: .4);

  /// 90%，滑块与波形的已走段
  Color get track => _s.onMedia.withValues(alpha: .9);

  /// 30%，滑块与波形的未走段
  Color get trackDim => _s.onMedia.withValues(alpha: .3);

  /// 白 15% 发丝描边（沉浸式黑玻璃浮层那一档）
  Color get hairline => _s.immersiveBorder;

  /// 70% 黑，浮层底
  Color get panel => _s.scrim;
}

/// 当前主题解析出来的 art 档位表
_OnArt _onArt(BuildContext context) => _OnArt(AppSemantic.of(context));

/// 压在 art 上的滑块：进度条和音量浮层用同一份轨道口径
SliderThemeData _onArtSliderTheme(AppSemantic s) {
  final art = _OnArt(s);
  return SliderThemeData(
    trackHeight: scaleW(3),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: scaleW(6)),
    overlayShape: RoundSliderOverlayShape(overlayRadius: scaleW(12)),
    activeTrackColor: art.track,
    inactiveTrackColor: art.trackDim,
    thumbColor: art.primary,
  );
}

/// art 上的小号说明文字：进度时间、按钮标签、歌词行标签共用一档
TextStyle _artCaption(BuildContext context) =>
    AppTextStyles.caption(context).copyWith(color: _onArt(context).muted);

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
    final m = AppTheme.metrics;
    final art = _onArt(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            onPressed: viewModel.exitImmersiveMode,
            icon: DrawIcon(StrokeIcons.keyboardArrowDown),
            iconSize: m.iconSize28,
            color: art.primary,
            tooltip: '收起',
          ),
          const Spacer(),
          // 更多操作
          IconButton(
            onPressed: () {
              _showMoreOptions(context);
            },
            icon: DrawIcon(StrokeIcons.moreVert),
            color: art.primary,
            tooltip: '更多',
          ),
        ],
      ),
    );
  }

  /// 中间唱片机区域或歌词面板
  Widget _buildVinylArea(BuildContext context, String? coverPath, bool playing) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final showLyrics = viewModel.showLyricsPanel.value;
      if (showLyrics && viewModel.currentLyrics.isNotEmpty) {
        return _LyricsPanel(viewModel: viewModel);
      }
      final plateSize = scaleW(320);
      // 默认显示唱片机
      return Center(
        child: Container(
          width: plateSize,
          height: plateSize,
          decoration: BoxDecoration(
            // 白色唱片垫是有意跨明暗保持不变的：黑胶本体是深色物理质感，
            // 换成主题表面色后暗色模式下盘面会糊进背景里。
            // 这一档正是媒体 chrome 的恒白（`onMedia`），不参与明暗解析。
            color: s.onMedia,
            borderRadius: m.radiusOverlay,
            boxShadow: s.elevation(Elevation.card),
          ),
          child: Center(
            child: VinylDiscAnimation(
              coverPath: coverPath,
              isPlaying: playing,
              size: scaleW(260),
            ),
          ),
        ),
      );
    });
  }

  /// 底部信息 + 控制区
  Widget _buildBottomArea(BuildContext context, String title, String? artist, String? album) {
    final m = AppTheme.metrics;
    final art = _onArt(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 歌曲信息
          Text(
            title.isEmpty ? '未选择歌曲' : title,
            style: AppTextStyles.pageTitle(context).copyWith(color: art.primary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (artist != null || album != null)
            Padding(
              padding: EdgeInsets.only(top: m.kSpace8),
              child: Text(
                [?artist, ?album].join(' · '),
                style: AppTextStyles.body(context).copyWith(color: art.muted),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          SizedBox(height: m.kSpace24),
          // 进度条
          _buildProgressBar(context),
          SizedBox(height: m.kSpace16),
          // 播放控制（紧凑模式：仅上一首/播放/下一首，白色图标）
          PlayerControls(viewModel: viewModel, compact: true, color: art.primary),
          SizedBox(height: m.kSpace16),
          // 底部功能按钮
          _buildBottomActions(context),
          SizedBox(height: m.kSpace16),
        ],
      ),
    );
  }

  /// 进度条（普通模式或波形模式）
  Widget _buildProgressBar(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final art = _OnArt(s);
    return Obx(() {
      final position = viewModel.currentPositionMs.value;
      final duration = viewModel.durationMs.value;
      final showWaveform = viewModel.showWaveformMode.value;
      final waveform = viewModel.currentWaveform;
      final isLoading = viewModel.isWaveformLoading.value;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showWaveform && (waveform.isNotEmpty || isLoading))
            // 波形进度模式
            WaveformSeekBar(
              waveform: waveform,
              positionMs: position,
              durationMs: duration,
              onSeek: viewModel.seekTo,
              activeColor: art.track,
              inactiveColor: art.trackDim,
              isLoading: isLoading,
            )
          else
            // 普通进度条
            SliderTheme(
              data: _onArtSliderTheme(s),
              child: Slider(
                value: duration > 0 ? position.clamp(0, duration).toDouble() : 0,
                min: 0,
                max: duration.toDouble(),
                onChanged: (v) => viewModel.seekTo(v.toInt()),
              ),
            ),
          SizedBox(height: m.kSpace4),
          // 时间显示
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(viewModel.formatDuration(position), style: _artCaption(context)),
              Text(viewModel.formatDuration(duration), style: _artCaption(context)),
            ],
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
            // 选中态靠"空心→实心"区分，不额外染红：原先的 Colors.redAccent
            // 既不在状态色体系里，也不在这页的白色口径里。
            icon: isFav ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
            label: '收藏',
            active: isFav,
            onTap: item != null ? () => viewModel.toggleFavorite(item.id) : null,
          );
        }),
        // 歌词
        Obx(() => _ActionButton(
          icon: StrokeIcons.lyrics,
          label: '歌词',
          active: viewModel.showLyricsPanel.value,
          onTap: viewModel.toggleLyricsPanel,
        )),
        // 波形进度
        Obx(() => _ActionButton(
          icon: StrokeIcons.graphicEq,
          label: '波形',
          active: viewModel.showWaveformMode.value,
          onTap: viewModel.toggleWaveformMode,
        )),
        // 均衡器
        _ActionButton(
          icon: StrokeIcons.equalizer,
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
              leading: DrawIcon(StrokeIcons.share),
              title: const Text('分享'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: DrawIcon(StrokeIcons.playlistAdd),
              title: const Text('添加到播放列表'),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: DrawIcon(StrokeIcons.infoOutline),
              title: const Text('歌曲信息'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showEqPanel(BuildContext context) {
    // 复用主页面那份 EqPanel：这里原先自己写过一套 _EqSliders，
    // 拖滑块只改本地状态、不 applyEqBands，沉浸式里调 EQ 等于没调。
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => const EqPanel(),
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
            // 压成"化成一团"的重模糊，量级超出 AppGlass 的三档玻璃，走 blurArtwork
            imageFilter: ImageFilter.blur(
              sigmaX: AppGlass.blurArtwork,
              sigmaY: AppGlass.blurArtwork,
            ),
            child: Image.file(
              File(coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        // 半透明遮罩：把封面压暗到能看清白色文字，档位用全局 scrim 而不是本地再调一次
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppGlass.blurMedium, sigmaY: AppGlass.blurMedium),
          child: ColoredBox(color: AppSemantic.of(context).scrim),
        ),
      ],
    );
  }
}

/// 功能按钮
class _ActionButton extends StatelessWidget {
  final StrokeIcon icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 选中用纯白、未选中用 70% 白：这页压在深色 art 上，
    // 语义强调色在亮色模式下是深色，选中态会变成"看不见的那一档"。
    final art = _onArt(context);
    final color = active ? art.primary : art.muted;
    final m = AppTheme.metrics;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: DrawIcon(icon, size: m.iconSize24),
          color: color,
        ),
        Text(label, style: _artCaption(context).copyWith(color: color)),
      ],
    );
  }
}

/// 音量按钮（点击弹出浮层调节音量）
class _VolumeSlider extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  const _VolumeSlider({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final art = _onArt(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _showVolumePopup(context),
          icon: Obx(() {
            final vol = viewModel.volume.value;
            return DrawIcon(
              vol == 0
                  ? StrokeIcons.volumeOff
                  : vol < 50
                      ? StrokeIcons.volumeDown
                      : StrokeIcons.volumeUp,
              size: m.iconSize24,
            );
          }),
          color: art.muted,
        ),
        Text('音量', style: _artCaption(context)),
      ],
    );
  }

  void _showVolumePopup(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _VolumePopupOverlay(
        viewModel: viewModel,
        anchorOffset: offset,
        anchorSize: size,
        onClose: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }
}

/// 音量浮层
class _VolumePopupOverlay extends StatelessWidget {
  final MusicPlayerViewModel viewModel;
  final Offset anchorOffset;
  final Size anchorSize;
  final VoidCallback onClose;

  const _VolumePopupOverlay({
    required this.viewModel,
    required this.anchorOffset,
    required this.anchorSize,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final art = _OnArt(s);
    final m = AppTheme.metrics;
    final popupWidth = scaleW(200);
    final popupHeight = scaleW(48);
    // 浮层居中于音量按钮上方
    final left = (anchorOffset.dx + anchorSize.width / 2 - popupWidth / 2)
        .clamp(m.kSpace16, MediaQuery.of(context).size.width - popupWidth - m.kSpace16);
    final top = anchorOffset.dy - popupHeight - m.kSpace12;

    return Stack(
      children: [
        // 点击背景关闭
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // 浮层
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: popupWidth,
              height: popupHeight,
              decoration: BoxDecoration(
                color: art.panel,
                borderRadius: m.radiusPill,
                border: Border.all(color: art.hairline, width: AppTheme.metrics.strokeHairline),
                boxShadow: s.elevation(Elevation.overlay),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace16),
                child: Row(
                  children: [
                    // 静音按钮
                    Obx(() {
                      final vol = viewModel.volume.value;
                      return GestureDetector(
                        onTap: () => viewModel.setVolume(vol > 0 ? 0 : 100),
                        child: DrawIcon(
                          vol == 0
                              ? StrokeIcons.volumeOff
                              : vol < 50
                                  ? StrokeIcons.volumeDown
                                  : StrokeIcons.volumeUp,
                          size: m.iconSize20,
                          color: art.secondary,
                        ),
                      );
                    }),
                    SizedBox(width: m.kSpace8),
                    // 音量滑块
                    Expanded(
                      child: Obx(() {
                        final vol = viewModel.volume.value;
                        return SliderTheme(
                          data: _onArtSliderTheme(s),
                          child: Slider(
                            value: vol.toDouble(),
                            min: 0,
                            max: 100,
                            onChanged: (v) => viewModel.setVolume(v.toInt()),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 歌词面板（沉浸式播放器内使用）
class _LyricsPanel extends StatefulWidget {
  final MusicPlayerViewModel viewModel;
  const _LyricsPanel({required this.viewModel});

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    // 行高必须和 ListView 的 itemExtent 取同一个 token，否则高亮行会越滚越偏
    final itemHeight = AppTheme.metrics.kSpace48;
    final targetOffset =
        (index * itemHeight) - (_scrollController.position.viewportDimension / 2) +
            (itemHeight / 2);
    final clamped = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      clamped,
      duration: AppMotion.slow,
      curve: AppMotion.decelerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final art = _onArt(context);
    return Obx(() {
      final lyrics = widget.viewModel.currentLyrics;
      final currentIndex = widget.viewModel.currentLyricIndex.value;
      final translatedLyrics = widget.viewModel.translatedLyrics;
      final isTranslating = widget.viewModel.isTranslatingLyrics.value;
      final hasTranslation = translatedLyrics.isNotEmpty && translatedLyrics.any((t) => t != null);

      // 当高亮索引变化时自动滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (currentIndex >= 0) _scrollToIndex(currentIndex);
      });

      if (lyrics.isEmpty) {
        return Center(
          child: Text(
            '暂无歌词',
            style: AppTextStyles.body(context).copyWith(color: art.muted),
          ),
        );
      }

      return Column(
        children: [
          // 翻译按钮
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isTranslating)
                  Padding(
                    padding: EdgeInsets.only(right: m.kSpace8),
                    child: SizedBox(
                      width: m.iconSize14,
                      height: m.iconSize14,
                      child: CircularProgressIndicator(
                        strokeWidth: AppTheme.metrics.strokeRegular,
                        color: art.muted,
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: isTranslating ? null : widget.viewModel.translateLyrics,
                  // 这页恒压在深色 art 上，选中态用白色而不是强调色：
                  // 亮色主题的 accent 是深色，落在 art 上等于把按钮关掉。
                  icon: DrawIcon(StrokeIcons.translate,
                    size: m.iconSize16,
                    color: hasTranslation ? art.primary : art.muted,
                  ),
                  label: Text(
                    hasTranslation ? '显示原文' : '翻译为中文',
                    // 走 role 而不是裸 TextStyle：裸构造会丢掉 fontFamily，
                    // 中西文混排时这行会跳回系统字体。
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      height: 1.2,
                      color: hasTranslation ? art.primary : art.muted,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // 歌词列表
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24),
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.height * 0.15,
                ),
                itemCount: lyrics.length,
                // 行高与 _scrollToIndex 的居中计算必须同一个值，否则高亮行会越滚越偏
                itemExtent: m.kSpace48,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  final track = lyrics[index];
                  final translated = index < translatedLyrics.length ? translatedLyrics[index] : null;
                  final displayText = (hasTranslation && translated != null) ? translated : track.title;
                  return GestureDetector(
                    onTap: () => widget.viewModel.seekTo(track.startMs.toInt()),
                    child: Center(
                      // 逐行淡入淡出而不是硬切：歌词高亮每隔几秒换一次，
                      // 瞬时切换在暗背景上会闪一下。动画时长走全局 AppMotion。
                      child: AnimatedDefaultTextStyle(
                        duration: AppMotion.base,
                        curve: AppMotion.standard,
                        style: AppTextStyles.body(context).copyWith(
                          color: isCurrent ? art.primary : art.faint,
                          fontSize: isCurrent ? m.fontSize18 : m.fontSize15,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        ),
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    });
  }
}
