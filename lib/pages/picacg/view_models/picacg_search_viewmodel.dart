library;

/// PicACG 搜索 ViewModel

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/components/picacg_block_words_dialog.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 搜索历史存储 Key（SharedPreferences）
const String _kSearchHistoryKey = 'picacg_search_history';

/// 搜索历史最大条数
const int _kSearchHistoryMaxCount = 20;

/// 搜索结果状态管理
class PicAcgSearchViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 搜索结果列表（含屏蔽词过滤）
  final RxList<PicAcgComic> results = <PicAcgComic>[].obs;

  /// 搜索历史记录（最近 20 条）
  final RxList<String> searchHistory = <String>[].obs;

  /// 分页信息
  final Rx<PicAcgPagination?> pagination = Rx<PicAcgPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  /// 已选分类过滤
  final RxList<String> selectedCategories = <String>[].obs;

  /// 当前排序方式（Rx 以驱动 UI 响应）
  final Rx<PicAcgSortOrder> sort = PicAcgSortOrder.dateDescending.obs;

  String _keyword = '';
  int _currentPage = 1;

  String get keyword => _keyword;

  PicAcgSearchViewModel() {
    _loadHistory();
  }

  // ==================== 历史记录 ====================

  /// 从本地加载搜索历史
  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kSearchHistoryKey) ?? [];
      searchHistory.assignAll(list);
    } catch (e) {
      logger.log('加载搜索历史失败: $e');
    }
  }

  /// 保存关键词到搜索历史（去重 + 置顶 + 最多 20 条）
  Future<void> _addToHistory(String keyword) async {
    if (keyword.isEmpty) return;
    try {
      final list = List<String>.from(searchHistory);
      list.remove(keyword); // 去重
      list.insert(0, keyword); // 置顶
      if (list.length > _kSearchHistoryMaxCount) {
        list.removeRange(_kSearchHistoryMaxCount, list.length);
      }
      searchHistory.assignAll(list);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSearchHistoryKey, list);
    } catch (e) {
      logger.log('保存搜索历史失败: $e');
    }
  }

  /// 删除单条历史记录
  Future<void> removeHistory(String keyword) async {
    try {
      searchHistory.remove(keyword);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSearchHistoryKey, List<String>.from(searchHistory));
    } catch (e) {
      logger.log('删除搜索历史失败: $e');
    }
  }

  /// 清空所有搜索历史
  Future<void> clearHistory() async {
    try {
      searchHistory.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSearchHistoryKey);
    } catch (e) {
      logger.log('清空搜索历史失败: $e');
    }
  }

  // ==================== 搜索 ====================

  /// 执行搜索（重置到第一页）
  Future<void> search({
    required String keyword,
    List<String>? categories,
    PicAcgSortOrder? newSort,
  }) async {
    _keyword = keyword;
    if (categories != null) selectedCategories.assignAll(categories);
    if (newSort != null) sort.value = newSort;
    _currentPage = 1;
    results.clear();
    setLoading(true);
    try {
      if (keyword.isNotEmpty) {
        await _addToHistory(keyword);
      }
      final list = await _service.searchComics(
        keyword: keyword,
        categories: List<String>.from(selectedCategories),
        page: 1,
        sort: sort.value,
      );

      /// 加载屏蔽词配置并过滤结果
      final blockConfig = await PicAcgBlockWordsService.load();
      final filtered = list.comics
          .where(
            (c) => !PicAcgBlockWordsService.shouldBlock(
              title: c.title,
              categories: c.categories,
              tags: c.tags,
              config: blockConfig,
            ),
          )
          .toList();
      results.assignAll(filtered);
      pagination.value = list.pagination;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  /// 加载下一页搜索结果
  Future<void> loadMore() async {
    final p = pagination.value;
    if (p == null || _currentPage >= p.pages) return;
    isLoadingMore.value = true;
    try {
      _currentPage++;
      final list = await _service.searchComics(
        keyword: _keyword,
        categories: List<String>.from(selectedCategories),
        page: _currentPage,
        sort: sort.value,
      );

      /// 增量追加时同样应用屏蔽词过滤
      final blockConfig = await PicAcgBlockWordsService.load();
      final filtered = list.comics
          .where(
            (c) => !PicAcgBlockWordsService.shouldBlock(
              title: c.title,
              categories: c.categories,
              tags: c.tags,
              config: blockConfig,
            ),
          )
          .toList();
      results.addAll(filtered);
      pagination.value = list.pagination;
    } catch (e) {
      _currentPage--;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// 是否还有更多结果
  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentPage < p.pages;
  }
}
