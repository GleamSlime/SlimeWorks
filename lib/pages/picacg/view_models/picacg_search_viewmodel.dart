library;

/// PicACG 搜索 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 搜索结果状态管理
class PicAcgSearchViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 搜索结果列表
  final RxList<PicAcgComic> results = <PicAcgComic>[].obs;

  /// 分页信息
  final Rx<PicAcgPagination?> pagination = Rx<PicAcgPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  String _keyword = '';
  String _category = '';
  int _currentPage = 1;
  PicAcgSortOrder _sort = PicAcgSortOrder.dateDescending;

  String get keyword => _keyword;
  String get category => _category;
  PicAcgSortOrder get sort => _sort;

  /// 执行搜索（重置到第一页）
  Future<void> search({
    required String keyword,
    String category = '',
    PicAcgSortOrder sort = PicAcgSortOrder.dateDescending,
  }) async {
    _keyword = keyword;
    _category = category;
    _sort = sort;
    _currentPage = 1;
    results.clear();
    setLoading(true);
    try {
      final list = await _service.searchComics(
        keyword: keyword,
        categories: category.isNotEmpty ? [category] : [],
        page: 1,
        sort: sort,
      );
      results.assignAll(list.comics);
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
        categories: _category.isNotEmpty ? [_category] : [],
        page: _currentPage,
        sort: _sort,
      );
      results.addAll(list.comics);
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
