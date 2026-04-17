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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                decoration: BoxDecoration(color: Colors.grey[200]),
                child: Stack(
                  children: [
                    // 封面图片或默认背景
                    if (coverPath != null) _buildCoverImage() else _buildDefaultCover(),

                    // 格式标签
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          format,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
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
                          height: 4,
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
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      );
                    }

                    // 普通布局（在有足够高度时显示作者与阅读记录）
                    return Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 12, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ),
                            ],
                          ),
                          if (progress > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '阅读记录  已读 ${(progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 10,
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
              height: 40,
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
                      icon: const Icon(Icons.delete_outline, size: 20),
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
      child: const Center(child: Icon(Icons.menu_book, size: 64, color: Colors.white70)),
    );
  }

  void _showDeleteDialog() {
    Get.dialog(
      AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('确认删除'),
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
