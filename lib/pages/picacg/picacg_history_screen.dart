library;

/// PicACG 观看记录页面
///
/// 展示用户的漫画阅读历史，支持删除单条或清空全部
/// 点击记录可直接跳转到对应章节继续阅读

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_history_viewmodel.dart';

class PicAcgHistoryScreen extends BasePage<PicAcgHistoryViewModel> {
  const PicAcgHistoryScreen({super.key});

  @override
  State<PicAcgHistoryScreen> createState() => _PicAcgHistoryScreenState();
}

class _PicAcgHistoryScreenState extends BasePageState<PicAcgHistoryViewModel, PicAcgHistoryScreen> {
  @override
  PicAcgHistoryViewModel createViewModel() => PicAcgHistoryViewModel();

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(
        title: '观看记录',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
        actions: [
          Obx(
            () => viewModel.items.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: '清空记录',
                    onPressed: () => _confirmClearAll(context),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

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

    return Obx(() {
      if (viewModel.items.isEmpty) {
        final isDark = theme.brightness == Brightness.dark;
        return Center(
          child: Container(
            padding: EdgeInsets.all(appMetrics.kSpace32),
            margin: EdgeInsets.symmetric(horizontal: appMetrics.kSpace24),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.background2 : LightColors.background1,
              borderRadius: appMetrics.radius16,
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
                    borderRadius: appMetrics.radius16,
                  ),
                  child: Icon(
                    Icons.history_outlined,
                    size: scaleW(36),
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: appMetrics.kSpace20),
                Text(
                  '暂无观看记录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: appMetrics.kSpace8),
                Text(
                  '阅读漫画后会自动记录在这里',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return ListView.builder(
        padding: EdgeInsets.symmetric(vertical: appMetrics.kSpace8),
        itemCount: viewModel.items.length,
        itemBuilder: (ctx, i) {
          final item = viewModel.items[i];
          return _HistoryListItem(
            item: item,
            onTap: () => _openDetail(context, item),
            onDelete: () => viewModel.removeItem(item.comicId),
          );
        },
      );
    });
  }

  /// 点击条目打开漫画详情页
  void _openDetail(BuildContext context, PicAcgHistoryItem item) {
    PicAcgComicDetailRoute(comicId: item.comicId).push(context);
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空记录'),
        content: const Text('确定要清空所有观看记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('清空', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await viewModel.clearAll();
    }
  }
}

/// 单条观看记录列表项
class _HistoryListItem extends StatelessWidget {
  const _HistoryListItem({required this.item, required this.onTap, required this.onDelete});

  final PicAcgHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Dismissible(
      key: ValueKey(item.comicId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: metrics.kSpace20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16, vertical: metrics.kSpace8),
          child: Row(
            children: [
              /// 封面缩略图
              ClipRRect(
                borderRadius: AppTheme.metrics.radius6,
                child: item.thumbUrl.isNotEmpty
                    ? _ThumbImage(thumbUrl: item.thumbUrl)
                    : Container(
                        width: scaleW(52),
                        height: scaleW(72),
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: scaleW(24),
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
              ),
              SizedBox(width: metrics.kSpace12),

              /// 文字信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.comicTitle.isNotEmpty ? item.comicTitle : item.comicId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: metrics.kSpace4),
                    Text(
                      item.epsTitle.isNotEmpty ? item.epsTitle : '第${item.epsOrder}话',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    SizedBox(height: metrics.kSpace4),
                    Text(
                      _formatTime(item.tick),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        fontSize: AppTheme.metrics.fontSize11,
                      ),
                    ),
                  ],
                ),
              ),

              /// 删除按钮
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: scaleW(16),
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int tick) {
    if (tick == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(tick * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}月${dt.day}日';
  }
}

/// 从 URL 加载封面缩略图（使用 Image.network）
/// 从 thumbUrl（fileServer + /static/ + path 格式）解析出 PicAcgImage 并用
/// PicAcgImageView 渲染，保证走 Rust 带鉴权的图片请求通道。
class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.thumbUrl});

  final String thumbUrl;

  /// 将 `fullUrl` 拆解回 PicAcgImage；若格式无法识别则返回 null。
  static PicAcgImage? _parse(String url) {
    const sep = '/static/';
    final idx = url.indexOf(sep);
    if (idx < 0) return null;
    final path = url.substring(idx + sep.length);
    if (path.isEmpty) return null;
    return PicAcgImage(
      originalName: path.split('/').last,
      path: path,
      fileServer: url.substring(0, idx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _parse(thumbUrl);
    if (image == null) {
      return Container(
        width: scaleW(52),
        height: scaleW(72),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: scaleW(20),
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      );
    }
    return PicAcgImageView(
      image: image,
      width: scaleW(52),
      height: scaleW(72),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: scaleW(52),
        height: scaleW(72),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: scaleW(20),
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
