// Manga 封面预取并发闸门 + 首页首屏预取上限（审计 #8）

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_home_viewmodel.dart';

void main() {
  group('PrefetchLimiter 并发闸门', () {
    test('同时在飞不超过上限，且全部任务最终完成', () async {
      const limit = 4;
      final limiter = PrefetchLimiter(limit);
      final completers = List.generate(10, (_) => Completer<int>());
      var started = 0;
      var maxInFlight = 0;
      var inFlight = 0;

      final futures = [
        for (var i = 0; i < completers.length; i++)
          limiter.run(() async {
            started++;
            inFlight++;
            if (inFlight > maxInFlight) maxInFlight = inFlight;
            try {
              return await completers[i].future;
            } finally {
              inFlight--;
            }
          }),
      ];

      // 放行微任务队列，让闸门把首批任务全部起飞
      await Future<void>.delayed(Duration.zero);
      expect(started, limit, reason: '首批只能起飞上限数量');
      expect(maxInFlight, limit);
      expect(limiter.activeCount, limit);
      expect(limiter.queuedCount, completers.length - limit);

      // 逐个放行，验证每完成一个只补位一个，始终不超限
      for (var i = 0; i < completers.length; i++) {
        completers[i].complete(i);
        await Future<void>.delayed(Duration.zero);
        expect(inFlight, lessThanOrEqualTo(limit));
        expect(maxInFlight, lessThanOrEqualTo(limit));
      }

      final results = await Future.wait(futures);
      expect(results, List.generate(10, (i) => i));
      expect(started, completers.length);
      expect(limiter.activeCount, 0);
      expect(limiter.queuedCount, 0);
    });

    test('任务抛异常也会释放空位，不卡死后续排队任务', () async {
      final limiter = PrefetchLimiter(1);
      final failed = limiter.run<int>(() async => throw StateError('预取失败'));
      await expectLater(failed, throwsStateError);

      final ok = await limiter.run(() async => 42);
      expect(ok, 42);
      expect(limiter.activeCount, 0);
      expect(limiter.queuedCount, 0);
    });

    test('上限为 1 时严格串行', () async {
      final limiter = PrefetchLimiter(1);
      final order = <int>[];
      final first = limiter.run(() async {
        order.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add(2);
      });
      final second = limiter.run(() async {
        order.add(3);
      });
      await Future.wait([first, second]);
      expect(order, [1, 2, 3]);
    });
  });

  group('Manga 首页首屏预取上限', () {
    late _RecordingMangaService service;
    late MangaHomeViewModel vm;

    setUp(() {
      service = _RecordingMangaService();
      getIt.registerSingleton<MangaService>(service);
      // 不走 onInitAsync（它会自动 loadHomeData），由用例显式控制加载时机
      vm = MangaHomeViewModel();
    });

    tearDown(() {
      getIt.unregister<MangaService>();
    });

    test('首屏只预取前 24 张，而不是全部 100+ 张', () async {
      await vm.loadHomeData();
      expect(service.prefetchedPaths.length, 24);
      // 展示顺序：随机推荐在前，集合在后；随机一批 60 张已超上限，全取自随机段
      expect(service.prefetchedPaths.first, 'r0');
      expect(service.prefetchedPaths.last, 'r23');
    });

    test('滚动加载更多只预取新批次', () async {
      await vm.loadHomeData();
      service.prefetchedPaths.clear();
      service.batchSize = 20;
      await vm.loadMoreRandom();
      expect(service.prefetchedPaths.length, 20);
      expect(service.prefetchedPaths.first, 'r0');
      expect(vm.randomComics.length, 80);
    });

    test('换一批只预取新一批的首屏数量', () async {
      await vm.loadHomeData();
      service.prefetchedPaths.clear();
      await vm.refreshRandom();
      // getRandomComics 桩每次返回 60 张，超过首屏上限时截断为 24
      expect(service.prefetchedPaths.length, 24);
    });
  });
}

MangaComic _comic(String path) => MangaComic.fromJson({
  '_id': path,
  'title': path,
  'thumb': {'path': path, 'fileServer': 'https://img.example'},
});

/// 记录预取调用的桩服务：绕过真实 FFI / 网络
class _RecordingMangaService implements MangaService {
  final List<String> prefetchedPaths = [];

  /// 每次 getRandomComics 返回的批量（模拟上游一页数量，可被用例调整）
  int batchSize = 60;

  @override
  bool get isLoggedIn => true;

  @override
  MangaUser? get currentUser => null;

  @override
  Future<List<MangaCollection>> getCollections() async => [
    MangaCollection(title: '精选', comics: List.generate(40, (i) => _comic('c$i'))),
  ];

  @override
  Future<List<MangaComic>> getRandomComics() async =>
      List.generate(batchSize, (i) => _comic('r$i'));

  @override
  void prefetchImages(List<MangaImage> images) {
    prefetchedPaths.addAll(images.map((e) => e.path));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}