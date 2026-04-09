library;

/// PicACG 收藏夹 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 收藏夹状态管理
class PicAcgFavouritesViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 收藏漫画列表
  final RxList<PicAcgComic> comics = <PicAcgComic>[].obs;

  /// 分页信息
  final Rx<PicAcgPagination?> pagination = Rx<PicAcgPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  int _currentPage = 1;
  PicAcgSortOrder _sort = PicAcgSortOrder.dateDescending;

  PicAcgSortOrder get sort => _sort;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await refresh();
  }

  /// 刷新收藏列表（可更换排序方式）
  @override
  Future<void> refresh({PicAcgSortOrder? sort}) async {
    _sort = sort ?? _sort;
    _currentPage = 1;
    comics.clear();
    setLoading(true);
    try {
      final result = await _service.getFavourites(page: 1, sort: _sort);
      comics.assignAll(result.comics);
      pagination.value = result.pagination;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
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
      final result = await _service.getFavourites(page: _currentPage, sort: _sort);
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
