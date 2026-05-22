import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';

import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/pages/novel_library/components/novel_card.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 书籍库页面
class NovelLibraryPage extends StatelessWidget {
  const NovelLibraryPage({super.key});

  /// 显示书籍右键菜单
  void _showNovelContextMenu(BuildContext context, NovelMetadata novel, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'move_to_folder',
          child: Row(
            children: [
              Icon(Icons.folder, size: AppTheme.metrics.iconSize18),
              SizedBox(width: AppTheme.metrics.kSpace8),
              const Text('移动到文件夹'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete,
                size: AppTheme.metrics.iconSize18,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'move_to_folder') {
        // ignore: use_build_context_synchronously
        _showMoveToFolderDialog(context, novel);
      } else if (value == 'delete') {
        Get.find<NovelLibraryViewModel>().deleteNovel(novel.id);
      }
    });
  }

  /// 显示移动到文件夹对话框
  void _showMoveToFolderDialog(BuildContext context, NovelMetadata novel) {
    Get.dialog(
      AlertDialog(
        title: const Text('移动到文件夹'),
        content: const Text('文件夹功能开发中...'),
        actions: [TextButton(onPressed: () => Get.back(), child: const Text('确定'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NovelLibraryViewModel());
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '书籍库',
        forceLocalChrome: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '扫描文件夹',
            onPressed: () => controller.scanFolder(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加单个文件',
            onPressed: () => controller.addSingleNovel(),
          ),
          Obx(
            () => controller.novels.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    tooltip: '清空所有',
                    onPressed: () => Get.dialog(
                      AlertDialog(
                        title: const Text('清空所有书籍'),
                        content: const Text('确定要清空所有书籍吗？此操作不可撤销。'),
                        actions: [
                          TextButton(onPressed: Get.back, child: const Text('取消')),
                          FilledButton(
                            onPressed: () {
                              Get.back();
                              controller.clearAllNovelsAction();
                            },
                            child: const Text('确认'),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(isNarrow ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 扫描状态提示
              Obx(
                () => controller.isScanning.value
                    ? Container(
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                        margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          borderRadius: AppTheme.metrics.radius8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: AppTheme.metrics.kSpace20,
                              height: AppTheme.metrics.kSpace20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace12),
                            Text(
                              '正在扫描书籍文件...',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 清空书籍进度提示
              Obx(
                () => controller.isClearingNovels.value
                    ? Container(
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                        margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: AppTheme.metrics.radius8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: AppTheme.metrics.kSpace20,
                              height: AppTheme.metrics.kSpace20,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace12),
                            const Text(
                              '正在清空所有书籍...',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 搜索进度条
              Obx(
                () => controller.isSearching.value
                    ? Container(
                        padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                        margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: AppTheme.metrics.radius8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: AppTheme.metrics.kSpace20,
                                  height: AppTheme.metrics.kSpace20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: controller.searchProgress.value,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                                SizedBox(width: AppTheme.metrics.kSpace12),
                                Expanded(
                                  child: Text(
                                    '正在搜索书籍内容... ${(controller.searchProgress.value * 100).toStringAsFixed(0)}%（${controller.searchCompleted.value} / ${controller.searchTotal.value}）',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Obx(
                                  () => controller.isCancelling.value
                                      ? Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: AppTheme.metrics.kSpace12,
                                            vertical: AppTheme.metrics.kSpace8,
                                          ),
                                          child: SizedBox(
                                            width: AppTheme.metrics.kSpace16,
                                            height: AppTheme.metrics.kSpace16,
                                            child: const CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        )
                                      : TextButton.icon(
                                          onPressed: () => controller.cancelSearch(),
                                          icon: Icon(
                                            Icons.cancel,
                                            size: AppTheme.metrics.iconSize18,
                                          ),
                                          label: const Text('取消'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Theme.of(context).colorScheme.error,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: AppTheme.metrics.kSpace12,
                                              vertical: AppTheme.metrics.kSpace8,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            SizedBox(height: AppTheme.metrics.kSpace8),
                            LinearProgressIndicator(
                              value: controller.searchProgress.value,
                              backgroundColor: Theme.of(context).colorScheme.outline,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 书籍数量统计
              Obx(
                () => controller.novels.isNotEmpty
                    ? Padding(
                        padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace16),
                        child: Row(
                          children: [
                            Text(
                              '共 ${controller.novels.length} 本书籍',
                              style: TextStyle(
                                fontSize: AppTheme.metrics.fontSize13,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (controller.searchQuery.value.isNotEmpty)
                              Text(
                                ' （搜索到 ${controller.filteredNovels.length} 本）',
                                style: TextStyle(
                                  fontSize: AppTheme.metrics.fontSize13,
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 搜索栏
              Obx(
                () => controller.novels.isNotEmpty
                    ? Padding(
                        padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    onChanged: (value) {
                                      controller.searchQuery.value = value;
                                      // 按名字搜索时实时更新
                                      if (!controller.searchByContent.value) {
                                        // 无需额外操作，filteredNovels 会自动更新
                                      }
                                    },
                                    onSubmitted: (value) {
                                      if (controller.searchByContent.value && value.isNotEmpty) {
                                        controller.searchInContent(value);
                                      }
                                    },
                                    decoration: InputDecoration(
                                      hintText: controller.searchByContent.value
                                          ? '搜索书籍内容...'
                                          : '搜索书籍名字...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (controller.searchQuery.value.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                controller.searchQuery.value = '';
                                                controller.contentSearchResults.clear();
                                              },
                                            ),
                                          if (controller.searchByContent.value &&
                                              controller.searchQuery.value.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.search),
                                              onPressed: () => controller.searchInContent(
                                                controller.searchQuery.value,
                                              ),
                                            ),
                                        ],
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: AppTheme.metrics.radius8,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: AppTheme.metrics.kSpace16,
                                        vertical: AppTheme.metrics.kSpace12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: AppTheme.metrics.kSpace8),
                            Row(
                              children: [
                                Text(
                                  '搜索模式: ',
                                  style: TextStyle(fontSize: AppTheme.metrics.fontSize13),
                                ),
                                ChoiceChip(
                                  label: const Text('按名字'),
                                  selected: !controller.searchByContent.value,
                                  onSelected: (selected) {
                                    if (selected) {
                                      controller.searchByContent.value = false;
                                      controller.contentSearchResults.clear();
                                    }
                                  },
                                ),
                                SizedBox(width: AppTheme.metrics.kSpace8),
                                ChoiceChip(
                                  label: const Text('按内容'),
                                  selected: controller.searchByContent.value,
                                  onSelected: (selected) {
                                    if (selected) {
                                      controller.searchByContent.value = true;
                                      if (controller.searchQuery.value.isNotEmpty) {
                                        controller.searchInContent(controller.searchQuery.value);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 书籍列表
              Expanded(
                child: Obx(() {
                  final displayNovels = controller.filteredNovels;

                  if (controller.novels.isEmpty) {
                    return _buildEmptyView(context, isNarrow);
                  }

                  if (displayNovels.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: AppTheme.metrics.iconSize64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          SizedBox(height: AppTheme.metrics.kSpace16),
                          Text(
                            '没有找到匹配的书籍',
                            style: TextStyle(
                              fontSize: AppTheme.metrics.fontSize15,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: isNarrow ? 150 : 200,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: isNarrow ? 12 : 16,
                      mainAxisSpacing: isNarrow ? 12 : 16,
                    ),
                    itemCount: displayNovels.length,
                    itemBuilder: (context, index) {
                      final novel = displayNovels[index];
                      return Draggable<NovelMetadata>(
                        data: novel,
                        feedback: Material(
                          elevation: 8,
                          child: Opacity(
                            opacity: 0.8,
                            child: SizedBox(
                              width: isNarrow ? 150 : 200,
                              child: NovelCard(
                                title: novel.title,
                                author: novel.author ?? '未知作者',
                                coverPath: novel.coverPath,
                                format: novel.format.toString().split('.').last.toUpperCase(),
                                progress: novel.progress,
                                onTap: () {},
                                onDelete: () {},
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: NovelCard(
                            title: novel.title,
                            author: novel.author ?? '未知作者',
                            coverPath: novel.coverPath,
                            format: novel.format.toString().split('.').last.toUpperCase(),
                            progress: novel.progress,
                            onTap: () {},
                            onDelete: () {},
                          ),
                        ),
                        child: DragTarget<NovelMetadata>(
                          onWillAcceptWithDetails: (details) => details.data.id != novel.id,
                          onAcceptWithDetails: (details) {
                            // 重新排序：将拖拽的书籍移动到目标位置
                            final draggedNovel = details.data;
                            final draggedIndex = displayNovels.indexWhere(
                              (n) => n.id == draggedNovel.id,
                            );
                            if (draggedIndex != -1 && draggedIndex != index) {
                              controller.reorderItems(draggedIndex, index);
                            }
                          },
                          builder: (context, candidateData, rejectedData) {
                            return GestureDetector(
                              onSecondaryTapDown: (details) {
                                _showNovelContextMenu(context, novel, details.globalPosition);
                              },
                              child: NovelCard(
                                title: novel.title,
                                author: novel.author ?? '未知作者',
                                coverPath: novel.coverPath,
                                format: novel.format.toString().split('.').last.toUpperCase(),
                                progress: novel.progress,
                                onTap: () async {
                                  NovelReaderRoute($extra: novel).go(context);
                                  controller.loadNovels();
                                },
                                onDelete: () => controller.deleteNovel(novel.id),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context, bool isNarrow) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: isNarrow ? 80 : 120,
            color: Theme.of(context).colorScheme.outline,
          ),
          SizedBox(height: AppTheme.metrics.kSpace24),
          Text(
            '还没有添加书籍',
            style: TextStyle(
              fontSize: isNarrow ? 18 : 20,
              color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace12),
          Text(
            '点击右上角按钮添加书籍',
            style: TextStyle(fontSize: isNarrow ? 14 : 16, color: Theme.of(context).hintColor),
          ),
          SizedBox(height: AppTheme.metrics.kSpace32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => Get.find<NovelLibraryViewModel>().scanFolder(),
                icon: const Icon(Icons.folder_open),
                label: const Text('扫描文件夹'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 16 : 24,
                    vertical: isNarrow ? 12 : 16,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Get.find<NovelLibraryViewModel>().addSingleNovel(),
                icon: const Icon(Icons.add),
                label: const Text('添加单个文件'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 16 : 24,
                    vertical: isNarrow ? 12 : 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
