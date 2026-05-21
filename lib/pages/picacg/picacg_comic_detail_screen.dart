library;

/// PicACG 漫画详情页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_download_service.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_comic_detail_viewmodel.dart';
import 'package:slime_works/core/theme/app_colors.dart';

class PicAcgComicDetailScreen extends BasePage<PicAcgComicDetailViewModel> {
  const PicAcgComicDetailScreen({super.key, required this.comicId});

  final String comicId;

  @override
  State<PicAcgComicDetailScreen> createState() => _PicAcgComicDetailScreenState();
}

class _PicAcgComicDetailScreenState
    extends BasePageState<PicAcgComicDetailViewModel, PicAcgComicDetailScreen> {
  @override
  PicAcgComicDetailViewModel createViewModel() => PicAcgComicDetailViewModel();

  @override
  Future<void> onPageInit() async {
    await viewModel.loadDetail(widget.comicId);
  }

  @override
  bool get showAppBar => false;

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    final comic = viewModel.comic;

    return ScreenChromeData(
      title: comic?.title ?? '漫画详情',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          const PicAcgHomeRoute().go(context);
        },
      ),
      actions: comic == null
          ? const <Widget>[]
          : [
              /// 下载按钮
              Obx(() {
                final dl = getIt<PicAcgDownloadService>();
                final entry = dl.entries[comic.id];
                final hasDownloads = entry != null && entry.totalEps > 0;
                return IconButton(
                  icon: Icon(
                    hasDownloads ? Icons.download_done : Icons.download_outlined,
                    color: hasDownloads ? Colors.green : null,
                  ),
                  tooltip: '下载',
                  onPressed: () => _showDownloadSheet(context),
                );
              }),

              /// 收藏按鈕（使用 Obx 监听 RxBool 实时更新）
              Obx(
                () => IconButton(
                  icon: Icon(
                    viewModel.isFavourite.value ? Icons.favorite : Icons.favorite_border,
                    color: viewModel.isFavourite.value ? Colors.red : null,
                  ),
                  tooltip: viewModel.isFavourite.value ? '取消收藏' : '收藏',
                  onPressed: () => viewModel.toggleFavourite(comic.id),
                ),
              ),
            ],
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    /// isLoading / errorMessage 由基类 GetBuilder 触发重建，此处直接读取
    return ScreenChrome(
      data: _buildScreenChromeData(context),
      child: Builder(
        builder: (context) {
          if (viewModel.isLoading) {
            return const _ComicDetailSkeleton();
          }
          if (viewModel.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    viewModel.errorMessage!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace16),
                  FilledButton(
                    onPressed: () => viewModel.loadDetail(widget.comicId),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          if (viewModel.comic == null) return const SizedBox.shrink();
          return _buildDetail(context, viewModel);
        },
      ),
    );
  }

  Widget _buildDetail(BuildContext context, PicAcgComicDetailViewModel vm) {
    final comic = vm.comic!;
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return CustomScrollView(
      slivers: [
        // ── 封面 + 基本信息 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(metrics.kSpace16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(metrics.kSpace12),
                  child: SizedBox(
                    width: scaleW(110),
                    height: scaleW(146),
                    child: PicAcgImageView(
                      image: comic.thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, _) => const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                SizedBox(width: metrics.kSpace14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comic.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: metrics.kSpace8),
                      if (comic.creator != null)
                        GestureDetector(
                          onTap: () =>
                              PicAcgSearchRoute(keyword: comic.creator!.name).push(context),
                          child: Row(
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: scaleW(22),
                                  height: scaleW(22),
                                  child: comic.creator!.avatar != null
                                      ? PicAcgImageView(
                                          image: comic.creator!.avatar!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Icon(Icons.person, size: AppTheme.metrics.iconSize16),
                                        )
                                      : Icon(Icons.person, size: AppTheme.metrics.iconSize16),
                                ),
                              ),
                              SizedBox(width: metrics.kSpace8),
                              Flexible(
                                child: Text(
                                  comic.creator!.name,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (comic.author?.isNotEmpty == true)
                        GestureDetector(
                          onTap: () => PicAcgSearchRoute(keyword: comic.author!).push(context),
                          child: Text(
                            '作者: ${comic.author}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      if (comic.chineseTeam?.isNotEmpty == true)
                        SelectableText(
                          '汉化: ${comic.chineseTeam}',
                          style: theme.textTheme.bodySmall,
                        ),
                      SizedBox(height: metrics.kSpace6),

                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildInfoChip(
                            context,
                            '${comic.epsCount} 章',
                            Icons.photo_library_outlined,
                          ),
                          _buildInfoChip(context, '${comic.pagesCount} 页', Icons.image_outlined),
                          _buildInfoChip(
                            context,
                            _formatViewsCount(comic.viewsCount),
                            Icons.remove_red_eye_outlined,
                          ),
                          if (comic.finished)
                            _buildInfoChip(
                              context,
                              '完结',
                              Icons.check_circle_outline,
                              highlight: true,
                            ),
                        ],
                      ),
                      SizedBox(height: metrics.kSpace6),

                      if (comic.categories.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: comic.categories
                              .map(
                                (c) => GestureDetector(
                                  onTap: () => PicAcgSearchRoute(category: c).push(context),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: metrics.kSpace8,
                                      vertical: metrics.kSpace3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: metrics.radius12,
                                    ),
                                    child: Text(
                                      c,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
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

        // ── 互动按钮行 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 点赞
                Obx(
                  () => _ActionButton(
                    icon: vm.isLiked.value ? Icons.star : Icons.star_border,
                    label: '${vm.likesCount.value}',
                    active: vm.isLiked.value,
                    activeColor: Colors.amber,
                    onTap: () => vm.toggleLike(comic.id),
                  ),
                ),
                // 收藏
                Obx(
                  () => _ActionButton(
                    icon: vm.isFavourite.value ? Icons.favorite : Icons.favorite_border,
                    label: '收藏',
                    active: vm.isFavourite.value,
                    activeColor: Theme.of(context).colorScheme.error,
                    onTap: () => vm.toggleFavourite(comic.id),
                  ),
                ),
                // 评论
                _ActionButton(
                  icon: Icons.comment_outlined,
                  label: '${comic.commentsCount}',
                  onTap: () => _showCommentsSheet(context),
                ),
              ],
            ),
          ),
        ),

        // ── 上次阅读进度 ──
        Obx(() {
          final progress = vm.lastReadProgress.value;
          if (progress == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
          return SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(metrics.kSpace16, metrics.kSpace12, metrics.kSpace16, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(metrics.kSpace8),
                onTap: () {
                  final eps = vm.eps.cast<PicAcgEps?>().firstWhere(
                    (e) => e?.order == progress.epsOrder,
                    orElse: () => null,
                  );
                  PicAcgReaderRoute(
                    comicId: comic.id,
                    epsOrder: progress.epsOrder,
                    epsTitle: eps?.title ?? progress.epsTitle,
                  ).push(context);
                },
                child: Container(
                  padding: EdgeInsets.all(metrics.kSpace12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(metrics.kSpace8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bookmark,
                        size: AppTheme.metrics.iconSize18,
                        color: theme.colorScheme.primary,
                      ),
                      SizedBox(width: metrics.kSpace8),
                      Expanded(
                        child: Text(
                          '继续阅读：${progress.epsTitle}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: AppTheme.metrics.iconSize14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),

        // ── 描述 ──
        if (comic.description?.isNotEmpty == true)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(metrics.kSpace16, metrics.kSpace16, metrics.kSpace16, 0),
              child: _ExpandableText(label: '简介', text: comic.description!),
            ),
          ),

        // ── Tags ──
        if (comic.tags.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(metrics.kSpace16, metrics.kSpace16, metrics.kSpace16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tags',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: metrics.kSpace8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: comic.tags
                        .map(
                          (t) => GestureDetector(
                            onTap: () => PicAcgSearchRoute(keyword: t).push(context),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: metrics.kSpace10,
                                vertical: metrics.kSpace4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: metrics.radius12,
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                t,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

        // ── 元数据（ID / pica号 / 时间） ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(metrics.kSpace16, metrics.kSpace16, metrics.kSpace16, 0),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('ID: ${comic.id}'),
                  if (comic.shareId != null) SelectableText('pica号: ${comic.shareId}'),
                  if (comic.createdAt != null) Text('上传时间: ${_formatDate(comic.createdAt!)}'),
                  if (comic.updatedAt != null) Text('更新时间: ${_formatDate(comic.updatedAt!)}'),
                ],
              ),
            ),
          ),
        ),

        // ── 辅助按钮行 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(metrics.kSpace16, metrics.kSpace16, metrics.kSpace16, 0),
            child: Wrap(
              spacing: metrics.kSpace8,
              runSpacing: metrics.kSpace8,
              children: [
                // 已下载章节
                Obx(() {
                  final dl = getIt<PicAcgDownloadService>();
                  final entry = dl.entries[comic.id];
                  final count = entry?.episodes.values.where((e) => e.isCompleted).length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return OutlinedButton.icon(
                    icon: Icon(Icons.download_done, size: AppTheme.metrics.iconSize16),
                    label: Text('已下载 $count 话'),
                    onPressed: () => const PicAcgDownloadsRoute().push(context),
                  );
                }),
                // 看了这本的人也在看
                Obx(() {
                  if (vm.recommendations.isEmpty) return const SizedBox.shrink();
                  return OutlinedButton.icon(
                    icon: Icon(Icons.recommend_outlined, size: AppTheme.metrics.iconSize16),
                    label: Text('相关推荐 ${vm.recommendations.length}'),
                    onPressed: () => _showRecommendationsSheet(context, vm),
                  );
                }),
              ],
            ),
          ),
        ),

        // ── 章节标题 ──
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.kSpace16,
              metrics.kSpace20,
              metrics.kSpace16,
              metrics.kSpace8,
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: AppTheme.metrics.kSpace20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.4),
                      ],
                    ),
                    borderRadius: AppTheme.metrics.radius2,
                  ),
                ),
                SizedBox(width: metrics.kSpace10),
                Text(
                  '章节列表',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),

        // ── 章节 Grid ──
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final ep = vm.eps[i];
              return Obx(() {
                final dl = getIt<PicAcgDownloadService>();
                final info = dl.entries[comic.id]?.episodes[ep.order];
                final isDownloaded = info?.isCompleted == true;
                return OutlinedButton.icon(
                  onPressed: () => PicAcgReaderRoute(
                    comicId: comic.id,
                    epsOrder: ep.order,
                    epsTitle: ep.title,
                  ).push(context),
                  icon: isDownloaded
                      ? Icon(
                          Icons.check_circle,
                          size: AppTheme.metrics.iconSize14,
                          color: (Theme.of(context).brightness == Brightness.dark)
                              ? DarkColors.success
                              : LightColors.success,
                        )
                      : const SizedBox.shrink(),
                  label: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              });
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

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  void _showRecommendationsSheet(BuildContext context, PicAcgComicDetailViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace12),
              child: Text('相关推荐', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.6,
                ),
                itemCount: vm.recommendations.length,
                itemBuilder: (_, i) {
                  final c = vm.recommendations[i];
                  return PicAcgComicCard(
                    comic: c,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      PicAcgComicDetailRoute(comicId: c.id).push(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentsSheet(BuildContext context) {
    final comic = viewModel.comic;
    if (comic == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CommentsSheet(comicId: comic.id),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    String label,
    IconData icon, {
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final metrics = appMetrics;
    final bgColor = highlight
        ? theme.colorScheme.primary.withValues(alpha: 0.15)
        : theme.colorScheme.surfaceContainerHighest;
    final fgColor = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.kSpace8, vertical: metrics.kSpace3),
      decoration: BoxDecoration(color: bgColor, borderRadius: metrics.radius12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize12, color: fgColor),
          SizedBox(width: metrics.kSpace3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fgColor,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatViewsCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  void _showDownloadSheet(BuildContext context) {
    final comic = viewModel.comic;
    if (comic == null || viewModel.eps.isEmpty) return;

    final dl = getIt<PicAcgDownloadService>();
    final selected = <int>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            '选择下载章节',
                            style: TextStyle(
                              fontSize: AppTheme.metrics.fontSize15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                if (selected.length == viewModel.eps.length) {
                                  selected.clear();
                                } else {
                                  selected.addAll(viewModel.eps.map((e) => e.order));
                                }
                              });
                            },
                            child: Text(selected.length == viewModel.eps.length ? '取消全选' : '全选'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        controller: controller,
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.5,
                        ),
                        itemCount: viewModel.eps.length,
                        itemBuilder: (_, i) {
                          final ep = viewModel.eps[i];
                          final info = dl.entries[comic.id]?.episodes[ep.order];
                          final isDownloaded = info?.isCompleted == true;
                          final isSelected = selected.contains(ep.order);
                          return GestureDetector(
                            onTap: () {
                              if (isDownloaded) return;
                              setSheetState(() {
                                if (isSelected) {
                                  selected.remove(ep.order);
                                } else {
                                  selected.add(ep.order);
                                }
                              });
                            },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDownloaded
                                    ? Colors.green.withValues(alpha: 0.3)
                                    : isSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                                borderRadius: AppTheme.metrics.radius6,
                              ),
                              child: Text(
                                '${ep.order}',
                                style: TextStyle(
                                  fontSize: AppTheme.metrics.fontSize11,
                                  color: isDownloaded
                                      ? Colors.green
                                      : isSelected
                                      ? Theme.of(ctx).colorScheme.onPrimary
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.metrics.kSpace16,
                          vertical: AppTheme.metrics.kSpace8,
                        ),
                        child: FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  final selectedEps = viewModel.eps
                                      .where((e) => selected.contains(e.order))
                                      .toList();
                                  dl.downloadEpsMultiple(comic, selectedEps);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已加入下载队列：${selectedEps.length} 章')),
                                  );
                                },
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          child: Text('下载选中的 ${selected.length} 章'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 互动按钮
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? (activeColor ?? theme.colorScheme.primary)
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final bgColor = active
        ? (activeColor ?? theme.colorScheme.primary).withValues(alpha: 0.1)
        : theme.colorScheme.surfaceContainerHighest;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.metrics.radius10,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace16,
          vertical: AppTheme.metrics.kSpace10,
        ),
        decoration: BoxDecoration(color: bgColor, borderRadius: AppTheme.metrics.radius10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppTheme.metrics.iconSize22, color: color),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可展开文本
// ─────────────────────────────────────────────────────
// 骨架屏：漫画详情加载中占位
// ─────────────────────────────────────────────────────

/// 脉冲闪烁骨架屏，模拟漫画详情页布局。
/// 不依赖外部 shimmer 包，使用 AnimationController 自制动效。
class _ComicDetailSkeleton extends StatefulWidget {
  const _ComicDetailSkeleton();

  @override
  State<_ComicDetailSkeleton> createState() => _ComicDetailSkeletonState();
}

class _ComicDetailSkeletonState extends State<_ComicDetailSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        final alpha = 0.12 + _fade.value * 0.18;
        final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha);

        Widget box(double w, double h, {double r = 6}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(r)),
        );

        final metrics = appMetrics;
        final coverW = scaleW(100);
        final coverH = scaleW(133);

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(metrics.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 封面 + 标题区块 ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box(coverW, coverH, r: metrics.kSpace12),
                  SizedBox(width: metrics.kSpace12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        box(double.infinity, 18),
                        SizedBox(height: metrics.kSpace8),
                        box(120, 14),
                        SizedBox(height: metrics.kSpace8),
                        box(80, 14),
                        SizedBox(height: metrics.kSpace8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: List.generate(3, (_) => box(56, 26, r: 13)),
                        ),
                        SizedBox(height: metrics.kSpace8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: List.generate(2, (_) => box(64, 28, r: 14)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.kSpace16),

              // ── 互动按钮行 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (_) => box(64, 56, r: 8)),
              ),
              SizedBox(height: metrics.kSpace16),

              // ── 章节标题 ──
              box(80, 16),
              SizedBox(height: metrics.kSpace8),
              Wrap(spacing: 6, runSpacing: 6, children: List.generate(6, (_) => box(72, 32, r: 6))),
              SizedBox(height: metrics.kSpace16),

              // ── 简介标题 ──
              box(40, 14),
              SizedBox(height: metrics.kSpace8),
              box(double.infinity, 12),
              SizedBox(height: AppTheme.metrics.kSpace6),
              box(double.infinity, 12),
              SizedBox(height: AppTheme.metrics.kSpace6),
              box(200, 12),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────
// 可展开文本
// ─────────────────────────────────────────────────────

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.label, required this.text});
  final String label;
  final String text;
  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: theme.textTheme.titleSmall),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? '收起' : '展开',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
        SizedBox(height: AppTheme.metrics.kSpace6),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: SelectableText(
            widget.text,
            maxLines: _expanded ? null : 3,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

/// 评论列表 Sheet
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.comicId});
  final String comicId;
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _scrollController = ScrollController();
  List<PicAcgComment>? _comments;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  bool _loadingMore = false;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    if (current >= maxScroll - 200 && _hasMore && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      final service = getIt<PicAcgService>();
      final (list, pages) = await service.getComments(widget.comicId);
      if (mounted) {
        setState(() {
          _comments = list;
          _totalPages = pages;
          _page = 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final service = getIt<PicAcgService>();
      final (list, _) = await service.getComments(widget.comicId, page: _page + 1);
      if (mounted) {
        setState(() {
          _page += 1;
          _comments = [...?_comments, ...list];
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, sheetController) => Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace12),
            child: Text('评论', style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : _comments == null
                ? const Center(child: CircularProgressIndicator())
                : _comments!.isEmpty
                ? const Center(child: Text('暂无评论'))
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // 同步 DraggableScrollableSheet 的 controller → 我们的 scroll controller
                      // 实际上直接使用 sheetController 监听底部
                      if (n is ScrollUpdateNotification) {
                        final pos = n.metrics;
                        if (pos.extentAfter < 200 && _hasMore && !_loadingMore) {
                          _loadMore();
                        }
                      }
                      return false;
                    },
                    child: ListView.separated(
                      controller: sheetController,
                      padding: EdgeInsets.only(
                        left: AppTheme.metrics.kSpace12,
                        right: AppTheme.metrics.kSpace12,
                        top: AppTheme.metrics.kSpace12,
                        bottom: AppTheme.metrics.kSpace24,
                      ),
                      itemCount: _comments!.length + (_loadingMore ? 1 : (_hasMore ? 1 : 0)),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        // 底部加载指示器 / 触发行
                        if (i >= _comments!.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace16),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator(strokeWidth: 2)
                                  : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
                            ),
                          );
                        }
                        final c = _comments![i];
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: c.user.avatar != null
                                      ? PicAcgImageView(
                                          image: c.user.avatar!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(Icons.person),
                                        )
                                      : const Icon(Icons.person),
                                ),
                              ),
                              SizedBox(width: AppTheme.metrics.kSpace8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.user.name, style: theme.textTheme.labelMedium),
                                    SizedBox(height: AppTheme.metrics.kSpace2),
                                    Text(c.content, style: theme.textTheme.bodySmall),
                                    SizedBox(height: AppTheme.metrics.kSpace4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.thumb_up_outlined,
                                          size: AppTheme.metrics.iconSize12,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                        ),
                                        SizedBox(width: AppTheme.metrics.kSpace3),
                                        Text('${c.likesCount}', style: theme.textTheme.labelSmall),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
