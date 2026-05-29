library;

/// Manga 收藏夹页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_comic_card.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_favourites_viewmodel.dart';

class MangaFavouritesScreen extends BasePage<MangaFavouritesViewModel> {
  const MangaFavouritesScreen({super.key});

  @override
  State<MangaFavouritesScreen> createState() => _MangaFavouritesScreenState();
}

class _MangaFavouritesScreenState
    extends BasePageState<MangaFavouritesViewModel, MangaFavouritesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  MangaFavouritesViewModel createViewModel() => MangaFavouritesViewModel();

  @override
  bool get showAppBar => false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(
        title: '我的收藏',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final metrics = appMetrics;
    final theme = Theme.of(context);

    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null) {
      return Center(
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
              viewModel.errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
            SizedBox(height: metrics.kSpace12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: viewModel.refresh,
            ),
          ],
        ),
      );
    }

    return Obx(() {
      if (viewModel.comics.isEmpty && !viewModel.isLoadingMore.value) {
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
                    Icons.favorite_border,
                    size: scaleW(36),
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: metrics.kSpace20),
                Text(
                  '还没有收藏任何漫画',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: metrics.kSpace8),
                Text(
                  '浏览漫画时点击收藏按钮即可添加',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
      return NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 280) {
            viewModel.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: viewModel.refresh,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 排序 chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    metrics.kSpace16,
                    metrics.kSpace12,
                    metrics.kSpace16,
                    metrics.kSpace4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: metrics.kSpace8,
                          runSpacing: metrics.kSpace8,
                          children: [
                            Obx(
                              () => ChoiceChip(
                                label: const Text('新到旧'),
                                selected: viewModel.sort == MangaSortOrder.dateDescending,
                                onSelected: (_) =>
                                    viewModel.refresh(sort: MangaSortOrder.dateDescending),
                              ),
                            ),
                            Obx(
                              () => ChoiceChip(
                                label: const Text('热门'),
                                selected: viewModel.sort == MangaSortOrder.likeDescending,
                                onSelected: (_) =>
                                    viewModel.refresh(sort: MangaSortOrder.likeDescending),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: metrics.kSpace8),
                      Obx(
                        () => Text(
                          '${viewModel.comics.length} 部',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final comic = viewModel.comics[index];
                    return MangaComicCard(
                      comic: comic,
                      onTap: () => MangaComicDetailRoute(comicId: comic.id).push(context),
                    );
                  }, childCount: viewModel.comics.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: scaleW(8),
                    crossAxisSpacing: scaleW(8),
                    childAspectRatio: 0.6,
                  ),
                ),
              ),

              if (viewModel.hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(metrics.kSpace24),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),

              SliverToBoxAdapter(child: SizedBox(height: metrics.kSpace24)),
            ],
          ),
        ),
      );
    });
  }
}
