library;

/// Manga 收藏夹页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_comic_card.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_favourites_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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
          icon: DrawIcon(StrokeIcons.arrowBack),
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
    final s = AppSemantic.of(context);

    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(StrokeIcons.cloudOff,
              size: metrics.iconSize48,
              color: s.textDisabled,
            ),
            SizedBox(height: metrics.kSpace12),
            Text(
              viewModel.errorMessage!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(context).copyWith(color: s.danger.color),
            ),
            SizedBox(height: metrics.kSpace12),
            FilledButton.icon(
              icon: DrawIcon(StrokeIcons.refresh),
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
                  child: DrawIcon(StrokeIcons.favoriteBorder,
                    size: scaleW(36),
                    color: s.accent,
                  ),
                ),
                SizedBox(height: metrics.kSpace20),
                Text(
                  '还没有收藏任何漫画',
                  style: AppTextStyles.sectionTitle(context),
                ),
                SizedBox(height: metrics.kSpace8),
                Text(
                  '浏览漫画时点击收藏按钮即可添加',
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
        );
      }

      final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
      return NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - scaleW(280)) {
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
                      // 行尾的计数会跟着字号滑杆变长，必须封顶，否则顶破这一行。
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: metrics.kSpace56),
                        child: ClipRect(
                          child: Obx(
                            () => Text(
                              '${viewModel.comics.length} 部',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption(context),
                            ),
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
                    mainAxisSpacing: metrics.kSpace8,
                    crossAxisSpacing: metrics.kSpace8,
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
