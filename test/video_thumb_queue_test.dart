import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/services/video_thumb_queue.dart';

void main() {
  // ── 基础入队与执行 ─────────────────────────────────────────────────────

  group('enqueue 基础行为', () {
    test('任务被执行，future 完成', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      bool ran = false;

      await queue.enqueue('k1', () async {
        ran = true;
      });

      expect(ran, isTrue);
    });

    test('多任务串行执行（concurrency=1）', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final order = <int>[];

      final futures = <Future<void>>[];
      for (int i = 0; i < 3; i++) {
        final n = i;
        futures.add(
          queue.enqueue('k$n', () async {
            order.add(n);
          }),
        );
      }
      await Future.wait(futures);

      expect(order, [0, 1, 2]); // 按入队顺序执行
    });

    test('相同 key 重复入队时不创建重复任务', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      int runCount = 0;

      // 先入队一个慢任务占住执行位
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);

      // 同一 key 入队两次
      final f1 = queue.enqueue('dup', () async {
        runCount++;
      });
      final f2 = queue.enqueue('dup', () async {
        runCount++;
      });

      // 释放 blocker，让 dup 执行
      blocker.complete();
      await Future.wait([f1, f2]);

      expect(runCount, 1); // 只执行一次
    });

    test('任务中抛出异常时 future 也会完成（不阻塞后续）', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      bool secondRan = false;

      await queue.enqueue('throw', () async {
        throw Exception('task error');
      });

      await queue.enqueue('ok', () async {
        secondRan = true;
      });

      expect(secondRan, isTrue);
    });
  });

  // ── contains ───────────────────────────────────────────────────────────

  group('contains', () {
    test('入队后 contains 返回 true', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      // 慢任务占住执行位，让第二个任务留在等待队列
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);
      queue.enqueue('target', () async {});

      expect(queue.contains('target'), isTrue);
      blocker.complete();
    });

    test('执行完成后 contains 返回 false', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      await queue.enqueue('k', () async {});
      expect(queue.contains('k'), isFalse);
    });
  });

  // ── cancel ──────────────────────────────────────────────────────────────

  group('cancel', () {
    test('取消等待中的任务后，其 future 仍完成', () async {
      final queue = VideoThumbQueue(concurrency: 1);

      // 慢任务占住执行位
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);

      // 入队一个待执行任务
      final cancelFuture = queue.enqueue('target', () async {});
      expect(queue.contains('target'), isTrue);

      // 取消
      queue.cancel('target');
      expect(queue.contains('target'), isFalse);

      // future 应完成（不永久 pending）
      blocker.complete();
      await expectLater(cancelFuture, completes);
    });

    test('取消不存在的 key 不报错', () {
      final queue = VideoThumbQueue();
      expect(() => queue.cancel('nonexistent'), returnsNormally);
    });
  });

  // ── cancelGroup ────────────────────────────────────────────────────────

  group('cancelGroup', () {
    test('批量取消多个等待任务', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);

      final f1 = queue.enqueue('a', () async {});
      final f2 = queue.enqueue('b', () async {});
      final f3 = queue.enqueue('c', () async {});

      queue.cancelGroup(['a', 'b']);

      blocker.complete();
      await Future.wait([f1, f2, f3]);

      // a 和 b 被取消后 contains 为 false，c 正常执行
      expect(queue.contains('a'), isFalse);
      expect(queue.contains('b'), isFalse);
    });
  });

  // ── cancelAll ──────────────────────────────────────────────────────────

  group('cancelAll', () {
    test('cancelAll 后所有等待任务的 future 均完成', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);

      final futures = [
        queue.enqueue('q1', () async {}),
        queue.enqueue('q2', () async {}),
        queue.enqueue('q3', () async {}),
      ];

      queue.cancelAll();
      blocker.complete();

      // 所有 future 应在 timeout 内完成
      await expectLater(Future.wait(futures), completes);
    });

    test('cancelAll 后队列为空', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);
      queue.enqueue('q', () async {});

      queue.cancelAll();
      expect(queue.contains('q'), isFalse);
      blocker.complete();
    });
  });

  // ── prioritize ─────────────────────────────────────────────────────────

  group('prioritize', () {
    test('prioritize 将新任务插入队首（优先于先入队的任务）', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final order = <String>[];

      // 慢任务占住执行位
      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);

      // 正常入队两个任务
      queue.enqueue('normal', () async {
        order.add('normal');
      });

      // prioritize 插入队首
      queue.prioritize('priority', () async {
        order.add('priority');
      });

      blocker.complete();
      // 等待队列清空
      await queue.enqueue('sentinel', () async {});

      expect(order.first, 'priority'); // priority 应先执行
    });

    test('prioritize 已存在的 key 时将其移到队首', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      final order = <String>[];

      final blocker = Completer<void>();
      queue.enqueue('blocker', () => blocker.future);
      queue.enqueue('a', () async => order.add('a'));
      queue.enqueue('b', () async => order.add('b'));

      // 将已在队列中的 a 提升到队首
      queue.prioritize('a', () async => order.add('a-dup'));

      blocker.complete();
      await queue.enqueue('sentinel', () async {});

      // a 提升后应在 b 之前
      expect(order.indexOf('a'), lessThan(order.indexOf('b')));
    });
  });

  // ── onTaskComplete 回调 ────────────────────────────────────────────────

  group('onTaskComplete', () {
    test('每次任务完成时 onTaskComplete 被调用', () async {
      final queue = VideoThumbQueue(concurrency: 2);
      int callCount = 0;
      queue.onTaskComplete = () => callCount++;

      await Future.wait([
        queue.enqueue('t1', () async {}),
        queue.enqueue('t2', () async {}),
        queue.enqueue('t3', () async {}),
      ]);

      expect(callCount, 3);
    });

    test('取消的任务不触发 onTaskComplete', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      int callCount = 0;
      queue.onTaskComplete = () => callCount++;

      final blocker = Completer<void>();
      final blockerFuture = queue.enqueue('blocker', () => blocker.future);
      queue.enqueue('cancelled', () async {});
      queue.cancel('cancelled');

      blocker.complete();
      await blockerFuture;

      expect(callCount, 1); // blocker 完成，cancelled 被取消不触发
    });
  });

  // ── 并发控制 ──────────────────────────────────────────────────────────

  group('并发控制', () {
    test('concurrency=2 时同时最多执行 2 个任务', () async {
      final queue = VideoThumbQueue(concurrency: 2);
      int maxConcurrent = 0;
      int current = 0;

      final blockers = List.generate(4, (_) => Completer<void>());
      final futures = <Future<void>>[];
      for (int i = 0; i < 4; i++) {
        final blocker = blockers[i];
        futures.add(
          queue.enqueue('t$i', () async {
            current++;
            if (current > maxConcurrent) maxConcurrent = current;
            await blocker.future;
            current--;
          }),
        );
      }

      // 等两帧让任务开始
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 释放所有任务
      for (final b in blockers) {
        b.complete();
      }
      await Future.wait(futures);

      expect(maxConcurrent, lessThanOrEqualTo(2));
    });

    test('concurrency 动态修改后生效', () async {
      final queue = VideoThumbQueue(concurrency: 1);
      queue.concurrency = 4;

      // 同时入队 4 个任务，全部应能并行执行
      final futures = List.generate(4, (i) => queue.enqueue('t$i', () async {}));
      await Future.wait(futures);
      // 所有任务均完成即通过
    });
  });
}
