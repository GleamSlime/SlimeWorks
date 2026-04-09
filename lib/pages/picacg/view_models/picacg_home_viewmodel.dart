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
    } catch (e) {
      setError(e.toString());
    } finally {
      setLoading(false);
    }
  }

  /// 登录回调（登录成功后刷新页面）
  Future<void> onLoginSuccess() async {
    currentUser.value = _service.currentUser;
    await loadHomeData();
  }
}
