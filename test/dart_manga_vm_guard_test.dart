// Manga 页面层两个"静默失效"缺陷的回归测试
//
// 1) MangaFavouritesViewModel 曾把"重新拉数据"命名为 refresh()，覆写了
//    GetX 的 ListNotifierMixin.refresh：GetxController.update() 内部正是调
//    refresh() 通知监听者，覆写后 update() 走成"重新联网拉一遍"而不是通知
//    界面 —— 收藏加载失败时永远看不到错误态与重试按钮。已改名 reload()。
// 2) MangaSearchViewModel.loadMore 缺在飞保护：滚动帧会连着触发多次，
//    每次都会 _currentPage++ 并发请求，结果集乱序/重复。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_favourites_viewmodel.dart';
import 'package:slime_works/pages/manga/view_models/manga_search_viewmodel.dart';

MangaComicList _list(List<String> ids, {int page = 1, int pages = 3}) => MangaComicList(
  comics: [
    for (final id in ids) MangaComic.fromJson({'_id': id, 'title': id}),
  ],
  pagination: MangaPagination(total: 99, limit: 20, page: page, pages: pages),
);

/// 收藏桩：按需返回结果或抛错，并记录请求页码
class _FavouritesService implements MangaService {
  _FavouritesService({this.fail = false});

  final bool fail;
  final List<int> requested = [];

  @override
  Future<MangaComicList> getFavourites({
    int page = 1,
    MangaSortOrder sort = MangaSortOrder.dateDescending,
  }) async {
    requested.add(page);
    if (fail) throw Exception('网络错误: tcp connect error');
    return _list(['c1', 'c2']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 搜索桩：每页返回本页专属的两条，页间不重叠，用于检测乱序/重复
class _SearchService implements MangaService {
  final List<int> requested = [];

  @override
  Future<MangaComicList> searchComics({
    required String keyword,
    List<String> categories = const [],
    int page = 1,
    MangaSortOrder sort = MangaSortOrder.dateDescending,
  }) async {
    requested.add(page);
    // 让不同页的返回顺序可交换：页码越大延迟越短
    await Future<void>.delayed(Duration(milliseconds: 40 - page * 10));
    return _list(['p${page}a', 'p${page}b'], page: page);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('收藏夹错误态可达', () {
    test('加载失败后监听者被通知（错误态能显示出来）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      getIt.registerSingleton<MangaService>(_FavouritesService(fail: true));
      final vm = MangaFavouritesViewModel();
      var notifications = 0;
      vm.addListener(() => notifications++);
      try {
        await vm.reload();
        expect(vm.errorMessage, isNotNull, reason: '错误信息必须落到 VM 上');
        expect(
          notifications,
          greaterThan(0),
          reason: 'update() 必须真正通知监听者，否则页面看不到错误态与重试按钮',
        );
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });
  });

  group('搜索结果分页在飞保护', () {
    test('同一帧连续触发只请求一页，结果不重复不乱序', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = _SearchService();
      getIt.registerSingleton<MangaService>(service);
      final vm = MangaSearchViewModel();
      try {
        await vm.search(keyword: '测试');
        expect(service.requested, [1]);

        // 滚动监听会在一帧里连着打好几次
        await Future.wait([vm.loadMore(), vm.loadMore(), vm.loadMore()]);
        expect(service.requested, [1, 2], reason: '在飞期间重复触发不应再请求新页');
        expect(vm.results.map((c) => c.id).toList(), ['p1a', 'p1b', 'p2a', 'p2b']);
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });
  });
}
