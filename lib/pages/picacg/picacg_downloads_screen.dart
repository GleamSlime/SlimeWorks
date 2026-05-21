library;

/// PicACG 下载管理页面

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_download_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_downloads_viewmodel.dart';
import 'package:slime_works/core/theme/app_colors.dart';

class PicAcgDownloadsScreen extends BasePage<PicAcgDownloadsViewModel> {
  const PicAcgDownloadsScreen({super.key});

  @override
  State<PicAcgDownloadsScreen> createState() => _PicAcgDownloadsScreenState();
}

class _PicAcgDownloadsScreenState
    extends BasePageState<PicAcgDownloadsViewModel, PicAcgDownloadsScreen> {
  @override
  PicAcgDownloadsViewModel createViewModel() => PicAcgDownloadsViewModel();

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(
        title: '下载管理',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              const PicAcgHomeRoute().go(context);
            }
          },
        ),
      ),
      child: Obx(() {
        final entries = viewModel.entries;
        if (entries.isEmpty) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return Center(
            child: Container(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
              margin: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace24),
              decoration: BoxDecoration(
                color: isDark ? DarkColors.background2 : LightColors.background1,
                borderRadius: AppTheme.metrics.radius16,
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: isDark ? 0.2 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: scaleW(72),
                    height: scaleW(72),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: AppTheme.metrics.radius16,
                    ),
                    child: Icon(
                      Icons.download_outlined,
                      size: scaleW(36),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace20),
                  Text(
                    '还没有下载任何漫画',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace8),
                  Text(
                    '在漫画详情页选择章节进行下载',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
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
            onOpenDetail: () => PicAcgComicDetailRoute(comicId: list[i].comicId).push(context),
            onRetryEps: (epsOrder) => viewModel.retryEps(list[i].comicId, epsOrder),
            onDeleteEps: (epsOrder) => viewModel.deleteEps(list[i].comicId, epsOrder),
            onReadEps: (epsOrder) => PicAcgReaderRoute(
              comicId: list[i].comicId,
              epsOrder: epsOrder,
              epsTitle: list[i].episodes[epsOrder]?.epsTitle ?? '第$epsOrder话',
            ).push(context),
          ),
        );
      }),
    );
  }

  Future<void> _confirmDelete(BuildContext context, PicAcgDownloadEntry entry) async {
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

  final PicAcgDownloadEntry entry;
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
    final theme = Theme.of(context);
    final entry = widget.entry;
    final metrics = appMetrics;

    return Card(
      margin: EdgeInsets.only(bottom: metrics.kSpace12),
      child: InkWell(
        borderRadius: AppTheme.metrics.radius12,
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
                        child: PicAcgImageView(
                          image: entry.thumb!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, _) =>
                              Icon(Icons.broken_image_outlined, size: AppTheme.metrics.iconSize24),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: scaleW(56),
                      height: scaleW(75),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppTheme.metrics.radius6,
                      ),
                      child: const Icon(Icons.image_outlined),
                    ),
                  SizedBox(width: metrics.kSpace12),

                  // 标题 + 进度
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.comicTitle,
                          style: theme.textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: metrics.kSpace4),
                        Text(
                          '${entry.completedEps} / ${entry.totalEps} 章节完成',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        SizedBox(height: metrics.kSpace4),
                        LinearProgressIndicator(
                          value: entry.totalEps > 0 ? entry.completedEps / entry.totalEps : 0,
                          minHeight: AppTheme.metrics.kSpace6,
                          borderRadius: AppTheme.metrics.radius3,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  Column(
                    children: [
                      IconButton(
                        icon: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: AppTheme.metrics.iconSize20,
                        ),
                        onPressed: () => setState(() => _expanded = !_expanded),
                        tooltip: '查看章节',
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: AppTheme.metrics.iconSize20),
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
                const Divider(height: 1),
                SizedBox(height: metrics.kSpace8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
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

  final PicAcgDownloadEpsInfo info;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor;
    Color fgColor;
    Widget? trailing;

    switch (info.status) {
      case PicAcgDownloadStatus.completed:
        bgColor = Colors.green.withValues(alpha: 0.15);
        fgColor = Colors.green;
        trailing = Icon(
          Icons.play_circle_outline,
          size: AppTheme.metrics.iconSize13,
          color: (Theme.of(context).brightness == Brightness.dark)
              ? DarkColors.success
              : LightColors.success,
        );
      case PicAcgDownloadStatus.downloading:
        bgColor = theme.colorScheme.primaryContainer;
        fgColor = theme.colorScheme.onPrimaryContainer;
        trailing = SizedBox(
          width: AppTheme.metrics.kSpace10,
          height: AppTheme.metrics.kSpace10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            value: info.progress > 0 ? info.progress : null,
          ),
        );
      case PicAcgDownloadStatus.error:
        bgColor = theme.colorScheme.error.withValues(alpha: 0.15);
        fgColor = Colors.red;
        trailing = GestureDetector(
          onTap: onRetry,
          child: Icon(
            Icons.refresh,
            size: AppTheme.metrics.iconSize12,
            color: theme.colorScheme.error,
          ),
        );
      case PicAcgDownloadStatus.waiting:
        bgColor = theme.colorScheme.surfaceContainerHighest;
        fgColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
        trailing = null;
      case PicAcgDownloadStatus.paused:
        bgColor = theme.colorScheme.surfaceContainerHighest;
        fgColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
        trailing = null;
    }

    return GestureDetector(
      onTap: info.status == PicAcgDownloadStatus.completed ? onRead : null,
      onLongPress: onDelete,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace8,
          vertical: AppTheme.metrics.kSpace4,
        ),
        decoration: BoxDecoration(color: bgColor, borderRadius: AppTheme.metrics.radius6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '第${info.epsOrder}话',
              style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: fgColor),
            ),
            if (trailing != null) ...[SizedBox(width: AppTheme.metrics.kSpace4), trailing],
          ],
        ),
      ),
    );
  }
}
