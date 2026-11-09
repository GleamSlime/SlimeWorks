// Manga 主页 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_error_text.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

class MangaHomeViewModel extends BaseViewModel {
  final MangaService _service = getIt<MangaService>();

  /// 首页推荐集合
  final RxList<MangaCollection> collections = <MangaCollection>[].obs;

  /// 随机漫画
  final RxList<MangaComic> randomComics = <MangaComic>[].obs;

  /// 当前用户
  Rx<MangaUser?> currentUser = Rx<MangaUser?>(null);

  /// 是否已登录
  bool get isLoggedIn => _service.isLoggedIn;

  /// 是否正在追加随机漫画
  final RxBool isLoadingMoreRandom = false.obs;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    currentUser.value = _service.currentUser;
    await loadHomeData();
  }

  /// 加载主页数据
  Future<void> loadHomeData() async {
    if (!isLoggedIn) return;
    setLoading(true);
    try {
      final results = await Future.wait([_service.getCollections(), _service.getRandomComics()]);
      collections.value = results[0] as List<MangaCollection>;
      randomComics.value = results[1] as List<MangaComic>;
      clearError();
      _prefetchCovers();
    } catch (e) {
      setError(MangaErrorText.describe(e));
    } finally {
      setLoading(false);
    }
  }

  /// 滚动到底部时追加一批随机漫画
  Future<void> loadMoreRandom() async {
    if (!isLoggedIn) return;
    if (isLoadingMoreRandom.value) return;
    isLoadingMoreRandom.value = true;
    try {
      final more = await _service.getRandomComics();
      randomComics.addAll(more);
      _prefetchCovers(more);
    } catch (_) {
      // load-more 失败时静默忽略
    } finally {
      isLoadingMoreRandom.value = false;
    }
  }

  /// 「换一批」：替换当前随机推荐，不影响全局加载状态
  Future<void> refreshRandom() async {
    if (!isLoggedIn) return;
    if (isLoadingMoreRandom.value) return;
    isLoadingMoreRandom.value = true;
    try {
      final fresh = await _service.getRandomComics();
      randomComics.value = fresh;
      _prefetchCovers(fresh);
    } catch (_) {
    } finally {
      isLoadingMoreRandom.value = false;
    }
  }

  /// 登录回调（登录成功后刷新页面）
  Future<void> onLoginSuccess() async {
    currentUser.value = _service.currentUser;
    await loadHomeData();
  }

  /// 首屏预取上限：只预取首屏可视区数量的封面，
  /// 避免一次性把 collections + random 全部（轻松 100~200 张）同时预取（审计 #8）
  static const int _kFirstScreenPrefetchCount = 24;

  /// 后台预取封面图，加速卡片首次显示速度
  /// [comics] 为空时预取首屏内容：随机推荐 + 精选集合按展示顺序取前 [_kFirstScreenPrefetchCount] 张；
  /// 滚动加载更多 / 换一批时由调用方传入新批次，同样不超过首屏上限
  void _prefetchCovers([List<MangaComic>? comics]) {
    final list = (comics ??
            [
              ...randomComics,
              for (final c in collections) ...c.comics,
            ])
        .take(_kFirstScreenPrefetchCount)
        .toList();
    _service.prefetchImages(list.map((c) => c.thumb).toList());
  }
}
