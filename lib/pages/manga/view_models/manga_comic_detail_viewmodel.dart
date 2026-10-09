library;

/// Manga 漫画详情 ViewModel

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

/// 阅读进度记录
class MangaReadProgress {
  final int epsOrder;
  final String epsTitle;

  const MangaReadProgress({required this.epsOrder, required this.epsTitle});
}

/// 漫画详情状态管理
class MangaComicDetailViewModel extends BaseViewModel {
  final MangaService _service = getIt<MangaService>();

  /// 漫画完整信息
  MangaComic? comic;

  /// 章节列表
  List<MangaEps> eps = [];

  /// 章节分页
  MangaPagination? epsPagination;

  /// 章节补齐任务的句柄（上游分页只给 20 章；重进详情或换漫画要重新置空）
  Future<void>? _epsAllLoading;

  /// 当前详情页对应的漫画 id
  String _comicId = '';

  /// 是否已收藏（响应式，支持 Obx 监听）
  final RxBool isFavourite = false.obs;

  /// 是否已点赞
  final RxBool isLiked = false.obs;

  /// 点赞数（可变，点击后立即更新 UI）
  final RxInt likesCount = 0.obs;

  /// 推荐漫画（"看过这本的人也在看"）
  final RxList<MangaComic> recommendations = <MangaComic>[].obs;

  /// 上次阅读进度
  final Rx<MangaReadProgress?> lastReadProgress = Rx<MangaReadProgress?>(null);

  /// 加载漫画详情和章节列表
  Future<void> loadDetail(String comicId) async {
    setLoading(true);
    _comicId = comicId;
    // 换本子/重试都要重新补齐章节，否则 ensureAllEps 会拿着上一本的完成标记直接返回
    _epsAllLoading = null;
    try {
      final results = await Future.wait([
        _service.getComicDetail(comicId),
        _service.getComicEps(comicId, page: 1),
      ]);
      comic = results[0] as MangaComic;
      final epsList = results[1] as MangaEpsList;
      eps = epsList.eps;
      epsPagination = epsList.pagination;
      isFavourite.value = comic?.isFavourite ?? false;
      isLiked.value = comic?.isLiked ?? false;
      likesCount.value = comic?.likesCount ?? 0;
      clearError();

      // 后台加载推荐 + 进度（不阻塞主加载）
      _loadRecommendations(comicId);
      _loadReadProgress(comicId);
      // 章节分页补齐：首屏只有第 1 页那 20 章，剩下的静默拉完才算全量
      ensureAllEps();
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  /// 把章节列表补齐成全量（已在补齐中就等它，补齐过就直接返回）
  ///
  /// 下载弹层的"全选"与章节计数都要吃全量，调用点在弹层打开前 await 这一句，
  /// 免得用户以为下载整本、实际只排了前 20 章。
  Future<void> ensureAllEps() {
    if (_comicId.isEmpty || eps.isEmpty) return Future.value();
    return _epsAllLoading ??= () async {
      final pagination = epsPagination;
      if (pagination == null || pagination.pages <= 1) return;
      final all = await _service.getComicEpsAll(
        _comicId,
        MangaEpsList(eps: eps, pagination: pagination),
      );
      if (isClosed) return;
      eps = all;
      update();
    }();
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
      final raw = prefs.getString('manga_progress_$comicId');
      if (raw == null) return;
      final parts = raw.split(':');
      if (parts.length < 2) return;
      final epsOrder = int.tryParse(parts[0]);
      if (epsOrder == null) return;
      // 找到对应章节标题
      // eps 可能还未加载完，用 parts[1] 作为 title 备用
      final epsTitle = parts.length >= 3 ? parts[2] : '第$epsOrder话';
      lastReadProgress.value = MangaReadProgress(epsOrder: epsOrder, epsTitle: epsTitle);
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
