library;

/// Manga 下载管理页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_download_model.dart';
import 'package:slime_works/pages/manga/view_models/manga_downloads_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class MangaDownloadsScreen extends BasePage<MangaDownloadsViewModel> {
  const MangaDownloadsScreen({super.key});

  @override
  State<MangaDownloadsScreen> createState() => _MangaDownloadsScreenState();
}

class _MangaDownloadsScreenState
    extends BasePageState<MangaDownloadsViewModel, MangaDownloadsScreen> {
  @override
  MangaDownloadsViewModel createViewModel() => MangaDownloadsViewModel();

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(
        title: '下载管理',
        forceLocalChrome: true,
        leading: IconButton(
          icon: DrawIcon(StrokeIcons.arrowBack),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              const MangaHomeRoute().go(context);
            }
          },
        ),
      ),
      child: Obx(() {
        final entries = viewModel.entries;
        if (entries.isEmpty) {
          final s = AppSemantic.of(context);
          final m = AppTheme.metrics;
          return Center(
            child: Container(
              padding: EdgeInsets.all(m.kSpace32),
              margin: EdgeInsets.symmetric(horizontal: m.kSpace24),
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: m.radius16,
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
                      borderRadius: m.radius16,
                    ),
                    child: DrawIcon(StrokeIcons.download,
                      size: scaleW(36),
                      color: s.accent,
                    ),
                  ),
                  SizedBox(height: m.kSpace20),
                  Text(
                    '还没有下载任何漫画',
                    style: AppTextStyles.sectionTitle(context),
                  ),
                  SizedBox(height: m.kSpace8),
                  Text(
                    '在漫画详情页选择章节进行下载',
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
          );
        }

        final list = entries.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return ListView.builder(
          padding: EdgeInsets.all(appMetrics.kSpace16),
          itemCount: list.length,
          itemBuilder: (ctx, i) => _DownloadComicCard(
            entry: list[i],
            onDelete: () => _confirmDelete(context, list[i]),
            onOpenDetail: () => MangaComicDetailRoute(comicId: list[i].comicId).push(context),
            onRetryEps: (epsOrder) => viewModel.retryEps(list[i].comicId, epsOrder),
            onDeleteEps: (epsOrder) => viewModel.deleteEps(list[i].comicId, epsOrder),
            onReadEps: (epsOrder) => MangaReaderRoute(
              comicId: list[i].comicId,
              epsOrder: epsOrder,
              epsTitle: list[i].episodes[epsOrder]?.epsTitle ?? '第$epsOrder话',
            ).push(context),
          ),
        );
      }),
    );
  }

  Future<void> _confirmDelete(BuildContext context, MangaDownloadEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除下载'),
        content: Text('确定要删除《${entry.comicTitle}》的所有下载文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.deleteAll(entry.comicId);
    }
  }
}

/// 单个漫画下载卡片
class _DownloadComicCard extends StatefulWidget {
  const _DownloadComicCard({
    required this.entry,
    required this.onDelete,
    required this.onOpenDetail,
    required this.onRetryEps,
    required this.onDeleteEps,
    required this.onReadEps,
  });

  final MangaDownloadEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetail;
  final void Function(int epsOrder) onRetryEps;
  final void Function(int epsOrder) onDeleteEps;
  final void Function(int epsOrder) onReadEps;

  @override
  State<_DownloadComicCard> createState() => _DownloadComicCardState();
}

class _DownloadComicCardState extends State<_DownloadComicCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final entry = widget.entry;
    final metrics = appMetrics;

    return Card(
      margin: EdgeInsets.only(bottom: metrics.kSpace12),
      child: InkWell(
        borderRadius: metrics.radius12,
        onTap: widget.onOpenDetail,
        child: Padding(
          padding: EdgeInsets.all(metrics.kSpace12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  if (entry.thumb != null)
                    ClipRRect(
                      borderRadius: AppTheme.metrics.radius6,
                      child: SizedBox(
                        width: scaleW(56),
                        height: scaleW(75),
                        child: MangaImageView(
                          image: entry.thumb!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, _) =>
                              DrawIcon(StrokeIcons.brokenImage, size: AppTheme.metrics.iconSize24),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: scaleW(56),
                      height: scaleW(75),
                      decoration: BoxDecoration(
                        color: s.surfaceSunken,
                        borderRadius: metrics.radius6,
                      ),
                      child: DrawIcon(StrokeIcons.image, color: s.textDisabled),
                    ),
                  SizedBox(width: metrics.kSpace12),

                  // 标题 + 进度
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.comicTitle,
                          style: AppTextStyles.cardTitle(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: metrics.kSpace4),
                        Text(
                          '${entry.completedEps} / ${entry.totalEps} 章节完成',
                          style: AppTextStyles.caption(context),
                        ),
                        SizedBox(height: metrics.kSpace4),
                        LinearProgressIndicator(
                          value: entry.totalEps > 0 ? entry.completedEps / entry.totalEps : 0,
                          minHeight: metrics.kSpace6,
                          borderRadius: metrics.radius3,
                          backgroundColor: s.surfaceSunken,
                          color: s.accent,
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  Column(
                    children: [
                      IconButton(
                        icon: DrawIcon(
                          _expanded ? StrokeIcons.expandLess : StrokeIcons.expandMore,
                          size: AppTheme.metrics.iconSize20,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        tooltip: '查看章节',
                      ),
                      IconButton(
                        icon: DrawIcon(StrokeIcons.deleteOutline, size: AppTheme.metrics.iconSize20),
                        onPressed: widget.onDelete,
                        tooltip: '删除全部',
                      ),
                    ],
                  ),
                ],
              ),

              // 展开后的章节列表
              if (_expanded && entry.episodes.isNotEmpty) ...[
                SizedBox(height: metrics.kSpace8),
                Divider(height: metrics.kSpace1, color: s.hairline),
                SizedBox(height: metrics.kSpace8),
                Wrap(
                  spacing: metrics.kSpace6,
                  runSpacing: metrics.kSpace6,
                  children: entry.episodes.entries.map((e) {
                    final info = e.value;
                    return _EpsStatusChip(
                      info: info,
                      onRetry: () => widget.onRetryEps(info.epsOrder),
                      onDelete: () => widget.onDeleteEps(info.epsOrder),
                      onRead: () => widget.onReadEps(info.epsOrder),
                    );
                  }).toList()..sort((a, b) => a.info.epsOrder.compareTo(b.info.epsOrder)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单章节状态 chip
class _EpsStatusChip extends StatelessWidget {
  const _EpsStatusChip({
    required this.info,
    required this.onRetry,
    required this.onDelete,
    required this.onRead,
  });

  final MangaDownloadEpsInfo info;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    Color bgColor;
    Color fgColor;
    Widget? trailing;

    switch (info.status) {
      case MangaDownloadStatus.completed:
        bgColor = s.success.container;
        fgColor = s.success.color;
        trailing = DrawIcon(StrokeIcons.playCircleOutline,
          size: m.iconSize13,
          color: s.success.color,
        );
      case MangaDownloadStatus.downloading:
        bgColor = s.accentContainer;
        fgColor = s.accentText;
        trailing = SizedBox(
          width: m.kSpace10,
          height: m.kSpace10,
          child: CircularProgressIndicator(
            strokeWidth: AppTheme.metrics.strokeThin,
            value: info.progress > 0 ? info.progress : null,
          ),
        );
      case MangaDownloadStatus.error:
        bgColor = s.danger.container;
        fgColor = s.danger.color;
        trailing = GestureDetector(
          onTap: onRetry,
          child: DrawIcon(StrokeIcons.refresh,
            size: m.iconSize12,
            color: s.danger.color,
          ),
        );
      case MangaDownloadStatus.waiting:
        bgColor = s.surfaceSunken;
        fgColor = s.textSecondary;
        trailing = null;
      case MangaDownloadStatus.paused:
        bgColor = s.surfaceSunken;
        fgColor = s.textTertiary;
        trailing = null;
    }

    return GestureDetector(
      onTap: info.status == MangaDownloadStatus.completed ? onRead : null,
      onLongPress: onDelete,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.kSpace8,
          vertical: m.kSpace4,
        ),
        decoration: BoxDecoration(color: bgColor, borderRadius: m.radius6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '第${info.epsOrder}话',
              style: AppTextStyles.role(context, fontSize: m.fontSize11, color: fgColor),
            ),
            if (trailing != null) ...[SizedBox(width: m.kSpace4), trailing],
          ],
        ),
      ),
    );
  }
}
