import 'package:slime_works/core/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/core/theme/app_colors.dart';

/// 书籍库页面
class NovelLibraryPage extends StatelessWidget {
  const NovelLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NovelLibraryViewModel());

    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 操作栏
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => controller.scanFolder(),
                icon: const Icon(Icons.folder_open),
                label: const Text('扫描文件夹'),
              ),
              SizedBox(width: AppTheme.metrics.kSpace12),
              ElevatedButton.icon(
                onPressed: () => controller.addSingleNovel(),
                icon: const Icon(Icons.add),
                label: const Text('添加单个文件'),
              ),
              SizedBox(width: AppTheme.metrics.kSpace12),
              Obx(
                () => controller.isScanning.value
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: AppTheme.metrics.kSpace16,
                              height: AppTheme.metrics.kSpace16,
                              child: const CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace8),
                            const Text('扫描中...'),
                          ],
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
          SizedBox(height: AppTheme.metrics.kSpace24),

          // 书籍列表
          Expanded(
            child: Obx(() {
              if (controller.novels.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_outlined, size: AppTheme.metrics.iconSize64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(height: AppTheme.metrics.kSpace16),
                      Text('暂无书籍', style: TextStyle(fontSize: AppTheme.metrics.fontSize15, color: Theme.of(context).hintColor)),
                      SizedBox(height: AppTheme.metrics.kSpace8),
                      Text('点击上方按钮添加书籍', style: TextStyle(fontSize: AppTheme.metrics.fontSize13, color: Theme.of(context).hintColor)),
                    ],
                  ),
                );
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: controller.novels.length,
                itemBuilder: (context, index) {
                  final novel = controller.novels[index];
                  return _NovelCard(
                    title: novel.title,
                    author: novel.author ?? '未知作者',
                    coverPath: novel.coverPath,
                    format: novel.format.toString().split('.').last.toUpperCase(),
                    progress: novel.progress,
                    onTap: () => NovelReaderRoute($extra: novel).go(context),
                    onDelete: () => controller.deleteNovel(novel.id),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// 书籍卡片组件
class _NovelCard extends StatelessWidget {
  final String title;
  final String author;
  final String? coverPath;
  final String format;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NovelCard({
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant),
                child: Stack(
                  children: [
                    // 当有封面路径且文件存在时显示图片，否则显示默认图标和渐变背景
                    if (coverPath != null)
                      (() {
                        try {
                          final f = File(coverPath!);
                          if (f.existsSync()) {
                            return Positioned.fill(child: Image.file(f, fit: BoxFit.cover));
                          }
                        } catch (_) {}
                        return Center(
                          child: Icon(Icons.book, size: AppTheme.metrics.iconSize48, color: Colors.white70),
                        );
                      })()
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.blue.shade300, Colors.purple.shade300],
                          ),
                        ),
                        child: Center(
                          child: Icon(Icons.book, size: AppTheme.metrics.iconSize48, color: Colors.white70),
                        ),
                      ),

                    Positioned(
                      top: AppTheme.metrics.kSpace8,
                      right: AppTheme.metrics.kSpace8,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace6, vertical: AppTheme.metrics.kSpace2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: AppTheme.metrics.radius4,
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

                    if (progress > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(((Theme.of(context).brightness == Brightness.dark) ? DarkColors.success : LightColors.success).withValues(alpha: 0.7)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 信息区域
            Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.metrics.fontSize13),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace4),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.delete_outline, size: AppTheme.metrics.iconSize18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Get.dialog(
                      AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要从库中删除《$title》吗？'),
                        actions: [
                          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
                          TextButton(
                            onPressed: () {
                              Get.back();
                              onDelete();
                            },
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
