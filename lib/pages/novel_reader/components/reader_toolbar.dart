import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/pages/novel_reader/components/translation_config_panel.dart';

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isNarrow ? _buildNarrowToolbar(context) : _buildWideToolbar(context),
    );
  }

  /// 宽屏工具栏
  Widget _buildWideToolbar(BuildContext context) {
    return Row(
      children: [
        // 章节列表切换
        IconButton(
          icon: const Icon(Icons.menu_book),
          tooltip: '章节列表',
          onPressed: controller.toggleChapterList,
        ),
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
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              controller.chapters.isEmpty
                  ? '0/0'
                  : '${controller.currentChapterIndex.value + 1}/${controller.chapters.length}',
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
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${controller.selectedSearchIndex.value + 1}/${controller.searchMatches.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  tooltip: '上一个结果',
                  onPressed: controller.previousSearchResult,
                ),
                IconButton(
                  icon: const Icon(Icons.list, size: 20),
                  tooltip: '结果列表',
                  onPressed: controller.openSearchResultsList,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 20),
                  tooltip: '下一个结果',
                  onPressed: controller.nextSearchResult,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '清除搜索',
                  onPressed: controller.clearSearch,
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 20),
                  tooltip: '在文件管理器中显示',
                  onPressed: controller.revealFileInFolder,
                ),
                const SizedBox(width: 8),
              ],
            );
          }

          // 默认：显示搜索按钮与“在文件管理器中显示”按钮
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 翻译按钮
              Obx(() {
                final isEnabled = controller.isAutoTranslateEnabled.value;
                final isTranslating = controller.isTranslating.value;
                final progress = controller.translationProgress.value;
                final total = controller.translationTotal.value;

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isEnabled ? Icons.translate : Icons.translate_outlined,
                        color: isEnabled ? Colors.blue : null,
                      ),
                      tooltip: isEnabled ? '关闭自动翻译' : '开启翻译',
                      onPressed: () => _handleTranslateButton(context),
                    ),
                    if (isTranslating && total > 0) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$progress/$total',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ],
                );
              }),
              // 重试失败翻译按钮（仅在有失败翻译时显示）
              Obx(() {
                if (controller.failedTranslations.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: Badge(
                    label: Text('${controller.failedTranslations.length}'),
                    child: const Icon(Icons.refresh, color: Colors.orange),
                  ),
                  tooltip: '重试失败的翻译 (${controller.failedTranslations.length}个)',
                  onPressed: controller.retryAllFailedTranslations,
                );
              }),
              // Debug: 复制原始HTML按钮（仅在Debug模式显示）
              if (kDebugMode)
                IconButton(
                  icon: const Icon(Icons.code, color: Colors.orange),
                  tooltip: 'Debug: 复制原始HTML',
                  onPressed: controller.copyOriginalHtmlToClipboard,
                ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索',
                onPressed: controller.showSearchDialog,
              ),
              IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: '在文件管理器中显示',
                onPressed: controller.revealFileInFolder,
              ),
            ],
          );
        }),

        // 字体大小调节
        IconButton(
          icon: const Icon(Icons.text_decrease),
          tooltip: '减小字体',
          onPressed: controller.decreaseFontSize,
        ),
        Obx(
          () => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${controller.fontSize.value.toInt()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.text_increase),
          tooltip: '增大字体',
          onPressed: controller.increaseFontSize,
        ),

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
              child: Row(
                children: [Icon(Icons.delete, size: 20), SizedBox(width: 8), Text('删除书本')],
              ),
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
            IconButton(
              icon: const Icon(Icons.menu_book),
              tooltip: '章节列表',
              onPressed: controller.toggleChapterList,
              iconSize: 20,
            ),
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
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      controller.chapters.isEmpty
                          ? '0/0'
                          : '${controller.currentChapterIndex.value + 1}/${controller.chapters.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
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
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: controller.showSearchDialog,
              iconSize: 20,
            ),
            // 翻译按钮
            Obx(() {
              final isEnabled = controller.isAutoTranslateEnabled.value;
              final isTranslating = controller.isTranslating.value;
              final progress = controller.translationProgress.value;
              final total = controller.translationTotal.value;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isEnabled ? Icons.translate : Icons.translate_outlined,
                      color: isEnabled ? Colors.blue : null,
                    ),
                    tooltip: isEnabled ? '关闭自动翻译' : '开启翻译',
                    onPressed: () => _handleTranslateButton(context),
                    iconSize: 20,
                  ),
                  if (isTranslating && total > 0) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$progress/$total',
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ],
                ],
              );
            }),
            // 重试失败翻译按钮（仅在有失败翻译时显示）
            Obx(() {
              if (controller.failedTranslations.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: Badge(
                  label: Text('${controller.failedTranslations.length}'),
                  child: const Icon(Icons.refresh, color: Colors.orange),
                ),
                tooltip: '重试失败的翻译',
                onPressed: controller.retryAllFailedTranslations,
                iconSize: 20,
              );
            }),
            // Debug: 复制原始HTML按钮（仅在Debug模式显示）
            if (kDebugMode)
              IconButton(
                icon: const Icon(Icons.code, color: Colors.orange),
                tooltip: 'Debug: 复制原始HTML',
                onPressed: controller.copyOriginalHtmlToClipboard,
                iconSize: 20,
              ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '在文件管理器中显示',
              onPressed: controller.revealFileInFolder,
              iconSize: 20,
            ),
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
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${controller.selectedSearchIndex.value + 1}/${controller.searchMatches.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
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

  /// 处理翻译按钮点击
  void _handleTranslateButton(BuildContext context) async {
    // 如果已开启自动翻译，点击后关闭
    if (controller.isAutoTranslateEnabled.value) {
      controller.toggleAutoTranslate();
      return;
    }

    // 如果未开启，点击后打开配置面板
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(child: TranslationConfigPanel(viewModel: controller)),
    );

    // 如果用户确认了配置，开启自动翻译
    if (result == true && !controller.isAutoTranslateEnabled.value) {
      controller.toggleAutoTranslate();
    }
  }
}
