import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_01_search.dart';

import 'helpers/il_golden.dart';

// 1 号 Search：静止 / 磁吸 / 压缩 / 展开途中 / 展开终态
//
// 一帧一个 test（见 il_golden 的说明）。压缩那帧只有 90ms 窗口，必须在
// 按下之后、定时器改写目标之前拍；展开是弹簧，途中帧落在 55% 前后最能
// 看出"字还没露"那条派生曲线接没接上。

void main() {
  testWidgets('1. Search 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c01_idle', child: const Case01Search());
  });

  testWidgets('1. Search 磁吸帧', tags: 'golden', (tester) async {
    // 磁吸是"离中心越近偏得越多"，指针得落在半程以内才看得见位移：
    // 按舞台中心算偏移，别用窗口坐标（舞台在窗口里还有 24/55 的原点）
    await shootIlCase(
      tester,
      name: 'c01_lean',
      child: const Case01Search(),
      act: (t) => ilHoverAt(t, ilStageCenter(t) + const Offset(-40, -20)),
      thenMs: 300,
    );
  });

  testWidgets('1. Search 压缩帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c01_press',
      child: const Case01Search(),
      act: (t) => ilTap(t),
      thenMs: 48,
    );
  });

  testWidgets('1. Search 展开途中帧', tags: 'golden', (tester) async {
    // 90ms 之前一直是压缩段，弹簧只跑了 40ms 左右：这一档要看到的是
    // "宽度已经在走、字还没露"——`--say` 从弹簧进度 55% 才开始
    await shootIlCase(
      tester,
      name: 'c01_mid',
      child: const Case01Search(),
      act: (t) => ilTap(t),
      thenMs: 100,
    );
  });

  testWidgets('1. Search 露字帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c01_say',
      child: const Case01Search(),
      act: (t) => ilTap(t),
      thenMs: 140,
    );
  });

  testWidgets('1. Search 过冲帧', tags: 'golden', (tester) async {
    // 默认档 k=.16/d=.72 的弹簧会冲到约 375px（目标 320 的 1.17 倍）再回落，
    // 峰值在展开后第 9 帧附近；单独钉一帧，把这个量级写死成可核对的证据
    await shootIlCase(
      tester,
      name: 'c01_overshoot',
      child: const Case01Search(),
      act: (t) => ilTap(t),
      thenMs: 240,
    );
  });

  testWidgets('1. Search 展开终态帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c01_end',
      child: const Case01Search(),
      act: (t) => ilTap(t),
      thenMs: 1600,
    );
  });

  testWidgets('1. Search 输入后帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c01_typed',
      child: const Case01Search(),
      act: (t) async {
        await ilTap(t);
        for (var ms = 0; ms < 1600; ms += 16) {
          await t.pump(const Duration(milliseconds: 16));
        }
        await ilType(t, 'dune');
      },
      thenMs: 120,
    );
  });

  testWidgets('1. Search 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case01Search());
    await ilTap(tester);
    for (var ms = 16; ms <= 3000; ms += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      if (e != null) fail('1 号 ${ms}ms 抛了：$e');
    }
    await ilType(tester, 'hello world');
    for (var ms = 16; ms <= 800; ms += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      if (e != null) fail('1 号输入段 ${ms}ms 抛了：$e');
    }
    await unmountPage(tester);
  });
}
