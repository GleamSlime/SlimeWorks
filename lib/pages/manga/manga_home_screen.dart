// Manga 主页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_block_words_dialog.dart';
import 'package:slime_works/pages/manga/components/manga_comic_card.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/components/manga_login_dialog.dart';
import 'package:slime_works/pages/manga/manga_favourites_screen.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_home_viewmodel.dart';

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
      _showBackToTop.value = _scrollController.offset > 600;
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
                icon: const Icon(Icons.search),
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
                        width: 28,
                        height: 28,
                        child: avatarImage != null
                            ? MangaImageView(
                                image: avatarImage,
                                fit: BoxFit.cover,
                                loadingBuilder: (_) => const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  ),
                                ),
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.account_circle_outlined),
                              )
                            : Icon(
                                Icons.account_circle_outlined,
                                size: AppTheme.metrics.iconSize28,
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
    final theme = Theme.of(context);
    final metrics = appMetrics;
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Container(
        padding: EdgeInsets.all(metrics.kSpace32),
        margin: EdgeInsets.symmetric(horizontal: metrics.kSpace24),
        decoration: BoxDecoration(
          color: isDark ? DarkColors.background2 : LightColors.background1,
          borderRadius: metrics.radius16,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: scaleW(72),
              height: scaleW(72),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: metrics.radius16,
              ),
              child: Icon(
                Icons.lock_person_outlined,
                size: scaleW(36),
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: metrics.kSpace20),
            Text(
              '请先登录以使用 Manga',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: metrics.kSpace8),
            Text(
              '登录后可浏览、搜索和收藏漫画',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            SizedBox(height: metrics.kSpace24),
            FilledButton.icon(
              icon: const Icon(Icons.login),
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
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Stack(
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 400) {
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
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: scaleW(48),
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        SizedBox(height: metrics.kSpace12),
                        Text(
                          vm.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        SizedBox(height: metrics.kSpace12),
                        FilledButton(onPressed: vm.loadHomeData, child: const Text('重新加载')),
                      ],
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
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                heroTag: 'home_back_to_top',
                onPressed: () => _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                ),
                tooltip: '返回顶部',
                child: const Icon(Icons.keyboard_arrow_up),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Section 标题
  Widget _buildSectionHeader(BuildContext context, String title, VoidCallback? onRefresh) {
    final theme = Theme.of(context);
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
              width: 4,
              height: AppTheme.metrics.kSpace20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.4),
                  ],
                ),
                borderRadius: AppTheme.metrics.radius2,
              ),
            ),
            SizedBox(width: metrics.kSpace10),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (onRefresh != null) ...[
              const Spacer(),
              TextButton.icon(
                icon: Icon(Icons.refresh, size: AppTheme.metrics.iconSize16),
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
    final theme = Theme.of(context);
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
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
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
    final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) =>
            MangaComicCard(comic: comics[i], onTap: () => _goToDetail(context, comics[i].id)),
        childCount: comics.length,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: scaleW(8),
        crossAxisSpacing: scaleW(8),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
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
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.account_circle_outlined,
                                  size: AppTheme.metrics.iconSize28,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              child: Icon(
                                Icons.account_circle_outlined,
                                size: AppTheme.metrics.iconSize28,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vm.currentUser.value?.name ?? '未知用户',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace2),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.metrics.kSpace8,
                            vertical: AppTheme.metrics.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: AppTheme.metrics.radius4,
                          ),
                          child: Text(
                            'Lv.${vm.currentUser.value?.level ?? 0}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            _MenuTile(
              icon: Icons.favorite_outline,
              iconColor: Colors.red,
              title: '我的收藏',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const MangaFavouritesScreen()));
              },
            ),
            _MenuTile(
              icon: Icons.history_outlined,
              iconColor: theme.colorScheme.primary,
              title: '观看记录',
              onTap: () {
                Navigator.of(ctx).pop();
                const MangaHistoryRoute().push(context);
              },
            ),
            _MenuTile(
              icon: Icons.block_outlined,
              iconColor: Colors.orange,
              title: '屏蔽词管理',
              onTap: () {
                Navigator.of(ctx).pop();
                showMangaBlockWordsDialog(context);
              },
            ),
            _MenuTile(
              icon: Icons.download_outlined,
              iconColor: isDark ? DarkColors.blue : LightColors.blue,
              title: '下载管理',
              onTap: () {
                Navigator.of(ctx).pop();
                const MangaDownloadsRoute().push(context);
              },
            ),
            Divider(height: 1, color: theme.dividerColor),
            _MenuTile(
              icon: Icons.logout,
              iconColor: theme.colorScheme.error,
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

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace16,
          vertical: AppTheme.metrics.kSpace12,
        ),
        child: Row(
          children: [
            Container(
              width: AppTheme.metrics.kSpace32,
              height: AppTheme.metrics.kSpace32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: Icon(icon, size: AppTheme.metrics.iconSize18, color: iconColor),
            ),
            SizedBox(width: AppTheme.metrics.kSpace12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: AppTheme.metrics.iconSize20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
