// P2-2(c)：远程缩略图超时兜底要退避，不能每次重建都再打一次原图。
//
// 慢节点下同一屏会反复超时，兜底打的又是原图（解码最吃内存）。
// 退避策略本身是纯逻辑，这里钉住三件事：
// 1) 第一轮仍是 2s（与旧行为一致，不把首屏体验改坏）；
// 2) 连续失败按 2s → 4s → 8s 拉长；
// 3) 到上限后彻底放弃兜底，而不是无限重试。
// 另外用 Widget 侧断言：tile 在退避窗口内确实不再切到兜底源。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';

const String kThumb = 'http://127.0.0.1:1/node/media?path=/a.jpg&width=240&mode=cover';
const String kOriginal = 'http://127.0.0.1:1/node/media?path=/a.jpg&width=240';

// stale onError 回归专用：与上面 a.jpg 区分，避免污染进程级退避表
const String kThumbA = 'http://127.0.0.1:1/node/media?path=/ra.jpg&width=240&mode=cover';
const String kOriginalA = 'http://127.0.0.1:1/node/media?path=/ra.jpg&width=240';
const String kThumbB = 'http://127.0.0.1:1/node/media?path=/rb.jpg&width=240&mode=cover';
const String kOriginalB = 'http://127.0.0.1:1/node/media?path=/rb.jpg&width=240';

// 受控 HttpClient：按 URL 决定 precache 何时失败，用于制造「回收后才回调」的 stale onError。
// 表里有 completer 的 URL 等放行后回 404；不在表里的 URL 永远挂起（不回调，免干扰新 item）。
class _CtrlHttpClient implements HttpClient {
  _CtrlHttpClient(this.failures);
  final Map<String, Completer<void>> failures;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _CtrlRequest(url.toString(), failures);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CtrlRequest implements HttpClientRequest {
  _CtrlRequest(this.url, this.failures);
  final String url;
  final Map<String, Completer<void>> failures;
  @override
  Future<HttpClientResponse> close() {
    final gate = failures[url];
    if (gate == null) return Completer<HttpClientResponse>().future; // 永远挂起
    return gate.future.then((_) => _FailResponse());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FailResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.notFound;
  @override
  Future<E> drain<E>([E? defaultValue]) => Future<E>.value(defaultValue as E);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

media_api.MediaItem imageItem() => media_api.MediaItem(
  id: 'i1',
  collectionId: 'rc1',
  title: 'a.jpg',
  filePath: '/node/rc1/a.jpg',
  kind: media_api.MediaKind.image,
  fileSize: BigInt.from(1024),
  modifiedAt: 0,
  width: 4000,
  height: 3000,
  order: 0,
);

/// 当前这一格实际请求的图片 URL（远程源一定是 NetworkImage）
String? currentUrl(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isEmpty) return null;
  final provider = images.first.image;
  final inner = provider is ResizeImage ? provider.imageProvider : provider;
  return inner is NetworkImage ? inner.url : null;
}

/// 可复用的宿主树：回收用例靠 pumpWidget 换 source 触发 didUpdateWidget
Widget tileApp(String src, String fallback) {
  return ScreenUtilInit(
    designSize: const Size(600, 600),
    builder: (context, _) {
      AppTheme.resetMetrics();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 260,
              child: MediaItemTile(
                item: imageItem(),
                source: src,
                coverFallbackSource: fallback,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> mount(WidgetTester tester, String fallback, {String src = kThumb}) async {
  tester.view.physicalSize = const Size(600, 600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(tileApp(src, fallback));
  await tester.pump();
}

void main() {
  group('CoverFallbackBackoff 策略', () {
    test('首次 2s，随后翻倍', () {
      final backoff = CoverFallbackBackoff();
      const String url = 'u1';
      final t0 = DateTime(2026, 1, 1, 12);
      expect(backoff.delayFor(url, now: t0), const Duration(seconds: 2));

      backoff.recordAttempt(url, now: t0);
      expect(backoff.delayFor(url, now: t0), const Duration(seconds: 4));

      backoff.recordAttempt(url, now: t0);
      expect(backoff.delayFor(url, now: t0), const Duration(seconds: 8));
    });

    test('到上限后放弃兜底（返回 null）', () {
      final backoff = CoverFallbackBackoff();
      const String url = 'u2';
      final t0 = DateTime(2026, 1, 1, 12);
      for (int i = 0; i < 3; i++) {
        backoff.recordAttempt(url, now: t0);
      }
      expect(backoff.attemptsOf(url), 3);
      expect(backoff.delayFor(url, now: t0), isNull);
    });

    test('过了窗口重新计数（节点恢复后不必等完整退避）', () {
      final backoff = CoverFallbackBackoff();
      const String url = 'u3';
      final t0 = DateTime(2026, 1, 1, 12);
      for (int i = 0; i < 3; i++) {
        backoff.recordAttempt(url, now: t0);
      }
      expect(backoff.delayFor(url, now: t0), isNull);
      // 超过 window（5 分钟）后当作新一轮
      final later = t0.add(const Duration(minutes: 6));
      expect(backoff.delayFor(url, now: later), const Duration(seconds: 2));
    });

    test('不同 URL 各自独立计数', () {
      final backoff = CoverFallbackBackoff();
      final t0 = DateTime(2026, 1, 1, 12);
      backoff.recordAttempt('a', now: t0);
      backoff.recordAttempt('a', now: t0);
      expect(backoff.delayFor('a', now: t0), const Duration(seconds: 8));
      expect(backoff.delayFor('b', now: t0), const Duration(seconds: 2));
    });

    test('记录量不会无限增长（过期条目被清、极多时整体清空）', () {
      final backoff = CoverFallbackBackoff();
      final t0 = DateTime(2026, 1, 1, 12);
      for (int i = 0; i < 300; i++) {
        backoff.recordAttempt('k$i', now: t0);
      }
      // 300 > 256 触发清理；全部都在窗口内，故条数仍可能偏多，但不应崩
      expect(backoff.attemptsOf('k0'), lessThanOrEqualTo(1));
      final later = t0.add(const Duration(minutes: 10));
      for (int i = 0; i < 300; i++) {
        backoff.recordAttempt('j$i', now: later);
      }
      // 旧条目已过期被清掉，新条目正常记
      expect(backoff.attemptsOf('k0'), 0);
      expect(backoff.attemptsOf('j0'), 1);
    });
  });

  group('MediaItemTile 兜底闸门', () {
    setUp(() {
      if (!getIt.isRegistered<MediaPrefsService>()) {
        getIt.registerSingleton<MediaPrefsService>(MediaPrefsService());
      }
    });

    tearDown(() {
      if (getIt.isRegistered<MediaPrefsService>()) {
        getIt.unregister<MediaPrefsService>();
      }
    });

    testWidgets('首轮 2s 超时后切到兜底源', (tester) async {
      await mount(tester, kOriginal);
      expect(currentUrl(tester), kThumb, reason: '刚挂载时先请求缩略图');

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(currentUrl(tester), kOriginal, reason: '2s 未就绪 → 临时用兜底源');
    });

    testWidgets('回收后旧 src 的 stale onError 不取消新 item 的兜底计时器', (tester) async {
      // A 可控失败、B 永远挂起：放行 A 时 widget 已回收成 B，onError(A) 即 stale
      final failures = <String, Completer<void>>{kThumbA: Completer<void>()};
      debugNetworkImageHttpClientProvider = () => _CtrlHttpClient(failures);
      addTearDown(() => debugNetworkImageHttpClientProvider = null);

      await mount(tester, kOriginalA, src: kThumbA);
      // 先烧掉 A 的首轮 2s 兜底，让 A 退避=1（下次 4s），放大 stale 污染的可观测差
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // 回收成 B：didUpdateWidget 重置并起 B 的 2s 兜底计时器
      await tester.pumpWidget(tileApp(kThumbB, kOriginalB));
      await tester.pump();

      // 放行 A 的失败 → 旧闭包 onError(A) 此时才回调（widget.source 已是 B）
      failures[kThumbA]!.complete();
      await tester.pump();
      await tester.pump();

      // B 的 2s 兜底应独立生效；若被 A 的 stale onError 取消/改成 4s，这里就切不到兜底
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(currentUrl(tester), kOriginalB,
          reason: 'stale onError 不得取消新 item 计时器或把退避记到旧 URL');

      // 框架在测试体结束时校验 painting 调试变量已复位，须在此显式清掉（tearDown 太晚）
      debugNetworkImageHttpClientProvider = null;
    });
  });
}
