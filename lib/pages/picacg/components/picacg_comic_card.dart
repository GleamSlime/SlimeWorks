// PicACG 漫画卡片组件

import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 漫画网格卡片
class PicAcgComicCard extends StatefulWidget {
  const PicAcgComicCard({super.key, required this.comic, required this.onTap});

  final PicAcgComic comic;
  final VoidCallback onTap;

  @override
  State<PicAcgComicCard> createState() => _PicAcgComicCardState();
}

class _PicAcgComicCardState extends State<PicAcgComicCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.reverse();
  void _onTapUp(TapUpDetails _) {
    _controller.forward();
    widget.onTap();
  }

  void _onTapCancel() => _controller.forward();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(metrics.kSpace12),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// 封面图片
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(metrics.kSpace12)),
                  child: _ComicCoverImage(image: widget.comic.thumb),
                ),
              ),

              /// 标题
              Padding(
                padding: EdgeInsets.all(metrics.kSpace4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.comic.title,
                      style: theme.textTheme.labelSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.comic.author != null && widget.comic.author!.isNotEmpty)
                      Text(
                        widget.comic.author!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面图片组件（带加载/错误状态及淡入动效）
class _ComicCoverImage extends StatelessWidget {
  const _ComicCoverImage({required this.image});

  final PicAcgImage image;

  @override
  Widget build(BuildContext context) {
    return PicAcgImageView(
      image: image,
      fit: BoxFit.cover,
      loadingBuilder: (_) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, e, _) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined, size: 32)),
      ),
    );
  }
}

/// 漫画水平列表项（用于推荐区域）
class PicAcgComicListTile extends StatelessWidget {
  const PicAcgComicListTile({super.key, required this.comic, required this.onTap});

  final PicAcgComic comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(metrics.kSpace10),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: metrics.kSpace8, vertical: metrics.kSpace4),
        child: Row(
          children: [
            /// 封面缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(metrics.kSpace8),
              child: SizedBox(
                width: scaleW(48),
                height: scaleW(64),
                child: _ComicCoverImage(image: comic.thumb),
              ),
            ),
            SizedBox(width: metrics.kSpace8),

            /// 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    comic.title,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (comic.author != null)
                    Text(
                      comic.author!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  SizedBox(height: metrics.kSpace4),
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      SizedBox(width: scaleW(2)),
                      Text(
                        '${comic.epsCount}章',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      SizedBox(width: metrics.kSpace4),
                      Icon(
                        Icons.favorite_border,
                        size: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      SizedBox(width: scaleW(2)),
                      Text(
                        '${comic.likesCount}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (comic.finished) ...[
                        SizedBox(width: metrics.kSpace4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '完结',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
