import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/viewmodels/novel_library_viewmodel.dart';
import 'package:slime_works/pages/novel_library/components/novel_card.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 小说库页面
class NovelLibraryPage extends StatelessWidget {
  const NovelLibraryPage({super.key});

  /// 显示小说右键菜单
  void _showNovelContextMenu(BuildContext context, NovelMetadata novel, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(
          value: 'move_to_folder',
          child: Row(children: [Icon(Icons.folder, size: 18), SizedBox(width: 8), Text('移动到文件夹')]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'move_to_folder') {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('小说库'),
        actions: [
          IconButton(icon: const Icon(Icons.folder_open), tooltip: '扫描文件夹', onPressed: () => controller.scanFolder()),
          IconButton(icon: const Icon(Icons.add), tooltip: '添加单个文件', onPressed: () => controller.addSingleNovel()),
          Obx(
            () => controller.novels.isNotEmpty
                ? IconButton(icon: const Icon(Icons.delete_sweep), tooltip: '清空所有', onPressed: () => controller.confirmClearAllNovels())
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(isNarrow ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 扫描状态提示
            Obx(
              () => controller.isScanning.value
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '正在扫描小说文件...',
                            style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // 清空小说进度提示
            Obx(
              () => controller.isClearingNovels.value
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            '正在清空所有小说...',
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
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: controller.searchProgress.value,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '正在搜索小说内容... ${(controller.searchProgress.value * 100).toStringAsFixed(0)}%（${controller.searchCompleted.value} / ${controller.searchTotal.value}）',
                                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Obx(
                                () => controller.isCancelling.value
                                    ? const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    : TextButton.icon(
                                        onPressed: () => controller.cancelSearch(),
                                        icon: const Icon(Icons.cancel, size: 18),
                                        label: const Text('取消'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: controller.searchProgress.value,
                            backgroundColor: Colors.grey[300],
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // 小说数量统计
            Obx(
              () => controller.novels.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Text(
                            '共 ${controller.novels.length} 本小说',
                            style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
                          ),
                          if (controller.searchQuery.value.isNotEmpty)
                            Text(
                              ' （搜索到 ${controller.filteredNovels.length} 本）',
                              style: TextStyle(fontSize: 14, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500),
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
                      padding: const EdgeInsets.only(bottom: 16),
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
                                    hintText: controller.searchByContent.value ? '搜索小说内容...' : '搜索小说名字...',
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
                                        if (controller.searchByContent.value && controller.searchQuery.value.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.search),
                                            onPressed: () => controller.searchInContent(controller.searchQuery.value),
                                          ),
                                      ],
                                    ),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('搜索模式: ', style: TextStyle(fontSize: 14)),
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
                              const SizedBox(width: 8),
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

            // 小说列表
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
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('没有找到匹配的小说', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
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
                        onWillAccept: (data) => data != null && data.id != novel.id,
                        onAccept: (draggedNovel) {
                          // 重新排序：将拖拽的小说移动到目标位置
                          final draggedIndex = displayNovels.indexWhere((n) => n.id == draggedNovel.id);
                          if (draggedIndex != -1 && draggedIndex != index) {
                            controller.reorderNovels(draggedIndex, index);
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
                              context.push(Routes.novelReader, extra: novel);
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
    );
  }

  Widget _buildEmptyView(BuildContext context, bool isNarrow) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined, size: isNarrow ? 80 : 120, color: Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            '还没有添加小说',
            style: TextStyle(fontSize: isNarrow ? 18 : 20, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(
            '点击右上角按钮添加小说',
            style: TextStyle(fontSize: isNarrow ? 14 : 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 32),
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
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: isNarrow ? 12 : 16),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Get.find<NovelLibraryViewModel>().addSingleNovel(),
                icon: const Icon(Icons.add),
                label: const Text('添加单个文件'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: isNarrow ? 12 : 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
