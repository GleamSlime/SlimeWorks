import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';

/// 章节列表组件
class ChapterList extends StatelessWidget {
  final NovelReaderViewModel controller;

  const ChapterList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.chapters.isEmpty) {
        return const Center(
          child: Text('暂无章节', style: TextStyle(color: Colors.grey)),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(2, 0))],
        ),
        child: Column(
          children: [
            // 章节列表标题
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.list, size: 20),
                  const SizedBox(width: 8),
                  Text('章节列表', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('共 ${controller.chapters.length} 章', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),

            // 章节列表内容
            Expanded(
              child: ListView.builder(
                itemCount: controller.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = controller.chapters[index];

                  return Obx(() {
                    final isCurrent = controller.currentChapterIndex.value == index;

                    return Material(
                      color: isCurrent ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
                      child: InkWell(
                        onTap: () => controller.goToChapter(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                          ),
                          child: Row(
                            children: [
                              // 章节序号
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isCurrent ? Theme.of(context).primaryColor : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(color: isCurrent ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // 章节标题
                              Expanded(
                                child: Text(
                                  chapter.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent ? Theme.of(context).primaryColor : Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),

                              // 当前章节标记
                              if (isCurrent)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.play_arrow, size: 20, color: Theme.of(context).primaryColor),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}
