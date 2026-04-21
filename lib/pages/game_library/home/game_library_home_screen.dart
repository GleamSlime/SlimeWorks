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
          onPressed: () => GameLibraryRoute().go(context),
          icon: const Icon(Icons.library_books_outlined),
          tooltip: '游戏库',
        ),
      ],
    );
  }

  @override
  Widget buildContent(BuildContext context) {
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
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.secondaryContainer,
                    ],
                  ),
                ),
              ),

            // ── 层 1：暗色渐变遮罩，确保文字可读 ────────────────
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x22000000), Color(0xAA000000)],
                  stops: <double>[0.0, 1.0],
                ),
              ),
            ),

            // ── 层 2：内容 ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(24),
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
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            shadows: <Shadow>[const Shadow(blurRadius: 8, color: Colors.black54)],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '欢迎回来',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
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
                          const Icon(Icons.schedule, size: 20, color: Colors.white70),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '今日游玩时间',
                                style: Theme.of(
                                  context,
                                ).textTheme.labelSmall?.copyWith(color: Colors.white60),
                              ),
                              Text(
                                viewModel.formatDuration(data.todayPlayTimeSec),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
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
                              width: 200,
                              height: 280,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 20,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _buildCoverImage(lastGame.coverPath),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // 游戏信息 + 继续游玩按钮
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  lastGame.name,
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    shadows: <Shadow>[
                                      const Shadow(blurRadius: 8, color: Colors.black54),
                                    ],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                if (lastGame.lastPlayedAt != null)
                                  Text(
                                    '上次游玩: ${_formatDateTime(lastGame.lastPlayedAt!)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                                  ),
                                Text(
                                  '总游玩时长: ${viewModel.formatDuration(lastGame.totalPlayTimeSec)}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
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
                          const Icon(
                            Icons.sports_esports_outlined,
                            size: 64,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '还没有游玩记录',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '先去添加游戏，开始记录游玩时间吧。',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                            ),
                            onPressed: () => GameLibraryRoute().go(context),
                            icon: const Icon(Icons.library_books),
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
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                        onPressed: () async {
                          await viewModel.launchGame(lastGame);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('继续游玩', style: TextStyle(fontWeight: FontWeight.w700)),
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
    final String value = coverPath.trim();
    if (value.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 40),
        ),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const DecoratedBox(decoration: BoxDecoration(color: Colors.white12)),
        errorWidget: (_, __, ___) => const DecoratedBox(
          decoration: BoxDecoration(color: Colors.white12),
          child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38)),
        ),
      );
    }
    final File file = File(value);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.white12),
      child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38)),
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
    Widget image;
    final String value = coverPath.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(color: Colors.black),
        errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
    } else {
      final File file = File(value);
      if (file.existsSync()) {
        image = Image.file(file, fit: BoxFit.cover);
      } else {
        image = const ColoredBox(color: Colors.black);
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(40),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(60)),
          ),
          child: child,
        ),
      ),
    );
  }
}
