// Manga 漫画卡片组件

import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

/// 漫画网格卡片
class MangaComicCard extends StatefulWidget {
  const MangaComicCard({super.key, required this.comic, required this.onTap});

  final MangaComic comic;
  final VoidCallback onTap;

  @override
  State<MangaComicCard> createState() => _MangaComicCardState();
}

class _MangaComicCardState extends State<MangaComicCard> with SingleTickerProviderStateMixin {
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
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? DarkColors.background2 : LightColors.background1,
            borderRadius: metrics.radius12,
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: isDark ? 0.3 : 0.1),
                blurRadius: isDark ? 12 : 8,
                offset: Offset(0, isDark ? 4 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(metrics.kSpace12)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ComicCoverImage(image: widget.comic.thumb),
                      if (widget.comic.finished)
                        Positioned(
                          top: metrics.kSpace6,
                          right: metrics.kSpace6,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.kSpace6,
                              vertical: metrics.kSpace2,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(alpha: 0.8),
                                ],
                              ),
                              borderRadius: metrics.radius4,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              '完结',
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: metrics.fontSize9,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      if (widget.comic.categories.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.kSpace6,
                              vertical: metrics.kSpace3,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                            child: Text(
                              widget.comic.categories.first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: metrics.fontSize9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(metrics.kSpace6, metrics.kSpace6, metrics.kSpace6, metrics.kSpace8),
                decoration: BoxDecoration(
                  color: isDark ? DarkColors.background2 : LightColors.background1,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(metrics.kSpace12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.comic.title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.comic.author != null && widget.comic.author!.isNotEmpty) ...[
                      SizedBox(height: metrics.kSpace2),
                      Text(
                        widget.comic.author!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          fontSize: metrics.fontSize10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

  final MangaImage image;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MangaImageView(
      image: image,
      fit: BoxFit.cover,
      loadingBuilder: (_) {
        return Container(
          color: isDark ? DarkColors.background3 : LightColors.background2,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
        );
      },
      errorBuilder: (_, e, _) => Container(
        color: isDark ? DarkColors.background3 : LightColors.background2,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: AppTheme.metrics.iconSize32,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}

/// 漫画水平列表项（用于推荐区域）
class MangaComicListTile extends StatelessWidget {
  const MangaComicListTile({super.key, required this.comic, required this.onTap});

  final MangaComic comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: metrics.radius10,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: metrics.kSpace8, vertical: metrics.kSpace6),
        decoration: BoxDecoration(
          borderRadius: metrics.radius10,
          color: isDark ? DarkColors.background2 : LightColors.background1,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: metrics.radius8,
              child: SizedBox(
                width: scaleW(52),
                height: scaleW(70),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ComicCoverImage(image: comic.thumb),
                    if (comic.finished)
                      Positioned(
                        top: metrics.kSpace3,
                        right: metrics.kSpace3,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: metrics.radius3,
                          ),
                          child: Text(
                            '完',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: metrics.fontSize9,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: metrics.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    comic.title,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (comic.author != null)
                    Padding(
                      padding: EdgeInsets.only(top: metrics.kSpace2),
                      child: Text(
                        comic.author!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  SizedBox(height: metrics.kSpace6),
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.photo_library_outlined,
                        label: '${comic.epsCount}章',
                        theme: theme,
                      ),
                      SizedBox(width: metrics.kSpace6),
                      _StatChip(
                        icon: Icons.favorite_border,
                        label: '${comic.likesCount}',
                        theme: theme,
                      ),
                      if (comic.finished) ...[
                        SizedBox(width: metrics.kSpace6),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.kSpace5,
                            vertical: metrics.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: metrics.radius3,
                          ),
                          child: Text(
                            '完结',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: metrics.fontSize10,
                              fontWeight: FontWeight.w600,
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.theme});

  final IconData icon;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AppTheme.metrics.iconSize12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        SizedBox(width: scaleW(2)),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            fontSize: AppTheme.metrics.fontSize10,
          ),
        ),
      ],
    );
  }
}
