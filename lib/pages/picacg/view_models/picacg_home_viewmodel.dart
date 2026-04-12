/// PicACG 主页 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

class PicAcgHomeViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 首页推荐集合
  final RxList<PicAcgCollection> collections = <PicAcgCollection>[].obs;

  /// 随机漫画
  final RxList<PicAcgComic> randomComics = <PicAcgComic>[].obs;

  /// 当前用户
  Rx<PicAcgUser?> currentUser = Rx<PicAcgUser?>(null);

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
      collections.value = results[0] as List<PicAcgCollection>;
      randomComics.value = results[1] as List<PicAcgComic>;
      clearError();
      _prefetchCovers();
    } catch (e) {
      setError(e.toString());
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

  /// 后台预取封面图，加速卡片首次显示速度
  void _prefetchCovers([List<PicAcgComic>? comics]) {
    final list = comics ?? [...randomComics, for (final c in collections) ...c.comics];
    _service.prefetchImages(list.map((c) => c.thumb).toList());
  }
}
