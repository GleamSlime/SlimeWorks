import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slime_works/components/window/desktop_head.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/library/components/library_book_append.dart';
import 'package:slime_works/pages/collection/library/components/library_book_card.dart';
import 'package:slime_works/pages/collection/library/components/library_folder_card.dart';
import 'package:slime_works/pages/collection/library/components/library_item.dart';
import 'package:slime_works/pages/collection/library/components/library_folder_breadcrumb.dart';
import 'package:slime_works/pages/collection/library/components/library_selection_bar.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

class CollectionLibraryScreen extends BasePage<NovelLibraryViewModel> {
  const CollectionLibraryScreen({super.key});

  @override
  State<CollectionLibraryScreen> createState() => _CollectionLibraryScreenState();
}

class _CollectionLibraryScreenState
    extends BasePageState<NovelLibraryViewModel, CollectionLibraryScreen> {
  /// 外部文件拖拽悬停状态
  bool _isExternalDropHovering = false;

  /// 框选相关状态
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  final GlobalKey _gridKey = GlobalKey();

  /// 判断是否桌面端（桌面用 Draggable，移动用 LongPressDraggable）
  bool get _isDesktop => !Platform.isAndroid && !Platform.isIOS;

  bool _isBookLost(NovelMetadata meta) {
    if (meta.coverPath == null || meta.coverPath!.isEmpty) return false;
    // 直接使用 dart:io 的 existsSync，避免同步 FFI 调用（checkPathsExist 已改为异步）
    return !File(meta.coverPath!).existsSync();
  }

  bool _isFolderLost(NovelFolder folder) {
    final covers = viewModel.getFolderCovers(folder.id);
    if (covers.isEmpty) return false;
    // 直接使用 dart:io 的 existsSync，避免同步 FFI 调用（checkPathsExist 已改为异步）
    return covers.every((p) => !File(p).existsSync());
  }

  /// 滚动控制器，用于保存和恢复滚动位置
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();

    // 如果有保存的滚动位置，预先加载更多项目以确保能滚动到该位置
    if (viewModel.savedScrollOffset.value > 0) {
      viewModel.displayedItemCount.value = 200; // 预加载足够的项目
    }

    _scrollController = ScrollController(initialScrollOffset: viewModel.savedScrollOffset.value);

    // 添加滚动监听，接近底部时加载更多
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    const threshold = 500.0; // 距离底部500像素时触发加载

    if (maxScroll - currentScroll <= threshold && viewModel.canLoadMore) {
      viewModel.loadMoreItems();
    }
  }

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    final s = AppSemantic.of(context);
    return ScreenChromeData(
      title: '书库',
      toolbarHeight: AppTheme.metrics.kSpace48,
      toolbar: Obx(() {
        final activeTagCount = viewModel.selectedFilterTags.length;
        final isFavoritesOnly = viewModel.showFavoritesOnly.value;
        return Align(
          alignment: Alignment.centerRight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppTheme.metrics.kSpace8,
              children: [
                DesktopHeadToolsButton(
                  icon: DrawIcon(StrokeIcons.refresh),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () => _confirmClearAll(context),
                ),
                DesktopHeadToolsButton(
                  icon: DrawIcon(StrokeIcons.createNewFolder),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () => _showCreateFolderDialog(context),
                ),
                DesktopHeadToolsButton(
                  icon: DrawIcon(
                    isFavoritesOnly ? StrokeIcons.favorite : StrokeIcons.favoriteBorder,
                    // 收藏是"选中"状态，按口径走强调色而不是 danger 红（见 DESIGN §2.5）。
                    color: isFavoritesOnly ? s.accent : null,
                  ),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () {
                    viewModel.showFavoritesOnly.value = !viewModel.showFavoritesOnly.value;
                  },
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Builder(
                      builder: (tagBtnCtx) => DesktopHeadToolsButton(
                        icon: DrawIcon(StrokeIcons.labelOutline,
                          color: activeTagCount > 0 ? s.accent : null,
                        ),
                        size: AppTheme.metrics.kSpace40,
                        onTap: () => _showTagFilterMenu(tagBtnCtx),
                      ),
                    ),
                    if (activeTagCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: Container(
                            padding: EdgeInsets.all(AppTheme.metrics.kSpace3),
                            decoration: BoxDecoration(
                              color: s.accent,
                              borderRadius: AppTheme.metrics.radius10,
                            ),
                            constraints: BoxConstraints(
                              minWidth: AppTheme.metrics.kSpace16,
                              minHeight: AppTheme.metrics.kSpace16,
                            ),
                            child: Text(
                              '$activeTagCount',
                              style: AppTextStyles.role(
                                context,
                                fontSize: AppTheme.metrics.fontSize10,
                                weight: FontWeight.bold,
                                color: s.accentOn,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Builder(
                  builder: (sortBtnCtx) => DesktopHeadToolsButton(
                    icon: DrawIcon(StrokeIcons.sort),
                    size: AppTheme.metrics.kSpace40,
                    onTap: () => _showSortMenu(sortBtnCtx),
                  ),
                ),
                DesktopHeadToolsButton(
                  icon: DrawIcon(StrokeIcons.autoAwesome),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () => _showKeywordRulesDialog(),
                ),
                DesktopHeadToolsButton(
                  icon: DrawIcon(StrokeIcons.deviceHub),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () => context.go('/lan-transfer'),
                ),
                DesktopHeadToolsButton(
                  icon: DrawIcon(StrokeIcons.cloudSync),
                  size: AppTheme.metrics.kSpace40,
                  onTap: () => viewModel.refreshRemoteNovels(),
                ),
                LibraryBookAppendButton(viewModel: viewModel),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Tag 下拉多选（定位至按钞下方）
  void _showTagFilterMenu(BuildContext btnCtx) {
    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }

    final RenderBox button = btnCtx.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(navigatorContext, rootOverlay: true).context.findRenderObject()! as RenderBox;

    final Offset overlayTopLeft = overlay.localToGlobal(Offset.zero);
    final Offset buttonTopLeft = button.localToGlobal(Offset.zero);
    final Offset buttonBottomRight = button.localToGlobal(button.size.bottomRight(Offset.zero));

    final Offset topLeft = buttonTopLeft - overlayTopLeft;
    final Offset bottomRight = buttonBottomRight - overlayTopLeft;

    final RelativeRect position = RelativeRect.fromLTRB(
      topLeft.dx,
      bottomRight.dy + 4,
      overlay.size.width - bottomRight.dx,
      0,
    );

    showMenu<void>(
      context: navigatorContext,
      useRootNavigator: true,
      position: position,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (menuCtx, setMenuState) {
              final allTags = viewModel.allAvailableTags;
              final tagCounts = viewModel.allTagCounts;
              final m = AppTheme.metrics;
              final s = AppSemantic.of(context);
              return DefaultTextStyle(
                style: AppTextStyles.body(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '按标签筛选',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize13,
                                weight: FontWeight.w600,
                                height: 1.5,
                                color: s.textSecondary,
                              ),
                            ),
                          ),
                          if (viewModel.selectedFilterTags.isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: () {
                                viewModel.selectedFilterTags.clear();
                                setMenuState(() {});
                              },
                              child: Text(
                                '清除',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize12,
                                  weight: FontWeight.w500,
                                  height: 1.2,
                                  letterSpacing: 0.2,
                                  color: s.accentText,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (allTags.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text('暂无标签，请先为书籍添加标签。'),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: allTags.map((tag) {
                              final isSelected = viewModel.selectedFilterTags.contains(tag);
                              final count = tagCounts[tag] ?? 0;
                              return CheckboxListTile(
                                value: isSelected,
                                dense: true,
                                title: Text(
                                  '$tag ($count)',
                                  style: AppTextStyles.body(context),
                                ),
                                onChanged: (_) {
                                  if (isSelected) {
                                    viewModel.selectedFilterTags.remove(tag);
                                  } else {
                                    viewModel.selectedFilterTags.add(tag);
                                  }
                                  setMenuState(() {});
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    SizedBox(height: AppTheme.metrics.kSpace4),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 排序菜单
  void _showSortMenu(BuildContext btnCtx) {
    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) {
      return;
    }

    final RenderBox button = btnCtx.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(navigatorContext, rootOverlay: true).context.findRenderObject()! as RenderBox;

    final Offset overlayTopLeft = overlay.localToGlobal(Offset.zero);
    final Offset buttonTopLeft = button.localToGlobal(Offset.zero);
    final Offset buttonBottomRight = button.localToGlobal(button.size.bottomRight(Offset.zero));

    final Offset topLeft = buttonTopLeft - overlayTopLeft;
    final Offset bottomRight = buttonBottomRight - overlayTopLeft;

    final RelativeRect position = RelativeRect.fromLTRB(
      topLeft.dx,
      bottomRight.dy + 4,
      overlay.size.width - bottomRight.dx,
      0,
    );

    final sortOptions = [
      {'field': 'addedAt', 'label': '添加时间'},
      {'field': 'title', 'label': '书籍名称'},
      {'field': 'fileSize', 'label': '文件大小'},
    ];

    showMenu<void>(
      context: navigatorContext,
      useRootNavigator: true,
      position: position,
      constraints: const BoxConstraints(minWidth: 200),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Obx(() {
            final currentField = viewModel.sortField.value;
            final currentAscending = viewModel.sortAscending.value;
            final m = AppTheme.metrics;
            final s = AppSemantic.of(context);

            return DefaultTextStyle(
              style: AppTextStyles.body(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Text(
                      '排序方式',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize13,
                        weight: FontWeight.w600,
                        height: 1.5,
                        color: s.textSecondary,
                      ),
                    ),
                  ),
                  ...sortOptions.map((option) {
                    final field = option['field']!;
                    final label = option['label']!;
                    final isCurrentField = currentField == field;
                    final isAscendingActive = isCurrentField && currentAscending;
                    final isDescendingActive = isCurrentField && !currentAscending;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 升序选项
                        ListTile(
                          dense: true,
                          leading: DrawIcon(StrokeIcons.arrowUpward,
                            size: AppTheme.metrics.iconSize18,
                            color: isAscendingActive ? s.accent : null,
                          ),
                          title: Text(
                            '$label升序',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize13,
                              weight: isAscendingActive ? FontWeight.w600 : FontWeight.normal,
                              color: isAscendingActive ? s.accent : s.textPrimary,
                            ),
                          ),
                          trailing: isAscendingActive
                              ? DrawIcon(StrokeIcons.check,
                                  size: AppTheme.metrics.iconSize18,
                                  color: s.accent,
                                )
                              : null,
                          onTap: () {
                            viewModel.setSortOption(field, true);
                            Navigator.of(navigatorContext, rootNavigator: true).pop();
                          },
                        ),
                        // 降序选项
                        ListTile(
                          dense: true,
                          leading: DrawIcon(StrokeIcons.arrowDownward,
                            size: AppTheme.metrics.iconSize18,
                            color: isDescendingActive ? s.accent : null,
                          ),
                          title: Text(
                            '$label降序',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize13,
                              weight: isDescendingActive ? FontWeight.w600 : FontWeight.normal,
                              color: isDescendingActive ? s.accent : s.textPrimary,
                            ),
                          ),
                          trailing: isDescendingActive
                              ? DrawIcon(StrokeIcons.check,
                                  size: AppTheme.metrics.iconSize18,
                                  color: s.accent,
                                )
                              : null,
                          onTap: () {
                            viewModel.setSortOption(field, false);
                            Navigator.of(navigatorContext, rootNavigator: true).pop();
                          },
                        ),
                        if (option != sortOptions.last) const Divider(height: 1),
                      ],
                    );
                  }),
                  SizedBox(height: AppTheme.metrics.kSpace4),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  /// 关键词自动打标规则管理弹窗
  void _showKeywordRulesDialog() {
    final keywordCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (_, setModalState) {
          final rules = viewModel.keywordRules.toList();
          final m = AppTheme.metrics;
          final s = AppSemantic.of(context);
          return AlertDialog(
            title: const Text('关键词自动打标签'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '导入书籍时，若书内包含关键词则自动添加对应标签。',
                    style: AppTextStyles.role(context, fontSize: m.fontSize12, color: s.textSecondary),
                  ),
                  SizedBox(height: AppTheme.metrics.kSpace12),
                  if (rules.isNotEmpty)
                    LimitedBox(
                      maxHeight: 200,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: rules.length,
                        itemBuilder: (_, i) {
                          final kw = rules[i]['keyword'] ?? '';
                          final tag = rules[i]['tag'] ?? '';
                          return ListTile(
                            dense: true,
                            title: Text('搜索 "$kw" → 添加标签 "$tag"'),
                            trailing: IconButton(
                              icon: DrawIcon(StrokeIcons.deleteOutline, size: AppTheme.metrics.iconSize18),
                              onPressed: () async {
                                await viewModel.removeKeywordRule(i);
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
                      child: Text(
                        '暂无规则',
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize13,
                          color: s.textTertiary,
                        ),
                      ),
                    ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: keywordCtrl,
                          decoration: const InputDecoration(
                            labelText: '关键词',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(width: AppTheme.metrics.kSpace8),
                      Expanded(
                        child: AppTextField(
                          controller: tagCtrl,
                          decoration: const InputDecoration(
                            labelText: '标签（留空同关键词）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(width: AppTheme.metrics.kSpace8),
                      IconButton(
                        icon: DrawIcon(StrokeIcons.add),
                        onPressed: () async {
                          final kw = keywordCtrl.text.trim();
                          if (kw.isEmpty) return;
                          await viewModel.addKeywordRule(
                            kw,
                            tagCtrl.text.trim().isEmpty ? kw : tagCtrl.text.trim(),
                          );
                          keywordCtrl.clear();
                          tagCtrl.clear();
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              Obx(
                () => viewModel.isScanning.value
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12),
                        child: SizedBox(
                          width: AppTheme.metrics.kSpace18,
                          height: AppTheme.metrics.kSpace18,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton.icon(
                        icon: DrawIcon(StrokeIcons.autoAwesome, size: AppTheme.metrics.iconSize16),
                        label: const Text('应用到所有书籍'),
                        onPressed: () async {
                          final pendingKeyword = keywordCtrl.text.trim();
                          if (pendingKeyword.isNotEmpty) {
                            final pendingTag = tagCtrl.text.trim();
                            await viewModel.addKeywordRule(
                              pendingKeyword,
                              pendingTag.isEmpty ? pendingKeyword : pendingTag,
                            );
                            keywordCtrl.clear();
                            tagCtrl.clear();
                          }
                          await viewModel.applyKeywordRulesToAll();
                          if (!dlgCtx.mounted) return;
                          Navigator.of(dlgCtx, rootNavigator: true).pop();
                        },
                      ),
              ),
              Obx(() {
                final total = viewModel.keywordApplyTotal.value;
                if (total <= 0) {
                  return const SizedBox.shrink();
                }
                final completed = viewModel.keywordApplyCompleted.value;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace4),
                  child: Text(
                    '$completed/$total',
                    style: AppTextStyles.role(
                      context,
                      fontSize: AppTheme.metrics.fontSize12,
                      height: 1.6,
                      color: AppSemantic.of(context).textTertiary,
                    ),
                  ),
                );
              }),
              FilledButton(
                onPressed: () => Navigator.of(dlgCtx, rootNavigator: true).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Tag 多选筛选弹窗

  void _confirmClearAll(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('清空书籍？'),
        content: const Text('确定要清空所有书籍吗？此操作不可撤销，所有书籍及阅读记录将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx, rootNavigator: true).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppSemantic.of(dlgCtx).danger.color),
            onPressed: () {
              Navigator.of(dlgCtx, rootNavigator: true).pop();
              viewModel.clearAllNovelsAction();
            },
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext ctx) {
    final controller = TextEditingController();
    final inFolder = viewModel.currentFolderId.value != null;
    showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      builder: (dlgCtx) => AlertDialog(
        title: Text(inFolder ? '新建子文件夹' : '新建文件夹'),
        content: AppTextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: inFolder ? '请输入子文件夹名' : '请输入文件夹名称',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) {
              Navigator.of(dlgCtx, rootNavigator: true).pop();
              viewModel.createFolderWithName(name);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx, rootNavigator: true).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(dlgCtx, rootNavigator: true).pop();
                viewModel.createFolderWithName(name);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 保存当前滚动位置
    if (_scrollController.hasClients) {
      viewModel.savedScrollOffset.value = _scrollController.offset;
    }
    _scrollController.dispose();
    super.dispose();
  }

  late final NovelLibraryViewModel _persistentViewModel = Get.put(
    NovelLibraryViewModel(),
    permanent: true,
  );

  @override
  NovelLibraryViewModel createViewModel() => _persistentViewModel;

  @override
  Widget buildContent(BuildContext context) {
    final s = AppSemantic.of(context);
    return ScreenChrome(
      data: _buildScreenChromeData(context),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey.keyLabel == 'Escape') {
              if (viewModel.isSelecting.value) {
                viewModel.exitSelection();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey.keyLabel == 'A' &&
                (HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed)) {
              if (!viewModel.isSelecting.value) {
                viewModel.isSelecting.value = true;
              }
              viewModel.toggleSelectAll();
              return KeyEventResult.handled;
            } else if (event.logicalKey.keyLabel == 'Delete') {
              if (viewModel.isSelecting.value && viewModel.selectedIds.isNotEmpty) {
                _showDeleteNotImplemented(context);
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: DropTarget(
          onDragDone: (details) {
            viewModel.addDroppedFiles(details.files.map((f) => f.path).toList());
            setState(() => _isExternalDropHovering = false);
          },
          onDragEntered: (_) => setState(() => _isExternalDropHovering = true),
          onDragExited: (_) => setState(() => _isExternalDropHovering = false),
          child: Stack(
            children: [
              Obx(() {
                final isSelecting = viewModel.isSelecting.value;
                final inFolder = viewModel.currentFolderId.value != null;
                final folderName = viewModel.currentFolderName;
                final currentBookCount = viewModel.filteredItems
                    .whereType<LibraryBookItem>()
                    .length;

                return Column(
                  children: [
                    if (inFolder)
                      FolderBreadcrumb(folderName: folderName, onBack: viewModel.exitFolder),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: appMetrics.kSpace12,
                        vertical: appMetrics.kSpace8,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '当前书籍：$currentBookCount 本',
                          style: AppTextStyles.role(
                            context,
                            fontSize: appMetrics.fontSize12,
                            height: 1.6,
                            color: s.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _buildGrid(isSelecting, inFolder)),
                    if (isSelecting) LibrarySelectionBar(viewModel: viewModel),
                  ],
                );
              }),
              if (_isExternalDropHovering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: s.accent.withAlpha(30),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DrawIcon(StrokeIcons.fileDownload,
                              size: scaleW(64),
                              color: s.accent,
                            ),
                            SizedBox(height: appMetrics.kSpace16),
                            Text(
                              '松开以导入书籍',
                              style: AppTextStyles.role(
                                context,
                                fontSize: appMetrics.fontSize18,
                                weight: FontWeight.w600,
                                color: s.accent,
                              ),
                            ),
                            SizedBox(height: appMetrics.kSpace8),
                            Text(
                              '支持 .txt / .epub 格式',
                              style: AppTextStyles.role(
                                context,
                                fontSize: appMetrics.fontSize13,
                                color: s.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示删除功能未实现提示
  void _showDeleteNotImplemented(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('批量删除功能尚未实现，请单独删除书籍或文件夹。'),
        actions: [FilledButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('确定'))],
      ),
    );
  }

  Widget _buildGrid(bool isSelecting, bool inFolder) {
    return Obx(() {
      final s = AppSemantic.of(context);
      // ignore: unused_local_variable
      final selectedCount = viewModel.selectedIds.length;
      final items = viewModel.displayedItems; // 使用分页后的项目
      final hasBackButton = inFolder;

      if (items.isEmpty && !hasBackButton) {
        return _buildEmptyState(inFolder);
      }

      // 计算总条目数：返回按钮（如果有）+ 实际条目
      final totalCount = (hasBackButton ? 1 : 0) + items.length;

      // 使用 GridView.custom 恢复之前的实现以改善滚动流畅度
      final gridView = GridView.custom(
        key: _gridKey,
        controller: _scrollController,
        padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
        cacheExtent: 500,
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: scaleW(200),
          childAspectRatio: 0.65,
          mainAxisSpacing: AppTheme.metrics.kSpace12,
          crossAxisSpacing: AppTheme.metrics.kSpace12,
        ),
        childrenDelegate: SliverChildBuilderDelegate((context, index) {
          // 如果有返回按钮且是第一个索引，显示返回按钮
          if (hasBackButton && index == 0) {
            return _buildBackButton();
          }

          // 调整实际条目索引
          final itemIndex = hasBackButton ? index - 1 : index;
          final item = items[itemIndex];
          final isSelected = viewModel.selectedIds.contains(item.id);

          return _buildDraggableItem(context, itemIndex, item, isSelected, isSelecting);
        }, childCount: totalCount),
      );

      if (!_isDesktop) {
        return gridView;
      }

      // 框选功能包装
      return GestureDetector(
        onPanStart: (details) {
          setState(() {
            _selectionBoxStart = details.localPosition;
            _selectionBoxEnd = details.localPosition;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            _selectionBoxEnd = details.localPosition;
          });
          _updateSelectionByBox();
        },
        onPanEnd: (_) {
          setState(() {
            _selectionBoxStart = null;
            _selectionBoxEnd = null;
          });
        },
        child: Stack(
          children: [
            gridView,
            if (_selectionBoxStart != null && _selectionBoxEnd != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SelectionBoxPainter(
                    start: _selectionBoxStart!,
                    end: _selectionBoxEnd!,
                    color: s.accent.withAlpha(50),
                    borderColor: s.accent,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _buildDraggableItem(
    BuildContext ctx,
    int itemIndex,
    LibraryItem item,
    bool isSelected,
    bool isSelecting,
  ) {
    Widget buildCard({bool isBookHover = false, bool isReorderTarget = false}) {
      // 只在需要时才应用边框装饰，避免不必要的 Container
      if (isReorderTarget) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppSemantic.of(ctx).accent, width: scaleW(2)),
            borderRadius: appMetrics.radius8,
          ),
          child: _buildItemCard(ctx, item, isSelected, isSelecting, isBookHover),
        );
      }
      return _buildItemCard(ctx, item, isSelected, isSelecting, isBookHover);
    }

    // 选择模式下禁用拖拽
    if (isSelecting) {
      return RepaintBoundary(key: ValueKey(item.id), child: buildCard());
    }

    if (!_isDesktop) {
      return RepaintBoundary(key: ValueKey(item.id), child: buildCard());
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final movedId = details.data;
        developer.log('onWillAccept: moved=$movedId -> target=${item.id}', name: '库-拖拽');
        if (movedId == item.id) return false;
        final items = viewModel.filteredItems;
        final movedIndex = items.indexWhere((i) => i.id == movedId);
        if (movedIndex == -1) return false;
        final draggedItem = items[movedIndex];
        // 书拖入文件夹：不显示 ghost，只显示文件夹高亮
        if (draggedItem is LibraryBookItem && item is LibraryFolderItem) return true;
        // 同类型排序
        if (draggedItem.runtimeType == item.runtimeType) return true;
        return false;
      },
      onAcceptWithDetails: (details) {
        final movedId = details.data;
        developer.log('onAcceptWithDetails: moved=$movedId -> target=${item.id}', name: '库-拖拽');
        final items = viewModel.filteredItems;
        final movedIndex = items.indexWhere((i) => i.id == movedId);
        if (movedIndex == -1) return;
        final draggedItem = items[movedIndex];
        if (draggedItem is LibraryBookItem && item is LibraryFolderItem) {
          viewModel.moveNovelToFolder(draggedItem.metadata.id, item.folder.id);
        } else {
          viewModel.reorderItemsById(movedId, item.id);
        }
      },
      builder: (ctx, candidateData, rejectedData) {
        final items = viewModel.filteredItems;
        final candidateId = candidateData.isNotEmpty ? candidateData.first : null;
        final candidateIndex = candidateId == null
            ? -1
            : items.indexWhere((i) => i.id == candidateId);
        final isBookHover =
            candidateId != null &&
            item is LibraryFolderItem &&
            candidateIndex != -1 &&
            items[candidateIndex] is LibraryBookItem;
        // 同类型排序时用边框高亮目标，ghost 在被拖拽项原位
        final movedId = candidateData.isNotEmpty ? candidateData.first : null;
        final movedItem = movedId != null ? items.firstWhereOrNull((i) => i.id == movedId) : null;
        final isReorderTarget = movedItem != null && movedItem.runtimeType == item.runtimeType;
        final child = buildCard(isBookHover: isBookHover, isReorderTarget: isReorderTarget);

        if (_isDesktop) {
          return RepaintBoundary(
            key: ValueKey(item.id),
            child: Draggable<String>(
              data: item.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              maxSimultaneousDrags: 1,
              onDragStarted: () {
                developer.log('dragStarted (desktop) id=${item.id}', name: '库-拖拽');
              },
              feedback: _buildDragFeedback(context, item),
              childWhenDragging: Opacity(opacity: 0.3, child: child),
              child: child,
            ),
          );
        } else {
          return RepaintBoundary(
            key: ValueKey(item.id),
            child: LongPressDraggable<String>(
              data: item.id,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              hapticFeedbackOnStart: true,
              onDragStarted: () {
                developer.log('dragStarted (mobile) id=${item.id}', name: '库-拖拽');
                if (!isSelecting) viewModel.enterSelection(item.id);
              },
              feedback: _buildDragFeedback(context, item),
              childWhenDragging: Opacity(opacity: 0.3, child: child),
              child: child,
            ),
          );
        }
      },
    );
  }

  Widget _buildItemCard(
    BuildContext ctx,
    LibraryItem item,
    bool isSelected,
    bool isSelecting,
    bool isBookHover,
  ) {
    if (item is LibraryFolderItem) {
      return LibraryFolderCard(
        folder: item.folder,
        viewModel: viewModel,
        isSelected: isSelected,
        isSelecting: isSelecting,
        isBookHover: isBookHover,
        isLost: _isFolderLost(item.folder),
        onTap: () {
          if (isSelecting) {
            viewModel.toggleSelection(item.id);
          } else {
            viewModel.enterFolder(item.folder.id);
          }
        },
        onLongPress: () => viewModel.enterSelection(item.id),
        onDoubleTap: () {}, // 双击将在LibraryFolderCard内部处理为进入重命名模式
      );
    } else if (item is LibraryBookItem) {
      return LibraryBookCard(
        metadata: item.metadata,
        viewModel: viewModel,
        isSelected: isSelected,
        isSelecting: isSelecting,
        isLost: _isBookLost(item.metadata),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDragFeedback(BuildContext context, LibraryItem item) {
    final s = AppSemantic.of(context);
    // 简化并明确括号/层级，减少语法错误风险
    if (item is LibraryBookItem) {
      final meta = item.metadata;
      final double w = scaleW(100);
      final double h = w / 0.65;

      Widget cover;
      if (FakeCover.enabled && meta.coverPath != null) {
        // 伪封面：拖拽浮影是最容易被旁人看到的一处，同样不能带出真实封面
        cover = const FakeCover();
      } else if (meta.coverPath != null && File(meta.coverPath!).existsSync()) {
        final privacyOn = getIt.isRegistered<MediaPrefsService>()
            ? getIt<MediaPrefsService>().privacyMode.value
            : false;
        final blurSigma = getIt.isRegistered<MediaPrefsService>()
            ? getIt<MediaPrefsService>().privacyBlurSigma.value
            : 15.0;
        // 拖拽反馈只有 100px 宽，按显示尺寸解码避免整张封面进内存
        final rawCover = Image.file(File(meta.coverPath!), fit: BoxFit.cover, cacheWidth: 200);
        cover = privacyOn
            ? ClipRRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    rawCover,
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: Container(color: Colors.transparent),
                    ),
                  ],
                ),
              )
            : rawCover;
      } else {
        // 占位封面要压得住它上面那枚白图标，所以底色走实心的 border 档
        cover = Container(
          color: s.border,
          child: Center(
            child: DrawIcon(StrokeIcons.book, size: scaleW(28), color: Colors.white70),
          ),
        );
      }

      return Transform.translate(
        offset: Offset(-w / 2, -h / 2),
        child: Opacity(
          opacity: 0.85,
          child: Material(
            // canvasColor 现为透明，拖拽浮影需要自己铺底
            color: s.surface,
            elevation: 12,
            borderRadius: AppTheme.metrics.radius8,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  cover,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: scaleW(4), vertical: scaleW(4)),
                      // 封面底图上的压暗层恒为深色，白字不随主题反转
                      color: s.scrim.withAlpha(140),
                      child: Text(
                        meta.title,
                        style: AppTextStyles.role(
                          context,
                          fontSize: AppTheme.metrics.fontSize9,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (item is LibraryFolderItem) {
      final double w = scaleW(100);
      final double h = w;
      return Transform.translate(
        offset: Offset(-w / 2, -h / 2),
        child: Opacity(
          opacity: 0.85,
          child: Material(
            // canvasColor 现为透明，拖拽浮影需要自己铺底
            color: s.surface,
            elevation: 12,
            borderRadius: AppTheme.metrics.radius8,
            child: SizedBox(
              width: w,
              height: h,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppTheme.metrics.radius8,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // 文件夹这一路的身份色统一走 info，浮影与卡片同档
                    colors: [s.info.color.withAlpha(60), s.info.color.withAlpha(30)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DrawIcon(StrokeIcons.folder, size: scaleW(36), color: s.info.color.withAlpha(200)),
                    SizedBox(height: scaleW(3)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: scaleW(6)),
                      child: Text(
                        item.folder.name,
                        style: AppTextStyles.role(
                          context,
                          fontSize: AppTheme.metrics.fontSize9,
                          weight: FontWeight.w600,
                          color: s.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBackButton() {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        final items = viewModel.filteredItems;
        final idx = items.indexWhere((i) => i.id == details.data);
        if (idx == -1) return false;
        return items[idx] is LibraryBookItem;
      },
      onAcceptWithDetails: (details) {
        final items = viewModel.filteredItems;
        final idx = items.indexWhere((i) => i.id == details.data);
        if (idx == -1) return;
        final item = items[idx];
        if (item is LibraryBookItem) {
          viewModel.moveNovelToParentFolder(item.metadata.id);
        }
      },
      builder: (ctx, candidateData, _) {
        final isDragHovering = candidateData.isNotEmpty;
        final parentFolderName = viewModel.currentFolderName;
        final s = AppSemantic.of(ctx);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: viewModel.exitFolder,
            child: Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                decoration: BoxDecoration(
                  // 与同排卡片卡面同底，只有拖拽悬停时才抬成强调容器
                  color: isDragHovering ? s.accentContainer : s.surface,
                  border: isDragHovering
                      ? Border.all(color: s.accent, width: scaleW(2))
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DrawIcon(
                      isDragHovering ? StrokeIcons.driveFileMoveRtl : StrokeIcons.arrowBack,
                      size: scaleW(40),
                      color: isDragHovering ? s.accent : s.textSecondary,
                    ),
                    SizedBox(height: appMetrics.kSpace8),
                    Text(
                      isDragHovering ? '移至上级' : '返回',
                      style: AppTextStyles.role(
                        ctx,
                        fontSize: appMetrics.fontSize11,
                        weight: isDragHovering ? FontWeight.w600 : FontWeight.normal,
                        color: isDragHovering ? s.accent : s.textSecondary,
                      ),
                    ),
                    if (parentFolderName.isNotEmpty && !isDragHovering) ...[
                      SizedBox(height: appMetrics.kSpace4),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace8),
                        child: Text(
                          parentFolderName,
                          style: AppTextStyles.role(
                            ctx,
                            fontSize: appMetrics.fontSize9,
                            color: s.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool inFolder) {
    final s = AppSemantic.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrawIcon(
            inFolder ? StrokeIcons.folderOpen : StrokeIcons.libraryBooks,
            size: AppTheme.metrics.iconSize64,
            color: s.textDisabled,
          ),
          SizedBox(height: AppTheme.metrics.kSpace16),
          Text(
            inFolder ? '此文件夹暂无书籍' : '书籍库为空，点击右上角添加书籍',
            style: AppTextStyles.body(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 根据框选框更新选中的items
  void _updateSelectionByBox() {
    if (_selectionBoxStart == null || _selectionBoxEnd == null) return;

    // 计算选择框的矩形区域
    final selectionRect = Rect.fromPoints(_selectionBoxStart!, _selectionBoxEnd!);

    // 获取GridView的RenderBox
    final gridRenderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridRenderBox == null) return;

    // 遍历所有items,检查是否与选择框相交
    final items = viewModel.displayedItems;
    final newSelection = <String>{};

    // 基于GridView布局参数估算每个item的位置
    final maxCrossAxisExtent = scaleW(200);
    final mainAxisSpacing = AppTheme.metrics.kSpace12;
    final crossAxisSpacing = AppTheme.metrics.kSpace12;
    final padding = AppTheme.metrics.kSpace12;

    // 计算每行的列数
    final gridWidth = gridRenderBox.size.width - 2 * padding;
    final crossAxisCount = (gridWidth / (maxCrossAxisExtent + crossAxisSpacing)).floor();
    if (crossAxisCount <= 0) return;

    final itemWidth = (gridWidth - (crossAxisCount - 1) * crossAxisSpacing) / crossAxisCount;
    final itemHeight = itemWidth / 0.65; // childAspectRatio

    // 遍历items计算位置
    for (int i = 0; i < items.length; i++) {
      final row = i ~/ crossAxisCount;
      final col = i % crossAxisCount;

      final left = padding + col * (itemWidth + crossAxisSpacing);
      final top = padding + row * (itemHeight + mainAxisSpacing);
      final right = left + itemWidth;
      final bottom = top + itemHeight;

      final itemRect = Rect.fromLTRB(left, top, right, bottom);

      // 判断item是否与选择框相交
      if (selectionRect.overlaps(itemRect)) {
        newSelection.add(items[i].id);
      }
    }

    // 更新选中状态
    if (!viewModel.isSelecting.value && newSelection.isEmpty) {
      return;
    }

    viewModel.selectedIds.assignAll(newSelection);
    if (newSelection.isNotEmpty) {
      viewModel.isSelecting.value = true;
    } else {
      viewModel.exitSelection();
    }
  }
}

/// 绘制框选矩形的Painter
class _SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final Color color;
  final Color borderColor;

  _SelectionBoxPainter({
    required this.start,
    required this.end,
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // 填充
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // 边框
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SelectionBoxPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
