library;

/// PicACG 收藏夹页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
  String? get title => '我的收藏';

  @override
  Future<void> onPageInit() async {
    _scrollController.addListener(_onScroll);
    await super.onPageInit();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 280) {
      viewModel.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    final metrics = appMetrics;

    /// isLoading / errorMessage 由基类 GetBuilder 触发重建，此处直接读取
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(viewModel.errorMessage!, textAlign: TextAlign.center),
            SizedBox(height: metrics.kSpace12),
            FilledButton(onPressed: viewModel.refresh, child: const Text('重试')),
          ],
        ),
      );
    }

    /// 列表内容用 Obx 监听，修复 loadMore 后列表不更新的问题
    return Obx(() {
      if (viewModel.comics.isEmpty) {
        return Center(
          child: Text(
            '还没有收藏任何漫画',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        );
      }

      final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
      return RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.kSpace16,
                  metrics.kSpace12,
                  metrics.kSpace16,
                  metrics.kSpace4,
                ),
                child: Wrap(
                  spacing: metrics.kSpace8,
                  runSpacing: metrics.kSpace8,
                  children: [
                    ChoiceChip(
                      label: const Text('新到旧'),
                      selected: viewModel.sort == PicAcgSortOrder.dateDescending,
                      onSelected: (_) => viewModel.refresh(sort: PicAcgSortOrder.dateDescending),
                    ),
                    ChoiceChip(
                      label: const Text('热门'),
                      selected: viewModel.sort == PicAcgSortOrder.likeDescending,
                      onSelected: (_) => viewModel.refresh(sort: PicAcgSortOrder.likeDescending),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.all(metrics.kSpace16),
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
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      );
    });
  }
}
