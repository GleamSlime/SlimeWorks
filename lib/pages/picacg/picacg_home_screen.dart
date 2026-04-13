/// PicACG 主页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_block_words_dialog.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/components/picacg_login_dialog.dart';
import 'package:slime_works/pages/picacg/picacg_favourites_screen.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_home_viewmodel.dart';

class PicAcgHomeScreen extends BasePage<PicAcgHomeViewModel> {
  const PicAcgHomeScreen({super.key});

  @override
  State<PicAcgHomeScreen> createState() => _PicAcgHomeScreenState();
}

class _PicAcgHomeScreenState extends BasePageState<PicAcgHomeViewModel, PicAcgHomeScreen> {
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
  PicAcgHomeViewModel createViewModel() => PicAcgHomeViewModel();

  @override
  String? get title => 'PicACG';

  @override
  bool get showAppBar => false;

  ScreenChromeData _buildScreenChromeData(BuildContext context, PicAcgHomeViewModel vm) {
    final avatarImage = vm.currentUser.value?.avatar;
    return ScreenChromeData(
      title: 'PicACG',
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
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _showUserMenu(context, vm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: ClipOval(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: avatarImage != null
                            ? PicAcgImageView(
                                image: avatarImage,
                                fit: BoxFit.cover,
                                loadingBuilder: (_) => const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  ),
                                ),
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.account_circle_outlined),
                              )
                            : const Icon(Icons.account_circle_outlined, size: 28),
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
    return GetBuilder<PicAcgHomeViewModel>(
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_person_outlined,
            size: scaleW(64),
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          SizedBox(height: metrics.kSpace12),
          Text(
            '请先登录以使用 PicACG',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: metrics.kSpace20),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('登录'),
            onPressed: () async {
              final success = await showPicAcgLoginDialog(context);
              if (success) {
                await viewModel.onLoginSuccess();
              }
            },
          ),
        ],
      ),
    );
  }

  /// 主页内容（已登录）
  Widget _buildHomeContent(BuildContext context, PicAcgHomeViewModel vm) {
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
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
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
          bottom: 80,
          right: 16,
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
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: metrics.kSpace8),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            if (onRefresh != null) ...[
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
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
  Widget _buildCollections(BuildContext context, List<PicAcgCollection> collections) {
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
              metrics.kSpace4,
            ),
            child: Text(collection.title, style: Theme.of(context).textTheme.titleSmall),
          ),
          SizedBox(
            height: scaleW(200),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
              itemCount: collection.comics.length,
              separatorBuilder: (_, i) => SizedBox(width: metrics.kSpace8),
              itemBuilder: (ctx, i) {
                final comic = collection.comics[i];
                return SizedBox(
                  width: scaleW(120),
                  child: PicAcgComicCard(comic: comic, onTap: () => _goToDetail(context, comic.id)),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  /// 随机漫画网格
  Widget _buildRandomComicsGrid(BuildContext context, List<PicAcgComic> comics) {
    final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) =>
            PicAcgComicCard(comic: comics[i], onTap: () => _goToDetail(context, comics[i].id)),
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
    const PicAcgSearchRoute().push(context);
  }

  /// 跳转到漫画详情
  void _goToDetail(BuildContext context, String comicId) {
    PicAcgComicDetailRoute(comicId: comicId).push(context);
  }

  /// 显示用户菜单
  void _showUserMenu(BuildContext context, PicAcgHomeViewModel vm) {
    if (_isMenuOpen) return;
    _isMenuOpen = true;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(vm.currentUser.value?.name ?? '未知用户'),
              subtitle: Text('Lv.${vm.currentUser.value?.level ?? 0}'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('我的收藏'),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const PicAcgFavouritesScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('观看记录'),
              onTap: () {
                Navigator.of(ctx).pop();
                const PicAcgHistoryRoute().push(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('屏蔽词管理'),
              onTap: () {
                Navigator.of(ctx).pop();
                showPicAcgBlockWordsDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载管理'),
              onTap: () {
                Navigator.of(ctx).pop();
                const PicAcgDownloadsRoute().push(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await getIt<PicAcgService>().logout();
                vm.currentUser.value = null;
                vm.collections.clear();
                vm.randomComics.clear();
                if (context.mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() => _isMenuOpen = false);
  }
}
