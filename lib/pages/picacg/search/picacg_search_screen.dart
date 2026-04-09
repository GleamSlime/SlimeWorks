/// PicACG 搜索页面

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

/// 搜索 ViewModel
class PicacgSearchViewModel extends BaseViewModel {
  final PicacgService _service = getIt<PicacgService>();

  final RxList<PicacgComic> results = <PicacgComic>[].obs;
  final Rx<PicacgPagination?> pagination = Rx<PicacgPagination?>(null);
  final RxBool isLoadingMore = false.obs;

  String _keyword = '';
  String _category = '';
  int _currentPage = 1;
  PicacgSortOrder _sort = PicacgSortOrder.dateDescending;

  String get keyword => _keyword;
  String get category => _category;
  PicacgSortOrder get sort => _sort;

  Future<void> search({
    required String keyword,
    String category = '',
    PicacgSortOrder sort = PicacgSortOrder.dateDescending,
  }) async {
    _keyword = keyword;
    _category = category;
    _sort = sort;
    _currentPage = 1;
    results.clear();
    setLoading(true);
    try {
      final list = await _service.searchComics(
        keyword: keyword,
        categories: category.isNotEmpty ? [category] : [],
        page: 1,
        sort: sort,
      );
      results.assignAll(list.comics);
      pagination.value = list.pagination;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<void> loadMore() async {
    final p = pagination.value;
    if (p == null || _currentPage >= p.pages) return;
    isLoadingMore.value = true;
    try {
      _currentPage++;
      final list = await _service.searchComics(
        keyword: _keyword,
        categories: _category.isNotEmpty ? [_category] : [],
        page: _currentPage,
        sort: _sort,
      );
      results.addAll(list.comics);
      pagination.value = list.pagination;
    } catch (e) {
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

class PicacgSearchScreen extends BasePage<PicacgSearchViewModel> {
  const PicacgSearchScreen({super.key, this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  State<PicacgSearchScreen> createState() => _PicacgSearchScreenState();
}

class _PicacgSearchScreenState extends BasePageState<PicacgSearchViewModel, PicacgSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  PicacgSearchViewModel createViewModel() => PicacgSearchViewModel();

  @override
  Future<void> onPageInit() async {
    _searchController.text = widget.keyword;
    if (widget.keyword.isNotEmpty || widget.category.isNotEmpty) {
      await viewModel.search(keyword: widget.keyword, category: widget.category);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      viewModel.loadMore();
    }
  }

  Future<void> _doSearch() async {
    final kw = _searchController.text.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();
    await viewModel.search(keyword: kw, category: widget.category);
  }

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Column(
      children: [
        /// 搜索栏
        AppBar(
          leading: const BackButton(),
          title: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索漫画、作者、标签...',
              border: InputBorder.none,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            onSubmitted: (_) => _doSearch(),
            autofocus: true,
          ),
          actions: [IconButton(icon: const Icon(Icons.search), onPressed: _doSearch)],
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),

        /// 结果区域
        Expanded(
          child: GetBuilder<PicacgSearchViewModel>(
            builder: (vm) {
              if (vm.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (vm.errorMessage != null) {
                return Center(
                  child: Text(
                    vm.errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                );
              }
              if (vm.results.isEmpty && vm.keyword.isNotEmpty) {
                return Center(
                  child: Text(
                    '没有找到相关漫画',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                );
              }
              if (vm.results.isEmpty) {
                return const SizedBox.shrink();
              }
              final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
              return GridView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(metrics.kSpace16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: scaleW(8),
                  crossAxisSpacing: scaleW(8),
                  childAspectRatio: 0.6,
                ),
                itemCount: vm.results.length + (vm.hasMore ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= vm.results.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final comic = vm.results[i];
                  return PicacgComicCard(
                    comic: comic,
                    onTap: () => PicacgComicDetailRoute(comicId: comic.id).push(context),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
