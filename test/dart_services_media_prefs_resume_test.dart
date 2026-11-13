// P2-16 回归：视频续播位置不能每秒全量写盘。
//
// 播放器每秒 tick 一次调 setVideoResumePosition，旧实现每 tick 都整体
// jsonEncode 整张表 + 写 SharedPreferences。这里用 fakeAsync 快进 60 秒，
// 断言写盘次数被节流住（同一条目进度前进不触发写盘），并且显式 flush
// （暂停/退出时调用）一定会把最后一段进度落盘。
import 'dart:convert';

// fake_async 是 flutter_test 的传递依赖，测试里直接用（项目其他测试同做法）
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keyResume = 'media_video_resume_positions';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('续播位置节流落盘（P2-16）', () {
    test('60 次 tick（每秒一次）写盘次数 ≤ 6', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        final baseline = svc.resumePersistCount;

        // 同一条目每秒推进 1 秒进度，共 60 秒
        for (var i = 1; i <= 60; i++) {
          svc.setVideoResumePosition('/movies/a.mp4', 30000 + i * 1000);
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        final writes = svc.resumePersistCount - baseline;
        expect(writes, lessThanOrEqualTo(6),
            reason: '10s 节流下 60s 最多写 6 次，实测 $writes 次');
        // 内存里的值必须始终是最新的（节流只影响落盘，不影响读取）
        expect(svc.videoResumePosition('/movies/a.mp4'), 90000);
      });
    });

    test('退出时 flush 一次：最后一段进度不丢', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();

        // 连续 20 次推进，中间不跨越落盘边界（每次 100ms）
        for (var i = 1; i <= 20; i++) {
          svc.setVideoResumePosition('/movies/b.mp4', 40000 + i * 100);
          async.elapse(const Duration(milliseconds: 100));
        }
        final beforeFlush = svc.resumePersistCount;

        svc.flushVideoResumePositions();
        async.flushMicrotasks();

        expect(svc.resumePersistCount, beforeFlush + 1, reason: 'flush 只写一次');

        // 落盘内容要真的拿到最新值（断言放在 then 外面才能正常冒泡失败）
        String? raw;
        SharedPreferences.getInstance().then((p) => raw = p.getString(keyResume));
        async.flushMicrotasks();
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['/movies/b.mp4'], 42000);
      });
    });

    test('新增条目立刻落盘（结构变化不等节流）', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        final baseline = svc.resumePersistCount;

        svc.setVideoResumePosition('/movies/c.mp4', 60000);
        async.flushMicrotasks();

        expect(svc.resumePersistCount, baseline + 1,
            reason: '新条目要立刻持久化，否则崩溃就丢这条记忆');
      });
    });

    test('回到片头（≤5s）清记录并立刻落盘', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        svc.setVideoResumePosition('/movies/d.mp4', 90000);
        async.flushMicrotasks();
        final baseline = svc.resumePersistCount;

        svc.setVideoResumePosition('/movies/d.mp4', 3000);
        async.flushMicrotasks();

        expect(svc.videoResumePosition('/movies/d.mp4'), isNull);
        expect(svc.resumePersistCount, baseline + 1);
      });
    });

    test('落盘内容可被新实例读回（重启后仍能续播）', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        svc.setVideoResumePosition('/movies/e.mp4', 123000);
        async.flushMicrotasks();

        final reloaded = MediaPrefsService();
        reloaded.init();
        async.flushMicrotasks();

        expect(reloaded.videoResumePosition('/movies/e.mp4'), 123000);
      });
    });

    test('退出时值更新走节流，紧随的 flush 立即落盘（不等 10s）', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        // 先建条目（结构变化立刻落盘），把节流计时起点定下来
        svc.setVideoResumePosition('/movies/exit.mp4', 60000);
        async.flushMicrotasks();
        final baseline = svc.resumePersistCount;

        // 节流窗内推进进度：值更新只置脏不写盘（模拟播放器每秒 tick）
        svc.setVideoResumePosition('/movies/exit.mp4', 61000);
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(svc.resumePersistCount, baseline, reason: '节流窗内值更新不该写盘');

        // 模拟退出：_flushResumePosition 在 setVideoResumePosition 后立即 flush
        svc.flushVideoResumePositions();
        async.flushMicrotasks();
        expect(svc.resumePersistCount, baseline + 1,
            reason: '退出 flush 必须立即落盘，无需等满 10s 节流');

        // 落盘内容拿到最新值（节流窗内杀进程也不丢这几秒）
        String? raw;
        SharedPreferences.getInstance().then((p) => raw = p.getString(keyResume));
        async.flushMicrotasks();
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['/movies/exit.mp4'], 61000);
      });
    });
  });

  group('续播表 LRU 上限（P2-16）', () {
    test('超过 500 条时淘汰最久未碰的条目', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();

        for (var i = 0; i < MediaPrefsService.resumeMaxEntries + 20; i++) {
          svc.setVideoResumePosition('/movies/file_$i.mp4', 60000);
        }
        async.flushMicrotasks();

        expect(svc.videoResumePositions.length, MediaPrefsService.resumeMaxEntries);
        // 最早的 20 条被淘汰，最新的还在
        expect(svc.videoResumePosition('/movies/file_0.mp4'), isNull);
        expect(svc.videoResumePosition('/movies/file_19.mp4'), isNull);
        expect(
          svc.videoResumePosition(
              '/movies/file_${MediaPrefsService.resumeMaxEntries + 19}.mp4'),
          60000,
        );
      });
    });

    test('正在播放的条目被重新触碰后会挪到队尾，不被误淘汰', () {
      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();

        // 先塞满一整轮
        for (var i = 0; i < MediaPrefsService.resumeMaxEntries; i++) {
          svc.setVideoResumePosition('/movies/f_$i.mp4', 60000);
        }
        // 再碰一下最早那条 → 它应该挪到队尾
        svc.setVideoResumePosition('/movies/f_0.mp4', 70000);
        // 插入一条新条目触发淘汰
        svc.setVideoResumePosition('/movies/newest.mp4', 60000);
        async.flushMicrotasks();

        expect(svc.videoResumePosition('/movies/f_0.mp4'), 70000,
            reason: '刚碰过的条目不该被淘汰');
        expect(svc.videoResumePosition('/movies/f_1.mp4'), isNull,
            reason: '真正最久未碰的是 f_1');
      });
    });

    test('init 时把存量超限表按上限截断', () {
      final many = <String, int>{
        for (var i = 0; i < MediaPrefsService.resumeMaxEntries + 50; i++)
          '/old/g_$i.mp4': 60000,
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        keyResume: jsonEncode(many),
      });

      fakeAsync((async) {
        final svc = MediaPrefsService();
        svc.init();
        async.flushMicrotasks();
        expect(svc.videoResumePositions.length, MediaPrefsService.resumeMaxEntries);
      });
    });
  });
}
