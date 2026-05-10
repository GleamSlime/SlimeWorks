library;

/// PicACG 搜索页面
///
/// 遵循 头部规范：
/// - 搜索输入框置于 titleWidget 位置，不使用 AppBar
/// - 支持搜索历史 Tag（本地存储，上限 20 条）
/// - 支持排序切换

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_comic_card.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_search_viewmodel.dart';

class PicAcgSearchScreen extends BasePage<PicAcgSearchViewModel> {
  const PicAcgSearchScreen({super.key, this.keyword = '', this.category = ''});

  final String keyword;
  final String category;

  @override
  State<PicAcgSearchScreen> createState() => _PicAcgSearchScreenState();
}

class _PicAcgSearchScreenState extends BasePageState<PicAcgSearchViewModel, PicAcgSearchScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// 是否显示历史记录区（无搜索结果时）
  final RxBool _showHistory = false.obs;

  @override
  PicAcgSearchViewModel createViewModel() => PicAcgSearchViewModel();

  @override
  Future<void> onPageInit() async {
    _searchController.text = widget.keyword;
    if (widget.keyword.isNotEmpty || widget.category.isNotEmpty) {
      final initCategories = widget.category.isNotEmpty ? [widget.category] : <String>[];
      await viewModel.search(keyword: widget.keyword, categories: initCategories);
    } else {
      _showHistory.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      viewModel.loadMore();
    }
  }

  Future<void> _doSearch({String? kw}) async {
    final keyword = kw ?? _searchController.text.trim();
    if (keyword.isEmpty) return;
    _searchController.text = keyword;
    _focusNode.unfocus();
    _showHistory.value = false;
    await viewModel.search(keyword: keyword);
  }

  void _clearSearch() {
    _searchController.clear();
    viewModel.results.clear();
    _showHistory.value = true;
    _focusNode.requestFocus();
  }

  ScreenChromeData _buildChromeData(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenChromeData(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) context.pop();
        },
      ),
      titleWidget: _SearchInputField(
        controller: _searchController,
        focusNode: _focusNode,
        theme: theme,
        onSubmitted: (_) => _doSearch(),
        onClear: _clearSearch,
        onChanged: (val) {
          if (val.isEmpty && viewModel.results.isEmpty) {
            _showHistory.value = true;
          }
        },
      ),
      actions: [
        /// 分类过滤按钮（已选时显示数字徽章）
        Obx(
          () => IconButton(
            tooltip: '分类过滤',
            icon: viewModel.selectedCategories.isEmpty
                ? const Icon(Icons.filter_list_outlined)
                : Badge(
                    label: Text('${viewModel.selectedCategories.length}'),
                    child: const Icon(Icons.filter_list),
                  ),
            onPressed: () => _showCategoryFilter(context),
          ),
        ),

        /// 排序按钮（读取 sort.value，Obx 响应式更新）
        Obx(
          () => _SortButton(
            current: viewModel.sort.value,
            onChanged: (sort) {
              if (viewModel.keyword.isNotEmpty || viewModel.selectedCategories.isNotEmpty) {
                viewModel.search(keyword: viewModel.keyword, newSort: sort);
              } else {
                viewModel.sort.value = sort;
              }
            },
          ),
        ),
        IconButton(icon: const Icon(Icons.search), onPressed: _doSearch),
      ],
    );
  }

  /// 分类过滤 BottomSheet
  void _showCategoryFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CategoryFilterSheet(
        selected: List<String>.from(viewModel.selectedCategories),
        onApply: (cats) {
          viewModel.selectedCategories.assignAll(cats);
          if (viewModel.keyword.isNotEmpty || cats.isNotEmpty) {
            viewModel.search(keyword: viewModel.keyword, categories: cats);
          }
        },
      ),
    );
  }

  @override
  bool get showAppBar => false;

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildChromeData(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 历史记录区域（无搜索结果时展示）
          Obx(() {
            if (!_showHistory.value) return const SizedBox.shrink();
            return _SearchHistorySection(
              history: viewModel.searchHistory,
              onTap: (tag) => _doSearch(kw: tag),
              onClear: () => viewModel.clearHistory(),
              onDelete: (tag) => viewModel.removeHistory(tag),
            );
          }),

          /// 搜索结果
          Expanded(child: _buildResults(context)),
        ],
      ),
    );
  }

  /// 搜索结果区域（使用 Obx 监听 RxList 变化，修复 loadMore 后列表不更新的问题）
  Widget _buildResults(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    /// isLoading / errorMessage 由基类 GetBuilder 触发重建，此处直接读取
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.errorMessage != null) {
      return Center(
        child: Text(
          viewModel.errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }

    /// 列表数据由 Obx 监听，确保 loadMore 时新条目即时显示
    return Obx(() {
      if (viewModel.results.isEmpty && viewModel.keyword.isNotEmpty) {
        return Center(
          child: Text(
            '没有找到相关漫画',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        );
      }
      if (viewModel.results.isEmpty) {
        return const SizedBox.shrink();
      }
      final crossAxisCount = PlatformUtil.isDesktop ? 6 : 3;
      return GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(metrics.kSpace16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: scaleW(8),
          crossAxisSpacing: scaleW(8),
          childAspectRatio: 0.6,
        ),
        itemCount: viewModel.results.length + (viewModel.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= viewModel.results.length) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final comic = viewModel.results[i];
          return PicAcgComicCard(
            comic: comic,
            onTap: () => PicAcgComicDetailRoute(comicId: comic.id).push(context),
          );
        },
      );
    });
  }
}

class _SearchInputField extends StatelessWidget {
  const _SearchInputField({
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.onSubmitted,
    required this.onClear,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ThemeData theme;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        hintText: '搜索漫画、作者、标签...',
        border: InputBorder.none,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close,
                    size: scaleW(18),
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  onPressed: onClear,
                )
              : const SizedBox.shrink(),
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
      ),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
    );
  }
}

/// 搜索历史区域（标签云展示）
class _SearchHistorySection extends StatelessWidget {
  const _SearchHistorySection({
    required this.history,
    required this.onTap,
    required this.onClear,
    required this.onDelete,
  });

  final RxList<String> history;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Obx(() {
      if (history.isEmpty) return const SizedBox.shrink();
      return Container(
        padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16, vertical: metrics.kSpace8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '搜索历史',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.delete_sweep_outlined,
                    size: scaleW(18),
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.kSpace8),
            Wrap(
              spacing: scaleW(8),
              runSpacing: scaleW(6),
              children: history
                  .map(
                    (tag) => _HistoryTag(
                      label: tag,
                      onTap: () => onTap(tag),
                      onDelete: () => onDelete(tag),
                    ),
                  )
                  .toList(),
            ),
            SizedBox(height: metrics.kSpace4),
          ],
        ),
      );
    });
  }
}

/// 单个历史 Tag 组件
class _HistoryTag extends StatelessWidget {
  const _HistoryTag({required this.label, required this.onTap, required this.onDelete});

  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Chip(
        label: Text(label, style: theme.textTheme.bodySmall),
        deleteIcon: Icon(Icons.close, size: scaleW(14)),
        onDeleted: onDelete,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(horizontal: scaleW(4)),
      ),
    );
  }
}

/// 排序选择按钮（PopupMenu 展示四种排序方式）
class _SortButton extends StatelessWidget {
  const _SortButton({required this.current, required this.onChanged});

  final PicAcgSortOrder current;
  final ValueChanged<PicAcgSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PicAcgSortOrder>(
      tooltip: '排序方式',
      icon: const Icon(Icons.sort),
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (_) => [
        _buildItem(PicAcgSortOrder.dateDescending, '最新发布', Icons.new_releases_outlined),
        _buildItem(PicAcgSortOrder.dateAscending, '最旧发布', Icons.history_outlined),
        _buildItem(PicAcgSortOrder.likeDescending, '最多点赞', Icons.favorite_border),
        _buildItem(PicAcgSortOrder.viewDescending, '最多浏览', Icons.visibility_outlined),
      ],
    );
  }

  PopupMenuItem<PicAcgSortOrder> _buildItem(PicAcgSortOrder value, String label, IconData icon) {
    return PopupMenuItem<PicAcgSortOrder>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize18),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Text(label),
          if (current == value) ...[
            const Spacer(),
            Icon(Icons.check, size: AppTheme.metrics.iconSize16),
          ],
        ],
      ),
    );
  }
}

/// PicACG 标准分类列表（来自原项目 CateGoryMgr）
const List<String> _kPicAcgCategories = [
  '嗶咔漢化',
  '全彩',
  '長篇',
  '同人',
  '短篇',
  '圓神領域',
  '碧藍幻想',
  'CG雜圖',
  '英語 ENG',
  '生肉',
  '純愛',
  '百合花園',
  '耽美花園',
  '偽娘哲學',
  '後宮閃光',
  '扶他樂園',
  '單行本',
  '姐姐系',
  '妹妹系',
  'SM',
  '性轉換',
  '足の恋',
  '人妻',
  'NTR',
  '強暴',
  '非人類',
  '艦隊收藏',
  'Love Live',
  'SAO 刀劍神域',
  'Fate',
  '東方',
  'WEBTOON',
  '禁書目錄',
  '歐美',
  'Cosplay',
  '重口地帶',
];

/// 分类过滤底部弹窗
class _CategoryFilterSheet extends StatefulWidget {
  const _CategoryFilterSheet({required this.selected, required this.onApply});

  final List<String> selected;
  final ValueChanged<List<String>> onApply;

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  late final List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16, vertical: metrics.kSpace12),
            child: Row(
              children: [
                Text('分类过滤', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('清空'),
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onApply(List<String>.from(_selected));
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.all(metrics.kSpace12),
              children: [
                Wrap(
                  spacing: scaleW(8),
                  runSpacing: scaleW(6),
                  children: _kPicAcgCategories.map((cat) {
                    final selected = _selected.contains(cat);
                    return FilterChip(
                      label: Text(cat, style: theme.textTheme.bodySmall),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selected.add(cat);
                        } else {
                          _selected.remove(cat);
                        }
                      }),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
