import 'package:slime_works/core/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant),
                child: Stack(
                  children: [
                    // 封面图片或默认背景
                    if (coverPath != null) _buildCoverImage() else _buildDefaultCover(),

                    // 格式标签
                    Positioned(
                      top: AppTheme.metrics.kSpace8,
                      right: AppTheme.metrics.kSpace8,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: AppTheme.metrics.radius12,
                        ),
                        child: Text(
                          format,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppTheme.metrics.fontSize10,
                            fontWeight: FontWeight.bold,
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
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
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
                constraints: const BoxConstraints(maxHeight: 110),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 记录卡片信息区在不同布局下的尺寸，便于调试溢出问题
                    // 仅在 debug 模式打印，避免生产日志污染
                    assert(() {
                      // 打印宽高信息
                      // ignore: avoid_print
                      print(
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.metrics.fontSize13),
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
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.metrics.fontSize13),
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace6),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: AppTheme.metrics.iconSize12, color: Theme.of(context).hintColor),
                              SizedBox(width: AppTheme.metrics.kSpace4),
                              Expanded(
                                child: Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).hintColor),
                                ),
                              ),
                            ],
                          ),
                          if (progress > 0) ...[
                            SizedBox(height: AppTheme.metrics.kSpace4),
                            Text(
                              '阅读记录  已读 ${(progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: AppTheme.metrics.fontSize10,
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
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
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: AppTheme.metrics.iconSize20),
                      color: Colors.red[400],
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

  Widget _buildCoverImage() {
    try {
      final file = File(coverPath!);
      if (file.existsSync()) {
        return Positioned.fill(child: Image.file(file, fit: BoxFit.cover));
      }
    } catch (_) {}
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade400, Colors.purple.shade400, Colors.pink.shade400],
        ),
      ),
      child: Center(child: Icon(Icons.menu_book, size: AppTheme.metrics.iconSize64, color: Colors.white70)),
    );
  }

  void _showDeleteDialog() {
    final context = Get.context!;
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
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
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
