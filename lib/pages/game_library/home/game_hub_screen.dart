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
import 'package:slime_works/view_models/game_library/game_library_categories_viewmodel.dart';
import 'package:slime_works/view_models/game_library/game_library_stats_viewmodel.dart';

class GameHubScreen extends StatefulWidget {
  const GameHubScreen({super.key});

  @override
  State<GameHubScreen> createState() => _GameHubScreenState();
}

class _GameHubScreenState extends State<GameHubScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late GameLibraryHomeViewModel _homeVm;
  late GameLibraryCategoriesViewModel _catVm;
  late GameLibraryStatsViewModel _statsVm;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _homeVm = Get.put(GameLibraryHomeViewModel());
    _catVm = Get.put(GameLibraryCategoriesViewModel());
    _statsVm = Get.put(GameLibraryStatsViewModel());

    _homeVm.onInitAsync();
    _catVm.onInitAsync();
    _statsVm.onInitAsync();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _entranceController.dispose();
    try {
      Get.delete<GameLibraryHomeViewModel>(force: true);
      Get.delete<GameLibraryCategoriesViewModel>(force: true);
      Get.delete<GameLibraryStatsViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ScreenChrome(
      data: ScreenChromeData(title: '游戏', toolbarHeight: 0),
      child: Container(
        color: isDark ? DarkColors.background3 : LightColors.background3,
        child: AnimatedBuilder(
          animation: _entranceAnimation,
          builder: (context, _) {
            return Opacity(
              opacity: _entranceAnimation.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - _entranceAnimation.value)),
                child: Column(
                  children: [
                    _buildTabBar(context, theme, m, isDark),
                    SizedBox(height: m.kSpace12),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _HomeTab(homeVm: _homeVm),
                          _CategoriesTab(catVm: _catVm),
                          _StatsTab(statsVm: _statsVm),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? DarkColors.background1.withAlpha(200)
                  : LightColors.background1.withAlpha(220),
              borderRadius: m.radius12,
              border: Border.all(
                color: isDark
                    ? DarkColors.white10.withAlpha(40)
                    : LightColors.black10.withAlpha(30),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? DarkColors.black10 : LightColors.black10,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: (isDark ? DarkColors.primary : LightColors.primary).withAlpha(6),
                  blurRadius: scaleW(20),
                  offset: Offset(0, scaleW(4)),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 3),
                insets: EdgeInsets.symmetric(horizontal: -m.kSpace8),
              ),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.hintColor,
              labelStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
              dividerColor: Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24),
              tabs: [
                Tab(
                  height: m.kSpace40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_esports_outlined, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      const Text('首页'),
                    ],
                  ),
                ),
                Tab(
                  height: m.kSpace40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_copy_outlined, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      const Text('分类'),
                    ],
                  ),
                ),
                Tab(
                  height: m.kSpace40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.query_stats_rounded, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      const Text('统计'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final GameLibraryHomeViewModel homeVm;
  const _HomeTab({required this.homeVm});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Obx(() {
      final GameLibraryHomeData? data = homeVm.homeData.value;
      if (data == null) {
        return const Center(child: CircularProgressIndicator());
      }

      final GameItem? lastGame = data.lastPlayedGame;

      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (lastGame != null && lastGame.coverPath.isNotEmpty)
            _BlurredCoverBackground(coverPath: lastGame.coverPath)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    isDark ? DarkColors.background4 : LightColors.background5,
                    isDark ? DarkColors.primary.withAlpha(40) : LightColors.primary.withAlpha(30),
                  ],
                ),
              ),
            ),

          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x18000000), Color(0xBB000000)],
                stops: <double>[0.0, 1.0],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.all(m.kSpace24),
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: 0,
                  left: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '游戏中心',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: <Shadow>[const Shadow(blurRadius: 8, color: Colors.black54)],
                        ),
                      ),
                      SizedBox(height: m.kSpace4),
                      Text(
                        '欢迎回来',
                        style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                Positioned(
                  top: 0,
                  right: 0,
                  child: _GlassCard(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.schedule, size: m.iconSize20, color: Colors.white70),
                        SizedBox(width: m.kSpace8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '今日游玩',
                              style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60),
                            ),
                            Text(
                              homeVm.formatDuration(data.todayPlayTimeSec),
                              style: theme.textTheme.titleMedium?.copyWith(
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

                // 统计概览卡片
                Positioned(
                  top: 80,
                  right: 0,
                  child: _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '总览',
                          style: theme.textTheme.labelSmall?.copyWith(color: Colors.white60),
                        ),
                        SizedBox(height: m.kSpace8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _GlassStatItem(
                              icon: Icons.library_books_outlined,
                              label: '游戏数',
                              value: '${data.totalGames}',
                            ),
                            SizedBox(width: m.kSpace16),
                            _GlassStatItem(
                              icon: Icons.timer_outlined,
                              label: '总时长',
                              value: homeVm.formatDuration(data.totalPlayTimeSec),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                if (lastGame != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        GestureDetector(
                          onTap: () => GameDetailRoute(gameId: lastGame.id).push<void>(context),
                          child: Container(
                            width: 180,
                            height: 250,
                            decoration: BoxDecoration(
                              borderRadius: m.radius14,
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 20,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: m.radius14,
                              child: _buildCoverImage(lastGame.coverPath),
                            ),
                          ),
                        ),
                        SizedBox(width: m.kSpace20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                lastGame.name,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: <Shadow>[
                                    const Shadow(blurRadius: 8, color: Colors.black54),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: m.kSpace8),
                              if (lastGame.lastPlayedAt != null)
                                Text(
                                  '上次游玩: ${_formatDateTime(lastGame.lastPlayedAt!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                ),
                              Text(
                                '总时长: ${homeVm.formatDuration(lastGame.totalPlayTimeSec)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                              ),
                              SizedBox(height: m.kSpace16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black87,
                                ),
                                onPressed: () async {
                                  await homeVm.launchGame(lastGame);
                                },
                                icon: const Icon(Icons.play_arrow),
                                label: const Text(
                                  '继续游玩',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
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
                        Icon(
                          Icons.sports_esports_outlined,
                          size: m.iconSize64,
                          color: Colors.white38,
                        ),
                        SizedBox(height: m.kSpace12),
                        Text(
                          '还没有游玩记录',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: m.kSpace8),
                        Text(
                          '先去添加游戏，开始记录游玩时间吧。',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                        ),
                        SizedBox(height: m.kSpace16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                          ),
                          onPressed: () => const GameLibraryRoute().go(context),
                          icon: const Icon(Icons.library_books),
                          label: const Text('浏览游戏库'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _buildCoverImage(String coverPath) {
    final String value = coverPath.trim();
    if (value.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.white12, borderRadius: AppTheme.metrics.radius14),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.white38,
            size: AppTheme.metrics.iconSize40,
          ),
        ),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, _) => const DecoratedBox(decoration: BoxDecoration(color: Colors.white12)),
        errorWidget: (_, _, _) => const DecoratedBox(
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

class _CategoriesTab extends StatelessWidget {
  final GameLibraryCategoriesViewModel catVm;
  const _CategoriesTab({required this.catVm});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
          child: Row(
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索分类',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (String value) => catVm.searchQuery.value = value,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreateDialog(context, catVm),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('新增分类'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final List<GameCategory> list = catVm.filtered;
            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_off_outlined,
                      size: m.iconSize48,
                      color: isDark ? DarkColors.white20 : LightColors.black20,
                    ),
                    SizedBox(height: m.kSpace12),
                    Text(
                      '暂无分类，先创建一个吧',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark ? DarkColors.white40 : LightColors.black40,
                      ),
                    ),
                  ],
                ),
              );
            }

            return GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.of(context).size.width / 200).floor().clamp(2, 6),
                childAspectRatio: 2.2,
                crossAxisSpacing: m.kSpace12,
                mainAxisSpacing: m.kSpace12,
              ),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) {
                final GameCategory category = list[index];
                return _CategoryCard(
                  category: category,
                  isDark: isDark,
                  primaryColor: primaryColor,
                  onTap: () => GameCategoryDetailRoute(categoryId: category.id).push<void>(context),
                  onEdit: () => _showEditDialog(context, catVm, category),
                  onDelete: () => _confirmDelete(context, catVm, category),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class _StatsTab extends StatelessWidget {
  final GameLibraryStatsViewModel statsVm;
  const _StatsTab({required this.statsVm});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Obx(() {
      final GameStatsData? data = statsVm.statsData.value;
      if (data == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return ListView(
        padding: EdgeInsets.all(m.kSpace16),
        children: <Widget>[
          // 日期选择 + 概览
          Row(
            children: [
              Expanded(
                child: _StatsOverviewCard(
                  icon: Icons.timer_outlined,
                  title: '总时长',
                  value: statsVm.formatDuration(data.totalPlayTimeSec),
                  isDark: isDark,
                  primaryColor: primaryColor,
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: _StatsOverviewCard(
                  icon: Icons.event_repeat_rounded,
                  title: '会话次数',
                  value: '${data.sessionCount} 次',
                  isDark: isDark,
                  primaryColor: primaryColor,
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: _DateRangeCard(statsVm: statsVm, isDark: isDark, primaryColor: primaryColor),
              ),
            ],
          ),
          SizedBox(height: m.kSpace20),
          Text('日维度趋势', style: theme.textTheme.titleMedium),
          SizedBox(height: m.kSpace12),
          if (data.timeline.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: m.kSpace32),
                child: Column(
                  children: [
                    Icon(
                      Icons.show_chart_rounded,
                      size: m.iconSize48,
                      color: isDark ? DarkColors.white20 : LightColors.black20,
                    ),
                    SizedBox(height: m.kSpace12),
                    Text(
                      '当前时间范围没有数据',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark ? DarkColors.white40 : LightColors.black40,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...data.timeline.map((DayPlayTime item) {
              final int maxValue = data.timeline
                  .map((DayPlayTime e) => e.durationSec)
                  .reduce((int a, int b) => a > b ? a : b);
              final double progress = maxValue > 0 ? item.durationSec / maxValue : 0;

              return Padding(
                padding: EdgeInsets.only(bottom: m.kSpace8),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace14),
                  decoration: BoxDecoration(
                    color: isDark ? DarkColors.background2 : LightColors.background1,
                    borderRadius: m.radius12,
                    border: Border.all(
                      color: isDark ? DarkColors.white10 : LightColors.black10,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            item.date.toLocal().toString().split(' ').first,
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            statsVm.formatDuration(item.durationSec),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: m.kSpace10),
                      ClipRRect(
                        borderRadius: m.radius6,
                        child: Stack(
                          children: [
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: isDark ? DarkColors.white10 : LightColors.black10,
                                borderRadius: m.radius6,
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: progress.clamp(0.02, 1.0),
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [primaryColor.withAlpha(180), primaryColor],
                                  ),
                                  borderRadius: m.radius6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 辅助组件
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius12,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace16,
            vertical: AppTheme.metrics.kSpace12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(40),
            borderRadius: AppTheme.metrics.radius12,
            border: Border.all(color: Colors.white.withAlpha(60)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _GlassStatItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: m.iconSize14, color: Colors.white60),
            SizedBox(width: m.kSpace4),
            Text(
              label,
              style: TextStyle(fontSize: m.fontSize11, height: 1.4, color: Colors.white60),
            ),
          ],
        ),
        SizedBox(height: m.kSpace2),
        Text(
          value,
          style: TextStyle(
            fontSize: m.fontSize13,
            height: 1.4,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

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
        placeholder: (_, _) => const ColoredBox(color: Colors.black),
        errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
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

class _CategoryCard extends StatefulWidget {
  final GameCategory category;
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
    required this.isDark,
    required this.primaryColor,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(m.kSpace16),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.primaryColor.withAlpha(widget.isDark ? 30 : 20)
                : (widget.isDark ? DarkColors.background2 : LightColors.background1),
            borderRadius: m.radius14,
            border: Border.all(
              color: _hovered
                  ? widget.primaryColor.withAlpha(80)
                  : (widget.isDark ? DarkColors.white10 : LightColors.black10),
              width: _hovered ? 1.5 : 0.5,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.primaryColor.withAlpha(15),
                      blurRadius: scaleW(16),
                      offset: Offset(0, scaleW(4)),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: scaleW(40),
                height: scaleW(40),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withAlpha(15),
                  borderRadius: m.radius10,
                ),
                child: Center(
                  child: Text(widget.category.emoji, style: TextStyle(fontSize: m.fontSize20)),
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.category.name,
                      style: TextStyle(
                        fontSize: m.fontSize13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: m.kSpace2),
                    Text(
                      '${widget.category.gameCount} 个游戏${widget.category.isSystem ? ' · 系统分类' : ''}',
                      style: TextStyle(
                        fontSize: m.fontSize11,
                        height: 1.4,
                        color: widget.isDark ? DarkColors.white80 : LightColors.black80,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.category.isSystem)
                Icon(
                  Icons.lock_outline,
                  size: m.iconSize16,
                  color: widget.isDark ? DarkColors.white40 : LightColors.black40,
                )
              else
                PopupMenuButton<String>(
                  onSelected: (String value) {
                    if (value == 'edit') widget.onEdit();
                    if (value == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'edit', child: Text('编辑')),
                    PopupMenuItem<String>(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsOverviewCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isDark;
  final Color primaryColor;

  const _StatsOverviewCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background2 : LightColors.background1,
        borderRadius: m.radius14,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: m.kSpace32,
                height: m.kSpace32,
                decoration: BoxDecoration(
                  color: primaryColor.withAlpha(15),
                  borderRadius: m.radius8,
                ),
                child: Icon(icon, size: m.iconSize16, color: primaryColor),
              ),
              SizedBox(width: m.kSpace8),
              Text(
                title,
                style: TextStyle(
                  fontSize: m.fontSize11,
                  height: 1.4,
                  color: isDark ? DarkColors.white80 : LightColors.black80,
                ),
              ),
            ],
          ),
          SizedBox(height: m.kSpace10),
          Text(
            value,
            style: TextStyle(fontSize: m.fontSize18, height: 1.3, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DateRangeCard extends StatelessWidget {
  final GameLibraryStatsViewModel statsVm;
  final bool isDark;
  final Color primaryColor;

  const _DateRangeCard({required this.statsVm, required this.isDark, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return GestureDetector(
      onTap: () async {
        final DateTime now = DateTime.now();
        final DateTimeRange? range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 10),
          lastDate: now,
          initialDateRange: DateTimeRange(
            start: statsVm.startDate.value,
            end: statsVm.endDate.value,
          ),
        );
        if (range != null) {
          await statsVm.setRange(range.start, range.end);
        }
      },
      child: Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: isDark ? DarkColors.background2 : LightColors.background1,
          borderRadius: m.radius14,
          border: Border.all(color: primaryColor.withAlpha(40), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace32,
                  height: m.kSpace32,
                  decoration: BoxDecoration(
                    color: primaryColor.withAlpha(15),
                    borderRadius: m.radius8,
                  ),
                  child: Icon(Icons.date_range_rounded, size: m.iconSize16, color: primaryColor),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '时间范围',
                  style: TextStyle(
                    fontSize: m.fontSize11,
                    height: 1.4,
                    color: isDark ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace10),
            Text(
              '${statsVm.startDate.value.toLocal().toString().split(' ').first} ~ ${statsVm.endDate.value.toLocal().toString().split(' ').first}',
              style: TextStyle(fontSize: m.fontSize13, height: 1.3, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分类弹窗
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _showCreateDialog(BuildContext context, GameLibraryCategoriesViewModel catVm) async {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emojiController = TextEditingController(text: '📁');

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('新增分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名'),
            ),
            TextField(
              controller: emojiController,
              decoration: const InputDecoration(labelText: 'Emoji'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await catVm.addCategory(nameController.text, emojiController.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  emojiController.dispose();
}

Future<void> _showEditDialog(
  BuildContext context,
  GameLibraryCategoriesViewModel catVm,
  GameCategory category,
) async {
  final TextEditingController nameController = TextEditingController(text: category.name);
  final TextEditingController emojiController = TextEditingController(text: category.emoji);

  await showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('编辑分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名'),
            ),
            TextField(
              controller: emojiController,
              decoration: const InputDecoration(labelText: 'Emoji'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              await catVm.updateCategory(category, nameController.text, emojiController.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );

  nameController.dispose();
  emojiController.dispose();
}

Future<void> _confirmDelete(
  BuildContext context,
  GameLibraryCategoriesViewModel catVm,
  GameCategory category,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('删除分类'),
        content: Text('确认删除 ${category.name} 吗？'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      );
    },
  );

  if (ok == true) {
    await catVm.deleteCategory(category.id);
  }
}
