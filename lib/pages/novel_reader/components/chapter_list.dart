import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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
    final itemH = AppTheme.metrics.kSpace56; // 每行大约高度
    // 将选中章节滚动到列表顶部（若已接近末尾则滚动到最大可滚动位置）
    final rawTarget = idx * itemH;
    final maxExtent = _scrollCtrl.position.maxScrollExtent;
    final target = rawTarget.clamp(0.0, maxExtent);
    _scrollCtrl.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      if (widget.controller.chapters.isEmpty) {
        return Center(
          child: Text(
            '暂无章节',
            style: AppTextStyles.role(context, fontSize: m.fontSize13, color: s.textTertiary),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          boxShadow: [
            // 侧栏向内容侧投的一道影，方向固定，不走 elevation 档位（那只有垂直偏移）
            BoxShadow(
              color: s.shadowKey,
              blurRadius: m.kSpace8,
              offset: Offset(m.kSpace2, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // 章节列表标题
            Container(
              padding: EdgeInsets.all(m.kSpace16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: s.border))),
              child: Row(
                children: [
                  DrawIcon(StrokeIcons.list, size: m.iconSize20),
                  SizedBox(width: m.kSpace8),
                  Text('章节列表', style: AppTextStyles.sectionTitle(context)),
                  const Spacer(),
                  Text(
                    '共 ${widget.controller.chapters.length} 章',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize11,
                      color: s.textTertiary,
                    ),
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
                      color: isCurrent ? s.accentContainer : Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.controller.goToChapter(index),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: s.hairline)),
                          ),
                          child: Row(
                            children: [
                              // 章节序号
                              Container(
                                width: m.kSpace32,
                                height: m.kSpace32,
                                decoration: BoxDecoration(
                                  color: isCurrent ? s.accent : s.surfaceSunken,
                                  borderRadius: m.radius4,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: AppTextStyles.role(
                                      context,
                                      fontSize: m.fontSize11,
                                      color: isCurrent ? s.accentOn : s.textPrimary,
                                      weight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: m.kSpace12),

                              // 章节标题（去除 HTML 标签）
                              Expanded(
                                child: Text(
                                  chapter.title.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: m.fontSize13,
                                    color: isCurrent ? s.accent : s.textPrimary,
                                    weight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),

                              // 当前章节标记
                              if (isCurrent)
                                Container(
                                  margin: EdgeInsets.only(left: m.kSpace8),
                                  child: DrawIcon(StrokeIcons.playArrow,
                                    size: m.iconSize20,
                                    color: s.accent,
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
