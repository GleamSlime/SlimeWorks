library;

/// PicACG 收藏夹页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_favourites_viewmodel.dart';

class PicAcgFavouritesScreen extends BasePage<PicAcgFavouritesViewModel> {
  const PicAcgFavouritesScreen({super.key});

  @override
  State<PicAcgFavouritesScreen> createState() => _PicAcgFavouritesScreenState();
}

class _PicAcgFavouritesScreenState
    extends BasePageState<PicAcgFavouritesViewModel, PicAcgFavouritesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  PicAcgFavouritesViewModel createViewModel() => PicAcgFavouritesViewModel();

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
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border,
                size: scaleW(64),
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              SizedBox(height: metrics.kSpace16),
              Text(
                '还没有收藏任何漫画',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
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
                      Obx(
                        () => ChoiceChip(
                          label: const Text('新到旧'),
                          selected: viewModel.sort == PicAcgSortOrder.dateDescending,
                          onSelected: (_) =>
                              viewModel.refresh(sort: PicAcgSortOrder.dateDescending),
                        ),
                      ),
                      SizedBox(width: metrics.kSpace8),
                      Obx(
                        () => ChoiceChip(
                          label: const Text('热门'),
                          selected: viewModel.sort == PicAcgSortOrder.likeDescending,
                          onSelected: (_) =>
                              viewModel.refresh(sort: PicAcgSortOrder.likeDescending),
                        ),
                      ),
                      const Spacer(),
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
                    return PicAcgComicCard(
                      comic: comic,
                      onTap: () => PicAcgComicDetailRoute(comicId: comic.id).push(context),
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
