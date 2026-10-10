import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_comic_detail_viewmodel.dart';

/// 上游章节分页桩：每页按"倒序"原样返回（与线上行为一致），并可指定某页失败
class _PagedMangaService implements MangaService {
  _PagedMangaService({required this.pages, this.failPage});

  /// 每页的章节，页内顺序即上游顺序（倒序）
  final List<List<MangaEps>> pages;

  /// 指定第几页抛错，用于验证补页失败不动已渲染的列表
  final int? failPage;

  /// 被请求过的页码（按发起顺序）
  final List<int> requested = [];

  int get requestedPageCount => requested.length;

  @override
  Future<MangaComic> getComicDetail(String comicId) async =>
      MangaComic.fromJson({'_id': comicId, 'title': '测试本子'});

  @override
  Future<MangaEpsList> getComicEps(String comicId, {int page = 1}) async {
    requested.add(page);
    if (failPage == page) {
      throw Exception('网络错误: error sending request caused by: tcp connect error');
    }
    return MangaEpsList(
      eps: pages[page - 1],
      pagination: MangaPagination(
        total: pages.expand((e) => e).length,
        limit: 20,
        page: page,
        pages: pages.length,
      ),
    );
  }

  @override
  Future<List<MangaComic>> getComicRecommendations(String comicId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<MangaEps> _page(int startOrder, int count) => [
  // order 从大到小：上游每页就是最新章在前
  for (int o = startOrder; o > startOrder - count; o--)
    MangaEps(id: 'e$o', title: '第$o话', order: o, updatedAt: ''),
];

Future<MangaComicDetailViewModel> _openDetail(_PagedMangaService service) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  getIt.registerSingleton<MangaService>(service);
  return MangaComicDetailViewModel();
}

void main() {
  group('漫画详情章节列表', () {
    test('首屏就是倒序，补齐后续页后前 20 章的位置不变', () async {
      final service = _PagedMangaService(pages: [_page(40, 20), _page(20, 20)]);
      final vm = await _openDetail(service);
      try {
        await vm.loadDetail('c1');
        final firstScreen = vm.epsDesc.map((e) => e.order).toList();
        expect(firstScreen, List.generate(20, (i) => 40 - i));

        await vm.loadMoreEps();
        final after = vm.epsDesc.map((e) => e.order).toList();
        expect(after.length, 40);
        // 翻车的写法是补齐后整表按升序落库直接给界面用，这里必须仍然是降序
        expect(after, List.generate(40, (i) => 40 - i));
        expect(after.sublist(0, 20), firstScreen);
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });

    test('滚到底自动补下一页，同一页不会被重复请求', () async {
      final service = _PagedMangaService(pages: [_page(60, 20), _page(40, 20), _page(20, 20)]);
      final vm = await _openDetail(service);
      try {
        await vm.loadDetail('c1');
        expect(service.requestedPageCount, 1);
        expect(vm.hasMoreEps, isTrue);

        // 两次并发触发（滚动帧连着发）只该产生一次请求
        await Future.wait([vm.loadMoreEps(), vm.loadMoreEps()]);
        expect(service.requested, [1, 2]);
        expect(vm.eps.length, 40);

        await vm.loadMoreEps();
        expect(service.requested, [1, 2, 3]);
        expect(vm.hasMoreEps, isFalse);
        await vm.loadMoreEps();
        expect(service.requested, [1, 2, 3]);
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });

    test('ensureAllEps 把剩余页补齐且只补齐一次', () async {
      final service = _PagedMangaService(pages: [_page(60, 20), _page(40, 20), _page(20, 20)]);
      final vm = await _openDetail(service);
      try {
        await vm.loadDetail('c1');
        await vm.ensureAllEps();
        expect(service.requested, [1, 2, 3]);
        expect(vm.eps.length, 60);
        await vm.ensureAllEps();
        expect(service.requested, [1, 2, 3]);
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });

    test('补页失败只出提示，已渲染的章节不丢、也不再空转重试', () async {
      final service = _PagedMangaService(pages: [_page(60, 20), _page(40, 20)], failPage: 2);
      final vm = await _openDetail(service);
      try {
        await vm.loadDetail('c1');
        await vm.ensureAllEps();
        expect(vm.eps.length, 20);
        expect(vm.isLoadingEpsPage, isFalse);
        // 一句话文案，不是异常原文
        expect(vm.errorMessage, '连不上服务器，试试切换分流节点');
      } finally {
        vm.onClose();
        getIt.unregister<MangaService>();
      }
    });
  });
}
