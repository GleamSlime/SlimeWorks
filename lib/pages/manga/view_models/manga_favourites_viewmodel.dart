library;

/// Manga 收藏夹 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

/// 收藏夹状态管理
class MangaFavouritesViewModel extends BaseViewModel {
  final MangaService _service = getIt<MangaService>();

  /// 收藏漫画列表
  final RxList<MangaComic> comics = <MangaComic>[].obs;

  /// 分页信息
  final Rx<MangaPagination?> pagination = Rx<MangaPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  int _currentPage = 1;
  final Rx<MangaSortOrder> _sort = MangaSortOrder.dateDescending.obs;
  bool _isRefreshing = false;

  MangaSortOrder get sort => _sort.value;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await refresh();
  }

  /// 刷新收藏列表（可更换排序方式）
  @override
  Future<void> refresh({MangaSortOrder? sort}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _sort.value = sort ?? _sort.value;
    _currentPage = 1;
    comics.clear();
    setLoading(true);
    try {
      final result = await _service.getFavourites(page: 1, sort: _sort.value);
      comics.assignAll(result.comics);
      pagination.value = result.pagination;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
      _isRefreshing = false;
    }
  }

  /// 加载下一页收藏
  Future<void> loadMore() async {
    final p = pagination.value;
    if (p == null || _currentPage >= p.pages || isLoadingMore.value) {
      return;
    }

    isLoadingMore.value = true;
    try {
      _currentPage++;
      final result = await _service.getFavourites(page: _currentPage, sort: _sort.value);
      comics.addAll(result.comics);
      pagination.value = result.pagination;
    } catch (_) {
      _currentPage--;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// 是否还有更多收藏
  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentPage < p.pages;
  }
}
