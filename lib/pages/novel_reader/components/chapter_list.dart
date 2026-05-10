import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';

/// 章节列表组件
class ChapterList extends StatefulWidget {
  final NovelReaderViewModel controller;

  const ChapterList({super.key, required this.controller});

  @override
  State<ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<ChapterList> {
  late final ScrollController _scrollCtrl;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    // 列表显示后滚动到当前章节
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentChapter());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCurrentChapter() {
    final idx = widget.controller.currentChapterIndex.value;
    if (!_scrollCtrl.hasClients || idx < 0) return;
    const itemH = 56.0; // 每行大约高度
    // 将选中章节滚动到列表顶部（若已接近末尾则滚动到最大可滚动位置）
    final rawTarget = idx * itemH;
    final maxExtent = _scrollCtrl.position.maxScrollExtent;
    final target = rawTarget.clamp(0.0, maxExtent);
    _scrollCtrl.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.controller.chapters.isEmpty) {
        return Center(
          child: Text('暂无章节', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // 章节列表标题
            Container(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.list, size: AppTheme.metrics.iconSize20),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Text(
                    '章节列表',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${widget.controller.chapters.length} 章',
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),

            // 章节列表内容
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: widget.controller.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = widget.controller.chapters[index];

                  return Obx(() {
                    final isCurrent = widget.controller.currentChapterIndex.value == index;

                    return Material(
                      color: isCurrent
                          ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.controller.goToChapter(index),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16, vertical: AppTheme.metrics.kSpace12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // 章节序号
                              Container(
                                width: AppTheme.metrics.kSpace32,
                                height: AppTheme.metrics.kSpace32,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? Theme.of(context).primaryColor
                                      : Theme.of(context).colorScheme.outline,
                                  borderRadius: AppTheme.metrics.radius4,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: isCurrent ? Colors.white : Colors.black87,
                                      fontSize: AppTheme.metrics.fontSize11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: AppTheme.metrics.kSpace12),

                              // 章节标题（去除 HTML 标签）
                              Expanded(
                                child: Text(
                                  chapter.title.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppTheme.metrics.fontSize13,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context).textTheme.bodyLarge?.color,
                                  ),
                                ),
                              ),

                              // 当前章节标记
                              if (isCurrent)
                                Container(
                                  margin: EdgeInsets.only(left: AppTheme.metrics.kSpace8),
                                  child: Icon(
                                    Icons.play_arrow,
                                    size: AppTheme.metrics.iconSize20,
                                    color: Theme.of(context).primaryColor,
                                  ),
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
