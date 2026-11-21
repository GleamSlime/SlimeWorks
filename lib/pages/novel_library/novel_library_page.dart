import 'dart:async';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/common/error_banner.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';

import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/widgets/glass_menu.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/pages/novel_library/components/novel_card.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 书籍库页面
///
/// ★ 必须是 StatefulWidget：`NovelLibraryViewModel.onInitAsync()` 只在
/// `BasePage.onPageInit` 里被调用，而本页不是 BasePage 子类。之前它是
/// StatelessWidget，**从不触发初始化**——于是 `refreshRemoteNovels()` 一次都
/// 没跑过，远程模式下书库永远是空的（本机模式靠 `loadNovels` 直接读 FFI 看
/// 不出异常，只有切到远程节点才暴露）。这里照 game_hub_screen 等页面的做法，
/// 在 initState 里显式触发一次。
class NovelLibraryPage extends StatefulWidget {
  const NovelLibraryPage({super.key});

  @override
  State<NovelLibraryPage> createState() => _NovelLibraryPageState();
}

class _NovelLibraryPageState extends State<NovelLibraryPage> {
  late final NovelLibraryViewModel _controller;

  @override
  void initState() {
    super.initState();
    // Get.put 在 build 里也行，但放这里能保证 initState 与 controller 同一实例
    _controller = Get.put(NovelLibraryViewModel());
    // 触发异步初始化（本机读 FFI、远程拉节点）。失败不该白屏，
    // 由 VM 内部的 showSnack 报出来。
    // 必须 await（用 unawaited 显式表达"故意不等"，并且要把异常捞出来）——
    // onInitAsync 里是真实 IO（本机 FFI / 远程 HTTP），直接丢弃 Future
    // 会让失败静默消失，也会让初始化看起来"从没发生"。
    unawaited(
      _controller.onInitAsync().catchError((Object e) {
        debugPrint('书籍库初始化失败: $e');
      }),
    );
    // 兜底：`onInitAsync` 内部有 `if (isInitialized) return;` 的提前返回，
    // 而 VM 是 permanent 单例、可能被别处先初始化过一次（那时节点还没选）。
    // 此时页面进来不会再走刷新，界面就停在上一次的空结果上。
    // `refreshRemoteNovels()` 本身幂等且带代际号防覆盖，这里显式再拉一轮，
    // 保证「选了远程节点进入书库」一定能拿到数据。
    unawaited(
      _controller.refreshRemoteNovels().catchError((Object e) {
        debugPrint('书籍库远程刷新失败: $e');
      }),
    );
  }

  /// 显示书籍右键菜单
  void _showNovelContextMenu(BuildContext context, NovelMetadata novel, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        GlassMenuItem<String>(
          value: 'move_to_folder',
          label: '移动到文件夹',
          icon: StrokeIcons.folderOpen,
        ),
        GlassMenuItem<String>(
          value: 'delete',
          label: '删除',
          icon: StrokeIcons.deleteOutline,
          destructive: true,
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final controller = _controller;
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '书籍库',
        forceLocalChrome: true,
        leading: IconButton(
          icon: DrawIcon(StrokeIcons.arrowBack),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: DrawIcon(StrokeIcons.folderOpen),
            tooltip: '扫描文件夹',
            onPressed: () => controller.scanFolder(),
          ),
          IconButton(
            icon: DrawIcon(StrokeIcons.add),
            tooltip: '添加单个文件',
            onPressed: () => controller.addSingleNovel(),
          ),
          Obx(
            () => controller.novels.isNotEmpty
                ? IconButton(
                    icon: DrawIcon(StrokeIcons.deleteSweep),
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
          padding: EdgeInsets.all(isNarrow ? m.kSpace12 : m.kSpace24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 扫描状态提示
              Obx(
                () => controller.isScanning.value
                    ? Container(
                        padding: EdgeInsets.all(m.kSpace12),
                        margin: EdgeInsets.only(bottom: m.kSpace16),
                        decoration: BoxDecoration(
                          color: s.accentContainer,
                          borderRadius: m.radius8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: m.kSpace20,
                              height: m.kSpace20,
                              child: CircularProgressIndicator(
                                strokeWidth: AppTheme.metrics.strokeRegular,
                                valueColor: AlwaysStoppedAnimation<Color>(s.accent),
                              ),
                            ),
                            SizedBox(width: m.kSpace12),
                            Text(
                              '正在扫描书籍文件...',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize13,
                                color: s.accentText,
                                weight: FontWeight.w500,
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
                        padding: EdgeInsets.all(m.kSpace12),
                        margin: EdgeInsets.only(bottom: m.kSpace16),
                        decoration: BoxDecoration(
                          color: s.warning.container,
                          borderRadius: m.radius8,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: m.kSpace20,
                              height: m.kSpace20,
                              child: CircularProgressIndicator(
                                strokeWidth: AppTheme.metrics.strokeRegular,
                                valueColor: AlwaysStoppedAnimation<Color>(s.warning.color),
                              ),
                            ),
                            SizedBox(width: m.kSpace12),
                            Text(
                              '正在清空所有书籍...',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize13,
                                color: s.warning.onContainer,
                                weight: FontWeight.w500,
                              ),
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
                        padding: EdgeInsets.all(m.kSpace12),
                        margin: EdgeInsets.only(bottom: m.kSpace16),
                        decoration: BoxDecoration(
                          color: s.info.container,
                          borderRadius: m.radius8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: m.kSpace20,
                                  height: m.kSpace20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: AppTheme.metrics.strokeRegular,
                                    value: controller.searchProgress.value,
                                    valueColor: AlwaysStoppedAnimation<Color>(s.info.color),
                                  ),
                                ),
                                SizedBox(width: m.kSpace12),
                                Expanded(
                                  child: Text(
                                    '正在搜索书籍内容... ${(controller.searchProgress.value * 100).toStringAsFixed(0)}%（${controller.searchCompleted.value} / ${controller.searchTotal.value}）',
                                    style: AppTextStyles.role(
                                      context,
                                      fontSize: m.fontSize13,
                                      color: s.info.onContainer,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Obx(
                                  () => controller.isCancelling.value
                                      ? Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: m.kSpace12,
                                            vertical: m.kSpace8,
                                          ),
                                          child: SizedBox(
                                            width: m.kSpace16,
                                            height: m.kSpace16,
                                            child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular),
                                          ),
                                        )
                                      : TextButton.icon(
                                          onPressed: () => controller.cancelSearch(),
                                          icon: DrawIcon(StrokeIcons.cancel,
                                            size: m.iconSize18,
                                          ),
                                          label: const Text('取消'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: s.danger.color,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: m.kSpace12,
                                              vertical: m.kSpace8,
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            SizedBox(height: m.kSpace8),
                            LinearProgressIndicator(
                              value: controller.searchProgress.value,
                              backgroundColor: s.border,
                              valueColor: AlwaysStoppedAnimation<Color>(s.info.color),
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
                        padding: EdgeInsets.only(bottom: m.kSpace16),
                        child: Row(
                          children: [
                            Text(
                              '共 ${controller.novels.length} 本书籍',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize13,
                                color: s.textTertiary,
                                weight: FontWeight.w500,
                              ),
                            ),
                            if (controller.searchQuery.value.isNotEmpty)
                              Text(
                                ' （搜索到 ${controller.filteredNovels.length} 本）',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize13,
                                  color: s.accent,
                                  weight: FontWeight.w500,
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
                        padding: EdgeInsets.only(bottom: m.kSpace16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: AppTextField(
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
                                      prefixIcon: DrawIcon(StrokeIcons.search),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (controller.searchQuery.value.isNotEmpty)
                                            IconButton(
                                              icon: DrawIcon(StrokeIcons.clear),
                                              onPressed: () {
                                                controller.searchQuery.value = '';
                                                controller.contentSearchResults.clear();
                                              },
                                            ),
                                          if (controller.searchByContent.value &&
                                              controller.searchQuery.value.isNotEmpty)
                                            IconButton(
                                              icon: DrawIcon(StrokeIcons.search),
                                              onPressed: () => controller.searchInContent(
                                                controller.searchQuery.value,
                                              ),
                                            ),
                                        ],
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: m.radiusField,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: m.kSpace16,
                                        vertical: m.kSpace12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: m.kSpace8),
                            Row(
                              children: [
                                Text(
                                  '搜索模式: ',
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: m.fontSize13,
                                    color: s.textSecondary,
                                  ),
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
                                SizedBox(width: m.kSpace8),
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

              // 远程取书失败提示：节点离线 / 地址错 / 授权码错
              // 以前只打日志，用户只看到「空书库」，分不清是没书还是没连上。
              Obx(
                () => ErrorBanner(
                  message: controller.remoteErrorMessage.value,
                  onRetry: () => controller.refreshRemoteNovels(),
                ),
              ),

              // 书籍列表
              Expanded(
                child: Obx(() {
                  final displayNovels = controller.filteredNovels;

                  // ★ 不能判 `controller.novels.isEmpty`：那是**本机书**，
                  // 远程模式下恒为空（loadNovels 在远程模式直接 clear）。
                  // 用它会把"已取到一批节点书"的界面渲染成空状态，
                  // 用户看到的就是"远程书库读不到"。
                  // 空状态应看合并后的渲染源 filteredItems。
                  if (controller.filteredItems.isEmpty) {
                    return _buildEmptyView(context, isNarrow);
                  }

                  if (displayNovels.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DrawIcon(StrokeIcons.searchOff,
                            size: m.iconSize64,
                            color: s.textTertiary,
                          ),
                          SizedBox(height: m.kSpace16),
                          Text(
                            '没有找到匹配的书籍',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize15,
                              color: s.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: isNarrow ? scaleW(150) : scaleW(200),
                      childAspectRatio: 0.65,
                      crossAxisSpacing: isNarrow ? m.kSpace12 : m.kSpace16,
                      mainAxisSpacing: isNarrow ? m.kSpace12 : m.kSpace16,
                    ),
                    itemCount: displayNovels.length,
                    itemBuilder: (context, index) {
                      final novel = displayNovels[index];
                      return Draggable<NovelMetadata>(
                        data: novel,
                        feedback: Material(
                          // canvasColor 现为透明，拖拽浮影需要自己铺底
                          color: s.surface,
                          elevation: 8,
                          child: Opacity(
                            opacity: 0.8,
                            child: SizedBox(
                              width: isNarrow ? scaleW(150) : scaleW(200),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    // 移动端没有本机书库：空著的真实原因通常是「没连节点」或「节点上没书」，
    // 而不是「还没添加书籍」——直接说清该做什么，别让用户去本机找文件。
    final mobile = PlatformUtil.isMobile;
    final nodeService = getIt<NodeSettingsService>();
    final mobileNoNode = mobile && nodeService.enabledRemoteNodes.isEmpty;
    final title = mobileNoNode
        ? '还没有连接节点'
        : (mobile ? '节点上还没有书籍' : '还没有添加书籍');
    final hint = mobileNoNode
        ? '移动端只能读取远程节点：请到「设置 → 节点」添加一个节点'
        : (mobile ? '书籍保存在节点上，请到节点机器上导入' : '点击右上角按钮添加书籍');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DrawIcon(StrokeIcons.menuBook,
            size: isNarrow ? scaleW(80) : scaleW(120),
            color: s.textTertiary,
          ),
          SizedBox(height: m.kSpace24),
          Text(
            title,
            style: AppTextStyles.role(
              context,
              fontSize: isNarrow ? m.fontSize18 : m.fontSize20,
              color: s.textTertiary,
              weight: FontWeight.w500,
            ),
          ),
          SizedBox(height: m.kSpace12),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTextStyles.role(
              context,
              fontSize: isNarrow ? m.fontSize14 : m.fontSize16,
              color: s.textTertiary,
            ),
          ),
          SizedBox(height: m.kSpace32),
          Wrap(
            spacing: m.kSpace12,
            runSpacing: m.kSpace12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => Get.find<NovelLibraryViewModel>().scanFolder(),
                icon: DrawIcon(StrokeIcons.folderOpen),
                label: const Text('扫描文件夹'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? m.kSpace16 : m.kSpace24,
                    vertical: isNarrow ? m.kSpace12 : m.kSpace16,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Get.find<NovelLibraryViewModel>().addSingleNovel(),
                icon: DrawIcon(StrokeIcons.add),
                label: const Text('添加单个文件'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? m.kSpace16 : m.kSpace24,
                    vertical: isNarrow ? m.kSpace12 : m.kSpace16,
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
