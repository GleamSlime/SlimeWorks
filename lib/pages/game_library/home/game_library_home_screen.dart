import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_home_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class GameLibraryHomeScreen extends BasePage<GameLibraryHomeViewModel> {
  const GameLibraryHomeScreen({super.key});

  @override
  State<GameLibraryHomeScreen> createState() => _GameLibraryHomeScreenState();
}

class _GameLibraryHomeScreenState
    extends BasePageState<GameLibraryHomeViewModel, GameLibraryHomeScreen> {
  @override
  bool get showAppBar => false;

  @override
  GameLibraryHomeViewModel createViewModel() => GameLibraryHomeViewModel();

  ScreenChromeData _buildChromeData() {
    return ScreenChromeData(
      title: '首页',
      actions: <Widget>[
        IconButton(
          onPressed: () => const GameLibraryRoute().go(context),
          icon: DrawIcon(StrokeIcons.libraryBooks),
          tooltip: '游戏库',
        ),
      ],
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    final s = AppSemantic.of(context);
    return ScreenChrome(
      data: _buildChromeData(),
      child: Obx(() {
        final GameLibraryHomeData? data = viewModel.homeData.value;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final GameItem? lastGame = data.lastPlayedGame;

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // ── 层 0：模糊背景封面 ────────────────────────────────
            if (lastGame != null && lastGame.coverPath.isNotEmpty)
              _BlurredCoverBackground(coverPath: lastGame.coverPath)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      s.accentContainer,
                      // secondaryContainer 在语义层没有对等角色，暂保留字阶色
                      Theme.of(context).colorScheme.secondaryContainer,
                    ],
                  ),
                ),
              ),

            // ── 层 1：暗色渐变遮罩，确保文字可读 ────────────────
            // 遮罩压的是封面，底色由内容决定，两档主题下同值，不跟随翻转
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[s.mediaScrimSoft, s.mediaScrimFoot],
                  stops: <double>[0.0, 1.0],
                ),
              ),
            ),

            // ── 层 2：内容 ───────────────────────────────────────
            Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
              child: Stack(
                children: <Widget>[
                  // 左上：标题
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '首页',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: s.onMedia,
                            fontWeight: FontWeight.w700,
                            shadows: <Shadow>[Shadow(blurRadius: 8, color: s.mediaScrimMedium)],
                          ),
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace4),
                        Text(
                          '欢迎回来',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: s.onMediaSecondary),
                        ),
                      ],
                    ),
                  ),

                  // 右上：今日游玩时间卡片
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _GlassCard(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DrawIcon(StrokeIcons.schedule, size: AppTheme.metrics.iconSize20, color: s.onMediaSecondary),
                          SizedBox(width: AppTheme.metrics.kSpace8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '今日游玩时间',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelSmall?.copyWith(color: s.onMediaTertiary),
                              ),
                              Text(
                                viewModel.formatDuration(data.todayPlayTimeSec),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: s.onMedia,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 底部内容（最近游玩或空状态）
                  if (lastGame != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          // 封面卡片
                          GestureDetector(
                            onTap: () => GameDetailRoute(gameId: lastGame.id).push<void>(context),
                            child: Container(
                              width: scaleW(200),
                              height: scaleW(280),
                              decoration: BoxDecoration(
                                borderRadius: AppTheme.metrics.radius14,
                                // 封面投影收进语义档位（原 black38/blur20/y8 ≈ floating）
                                boxShadow: s.elevation(Elevation.floating),
                              ),
                              child: ClipRRect(
                                borderRadius: AppTheme.metrics.radius14,
                                child: _buildCoverImage(lastGame.coverPath),
                              ),
                            ),
                          ),
                          SizedBox(width: AppTheme.metrics.kSpace20),
                          // 游戏信息 + 继续游玩按钮
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  lastGame.name,
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: s.onMedia,
                                    fontWeight: FontWeight.w700,
                                    shadows: <Shadow>[
                                      Shadow(blurRadius: 8, color: s.mediaScrimMedium),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: AppTheme.metrics.kSpace8),
                                if (lastGame.lastPlayedAt != null)
                                  Text(
                                    '上次游玩: ${_formatDateTime(lastGame.lastPlayedAt!)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(color: s.onMediaSecondary),
                                  ),
                                Text(
                                  '总游玩时长: ${viewModel.formatDuration(lastGame.totalPlayTimeSec)}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(color: s.onMediaSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DrawIcon(StrokeIcons.sportsEsports,
                            size: AppTheme.metrics.iconSize64,
                            color: s.onMediaFaint,
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace12),
                          Text(
                            '还没有游玩记录',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: s.onMedia,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace8),
                          Text(
                            '先去添加游戏，开始记录游玩时间吧。',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: s.onMediaSecondary),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              // 按钮铺恒白实底，字恒深墨：这一层不吃主题翻转
                              backgroundColor: s.onMedia,
                              foregroundColor: s.onMediaInk,
                            ),
                            onPressed: () => const GameLibraryRoute().go(context),
                            icon: DrawIcon(StrokeIcons.libraryBooks),
                            label: const Text('浏览游戏库'),
                          ),
                        ],
                      ),
                    ),

                  // 右下：继续游玩按钮
                  if (lastGame != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          // 浮在封面上的白底按钮，字不随主题反相
                          backgroundColor: s.onMedia,
                          foregroundColor: s.onMediaInk,
                          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace24, vertical: AppTheme.metrics.kSpace16),
                        ),
                        onPressed: () async {
                          await viewModel.launchGame(lastGame);
                        },
                        icon: DrawIcon(StrokeIcons.playArrow),
                        label: const Text('继续游玩'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildCoverImage(String coverPath) {
    final s = AppSemantic.of(context);
    final String value = coverPath.trim();
    if (value.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: s.onMediaWash, borderRadius: AppTheme.metrics.radius14),
        child: Center(
          child: DrawIcon(StrokeIcons.imageNotSupported, color: s.onMediaFaint, size: AppTheme.metrics.iconSize40),
        ),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, _) =>
            DecoratedBox(decoration: BoxDecoration(color: s.onMediaWash)),
        errorWidget: (_, _, _) => DecoratedBox(
          decoration: BoxDecoration(color: s.onMediaWash),
          child: Center(child: DrawIcon(StrokeIcons.brokenImage, color: s.onMediaFaint)),
        ),
      );
    }
    final File file = File(value);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: s.onMediaWash),
      child: Center(child: DrawIcon(StrokeIcons.brokenImage, color: s.onMediaFaint)),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 毛玻璃模糊背景封面
class _BlurredCoverBackground extends StatelessWidget {
  const _BlurredCoverBackground({required this.coverPath});

  final String coverPath;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    Widget image;
    final String value = coverPath.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        // 封面未就绪时铺的是看图舞台黑底，不是主题表面
        placeholder: (_, _) => ColoredBox(color: s.mediaStage),
        errorWidget: (_, _, _) => ColoredBox(color: s.mediaStage),
      );
    } else {
      final File file = File(value);
      if (file.existsSync()) {
        image = Image.file(file, fit: BoxFit.cover);
      } else {
        image = ColoredBox(color: s.mediaStage);
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppGlass.blurMedium, sigmaY: AppGlass.blurMedium),
          child: const ColoredBox(color: Colors.transparent),
        ),
      ],
    );
  }
}

/// 半透明玻璃卡片
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius12,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16, vertical: AppTheme.metrics.kSpace12),
          decoration: BoxDecoration(
            // 玻璃卡洗的是封面图，透明度沿用原值，只把色相收到媒体墨档
            color: s.onMedia.withAlpha(40),
            borderRadius: AppTheme.metrics.radius12,
            border: Border.all(color: s.onMedia.withAlpha(60)),
          ),
          child: child,
        ),
      ),
    );
  }
}
