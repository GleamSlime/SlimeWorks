// Manga 漫画卡片组件

import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

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
      duration: AppMotion.fast,
      reverseDuration: AppMotion.instant,
      lowerBound: AppMotion.scalePress,
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
    final s = AppSemantic.of(context);
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
            color: s.surface,
            borderRadius: metrics.radius12,
            boxShadow: s.elevation(Elevation.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: metrics.radius12.topLeft),
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
                              color: s.accent,
                              borderRadius: metrics.radius4,
                            ),
                            child: Text(
                              '完结',
                              style: AppTextStyles.role(
                                context,
                                fontSize: metrics.fontSize9,
                                color: s.accentOn,
                                weight: FontWeight.w600,
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
                              // 封面是任意内容的图片，压字的这层遮罩两端同色（70% 黑），
                              // 语义层的 scrim 正是这个值；上面的文字因此也必须固定浅色，
                              // 不能跟着明暗主题翻转。
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  s.scrim,
                                ],
                              ),
                            ),
                            child: Text(
                              widget.comic.categories.first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.role(
                                context,
                                fontSize: metrics.fontSize9,
                                color: AppBrand.inkOn,
                                weight: FontWeight.w500,
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
                  color: s.surface,
                  borderRadius: BorderRadius.vertical(bottom: metrics.radius12.bottomRight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.comic.title,
                      style: AppTextStyles.cardTitle(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.comic.author != null && widget.comic.author!.isNotEmpty) ...[
                      SizedBox(height: metrics.kSpace2),
                      Text(
                        widget.comic.author!,
                        style: AppTextStyles.caption(context),
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
    final s = AppSemantic.of(context);
    final metrics = AppTheme.metrics;
    return MangaImageView(
      image: image,
      fit: BoxFit.cover,
      loadingBuilder: (_) {
        return Container(
          color: s.surfaceSunken,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: AppTheme.metrics.strokeRegular,
              color: s.accent,
            ),
          ),
        );
      },
      errorBuilder: (_, e, _) => Container(
        color: s.surfaceSunken,
        child: Center(
          child: DrawIcon(StrokeIcons.brokenImage,
            size: metrics.iconSize32,
            color: s.textDisabled,
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
    final s = AppSemantic.of(context);
    final metrics = appMetrics;

    return InkWell(
      onTap: onTap,
      borderRadius: metrics.radius10,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: metrics.kSpace8, vertical: metrics.kSpace6),
        decoration: BoxDecoration(
          borderRadius: metrics.radius10,
          color: s.surface,
          boxShadow: s.elevation(Elevation.raised),
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
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.kSpace4,
                            vertical: metrics.kSpace1,
                          ),
                          decoration: BoxDecoration(
                            color: s.accent,
                            borderRadius: metrics.radius3,
                          ),
                          child: Text(
                            '完',
                            style: AppTextStyles.role(
                              context,
                              fontSize: metrics.fontSize9,
                              color: s.accentOn,
                              weight: FontWeight.w600,
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
                    style: AppTextStyles.rowTitle(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (comic.author != null)
                    Padding(
                      padding: EdgeInsets.only(top: metrics.kSpace2),
                      child: Text(
                        comic.author!,
                        style: AppTextStyles.caption(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  SizedBox(height: metrics.kSpace6),
                  Row(
                    children: [
                      Flexible(
                        child: _StatChip(
                          icon: StrokeIcons.photoLibrary,
                          label: '${comic.epsCount}章',
                        ),
                      ),
                      SizedBox(width: metrics.kSpace6),
                      Flexible(
                        child: _StatChip(
                          icon: StrokeIcons.favoriteBorder,
                          label: '${comic.likesCount}',
                        ),
                      ),
                      if (comic.finished) ...[
                        SizedBox(width: metrics.kSpace6),
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.kSpace5,
                              vertical: metrics.kSpace2,
                            ),
                            decoration: BoxDecoration(
                              color: s.accentContainer,
                              border: Border.all(
                                color: s.accentContainerBorder,
                                width: scaleW(1),
                              ),
                              borderRadius: metrics.radius3,
                            ),
                            child: Text(
                              '完结',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.role(
                                context,
                                fontSize: metrics.fontSize10,
                                color: s.accentText,
                                weight: FontWeight.w600,
                              ),
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
  const _StatChip({required this.icon, required this.label});

  final StrokeIcon icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DrawIcon(icon,
          size: AppTheme.metrics.iconSize12,
          color: s.textTertiary,
        ),
        SizedBox(width: AppTheme.metrics.kSpace2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.role(
              context,
              fontSize: AppTheme.metrics.fontSize10,
              color: s.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
