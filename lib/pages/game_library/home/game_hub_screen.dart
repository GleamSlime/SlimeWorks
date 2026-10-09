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
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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
      duration: AppMotion.entrance,
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: AppMotion.decelerate);

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
    final s = AppSemantic.of(context);

    return ScreenChrome(
      data: ScreenChromeData(title: '游戏', toolbarHeight: 0),
      child: Container(
        color: s.canvas,
        child: AnimatedBuilder(
          animation: _entranceAnimation,
          builder: (context, _) {
            return Opacity(
              opacity: _entranceAnimation.value.clamp(0.0, 1.0),
              child: Transform.translate(
                // 入场位移走宽度族档位，跟窗口缩放而不是写死 12
                offset: Offset(0, AppMotion.travelMedium * (1 - _entranceAnimation.value)),
                child: Column(
                  children: [
                    _buildTabBar(context, theme, m),
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

  Widget _buildTabBar(BuildContext context, ThemeData theme, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
          child: Container(
            decoration: BoxDecoration(
              // 磨砂页签条：着色/描边/投影统一走语义玻璃与投影档
              color: s.glassTint,
              borderRadius: m.radius12,
              border: Border.all(
                color: s.glassBorder,
                width: m.strokeUltraThin,
              ),
              boxShadow: s.elevation(Elevation.card),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: s.accent, width: m.strokeBold),
                insets: EdgeInsets.symmetric(horizontal: -m.kSpace8),
              ),
              labelColor: s.accent,
              unselectedLabelColor: s.textTertiary,
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
                      DrawIcon(StrokeIcons.sportsEsports, size: m.iconSize16),
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
                      DrawIcon(StrokeIcons.folderCopy, size: m.iconSize16),
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
                      DrawIcon(StrokeIcons.queryStats, size: m.iconSize16),
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
    final s = AppSemantic.of(context);

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
                  // 无封面时的兜底底：下沉表面 + 低浓度 info 容器，替代手挑调色板色
                  colors: <Color>[
                    s.surfaceSunken,
                    s.info.container,
                  ],
                ),
              ),
            ),

          // 压模糊封面的渐变遮罩：底色由封面自己决定，两档主题下同值，不跟随翻转
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[s.mediaScrimTrace, s.mediaScrimVeil],
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
                          color: s.onMedia,
                          fontWeight: FontWeight.w700,
                          shadows: <Shadow>[Shadow(blurRadius: 8, color: s.mediaScrimMedium)],
                        ),
                      ),
                      SizedBox(height: m.kSpace4),
                      Text(
                        '欢迎回来',
                        style: theme.textTheme.bodyMedium?.copyWith(color: s.onMediaSecondary),
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
                        DrawIcon(StrokeIcons.schedule, size: m.iconSize20, color: s.onMediaSecondary),
                        SizedBox(width: m.kSpace8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '今日游玩',
                              style: theme.textTheme.labelSmall?.copyWith(color: s.onMediaTertiary),
                            ),
                            Text(
                              homeVm.formatDuration(data.todayPlayTimeSec),
                              style: theme.textTheme.titleMedium?.copyWith(
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

                // 统计概览卡片
                Positioned(
                  top: m.kSpace80,
                  right: 0,
                  child: _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '总览',
                          style: theme.textTheme.labelSmall?.copyWith(color: s.onMediaTertiary),
                        ),
                        SizedBox(height: m.kSpace8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _GlassStatItem(
                              icon: StrokeIcons.libraryBooks,
                              label: '游戏数',
                              value: '${data.totalGames}',
                            ),
                            SizedBox(width: m.kSpace16),
                            _GlassStatItem(
                              icon: StrokeIcons.timer,
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
                            width: scaleW(180),
                            height: scaleW(250),
                            decoration: BoxDecoration(
                              borderRadius: m.radius14,
                              // 封面投影收进语义档位（原 black38/blur20/y8 ≈ floating）
                              boxShadow: s.elevation(Elevation.floating),
                            ),
                            child: ClipRRect(
                              borderRadius: m.radius14,
                              child: _buildCoverImage(lastGame.coverPath, s),
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
                                  color: s.onMedia,
                                  fontWeight: FontWeight.w700,
                                  shadows: <Shadow>[
                                    Shadow(blurRadius: 8, color: s.mediaScrimMedium),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: m.kSpace8),
                              if (lastGame.lastPlayedAt != null)
                                Text(
                                  '上次游玩: ${_formatDateTime(lastGame.lastPlayedAt!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: s.onMediaSecondary),
                                ),
                              Text(
                                '总时长: ${homeVm.formatDuration(lastGame.totalPlayTimeSec)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: s.onMediaSecondary),
                              ),
                              SizedBox(height: m.kSpace16),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  // 按钮铺的是恒白实心底，字也就恒深，不跟主题反相
                                  backgroundColor: s.onMedia,
                                  foregroundColor: s.onMediaInk,
                                ),
                                onPressed: () async {
                                  await homeVm.launchGame(lastGame);
                                },
                                icon: DrawIcon(StrokeIcons.playArrow),
                                label: const Text('继续游玩'),
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
                          size: m.iconSize64,
                          color: s.onMediaFaint,
                        ),
                        SizedBox(height: m.kSpace12),
                        Text(
                          '还没有游玩记录',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: s.onMedia,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: m.kSpace8),
                        Text(
                          '先去添加游戏，开始记录游玩时间吧。',
                          style: theme.textTheme.bodyMedium?.copyWith(color: s.onMediaSecondary),
                        ),
                        SizedBox(height: m.kSpace16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            // 同上：白实心按钮上的字恒深
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
              ],
            ),
          ),
        ],
      );
    });
  }

  // 封面槽位的占位层：它顶替的是画面本身，不吃主题翻转，故走媒体墨档
  Widget _buildCoverImage(String coverPath, AppSemantic s) {
    final String value = coverPath.trim();
    if (value.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: s.onMediaWash, borderRadius: AppTheme.metrics.radius14),
        child: Center(
          child: DrawIcon(StrokeIcons.imageNotSupported,
            color: s.onMediaFaint,
            size: AppTheme.metrics.iconSize40,
          ),
        ),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        placeholder: (_, _) => DecoratedBox(decoration: BoxDecoration(color: s.onMediaWash)),
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

class _CategoriesTab extends StatelessWidget {
  final GameLibraryCategoriesViewModel catVm;
  const _CategoriesTab({required this.catVm});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
          child: Row(
            children: [
              SizedBox(
                width: scaleW(220),
                child: AppTextField(
                  decoration: const InputDecoration(
                    hintText: '搜索分类',
                    prefixIcon: DrawIcon(StrokeIcons.search),
                    isDense: true,
                  ),
                  onChanged: (String value) => catVm.searchQuery.value = value,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showCreateDialog(context, catVm),
                icon: DrawIcon(StrokeIcons.createNewFolder),
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
                    DrawIcon(StrokeIcons.folderOff,
                      size: m.iconSize48,
                      color: s.textDisabled,
                    ),
                    SizedBox(height: m.kSpace12),
                    Text(
                      '暂无分类，先创建一个吧',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: s.textTertiary,
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
    final s = AppSemantic.of(context);
    // 品牌淡紫退出主色位后，统计页的点缀色相归入 info 角色
    final primaryColor = s.info.color;

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
                  icon: StrokeIcons.timer,
                  title: '总时长',
                  value: statsVm.formatDuration(data.totalPlayTimeSec),
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: _StatsOverviewCard(
                  icon: StrokeIcons.eventRepeat,
                  title: '会话次数',
                  value: '${data.sessionCount} 次',
                ),
              ),
              SizedBox(width: m.kSpace12),
              Expanded(
                child: _DateRangeCard(statsVm: statsVm),
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
                    DrawIcon(StrokeIcons.showChart,
                      size: m.iconSize48,
                      color: s.textDisabled,
                    ),
                    SizedBox(height: m.kSpace12),
                    Text(
                      '当前时间范围没有数据',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: s.textTertiary,
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
                    color: s.surfaceRaised,
                    borderRadius: m.radius12,
                    border: Border.all(
                      color: s.border,
                      width: m.strokeUltraThin,
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
                              height: m.kSpace6,
                              decoration: BoxDecoration(
                                color: s.surfaceSunken,
                                borderRadius: m.radius6,
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: progress.clamp(0.02, 1.0),
                              child: Container(
                                height: m.kSpace6,
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
    final s = AppSemantic.of(context);
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius12,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace16,
            vertical: AppTheme.metrics.kSpace12,
          ),
          decoration: BoxDecoration(
            // 玻璃卡洗的是封面图而不是主题表面，透明度沿用原值，只把色相收到媒体墨档
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

class _GlassStatItem extends StatelessWidget {
  final StrokeIcon icon;
  final String label;
  final String value;
  const _GlassStatItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(icon, size: m.iconSize14, color: s.onMediaTertiary),
            SizedBox(width: m.kSpace4),
            Text(
              label,
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize11,
                height: 1.4,
                color: s.onMediaTertiary,
              ),
            ),
          ],
        ),
        SizedBox(height: m.kSpace2),
        Text(
          value,
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize13,
            height: 1.4,
            weight: FontWeight.w700,
            color: s.onMedia,
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

class _CategoryCard extends StatefulWidget {
  final GameCategory category;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
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
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.decelerate,
          padding: EdgeInsets.all(m.kSpace16),
          decoration: BoxDecoration(
            // 悬停走中性水洗层，静止态是浮起卡片
            color: _hovered ? s.surfaceHover : s.surfaceRaised,
            borderRadius: m.radius14,
            border: Border.all(
              color: _hovered ? s.borderStrong : s.border,
              width: _hovered ? m.strokeThin : m.strokeUltraThin,
            ),
            boxShadow: _hovered ? s.elevation(Elevation.card) : null,
          ),
          child: Row(
            children: [
              Container(
                width: scaleW(40),
                height: scaleW(40),
                decoration: BoxDecoration(
                  color: s.info.container,
                  borderRadius: m.radius10,
                ),
                child: Center(
                  child: Text(
                    widget.category.emoji,
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize20,
                      color: s.textPrimary,
                    ),
                  ),
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
                      style: AppTextStyles.cardTitle(context).copyWith(
                        height: 1.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: m.kSpace2),
                    Text(
                      '${widget.category.gameCount} 个游戏${widget.category.isSystem ? ' · 系统分类' : ''}',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize11,
                        height: 1.4,
                        color: s.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.category.isSystem)
                DrawIcon(StrokeIcons.lockOutline,
                  size: m.iconSize16,
                  color: s.textTertiary,
                )
              else
                PopupMenuButton<String>(
                  onSelected: (String value) {
                    if (value == 'edit') widget.onEdit();
                    if (value == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    GlassMenuItem<String>(
                      value: 'edit',
                      label: '编辑',
                      icon: StrokeIcons.edit,
                    ),
                    GlassMenuItem<String>(
                      value: 'delete',
                      label: '删除',
                      icon: StrokeIcons.deleteOutline,
                      destructive: true,
                    ),
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
  final StrokeIcon icon;
  final String title;
  final String value;

  const _StatsOverviewCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final primaryColor = s.info.color;
    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.surfaceRaised,
        borderRadius: m.radius14,
        border: Border.all(color: s.border, width: m.strokeUltraThin),
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
                  color: s.info.container,
                  borderRadius: m.radius8,
                ),
                child: DrawIcon(icon, size: m.iconSize16, color: primaryColor),
              ),
              SizedBox(width: m.kSpace8),
              Text(
                title,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize11,
                  height: 1.4,
                  color: s.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: m.kSpace10),
          Text(
            value,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize18,
              height: 1.3,
              weight: FontWeight.w600,
              color: s.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeCard extends StatelessWidget {
  final GameLibraryStatsViewModel statsVm;

  const _DateRangeCard({required this.statsVm});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final primaryColor = s.info.color;
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
          color: s.surfaceRaised,
          borderRadius: m.radius14,
          border: Border.all(color: s.info.containerBorder, width: m.strokeUltraThin),
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
                    color: s.info.container,
                    borderRadius: m.radius8,
                  ),
                  child: DrawIcon(StrokeIcons.dateRange, size: m.iconSize16, color: primaryColor),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '时间范围',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize11,
                    height: 1.4,
                    color: s.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace10),
            Text(
              '${statsVm.startDate.value.toLocal().toString().split(' ').first} ~ ${statsVm.endDate.value.toLocal().toString().split(' ').first}',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize13,
                height: 1.3,
                weight: FontWeight.w600,
                color: s.textPrimary,
              ),
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
            AppTextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名'),
            ),
            AppTextField(
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
            AppTextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名'),
            ),
            AppTextField(
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
