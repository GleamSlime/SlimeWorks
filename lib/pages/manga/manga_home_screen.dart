// Manga 主页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/core/widgets/empty_state.dart';
import 'package:slime_works/pages/manga/components/manga_block_words_dialog.dart';
import 'package:slime_works/pages/manga/components/manga_comic_card.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/components/manga_login_dialog.dart';
import 'package:slime_works/pages/manga/manga_favourites_screen.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_home_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

class MangaHomeScreen extends BasePage<MangaHomeViewModel> {
  const MangaHomeScreen({super.key});

  @override
  State<MangaHomeScreen> createState() => _MangaHomeScreenState();
}

class _MangaHomeScreenState extends BasePageState<MangaHomeViewModel, MangaHomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final RxBool _showBackToTop = false.obs;

  /// 防止快速多次点击头像按钮弹出多个底部菜单
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _showBackToTop.value = _scrollController.offset > scaleW(600);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  MangaHomeViewModel createViewModel() => MangaHomeViewModel();

  @override
  String? get title => 'Manga';

  @override
  bool get showAppBar => false;

  ScreenChromeData _buildScreenChromeData(BuildContext context, MangaHomeViewModel vm) {
    final avatarImage = vm.currentUser.value?.avatar;
    return ScreenChromeData(
      title: 'Manga',
      actions: vm.isLoggedIn
          ? [
              IconButton(
                icon: DrawIcon(StrokeIcons.search),
                tooltip: '搜索',
                onPressed: () => _goToSearch(context),
              ),
              Tooltip(
                message: vm.currentUser.value?.name ?? '用户',
                child: InkWell(
                  borderRadius: AppTheme.metrics.radius20,
                  onTap: () => _showUserMenu(context, vm),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace8,
                      vertical: AppTheme.metrics.kSpace8,
                    ),
                    child: ClipOval(
                      child: SizedBox(
                        // 头像盒是固定尺寸，走宽度族而不是字号族
                        width: scaleW(28),
                        height: scaleW(28),
                        child: avatarImage != null
                            ? MangaImageView(
                                image: avatarImage,
                                fit: BoxFit.cover,
                                loadingBuilder: (_) => Center(
                                  child: SizedBox(
                                    width: AppTheme.metrics.kSpace14,
                                    height: AppTheme.metrics.kSpace14,
                                    child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeThin),
                                  ),
                                ),
                                errorBuilder: (_, _, _) =>
                                    DrawIcon(StrokeIcons.accountCircle),
                              )
                            : DrawIcon(StrokeIcons.accountCircle,
                                // 圆形头像盒是固定尺寸，图标只能走宽度族
                                size: scaleW(28),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ]
          : const <Widget>[],
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return GetBuilder<MangaHomeViewModel>(
      builder: (vm) {
        return ScreenChrome(
          data: _buildScreenChromeData(context, vm),
          child: vm.isLoggedIn ? _buildHomeContent(context, vm) : _buildLoginPrompt(context),
        );
      },
    );
  }

  /// 未登录提示区域
  Widget _buildLoginPrompt(BuildContext context) {
    final s = AppSemantic.of(context);
    final metrics = appMetrics;
    return Center(
      child: Container(
        padding: EdgeInsets.all(metrics.kSpace32),
        margin: EdgeInsets.symmetric(horizontal: metrics.kSpace24),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: metrics.radius16,
          boxShadow: s.elevation(Elevation.floating),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: scaleW(72),
              height: scaleW(72),
              decoration: BoxDecoration(
                color: s.accentContainer,
                borderRadius: metrics.radius16,
              ),
              child: DrawIcon(StrokeIcons.lockPerson,
                size: scaleW(36),
                color: s.accent,
              ),
            ),
            SizedBox(height: metrics.kSpace20),
            Text(
              '请先登录以使用 Manga',
              style: AppTextStyles.sectionTitle(context),
            ),
            SizedBox(height: metrics.kSpace8),
            Text(
              '登录后可浏览、搜索和收藏漫画',
              style: AppTextStyles.caption(context),
            ),
            SizedBox(height: metrics.kSpace24),
            FilledButton.icon(
              icon: DrawIcon(StrokeIcons.login),
              label: const Text('登录'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.kSpace24,
                  vertical: metrics.kSpace12,
                ),
              ),
              onPressed: () async {
                final success = await showMangaLoginDialog(context);
                if (success) {
                  await viewModel.onLoginSuccess();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 主页内容（已登录）
  Widget _buildHomeContent(BuildContext context, MangaHomeViewModel vm) {
    final metrics = appMetrics;

    return Stack(
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - scaleW(400)) {
              vm.loadMoreRandom();
            }
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              /// 加载中
              if (vm.isLoading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              /// 错误提示
              else if (vm.errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: StrokeIcons.cloudOff,
                    title: '内容加载失败',
                    description: vm.errorMessage,
                    action: FilledButton.icon(
                      icon: DrawIcon(StrokeIcons.refresh),
                      label: const Text('重新加载'),
                      onPressed: vm.loadHomeData,
                    ),
                  ),
                )
              else ...[
                /// 精选推荐
                if (vm.collections.isNotEmpty) ...[
                  _buildSectionHeader(context, '精选推荐', null),
                  SliverToBoxAdapter(child: _buildCollections(context, vm.collections)),
                ],

                /// 随机漫画（Obx 监听追加）
                if (vm.randomComics.isNotEmpty) ...[
                  _buildSectionHeader(context, '随机推荐', () => vm.refreshRandom()),
                  Obx(
                    () => SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
                      sliver: _buildRandomComicsGrid(context, vm.randomComics.toList()),
                    ),
                  ),
                ],

                /// 加载更多指示器
                Obx(
                  () => SliverToBoxAdapter(
                    child: vm.isLoadingMoreRandom.value
                        ? Padding(
                            padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace24),
                            child: const Center(child: CircularProgressIndicator()),
                          )
                        : SizedBox(height: metrics.kSpace24),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 返回顶部按钮
        Positioned(
          bottom: AppTheme.metrics.kSpace80,
          right: AppTheme.metrics.kSpace16,
          child: Obx(
            () => AnimatedScale(
              scale: _showBackToTop.value ? 1.0 : 0.0,
              duration: AppMotion.base,
              child: FloatingActionButton.small(
                heroTag: 'home_back_to_top',
                onPressed: () => _scrollController.animateTo(
                  0,
                  duration: AppMotion.slow,
                  curve: AppMotion.standard,
                ),
                tooltip: '返回顶部',
                child: DrawIcon(StrokeIcons.keyboardArrowUp),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Section 标题
  Widget _buildSectionHeader(BuildContext context, String title, VoidCallback? onRefresh) {
    final s = AppSemantic.of(context);
    final metrics = appMetrics;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.kSpace16,
          metrics.kSpace20,
          metrics.kSpace16,
          metrics.kSpace4,
        ),
        child: Row(
          children: [
            Container(
              width: metrics.kSpace4,
              height: metrics.kSpace20,
              decoration: BoxDecoration(
                color: s.accent,
                borderRadius: metrics.radius2,
              ),
            ),
            SizedBox(width: metrics.kSpace10),
            Text(title, style: AppTextStyles.sectionTitle(context)),
            if (onRefresh != null) ...[
              const Spacer(),
              TextButton.icon(
                icon: DrawIcon(StrokeIcons.refresh, size: metrics.iconSize16),
                label: const Text('换一批'),
                onPressed: onRefresh,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 推荐集合（纵向列表每个集合）
  Widget _buildCollections(BuildContext context, List<MangaCollection> collections) {
    final metrics = appMetrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final collection in collections) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.kSpace16,
              metrics.kSpace8,
              metrics.kSpace16,
              metrics.kSpace6,
            ),
            child: Text(
              collection.title,
              style: AppTextStyles.cardTitle(context),
            ),
          ),
          SizedBox(
            height: scaleW(220),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
              itemCount: collection.comics.length,
              separatorBuilder: (_, i) => SizedBox(width: metrics.kSpace10),
              itemBuilder: (ctx, i) {
                final comic = collection.comics[i];
                return SizedBox(
                  width: scaleW(130),
                  child: MangaComicCard(comic: comic, onTap: () => _goToDetail(context, comic.id)),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// 随机漫画网格
  Widget _buildRandomComicsGrid(BuildContext context, List<MangaComic> comics) {
    final metrics = appMetrics;
    final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) =>
            MangaComicCard(comic: comics[i], onTap: () => _goToDetail(context, comics[i].id)),
        childCount: comics.length,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: metrics.kSpace8,
        crossAxisSpacing: metrics.kSpace8,
        childAspectRatio: 0.6,
      ),
    );
  }

  /// 跳转到搜索页
  void _goToSearch(BuildContext context) {
    const MangaSearchRoute().push(context);
  }

  /// 跳转到漫画详情
  void _goToDetail(BuildContext context, String comicId) {
    MangaComicDetailRoute(comicId: comicId).push(context);
  }

  /// 显示用户菜单
  void _showUserMenu(BuildContext context, MangaHomeViewModel vm) {
    if (_isMenuOpen) return;
    _isMenuOpen = true;
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context);
    final m = AppTheme.metrics;
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: m.radius16.topLeft),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(m.kSpace16),
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: scaleW(44),
                      height: scaleW(44),
                      child: vm.currentUser.value?.avatar != null
                          ? MangaImageView(
                              image: vm.currentUser.value!.avatar!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: s.accentContainer,
                                child: DrawIcon(StrokeIcons.accountCircle,
                                  size: scaleW(28),
                                  color: s.accent,
                                ),
                              ),
                            )
                          : Container(
                              color: s.accentContainer,
                              child: DrawIcon(StrokeIcons.accountCircle,
                                size: scaleW(28),
                                color: s.accent,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: m.kSpace12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vm.currentUser.value?.name ?? '未知用户',
                          style: AppTextStyles.sectionTitle(context),
                        ),
                        SizedBox(height: m.kSpace2),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace8,
                            vertical: m.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: s.accentContainer,
                            borderRadius: m.radius4,
                          ),
                          child: Text(
                            'Lv.${vm.currentUser.value?.level ?? 0}',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize11,
                              color: s.accentText,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: m.kSpace1, color: s.hairline),
            _MenuTile(
              icon: StrokeIcons.favoriteOutline,
              iconColor: viz.coral.base,
              title: '我的收藏',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const MangaFavouritesScreen()));
              },
            ),
            _MenuTile(
              icon: StrokeIcons.history,
              iconColor: s.accent,
              title: '观看记录',
              onTap: () {
                Navigator.of(ctx).pop();
                const MangaHistoryRoute().push(context);
              },
            ),
            _MenuTile(
              icon: StrokeIcons.block,
              iconColor: viz.amber.base,
              title: '屏蔽词管理',
              onTap: () {
                Navigator.of(ctx).pop();
                showMangaBlockWordsDialog(context);
              },
            ),
            _MenuTile(
              icon: StrokeIcons.download,
              iconColor: viz.sky.base,
              title: '下载管理',
              onTap: () {
                Navigator.of(ctx).pop();
                const MangaDownloadsRoute().push(context);
              },
            ),
            Divider(height: m.kSpace1, color: s.hairline),
            _MenuTile(
              icon: StrokeIcons.logout,
              iconColor: s.danger.color,
              title: '退出登录',
              onTap: () async {
                Navigator.of(ctx).pop();
                await getIt<MangaService>().logout();
                vm.currentUser.value = null;
                vm.collections.clear();
                vm.randomComics.clear();
                if (context.mounted) setState(() {});
              },
            ),
            SizedBox(height: AppTheme.metrics.kSpace8),
          ],
        ),
      ),
    ).whenComplete(() => _isMenuOpen = false);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  final StrokeIcon icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      borderRadius: m.radiusControl,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace16,
          vertical: m.kSpace12,
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: m.radius8,
              ),
              child: DrawIcon(icon, size: scaleW(18), color: iconColor),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.rowTitle(context),
              ),
            ),
            DrawIcon(StrokeIcons.chevronRight,
              size: scaleW(20),
              color: s.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
