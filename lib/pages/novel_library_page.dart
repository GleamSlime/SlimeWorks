import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

/// 小说库页面
class NovelLibraryPage extends StatelessWidget {
  const NovelLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NovelLibraryViewModel());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 操作栏
          Row(
            children: [
              ElevatedButton.icon(onPressed: () => controller.scanFolder(), icon: const Icon(Icons.folder_open), label: const Text('扫描文件夹')),
              const SizedBox(width: 12),
              ElevatedButton.icon(onPressed: () => controller.addSingleNovel(), icon: const Icon(Icons.add), label: const Text('添加单个文件')),
              const SizedBox(width: 12),
              Obx(
                () => controller.isScanning.value
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('扫描中...'),
                          ],
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 小说列表
          Expanded(
            child: Obx(() {
              if (controller.novels.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('暂无小说', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('点击上方按钮添加小说', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
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

/// 小说卡片组件
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
                decoration: BoxDecoration(color: Colors.grey[200]),
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
                        return const Center(child: Icon(Icons.book, size: 48, color: Colors.white70));
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
                        child: const Center(child: Icon(Icons.book, size: 48, color: Colors.white70)),
                      ),

                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          format,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 信息区域
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
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
