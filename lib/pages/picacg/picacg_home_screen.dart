/// PicACG 主页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
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
  @override
  PicAcgHomeViewModel createViewModel() => PicAcgHomeViewModel();

  @override
  String? get title => 'PicACG';

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return GetBuilder<PicAcgHomeViewModel>(
      builder: (vm) {
        if (!vm.isLoggedIn) {
          return _buildLoginPrompt(context);
        }
        return _buildHomeContent(context, vm);
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

    return CustomScrollView(
      slivers: [
        /// 顶部 AppBar
        SliverAppBar(
          title: Row(
            children: [
              Text('PicACG', style: theme.textTheme.titleLarge),
              const Spacer(),

              /// 搜索按钮
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索',
                onPressed: () => _goToSearch(context),
              ),

              /// 用户信息按钮
              IconButton(
                icon: const Icon(Icons.account_circle_outlined),
                tooltip: vm.currentUser.value?.name ?? '用户',
                onPressed: () => _showUserMenu(context, vm),
              ),
            ],
          ),
          floating: true,
          snap: true,
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),

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
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                  SizedBox(height: metrics.kSpace12),
                  FilledButton(onPressed: vm.loadHomeData, child: const Text('重新加载')),
                ],
              ),
            ),
          )
        else ...[
          /// 神魔推荐
          if (vm.collections.isNotEmpty) ...[
            _buildSectionHeader(context, '精选推荐', null),
            SliverToBoxAdapter(child: _buildCollections(context, vm.collections)),
          ],

          /// 随机漫画
          if (vm.randomComics.isNotEmpty) ...[
            _buildSectionHeader(context, '随机推荐', () {
              vm.loadHomeData();
            }),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
              sliver: _buildRandomComicsGrid(context, vm.randomComics),
            ),
          ],

          SliverToBoxAdapter(child: SizedBox(height: metrics.kSpace24)),
        ],
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
            Text(title, style: theme.textTheme.titleMedium),
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
    );
  }
}
