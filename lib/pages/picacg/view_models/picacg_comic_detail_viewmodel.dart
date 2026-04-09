library;

/// PicACG 漫画详情 ViewModel

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 漫画详情状态管理
class PicAcgComicDetailViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 漫画完整信息
  PicAcgComic? comic;

  /// 章节列表
  List<PicAcgEps> eps = [];

  /// 章节分页
  PicAcgPagination? epsPagination;

  /// 是否已收藏
  bool isFavourite = false;

  /// 加载漫画详情和章节列表
  Future<void> loadDetail(String comicId) async {
    setLoading(true);
    try {
      final results = await Future.wait([
        _service.getComicDetail(comicId),
        _service.getComicEps(comicId, page: 1),
      ]);
      comic = results[0] as PicAcgComic;
      final epsList = results[1] as PicAcgEpsList;
      eps = epsList.eps;
      epsPagination = epsList.pagination;
      isFavourite = comic?.isFavourite ?? false;
      clearError();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  /// 切换收藏状态
  Future<void> toggleFavourite(String comicId) async {
    try {
      await _service.toggleFavourite(comicId);
      isFavourite = !isFavourite;
      update();
    } catch (e) {
      setError(e.toString());
    }
  }
}
