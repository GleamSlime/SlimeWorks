library;

/// Manga 漫画详情页

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/dialogs/node_directory_picker.dart';
import 'package:slime_works/components/dialogs/node_media_folder_picker.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/manga_download_service.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_comic_card.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_comic_detail_viewmodel.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

class MangaComicDetailScreen extends BasePage<MangaComicDetailViewModel> {
  const MangaComicDetailScreen({super.key, required this.comicId});

  final String comicId;

  @override
  State<MangaComicDetailScreen> createState() => _MangaComicDetailScreenState();
}

class _MangaComicDetailScreenState
    extends BasePageState<MangaComicDetailViewModel, MangaComicDetailScreen> {
  @override
  MangaComicDetailViewModel createViewModel() => MangaComicDetailViewModel();

  @override
  Future<void> onPageInit() async {
    await viewModel.loadDetail(widget.comicId);
  }

  @override
  bool get showAppBar => false;

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    final comic = viewModel.comic;
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context);

    return ScreenChromeData(
      title: comic?.title ?? '漫画详情',
      forceLocalChrome: true,
      leading: IconButton(
        icon: DrawIcon(StrokeIcons.arrowBack),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          const MangaHomeRoute().go(context);
        },
      ),
      actions: comic == null
          ? const <Widget>[]
          : [
              /// 下载按钮
              Obx(() {
                final dl = getIt<MangaDownloadService>();
                final entry = dl.entries[comic.id];
                final hasDownloads = entry != null && entry.totalEps > 0;
                return IconButton(
                  icon: DrawIcon(
                    hasDownloads ? StrokeIcons.downloadDone : StrokeIcons.download,
                    color: hasDownloads ? s.success.color : null,
                  ),
                  tooltip: '下载',
                  onPressed: () => _showDownloadSheet(context),
                );
              }),

              /// 收藏按鈕（使用 Obx 监听 RxBool 实时更新）
              Obx(
                () => IconButton(
                  icon: DrawIcon(
                    viewModel.isFavourite.value ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
                    color: viewModel.isFavourite.value ? viz.coral.base : null,
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
              child: SingleChildScrollView(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      viewModel.errorMessage!,
                      style: AppTextStyles.body(context).copyWith(
                        color: AppSemantic.of(context).danger.color,
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace16),
                    FilledButton(
                      onPressed: () => viewModel.loadDetail(widget.comicId),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (viewModel.comic == null) return const SizedBox.shrink();
          return _buildDetail(context, viewModel);
        },
      ),
    );
  }

  Widget _buildDetail(BuildContext context, MangaComicDetailViewModel vm) {
    final comic = vm.comic!;
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context);
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
                  borderRadius: metrics.radius12,
                  child: SizedBox(
                    width: scaleW(110),
                    height: scaleW(146),
                    child: MangaImageView(
                      image: comic.thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, _) => DrawIcon(StrokeIcons.brokenImage),
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
                        style: AppTextStyles.sectionTitle(context),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: metrics.kSpace8),
                      if (comic.creator != null)
                        GestureDetector(
                          onTap: () =>
                              MangaSearchRoute(keyword: comic.creator!.name).push(context),
                          child: Row(
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: scaleW(22),
                                  height: scaleW(22),
                                  // 头像框是固定宽度的宽度族容器，里面的兜底图标也必须走宽度族，
                                  // 否则字号滑杆一拉图标会长出框外。
                                  child: comic.creator!.avatar != null
                                      ? MangaImageView(
                                          image: comic.creator!.avatar!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              DrawIcon(StrokeIcons.person, size: scaleW(16)),
                                        )
                                      : DrawIcon(StrokeIcons.person, size: scaleW(16)),
                                ),
                              ),
                              SizedBox(width: metrics.kSpace8),
                              Flexible(
                                child: Text(
                                  comic.creator!.name,
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: metrics.fontSize12,
                                    color: s.accentText,
                                    weight: FontWeight.w500,
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
                          onTap: () => MangaSearchRoute(keyword: comic.author!).push(context),
                          child: Text(
                            '作者: ${comic.author}',
                            style: AppTextStyles.role(
                              context,
                              fontSize: metrics.fontSize12,
                              color: s.accentText,
                            ),
                          ),
                        ),
                      if (comic.chineseTeam?.isNotEmpty == true)
                        SelectableText(
                          '汉化: ${comic.chineseTeam}',
                          style: AppTextStyles.body(context),
                        ),
                      SizedBox(height: metrics.kSpace6),

                      Wrap(
                        spacing: metrics.kSpace6,
                        runSpacing: metrics.kSpace6,
                        children: [
                          _buildInfoChip(
                            context,
                            '${comic.epsCount} 章',
                            StrokeIcons.photoLibrary,
                          ),
                          _buildInfoChip(context, '${comic.pagesCount} 页', StrokeIcons.image),
                          _buildInfoChip(
                            context,
                            _formatViewsCount(comic.viewsCount),
                            StrokeIcons.removeRedEye,
                          ),
                          if (comic.finished)
                            _buildInfoChip(
                              context,
                              '完结',
                              StrokeIcons.checkCircleOutline,
                              highlight: true,
                            ),
                        ],
                      ),
                      SizedBox(height: metrics.kSpace6),

                      if (comic.categories.isNotEmpty)
                        Wrap(
                          spacing: metrics.kSpace4,
                          runSpacing: metrics.kSpace4,
                          children: comic.categories
                              .map(
                                (c) => GestureDetector(
                                  onTap: () => MangaSearchRoute(category: c).push(context),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: metrics.kSpace8,
                                      vertical: metrics.kSpace3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: s.accentContainer,
                                      borderRadius: metrics.radius12,
                                    ),
                                    child: Text(
                                      c,
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: metrics.fontSize11,
                                        color: s.accentText,
                                        weight: FontWeight.w500,
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
                    icon: vm.isLiked.value ? StrokeIcons.star : StrokeIcons.starBorder,
                    label: '${vm.likesCount.value}',
                    active: vm.isLiked.value,
                    activeColor: viz.amber.base,
                    onTap: () => vm.toggleLike(comic.id),
                  ),
                ),
                // 收藏
                Obx(
                  () => _ActionButton(
                    icon: vm.isFavourite.value ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
                    label: '收藏',
                    active: vm.isFavourite.value,
                    activeColor: viz.coral.base,
                    onTap: () => vm.toggleFavourite(comic.id),
                  ),
                ),
                // 评论
                _ActionButton(
                  icon: StrokeIcons.comment,
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
                borderRadius: metrics.radius8,
                onTap: () {
                  final eps = vm.eps.cast<MangaEps?>().firstWhere(
                    (e) => e?.order == progress.epsOrder,
                    orElse: () => null,
                  );
                  MangaReaderRoute(
                    comicId: comic.id,
                    epsOrder: progress.epsOrder,
                    epsTitle: eps?.title ?? progress.epsTitle,
                  ).push(context);
                },
                child: Container(
                  padding: EdgeInsets.all(metrics.kSpace12),
                  decoration: BoxDecoration(
                    color: s.accentContainer,
                    borderRadius: metrics.radius8,
                  ),
                  child: Row(
                    children: [
                      DrawIcon(
                        StrokeIcons.bookmark,
                        size: AppTheme.metrics.iconSize18,
                        color: s.accent,
                      ),
                      SizedBox(width: metrics.kSpace8),
                      Expanded(
                        child: Text(
                          '继续阅读：${progress.epsTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.role(
                            context,
                            fontSize: metrics.fontSize13,
                            color: s.accentText,
                          ),
                        ),
                      ),
                      DrawIcon(
                        StrokeIcons.arrowForwardIos,
                        size: AppTheme.metrics.iconSize14,
                        color: s.accent,
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
                  Text('Tags', style: AppTextStyles.sectionTitle(context)),
                  SizedBox(height: metrics.kSpace8),
                  Wrap(
                    spacing: metrics.kSpace6,
                    runSpacing: metrics.kSpace6,
                    children: comic.tags
                        .map(
                          (t) => GestureDetector(
                            onTap: () => MangaSearchRoute(keyword: t).push(context),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: metrics.kSpace10,
                                vertical: metrics.kSpace4,
                              ),
                              decoration: BoxDecoration(
                                color: s.surfaceSunken,
                                borderRadius: metrics.radius12,
                                border: Border.all(color: s.hairline, width: AppTheme.metrics.strokeHairline),
                              ),
                              child: Text(
                                t,
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: metrics.fontSize11,
                                  color: s.textSecondary,
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
              style: AppTextStyles.role(
                context,
                fontSize: metrics.fontSize12,
                color: s.textTertiary,
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
                  final dl = getIt<MangaDownloadService>();
                  final entry = dl.entries[comic.id];
                  final count = entry?.episodes.values.where((e) => e.isCompleted).length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return OutlinedButton.icon(
                    icon: DrawIcon(StrokeIcons.downloadDone, size: AppTheme.metrics.iconSize16),
                    label: Text('已下载 $count 话'),
                    onPressed: () => const MangaDownloadsRoute().push(context),
                  );
                }),
                // 看了这本的人也在看
                Obx(() {
                  if (vm.recommendations.isEmpty) return const SizedBox.shrink();
                  return OutlinedButton.icon(
                    icon: DrawIcon(StrokeIcons.recommend, size: AppTheme.metrics.iconSize16),
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
                  width: metrics.kSpace4,
                  height: metrics.kSpace20,
                  // UI 骨架上的强调条不给渐变与光晕，纯色一档。
                  decoration: BoxDecoration(color: s.accent, borderRadius: metrics.radius2),
                ),
                SizedBox(width: metrics.kSpace10),
                Text('章节列表', style: AppTextStyles.sectionTitle(context)),
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
                final dl = getIt<MangaDownloadService>();
                final info = dl.entries[comic.id]?.episodes[ep.order];
                final isDownloaded = info?.isCompleted == true;
                return OutlinedButton.icon(
                  onPressed: () => MangaReaderRoute(
                    comicId: comic.id,
                    epsOrder: ep.order,
                    epsTitle: ep.title,
                  ).push(context),
                  icon: isDownloaded
                      ? DrawIcon(
                          StrokeIcons.check,
                          size: AppTheme.metrics.iconSize14,
                          color: s.success.color,
                        )
                      : const SizedBox.shrink(),
                  label: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              });
            }, childCount: vm.eps.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: PlatformUtil.isDesktop ? 4 : 2,
              mainAxisSpacing: metrics.kSpace8,
              crossAxisSpacing: metrics.kSpace8,
              // 格子高度锁死在宽度族，章节名单行省略，字号滑杆拉到顶也不会顶破这一格。
              mainAxisExtent: metrics.kSpace40,
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

  void _showRecommendationsSheet(BuildContext context, MangaComicDetailViewModel vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius16.topLeft),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace12),
              child: Text('相关推荐', style: AppTextStyles.sectionTitle(context)),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppTheme.metrics.kSpace8,
                  crossAxisSpacing: AppTheme.metrics.kSpace8,
                  childAspectRatio: 0.6,
                ),
                itemCount: vm.recommendations.length,
                itemBuilder: (_, i) {
                  final c = vm.recommendations[i];
                  return MangaComicCard(
                    comic: c,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      MangaComicDetailRoute(comicId: c.id).push(context);
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius16.topLeft),
      ),
      builder: (ctx) => _CommentsSheet(comicId: comic.id),
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    String label,
    StrokeIcon icon, {
    bool highlight = false,
  }) {
    final s = AppSemantic.of(context);
    final metrics = appMetrics;
    final bgColor = highlight ? s.accentContainer : s.surfaceSunken;
    final fgColor = highlight ? s.accentText : s.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: metrics.kSpace8, vertical: metrics.kSpace3),
      decoration: BoxDecoration(color: bgColor, borderRadius: metrics.radius12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrawIcon(icon, size: AppTheme.metrics.iconSize12, color: fgColor),
          SizedBox(width: metrics.kSpace3),
          Text(
            label,
            style: AppTextStyles.role(
              context,
              fontSize: metrics.fontSize11,
              color: fgColor,
              weight: highlight ? FontWeight.w600 : FontWeight.w500,
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

  Future<void> _showDownloadSheet(BuildContext context) async {
    final comic = viewModel.comic;
    if (comic == null || viewModel.eps.isEmpty) return;
    // 章节上游是分页给的（每页 20 章），先把剩余页补齐再开弹层：
    // 否则"全选"只选得到第一页那 20 章，用户以为在下整本，实际只排了个头。
    await viewModel.ensureAllEps();
    if (!context.mounted) return;

    final dl = getIt<MangaDownloadService>();
    final messenger = ScaffoldMessenger.of(context);
    final selected = <int>{};

    // 下载目标：local（本机）/ node（推送到节点媒体库）
    String destMode = 'local';
    NodeEndpoint? pickedNode;
    String? nodeTargetDir;
    String? nodeBaseFolderId;
    String? nodeFolderLabel;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius16.topLeft),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final s = AppSemantic.of(ctx);
            final m = AppTheme.metrics;
            // 选择节点：列出已启用节点，选中后清空目录选择
            Future<void> pickNode() async {
              final nodes = getIt<NodeSettingsService>();
              final node = await showModalBottomSheet<NodeEndpoint>(
                context: ctx,
                useRootNavigator: true,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetCtx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppTheme.metrics.kSpace16,
                          AppTheme.metrics.kSpace4,
                          AppTheme.metrics.kSpace16,
                          AppTheme.metrics.kSpace8,
                        ),
                        child: Text('选择节点', style: AppTextStyles.sectionTitle(sheetCtx)),
                      ),
                      if (nodes.enabledRemoteNodes.isEmpty)
                        const ListTile(title: Text('暂无已启用的节点'))
                      else
                        // 节点多时内部滚动，避免超出弹层高度溢出
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(sheetCtx).size.height * 0.6,
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              ...nodes.enabledRemoteNodes.map(
                                (n) => ListTile(
                                  leading: DrawIcon(StrokeIcons.deviceHub),
                                  title: Text(
                                    n.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    n.effectiveApiBaseUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption(sheetCtx),
                                  ),
                                  trailing: n.id == pickedNode?.id
                                      ? DrawIcon(
                                          StrokeIcons.check,
                                          size: AppTheme.metrics.iconSize18,
                                          color: AppSemantic.of(sheetCtx).accent,
                                        )
                                      : null,
                                  onTap: () => Navigator.of(sheetCtx).pop(n),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: AppTheme.metrics.kSpace8),
                    ],
                  ),
                ),
              );
              if (node != null) {
                setSheetState(() {
                  pickedNode = node;
                  nodeTargetDir = null;
                  nodeBaseFolderId = null;
                  nodeFolderLabel = null;
                });
              }
            }

            // 选择节点目录：复用媒体库导入的目录浏览器，逐层进入后确认目标目录
            Future<void> pickFolder() async {
              if (pickedNode == null) return;
              final nodes = getIt<NodeSettingsService>();
              final node = pickedNode!;
              // 尽量从媒体库根目录开始浏览，解析失败则从节点根开始
              String initial = '/';
              try {
                final root = await nodes.resolveNodeUploadTarget(
                  nodeId: node.id,
                  folderId: '',
                );
                if (root.targetDir.isNotEmpty) {
                  initial = root.targetDir;
                } else if (root.candidates.isNotEmpty) {
                  initial = root.candidates.first;
                }
              } catch (_) {
                // 拿不到库根就从节点根目录开始浏览
              }
              final dir = await showDialog<String>(
                // ignore: use_build_context_synchronously
                context: ctx,
                builder: (_) => NodeDirectoryPicker(
                  nodeId: node.id,
                  nodeSettingsService: nodes,
                  initialPath: initial,
                ),
              );
              if (dir == null || dir.isEmpty) return;
              setSheetState(() {
                nodeTargetDir = dir;
              });
            }

            // 选择导入归位的媒体库文件夹（可选）：逐层浏览节点媒体库文件夹树
            Future<void> pickMediaFolder() async {
              if (pickedNode == null) return;
              final nodes = getIt<NodeSettingsService>();
              // ignore: use_build_context_synchronously
              final folder = await showDialog<(String, String)>(
                context: ctx,
                builder: (_) => NodeMediaFolderPicker(
                  nodeId: pickedNode!.id,
                  nodeSettingsService: nodes,
                ),
              );
              if (folder == null) return;
              setSheetState(() {
                nodeBaseFolderId = folder.$1.isEmpty ? null : folder.$1;
                nodeFolderLabel = folder.$2;
              });
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (_, controller) {
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace12, m.kSpace16, 0),
                      child: Row(
                        children: [
                          Text('选择下载章节', style: AppTextStyles.sectionTitle(ctx)),
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
                    // 下载目标：本机 / 节点
                    Padding(
                      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, 0),
                      child: Row(
                        children: [
                          Text(
                            '下载到',
                            style: AppTextStyles.role(ctx, fontSize: m.fontSize12, color: s.textSecondary),
                          ),
                          SizedBox(width: m.kSpace12),
                          ChoiceChip(
                            label: const Text('本机'),
                            visualDensity: VisualDensity.compact,
                            selected: destMode == 'local',
                            onSelected: (_) =>
                                setSheetState(() => destMode = 'local'),
                          ),
                          SizedBox(width: m.kSpace8),
                          ChoiceChip(
                            label: const Text('节点'),
                            visualDensity: VisualDensity.compact,
                            selected: destMode == 'node',
                            onSelected: (_) =>
                                setSheetState(() => destMode = 'node'),
                          ),
                        ],
                      ),
                    ),
                    if (destMode == 'node') ...[
                      // 节点选择行
                      Padding(
                        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, 0),
                        child: InkWell(
                          borderRadius: m.radius8,
                          onTap: pickNode,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: m.kSpace12,
                              vertical: m.kSpace8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '节点',
                                  style: AppTextStyles.role(
                                    ctx,
                                    fontSize: m.fontSize12,
                                    color: s.textSecondary,
                                  ),
                                ),
                                SizedBox(width: m.kSpace12),
                                Expanded(
                                  child: Text(
                                    pickedNode?.name ?? '选择节点',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.role(
                                      ctx,
                                      fontSize: m.fontSize13,
                                      color: pickedNode == null ? s.accentText : s.textPrimary,
                                    ),
                                  ),
                                ),
                                DrawIcon(
                                  StrokeIcons.chevronRight,
                                  size: m.iconSize16,
                                  color: s.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 目标目录行
                      Padding(
                        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace4, m.kSpace16, 0),
                        child: InkWell(
                          borderRadius: m.radius8,
                          onTap: pickFolder,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: m.kSpace12,
                              vertical: m.kSpace8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '目标目录',
                                  style: AppTextStyles.role(
                                    ctx,
                                    fontSize: m.fontSize12,
                                    color: s.textSecondary,
                                  ),
                                ),
                                SizedBox(width: m.kSpace12),
                                Expanded(
                                  child: Text(
                                    nodeTargetDir ?? '选择目录',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.role(
                                      ctx,
                                      fontSize: m.fontSize13,
                                      color: nodeTargetDir == null ? s.accentText : s.textPrimary,
                                    ),
                                  ),
                                ),
                                DrawIcon(
                                  StrokeIcons.chevronRight,
                                  size: m.iconSize16,
                                  color: s.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 归入的媒体库文件夹行（可选）
                      Padding(
                        padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace4, m.kSpace16, 0),
                        child: InkWell(
                          borderRadius: m.radius8,
                          onTap: pickMediaFolder,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: m.kSpace12,
                              vertical: m.kSpace8,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  '归入文件夹',
                                  style: AppTextStyles.role(
                                    ctx,
                                    fontSize: m.fontSize12,
                                    color: s.textSecondary,
                                  ),
                                ),
                                SizedBox(width: m.kSpace12),
                                Expanded(
                                  child: Text(
                                    nodeFolderLabel ?? '媒体库根目录（可选）',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.role(
                                      ctx,
                                      fontSize: m.fontSize13,
                                      color: nodeFolderLabel == null ? s.accentText : s.textPrimary,
                                    ),
                                  ),
                                ),
                                DrawIcon(
                                  StrokeIcons.chevronRight,
                                  size: m.iconSize16,
                                  color: s.textTertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: GridView.builder(
                        controller: controller,
                        padding: EdgeInsets.all(m.kSpace12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: m.kSpace8,
                          crossAxisSpacing: m.kSpace8,
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
                                    ? s.success.container
                                    : isSelected
                                    ? s.accent
                                    : s.surfaceRaised,
                                borderRadius: m.radius6,
                              ),
                              child: Text(
                                '${ep.order}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.role(
                                  ctx,
                                  fontSize: m.fontSize11,
                                  color: isDownloaded
                                      ? s.success.onContainer
                                      : isSelected
                                      ? s.accentOn
                                      : s.textSecondary,
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
                          onPressed: selected.isEmpty ||
                                  (destMode == 'node' &&
                                      (pickedNode == null ||
                                          nodeTargetDir == null))
                              ? null
                              : () {
                                  Navigator.of(ctx).pop();
                                  final selectedEps = viewModel.eps
                                      .where((e) => selected.contains(e.order))
                                      .toList();
                                  if (destMode == 'node') {
                                    _startNodePush(
                                      context,
                                      dl,
                                      comic,
                                      selectedEps,
                                      pickedNode!.id,
                                      nodeTargetDir!,
                                      nodeBaseFolderId,
                                    );
                                  } else {
                                    dl.downloadEpsMultiple(comic, selectedEps);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '已加入下载队列：${selectedEps.length} 章',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                          child: Text(
                            destMode == 'node'
                                ? '下载并推送 ${selected.length} 章'
                                : '下载选中的 ${selected.length} 章',
                          ),
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

  /// 下载章节并推送到节点：先弹常驻进度对话框，推送完成后关闭并汇总结果。
  void _startNodePush(
    BuildContext screenContext,
    MangaDownloadService dl,
    MangaComic comic,
    List<MangaEps> eps,
    String nodeId,
    String targetDir,
    String? baseFolderId,
  ) {
    final navigator = Navigator.of(screenContext, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(screenContext);
    showDialog(
      context: screenContext,
      barrierDismissible: false,
      builder: (dialogCtx) => Obx(() {
        return AlertDialog(
          title: const Text('下载并推送到节点'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dl.nodePushStage.value.isEmpty
                    ? '准备中...'
                    : dl.nodePushStage.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(dialogCtx),
              ),
              SizedBox(height: AppTheme.metrics.kSpace12),
              LinearProgressIndicator(
                value: dl.nodePushTotal.value > 0
                    ? (dl.nodePushDone.value / dl.nodePushTotal.value)
                        .clamp(0.0, 1.0)
                        .toDouble()
                    : null,
              ),
              SizedBox(height: AppTheme.metrics.kSpace8),
              Text(
                '${dl.nodePushDone.value}/${dl.nodePushTotal.value}',
                style: AppTextStyles.caption(dialogCtx),
              ),
            ],
          ),
        );
      }),
    );
    dl
        .downloadEpsToNode(
          comic,
          eps,
          nodeId: nodeId,
          targetDir: targetDir,
          baseFolderId: baseFolderId,
        )
        .then((result) {
          if (navigator.canPop()) navigator.pop();
          if (!mounted) return;
          final msg = result.fail == 0
              ? '成功推送 ${result.success} 章到节点'
              : '推送完成：成功 ${result.success} 章，失败 ${result.fail} 章';
          messenger.showSnackBar(SnackBar(content: Text(msg)));
        });
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

  final StrokeIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    // 未点亮走次要文字色；点亮时优先用调用方传入的语义色（收藏/点赞各有其色）
    final color = active ? (activeColor ?? s.accent) : s.textSecondary;
    final bgColor = active ? color.withValues(alpha: 0.1) : s.surfaceSunken;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radius10,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace16,
          vertical: m.kSpace10,
        ),
        decoration: BoxDecoration(color: bgColor, borderRadius: m.radius10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(icon, size: m.iconSize22, color: color),
            SizedBox(height: m.kSpace4),
            Text(
              label,
              // 图标走字号族、内距走宽度族，字号滑杆拉到顶时靠截断守住宽度
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize11,
                color: color,
                weight: active ? FontWeight.w600 : FontWeight.w500,
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
    // 骨架屏的呼吸周期走循环档 pulse：呼吸类一律不拿一次性过渡时长（base/slow）顶，
    // 否则加载中会闪得像在报错。曲线取通用档，正反面同形。
    _ctrl = AnimationController(vsync: this, duration: AppMotion.pulse)
      ..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: AppMotion.standard);
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
        final s = AppSemantic.of(context);
        final alpha = 0.12 + _fade.value * 0.18;
        final base = s.textPrimary.withValues(alpha: alpha);

        final metrics = appMetrics;
        // 占位块的尺寸全部走宽度族：骨架屏里没有任何文字，不能跟用户字号联动。
        Widget box(double w, double h, {double? r}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(r ?? metrics.kSpace6),
          ),
        );

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
                        box(double.infinity, metrics.kSpace18),
                        SizedBox(height: metrics.kSpace8),
                        box(scaleW(120), metrics.kSpace14),
                        SizedBox(height: metrics.kSpace8),
                        box(metrics.kSpace80, metrics.kSpace14),
                        SizedBox(height: metrics.kSpace8),
                        Wrap(
                          spacing: metrics.kSpace4,
                          runSpacing: metrics.kSpace4,
                          children: List.generate(3, (_) => box(scaleW(56), scaleW(26), r: scaleW(13))),
                        ),
                        SizedBox(height: metrics.kSpace8),
                        Wrap(
                          spacing: metrics.kSpace4,
                          runSpacing: metrics.kSpace4,
                          children: List.generate(2, (_) => box(scaleW(64), scaleW(28), r: scaleW(14))),
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
                children: List.generate(3, (_) => box(scaleW(64), metrics.kSpace56, r: metrics.kSpace8)),
              ),
              SizedBox(height: metrics.kSpace16),

              // ── 章节标题 ──
              box(metrics.kSpace80, metrics.kSpace16),
              SizedBox(height: metrics.kSpace8),
              Wrap(
                spacing: metrics.kSpace6,
                runSpacing: metrics.kSpace6,
                children: List.generate(6, (_) => box(scaleW(72), metrics.kSpace32)),
              ),
              SizedBox(height: metrics.kSpace16),

              // ── 简介标题 ──
              box(scaleW(40), metrics.kSpace14),
              SizedBox(height: metrics.kSpace8),
              box(double.infinity, metrics.kSpace12),
              SizedBox(height: metrics.kSpace6),
              box(double.infinity, metrics.kSpace12),
              SizedBox(height: metrics.kSpace6),
              box(scaleW(200), metrics.kSpace12),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: AppTextStyles.rowTitle(context)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? '收起' : '展开',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize11,
                  color: s.accentText,
                  weight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: m.kSpace6),
        AnimatedSize(
          duration: AppMotion.base,
          alignment: Alignment.topCenter,
          child: SelectableText(
            widget.text,
            maxLines: _expanded ? null : 3,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              color: s.textSecondary,
              height: 1.6,
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
  List<MangaComment>? _comments;
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
      final service = getIt<MangaService>();
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
      final service = getIt<MangaService>();
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      builder: (_, sheetController) => Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.kSpace12),
            child: Text('评论', style: AppTextStyles.sectionTitle(context)),
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
                      separatorBuilder: (_, _) => Divider(height: m.kSpace1, color: s.hairline),
                      itemBuilder: (_, i) {
                        // 底部加载指示器 / 触发行
                        if (i >= _comments!.length) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: m.kSpace16),
                            child: Center(
                              child: _loadingMore
                                  ? CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular, color: s.accent)
                                  : TextButton(onPressed: _loadMore, child: const Text('加载更多')),
                            ),
                          );
                        }
                        final c = _comments![i];
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: m.kSpace8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipOval(
                                child: SizedBox(
                                  width: scaleW(36),
                                  height: scaleW(36),
                                  child: c.user.avatar != null
                                      ? MangaImageView(
                                          image: c.user.avatar!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => DrawIcon(StrokeIcons.person),
                                        )
                                      : DrawIcon(StrokeIcons.person),
                                ),
                              ),
                              SizedBox(width: m.kSpace8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.user.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: m.fontSize12,
                                        color: s.textSecondary,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: m.kSpace2),
                                    Text(
                                      c.content,
                                      style: AppTextStyles.role(
                                        context,
                                        fontSize: m.fontSize12,
                                        color: s.textPrimary,
                                        height: 1.6,
                                      ),
                                    ),
                                    SizedBox(height: m.kSpace4),
                                    Row(
                                      children: [
                                        DrawIcon(StrokeIcons.thumbUp,
                                          size: m.iconSize12,
                                          color: s.textTertiary,
                                        ),
                                        SizedBox(width: m.kSpace3),
                                        Flexible(
                                          child: Text(
                                            '${c.likesCount}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.caption(context),
                                          ),
                                        ),
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
