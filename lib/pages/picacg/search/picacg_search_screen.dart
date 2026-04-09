library;

/// PicACG 搜索页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_search_viewmodel.dart';

class PicAcgSearchScreen extends BasePage<PicAcgSearchViewModel> {
  const PicAcgSearchScreen({super.key, this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  State<PicAcgSearchScreen> createState() => _PicAcgSearchScreenState();
}

class _PicAcgSearchScreenState extends BasePageState<PicAcgSearchViewModel, PicAcgSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  PicAcgSearchViewModel createViewModel() => PicAcgSearchViewModel();

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
        Expanded(child: _buildResults(context)),
      ],
    );
  }

  /// 搜索结果区域（使用 Obx 监听 RxList 变化，修复 loadMore 后列表不更新的问题）
  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    /// isLoading / errorMessage 由基类 GetBuilder 触发重建，此处直接读取
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null) {
      return Center(
        child: Text(
          viewModel.errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }

    /// 列表数据由 Obx 监听，确保 loadMore 时新条目即时显示
    return Obx(() {
      if (viewModel.results.isEmpty && viewModel.keyword.isNotEmpty) {
        return Center(
          child: Text(
            '没有找到相关漫画',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        );
      }
      if (viewModel.results.isEmpty) {
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
        itemCount: viewModel.results.length + (viewModel.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= viewModel.results.length) {
            return const Center(
              child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            );
          }
          final comic = viewModel.results[i];
          return PicAcgComicCard(
            comic: comic,
            onTap: () => PicAcgComicDetailRoute(comicId: comic.id).push(context),
          );
        },
      );
    });
  }
}
