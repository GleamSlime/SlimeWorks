import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/viewmodels/novel_reader_viewmodel.dart';

/// 阅读器工具栏组件
class ReaderToolbar extends StatelessWidget {
  final NovelReaderViewModel controller;

  const ReaderToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: isNarrow ? _buildNarrowToolbar(context) : _buildWideToolbar(context),
    );
  }

  /// 宽屏工具栏
  Widget _buildWideToolbar(BuildContext context) {
    return Row(
      children: [
        // 章节列表切换
        IconButton(icon: const Icon(Icons.menu_book), tooltip: '章节列表', onPressed: controller.toggleChapterList),
        const SizedBox(width: 8),

        // 上一章
        Obx(
          () => IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一章',
            onPressed: controller.hasPreviousChapter() ? controller.previousChapter : null,
          ),
        ),

        // 章节信息
        Obx(
          () => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(
              controller.chapters.isEmpty ? '0/0' : '${controller.currentChapterIndex.value + 1}/${controller.chapters.length}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
            ),
          ),
        ),

        // 下一章
        Obx(
          () => IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一章',
            onPressed: controller.hasNextChapter() ? controller.nextChapter : null,
          ),
        ),

        const Spacer(),

        // 搜索相关按钮
        Obx(() {
          if (controller.searchMatches.isNotEmpty) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 搜索匹配信息
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${controller.selectedSearchIndex.value + 1}/${controller.searchMatches.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.arrow_upward, size: 20), tooltip: '上一个结果', onPressed: controller.previousSearchResult),
                IconButton(icon: const Icon(Icons.list, size: 20), tooltip: '结果列表', onPressed: controller.openSearchResultsList),
                IconButton(icon: const Icon(Icons.arrow_downward, size: 20), tooltip: '下一个结果', onPressed: controller.nextSearchResult),
                IconButton(icon: const Icon(Icons.close, size: 20), tooltip: '清除搜索', onPressed: controller.clearSearch),
                const SizedBox(width: 8),
              ],
            );
          }
          return IconButton(icon: const Icon(Icons.search), tooltip: '搜索', onPressed: controller.showSearchDialog);
        }),

        // 字体大小调节
        IconButton(icon: const Icon(Icons.text_decrease), tooltip: '减小字体', onPressed: controller.decreaseFontSize),
        Obx(
          () => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(
              '${controller.fontSize.value.toInt()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.text_increase), tooltip: '增大字体', onPressed: controller.increaseFontSize),

        const SizedBox(width: 8),
        // 更多选项菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多选项',
          onSelected: (value) {
            if (value == 'delete') {
              controller.showDeleteDialog();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [Icon(Icons.delete, size: 20), SizedBox(width: 8), Text('删除书本')]),
            ),
          ],
        ),
      ],
    );
  }

  /// 窄屏工具栏
  Widget _buildNarrowToolbar(BuildContext context) {
    return Column(
      children: [
        // 第一行：导航控制
        Row(
          children: [
            IconButton(icon: const Icon(Icons.menu_book), tooltip: '章节列表', onPressed: controller.toggleChapterList, iconSize: 20),
            Obx(
              () => IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一章',
                onPressed: controller.hasPreviousChapter() ? controller.previousChapter : null,
                iconSize: 20,
              ),
            ),
            Obx(
              () => Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      controller.chapters.isEmpty ? '0/0' : '${controller.currentChapterIndex.value + 1}/${controller.chapters.length}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                    ),
                  ),
                ),
              ),
            ),
            Obx(
              () => IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一章',
                onPressed: controller.hasNextChapter() ? controller.nextChapter : null,
                iconSize: 20,
              ),
            ),
            IconButton(icon: const Icon(Icons.search), tooltip: '搜索', onPressed: controller.showSearchDialog, iconSize: 20),
          ],
        ),

        // 第二行：搜索结果控制（仅在有搜索结果时显示）
        Obx(() {
          if (controller.searchMatches.isNotEmpty) {
            return Container(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '${controller.selectedSearchIndex.value + 1}/${controller.searchMatches.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: controller.previousSearchResult,
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.list),
                    onPressed: controller.openSearchResultsList,
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: controller.nextSearchResult,
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: controller.clearSearch,
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }),
      ],
    );
  }
}
