import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

class PicacgFavouritesViewModel extends BaseViewModel {
  final PicacgService _service = getIt<PicacgService>();

  final RxList<PicacgComic> comics = <PicacgComic>[].obs;
  final Rx<PicacgPagination?> pagination = Rx<PicacgPagination?>(null);
  final RxBool isLoadingMore = false.obs;

  int _currentPage = 1;
  PicacgSortOrder _sort = PicacgSortOrder.dateDescending;

  PicacgSortOrder get sort => _sort;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await refresh();
  }

  @override
  Future<void> refresh({PicacgSortOrder? sort}) async {
    _sort = sort ?? _sort;
    _currentPage = 1;
    comics.clear();
    setLoading(true);
    try {
      final result = await _service.getFavourites(page: 1, sort: _sort);
      comics.assignAll(result.comics);
      pagination.value = result.pagination;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<void> loadMore() async {
    final p = pagination.value;
    if (p == null || _currentPage >= p.pages || isLoadingMore.value) {
      return;
    }

    isLoadingMore.value = true;
    try {
      _currentPage++;
      final result = await _service.getFavourites(page: _currentPage, sort: _sort);
      comics.addAll(result.comics);
      pagination.value = result.pagination;
    } catch (_) {
      _currentPage--;
    } finally {
      isLoadingMore.value = false;
    }
  }

  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentPage < p.pages;
  }
}

class PicacgFavouritesScreen extends BasePage<PicacgFavouritesViewModel> {
  const PicacgFavouritesScreen({super.key});

  @override
  State<PicacgFavouritesScreen> createState() => _PicacgFavouritesScreenState();
}

class _PicacgFavouritesScreenState
    extends BasePageState<PicacgFavouritesViewModel, PicacgFavouritesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  PicacgFavouritesViewModel createViewModel() => PicacgFavouritesViewModel();

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

    return GetBuilder<PicacgFavouritesViewModel>(
      builder: (vm) {
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (vm.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(vm.errorMessage!, textAlign: TextAlign.center),
                SizedBox(height: metrics.kSpace12),
                FilledButton(onPressed: vm.refresh, child: const Text('重试')),
              ],
            ),
          );
        }

        if (vm.comics.isEmpty) {
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
          onRefresh: vm.refresh,
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
                        selected: vm.sort == PicacgSortOrder.dateDescending,
                        onSelected: (_) => vm.refresh(sort: PicacgSortOrder.dateDescending),
                      ),
                      ChoiceChip(
                        label: const Text('热门'),
                        selected: vm.sort == PicacgSortOrder.likeDescending,
                        onSelected: (_) => vm.refresh(sort: PicacgSortOrder.likeDescending),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.all(metrics.kSpace16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final comic = vm.comics[index];
                    return PicacgComicCard(
                      comic: comic,
                      onTap: () => PicacgComicDetailRoute(comicId: comic.id).push(context),
                    );
                  }, childCount: vm.comics.length),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: scaleW(8),
                    crossAxisSpacing: scaleW(8),
                    childAspectRatio: 0.6,
                  ),
                ),
              ),
              if (vm.hasMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
