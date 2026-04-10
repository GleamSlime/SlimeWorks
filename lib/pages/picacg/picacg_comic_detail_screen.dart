library;

/// PicACG 漫画详情页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
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
              IconButton(
                icon: Icon(
                  viewModel.isFavourite ? Icons.favorite : Icons.favorite_border,
                  color: viewModel.isFavourite ? Colors.red : null,
                ),
                tooltip: viewModel.isFavourite ? '取消收藏' : '收藏',
                onPressed: () => viewModel.toggleFavourite(comic.id),
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
            return const Center(child: CircularProgressIndicator());
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
                  const SizedBox(height: 16),
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
                // 封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(metrics.kSpace12),
                  child: SizedBox(
                    width: scaleW(100),
                    height: scaleW(133),
                    child: PicAcgImageView(
                      image: comic.thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e) => const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                SizedBox(width: metrics.kSpace12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comic.title, style: theme.textTheme.titleMedium),
                      SizedBox(height: metrics.kSpace8),
                      // 发布者行
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
                                          errorBuilder: (_, __) =>
                                              const Icon(Icons.person, size: 16),
                                        )
                                      : const Icon(Icons.person, size: 16),
                                ),
                              ),
                              SizedBox(width: metrics.kSpace8),
                              Flexible(
                                child: Text(
                                  comic.creator!.name,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 作者/汉化组
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
                        Text('汉化: ${comic.chineseTeam}', style: theme.textTheme.bodySmall),
                      SizedBox(height: metrics.kSpace4),

                      // 统计 chips
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _buildChip(context, '${comic.epsCount} 章', Icons.photo_library_outlined),
                          _buildChip(context, '${comic.pagesCount} 张', Icons.image_outlined),
                          _buildChip(
                            context,
                            '${comic.viewsCount} 浏览',
                            Icons.remove_red_eye_outlined,
                          ),
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

                      // 分类
                      if (comic.categories.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: comic.categories
                              .map(
                                (c) => GestureDetector(
                                  onTap: () => PicAcgSearchRoute(category: c).push(context),
                                  child: Chip(
                                    label: Text(c),
                                    labelStyle: theme.textTheme.labelSmall,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                GetBuilder<PicAcgComicDetailViewModel>(
                  builder: (_) => _ActionButton(
                    icon: vm.isFavourite ? Icons.favorite : Icons.favorite_border,
                    label: '收藏',
                    active: vm.isFavourite,
                    activeColor: Colors.red,
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
                      Icon(Icons.bookmark, size: 18, color: theme.colorScheme.primary),
                      SizedBox(width: metrics.kSpace8),
                      Expanded(
                        child: Text(
                          '继续阅读：${progress.epsTitle}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.primary),
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
                  Text('Tags', style: theme.textTheme.titleSmall),
                  SizedBox(height: metrics.kSpace8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: comic.tags
                        .map(
                          (t) => GestureDetector(
                            onTap: () => PicAcgSearchRoute(keyword: t).push(context),
                            child: Chip(
                              label: Text(t),
                              labelStyle: theme.textTheme.labelSmall,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    icon: const Icon(Icons.download_done, size: 16),
                    label: Text('已下载 $count 话'),
                    onPressed: () => const PicAcgDownloadsRoute().push(context),
                  );
                }),
                // 看了这本的人也在看
                Obx(() {
                  if (vm.recommendations.isEmpty) return const SizedBox.shrink();
                  return OutlinedButton.icon(
                    icon: const Icon(Icons.recommend_outlined, size: 16),
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
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: metrics.kSpace8),
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
                      ? const Icon(Icons.check_circle, size: 14, color: Colors.green)
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('相关推荐', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.all(12),
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
                          const Text(
                            '选择下载章节',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        padding: const EdgeInsets.all(12),
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
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${ep.order}',
                                style: TextStyle(
                                  fontSize: 12,
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 可展开文本
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
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
  List<PicAcgComment>? _comments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = getIt<PicAcgService>();
      final list = await service.getComments(widget.comicId);
      if (mounted) setState(() => _comments = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('评论', style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : _comments == null
                ? const Center(child: CircularProgressIndicator())
                : _comments!.isEmpty
                ? const Center(child: Text('暂无评论'))
                : ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: _comments!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _comments![i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
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
                                        errorBuilder: (_, __) => const Icon(Icons.person),
                                      )
                                    : const Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.user.name, style: theme.textTheme.labelMedium),
                                  const SizedBox(height: 2),
                                  Text(c.content, style: theme.textTheme.bodySmall),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.thumb_up_outlined,
                                        size: 12,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                      ),
                                      const SizedBox(width: 3),
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
        ],
      ),
    );
  }
}
