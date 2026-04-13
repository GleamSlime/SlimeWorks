library;

/// PicACG 漫画详情 ViewModel

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 阅读进度记录
class PicAcgReadProgress {
  final int epsOrder;
  final String epsTitle;

  const PicAcgReadProgress({required this.epsOrder, required this.epsTitle});
}

/// 漫画详情状态管理
class PicAcgComicDetailViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 漫画完整信息
  PicAcgComic? comic;

  /// 章节列表
  List<PicAcgEps> eps = [];

  /// 章节分页
  PicAcgPagination? epsPagination;

  /// 是否已收藏（响应式，支持 Obx 监听）
  final RxBool isFavourite = false.obs;

  /// 是否已点赞
  final RxBool isLiked = false.obs;

  /// 点赞数（可变，点击后立即更新 UI）
  final RxInt likesCount = 0.obs;

  /// 推荐漫画（"看过这本的人也在看"）
  final RxList<PicAcgComic> recommendations = <PicAcgComic>[].obs;

  /// 上次阅读进度
  final Rx<PicAcgReadProgress?> lastReadProgress = Rx<PicAcgReadProgress?>(null);

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
      isFavourite.value = comic?.isFavourite ?? false;
      isLiked.value = comic?.isLiked ?? false;
      likesCount.value = comic?.likesCount ?? 0;
      clearError();

      // 后台加载推荐 + 进度（不阻塞主加载）
      _loadRecommendations(comicId);
      _loadReadProgress(comicId);
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  /// 后台加载推荐
  Future<void> _loadRecommendations(String comicId) async {
    try {
      final list = await _service.getComicRecommendations(comicId);
      recommendations.assignAll(list);
    } catch (_) {}
  }

  /// 从 SharedPreferences 读取上次阅读进度
  Future<void> _loadReadProgress(String comicId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('picacg_progress_$comicId');
      if (raw == null) return;
      final parts = raw.split(':');
      if (parts.length < 2) return;
      final epsOrder = int.tryParse(parts[0]);
      if (epsOrder == null) return;
      // 找到对应章节标题
      // eps 可能还未加载完，用 parts[1] 作为 title 备用
      final epsTitle = parts.length >= 3 ? parts[2] : '第$epsOrder话';
      lastReadProgress.value = PicAcgReadProgress(epsOrder: epsOrder, epsTitle: epsTitle);
    } catch (_) {}
  }

  /// 切换收藏状态（乐观更新：先更新 UI，失败后回退）
  Future<void> toggleFavourite(String comicId) async {
    final prev = isFavourite.value;
    isFavourite.value = !prev;
    try {
      await _service.toggleFavourite(comicId);
    } catch (e) {
      isFavourite.value = prev;
      setError(e.toString());
    }
  }

  /// 切换点赞状态
  Future<void> toggleLike(String comicId) async {
    // 乐观 UI：先更新，失败再回退
    final wasLiked = isLiked.value;
    isLiked.value = !wasLiked;
    likesCount.value += wasLiked ? -1 : 1;
    try {
      await _service.toggleLike(comicId);
    } catch (_) {
      isLiked.value = wasLiked;
      likesCount.value += wasLiked ? 1 : -1;
    }
  }
}
