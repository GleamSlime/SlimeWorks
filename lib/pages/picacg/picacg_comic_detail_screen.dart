/// PicACG 漫画详情页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 漫画详情 ViewModel
class PicacgComicDetailViewModel extends BaseViewModel {
  final PicacgService _service = getIt<PicacgService>();

  PicacgComic? comic;
  List<PicacgEps> eps = [];
  PicacgPagination? epsPagination;
  bool isFavourite = false;

  Future<void> loadDetail(String comicId) async {
    setLoading(true);
    try {
      final results = await Future.wait([
        _service.getComicDetail(comicId),
        _service.getComicEps(comicId, page: 1),
      ]);
      comic = results[0] as PicacgComic;
      final epsList = results[1] as PicacgEpsList;
      eps = epsList.eps;
      epsPagination = epsList.pagination;
      isFavourite = comic?.isFavourite ?? false;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  Future<void> toggleFavourite(String comicId) async {
    try {
      await _service.toggleFavourite(comicId);
      isFavourite = !isFavourite;
      update();
    } catch (e) {
      setError(e.toString());
    }
  }
}

class PicacgComicDetailScreen extends BasePage<PicacgComicDetailViewModel> {
  const PicacgComicDetailScreen({super.key, required this.comicId});

  final String comicId;

  @override
  State<PicacgComicDetailScreen> createState() => _PicacgComicDetailScreenState();
}

class _PicacgComicDetailScreenState
    extends BasePageState<PicacgComicDetailViewModel, PicacgComicDetailScreen> {
  @override
  PicacgComicDetailViewModel createViewModel() => PicacgComicDetailViewModel();

  @override
  Future<void> onPageInit() async {
    await viewModel.loadDetail(widget.comicId);
  }

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return GetBuilder<PicacgComicDetailViewModel>(
      builder: (vm) {
        if (vm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (vm.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.errorMessage!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => viewModel.loadDetail(widget.comicId),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        if (vm.comic == null) return const SizedBox.shrink();
        return _buildDetail(context, vm);
      },
    );
  }

  Widget _buildDetail(BuildContext context, PicacgComicDetailViewModel vm) {
    final comic = vm.comic!;
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return CustomScrollView(
      slivers: [
        /// 返回栏
        SliverAppBar(
          leading: const BackButton(),
          title: Text(comic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: Icon(
                vm.isFavourite ? Icons.favorite : Icons.favorite_border,
                color: vm.isFavourite ? Colors.red : null,
              ),
              tooltip: vm.isFavourite ? '取消收藏' : '收藏',
              onPressed: () => vm.toggleFavourite(comic.id),
            ),
          ],
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
        ),

        /// 漫画头部信息
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(metrics.kSpace16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(metrics.kSpace12),
                  child: SizedBox(
                    width: scaleW(100),
                    height: scaleW(133),
                    child: PicacgImageView(
                      image: comic.thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __) => const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                SizedBox(width: metrics.kSpace12),

                /// 文字信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comic.title, style: theme.textTheme.titleMedium),
                      if (comic.author != null && comic.author!.isNotEmpty) ...[
                        SizedBox(height: metrics.kSpace4),
                        Text('作者: ${comic.author}', style: theme.textTheme.bodySmall),
                      ],
                      SizedBox(height: metrics.kSpace4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _buildChip(context, '${comic.epsCount} 章', Icons.photo_library_outlined),
                          _buildChip(context, '${comic.pagesCount} 张', Icons.image_outlined),
                          _buildChip(context, '${comic.likesCount} 喜欢', Icons.favorite_border),
                          if (comic.finished)
                            _buildChip(
                              context,
                              '完结',
                              Icons.check_circle_outline,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                      SizedBox(height: metrics.kSpace4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: comic.categories
                            .map(
                              (c) => ActionChip(
                                label: Text(c),
                                labelStyle: theme.textTheme.labelSmall,
                                onPressed: () {},
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        /// 简介
        if (comic.description != null && comic.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.kSpace16,
                vertical: metrics.kSpace4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('简介', style: theme.textTheme.titleSmall),
                  SizedBox(height: metrics.kSpace4),
                  Text(
                    comic.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),

        /// 章节标题
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.kSpace16,
              metrics.kSpace20,
              metrics.kSpace16,
              metrics.kSpace8,
            ),
            child: Text('章节列表', style: theme.textTheme.titleSmall),
          ),
        ),

        /// 章节列表（两列）
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final ep = vm.eps[i];
              return OutlinedButton(
                onPressed: () {
                  PicacgReaderRoute(
                    comicId: comic.id,
                    epsOrder: ep.order,
                    epsTitle: ep.title,
                  ).push(context);
                },
                child: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }, childCount: vm.eps.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: PlatformUtil.isDesktop ? 4 : 2,
              mainAxisSpacing: scaleW(8),
              crossAxisSpacing: scaleW(8),
              mainAxisExtent: scaleW(40),
            ),
          ),
        ),

        SliverToBoxAdapter(child: SizedBox(height: metrics.kSpace24)),
      ],
    );
  }

  Widget _buildChip(BuildContext context, String label, IconData icon, {Color? color}) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: effectiveColor),
        const SizedBox(width: 2),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: effectiveColor)),
      ],
    );
  }
}
