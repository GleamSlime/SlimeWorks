library;

/// Manga 漫画详情 ViewModel

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_error_text.dart';
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

  /// 章节列表（规范序：order 升序）
  ///
  /// 下载排队与"这一章在第几页"都按这条序推进；界面一律读 [epsDesc]，
  /// 不要在这一份数据上就地反转。
  List<MangaEps> eps = [];

  /// 展示序：最新一章在最前
  ///
  /// 上游每页都是倒序返回，页与页接起来仍是倒序；补齐后续页只做尾部追加，
  /// 所以从首屏到全量看到的是同一份顺序，不会"加载完突然整表翻面"。
  List<MangaEps> get epsDesc => eps.reversed.toList();

  /// 已加载到的上游页码（上游每页只给 20 章）
  int _epsPage = 0;

  /// 上游章节总页数
  int _epsTotalPages = 1;

  /// 当前在飞的章节分页请求（滚动触发与下载弹层共用同一页，别重复发）
  Future<void>? _epsPageLoading;

  /// 章节分页是否正在补（章节表尾部那条 loading 指示读这里）
  bool _isLoadingEpsPage = false;

  /// 是否还有没加载的章节页
  bool get hasMoreEps => _epsPage < _epsTotalPages;

  bool get isLoadingEpsPage => _isLoadingEpsPage;

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
    // 换本子/重试都要把分页游标归零，否则 loadMoreEps 会接着上一本的页码往下走
    _epsPage = 0;
    _epsTotalPages = 1;
    _epsPageLoading = null;
    try {
      final results = await Future.wait([
        _service.getComicDetail(comicId),
        _service.getComicEps(comicId, page: 1),
      ]);
      comic = results[0] as MangaComic;
      final epsList = results[1] as MangaEpsList;
      eps = _ascending(epsList.eps);
      _epsPage = 1;
      _epsTotalPages = epsList.pagination.pages;
      isFavourite.value = comic?.isFavourite ?? false;
      isLiked.value = comic?.isLiked ?? false;
      likesCount.value = comic?.likesCount ?? 0;
      clearError();

      // 后台加载推荐 + 进度（不阻塞主加载）
      _loadRecommendations(comicId);
      _loadReadProgress(comicId);
      // 章节剩余分页不在这里抢跑：首屏只有第 1 页那 20 章，剩下的等滚到章节表
      // 尾部由 loadMoreEps 逐页补，几百章的本子不至于开机就连发十几个请求。
    } catch (e) {
      setError(MangaErrorText.describe(e));
    } finally {
      setLoading(false);
    }
  }

  /// 自动补下一页章节（章节表滚到底部触发）
  ///
  /// 只往尾部追加再按 order 重排：中途整表替换会把用户眼前的章节顺序翻面。
  Future<void> loadMoreEps() {
    if (_comicId.isEmpty || !hasMoreEps) return Future.value();
    return _epsPageLoading ??= () async {
      final page = _epsPage + 1;
      _isLoadingEpsPage = true;
      _notify();
      try {
        final next = await _service.getComicEps(_comicId, page: page);
        if (!isClosed) {
          eps = _ascending([...eps, ...next.eps]);
          _epsPage = page;
          _epsTotalPages = next.pagination.pages;
        }
      } catch (e) {
        // 补页失败只是看不全，别把已经渲染出来的整页打成错误页
        setError(MangaErrorText.describe(e));
      } finally {
        _isLoadingEpsPage = false;
        _epsPageLoading = null;
        _notify();
      }
    }();
  }

  void _notify() {
    if (!isClosed) update();
  }

  /// 把章节列表补齐成全量（已在补齐中就等它，补齐过就直接返回）
  ///
  /// 下载弹层的"全选"与章节计数都要吃全量，调用点在弹层打开前 await 这一句，
  /// 免得用户以为下载整本、实际只排了前 20 章。
  Future<void> ensureAllEps() async {
    if (_comicId.isEmpty || eps.isEmpty) return;
    while (hasMoreEps) {
      final before = _epsPage;
      await loadMoreEps();
      // 页码没推进说明这一页拉失败了，继续循环就是原地打转
      if (isClosed || _epsPage == before) return;
    }
  }

  /// 规范序：order 升序
  static List<MangaEps> _ascending(List<MangaEps> list) =>
      [...list]..sort((a, b) => a.order.compareTo(b.order));

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
      setError(MangaErrorText.describe(e));
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
