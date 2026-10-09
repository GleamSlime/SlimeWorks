import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
const Loggers _logger = Loggers(name: '书籍卡片');


/// 书籍卡片组件
class NovelCard extends StatelessWidget {
  final String title;
  final String author;
  final String? coverPath;
  final String format;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NovelCard({
    super.key,
    required this.title,
    required this.author,
    this.coverPath,
    required this.format,
    required this.progress,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: AppTheme.metrics.radius12),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.85,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: s.surfaceSunken),
                child: Stack(
                  children: [
                    // 封面图片或默认背景
                    if (coverPath != null) _buildCoverImage(context) else _buildDefaultCover(context),

                    // 格式标签
                    Positioned(
                      top: AppTheme.metrics.kSpace8,
                      right: AppTheme.metrics.kSpace8,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.metrics.kSpace8,
                          vertical: AppTheme.metrics.kSpace4,
                        ),
                        decoration: BoxDecoration(
                          // 压在封面图上的暗色标签底，语义就是模态遮罩那一档
                          color: s.scrim,
                          borderRadius: AppTheme.metrics.radius12,
                        ),
                        child: Text(
                          format,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize10,
                            // 封面上的固定浅字：走媒体 chrome 档，明暗两档都不反转
                            color: s.onMedia,
                            weight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // 阅读进度条
                    if (progress > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          height: AppTheme.metrics.kSpace4,
                          child: LinearProgressIndicator(
                            value: progress,
                            // 进度条压在封面 art 上：轨道用恒白水洗，alpha 沿用原值
                            backgroundColor: s.onMedia.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(s.accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 信息区域：使用 Flexible 并限制最大高度，避免父容器极小时发生溢出
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: scaleW(110)),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 记录卡片信息区在不同布局下的尺寸，便于调试溢出问题
                    // 仅在 debug 模式打印，避免生产日志污染
                    assert(() {
                      _logger.info(
                        '[NovelCard] info area constraints: w=${constraints.maxWidth}, h=${constraints.maxHeight}',
                      );
                      return true;
                    }());

                    // 当可用高度非常受限时，使用更紧凑的布局：仅显示一行标题并省略其他信息，避免溢出和内部滚动条
                    final cramped = constraints.maxHeight < 36;
                    if (cramped) {
                      return Padding(
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize13,
                            color: s.textPrimary,
                            weight: FontWeight.bold,
                          ),
                        ),
                      );
                    }

                    // 普通布局（在有足够高度时显示作者与阅读记录）
                    return Padding(
                      padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize13,
                              color: s.textPrimary,
                              weight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace6),
                          Row(
                            children: [
                              DrawIcon(StrokeIcons.personOutline,
                                size: AppTheme.metrics.iconSize12,
                                color: s.textTertiary,
                              ),
                              SizedBox(width: AppTheme.metrics.kSpace4),
                              Expanded(
                                child: Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption(context),
                                ),
                              ),
                            ],
                          ),
                          if (progress > 0) ...[
                            SizedBox(height: AppTheme.metrics.kSpace4),
                            Text(
                              '阅读记录  已读 ${(progress * 100).toInt()}%',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize10,
                                color: s.accent,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            // 底部操作栏
            SizedBox(
              height: AppTheme.metrics.kSpace40,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: s.hairline)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: DrawIcon(StrokeIcons.deleteOutline, size: AppTheme.metrics.iconSize20),
                      color: s.danger.color,
                      tooltip: '删除',
                      onPressed: () => _showDeleteDialog(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context) {
    try {
      final file = File(coverPath!);
      if (file.existsSync()) {
        return Positioned.fill(child: Image.file(file, fit: BoxFit.cover));
      }
    } catch (_) {}
    return _buildDefaultCover(context);
  }

  Widget _buildDefaultCover(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, Colors.purple.shade400, Colors.pink.shade400],
        ),
      ),
      child: Center(
        // 占位封面的渐变底恒不反转，图标走媒体 chrome 档
        child: DrawIcon(
          StrokeIcons.menuBook,
          size: AppTheme.metrics.iconSize64,
          color: AppSemantic.of(context).onMediaSecondary,
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    final context = Get.context!;
    final s = AppSemantic.of(context);
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            DrawIcon(StrokeIcons.warningAmber, color: s.warning.color),
            SizedBox(width: AppTheme.metrics.kSpace8),
            const Text('确认删除'),
          ],
        ),
        content: Text('确定要从库中删除《$title》吗？\n此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              Get.back();
              onDelete();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: s.danger.color,
              foregroundColor: s.accentOn,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
