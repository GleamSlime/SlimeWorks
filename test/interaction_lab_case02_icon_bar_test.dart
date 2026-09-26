import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_02_icon_bar.dart';

import 'helpers/il_golden.dart';

// 2 号 Icon bar：滑块的两相位必须各拍一帧才验得出来
//
// 单看终态只能证明"滑块到了那一格"，证明不了中间那次横跨。stretch 的钟
// 有 190ms 但 150ms 就被 settle 接管，所以 90ms 那帧是"横跨中"，170ms
// 那帧是"刚开始往回收"，350ms 那帧才看得见过冲探过头的位置。

/// 第 i 格图标的中心（窗口坐标）
///
/// 条宽 210、格 38、间隙 2、内衬 6，整条在舞台正中：
/// 中心 x = 舞台中心 -105 +6 +19 + i*40
Offset _itemAt(WidgetTester tester, int i) =>
    ilStageCenter(tester) + Offset(-80.0 + 40.0 * i, 0);

Future<void> _pick(WidgetTester tester, int i) => tester.tapAt(_itemAt(tester, i));

void main() {
  testWidgets('2. Icon bar 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c02_idle', child: const Case02IconBar());
  });

  testWidgets('2. Icon bar 横跨帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c02_stretch',
      child: const Case02IconBar(),
      act: (t) => _pick(t, 4),
      thenMs: 90,
    );
  });

  testWidgets('2. Icon bar 交接帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c02_handoff',
      child: const Case02IconBar(),
      act: (t) => _pick(t, 4),
      thenMs: 170,
    );
  });

  testWidgets('2. Icon bar 回弹帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c02_settle',
      child: const Case02IconBar(),
      act: (t) => _pick(t, 4),
      thenMs: 380,
    );
  });

  testWidgets('2. Icon bar 终态帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c02_end',
      child: const Case02IconBar(),
      act: (t) => _pick(t, 4),
      thenMs: 1200,
    );
  });

  testWidgets('2. Icon bar 悬停帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c02_hover',
      child: const Case02IconBar(),
      act: (t) => ilHoverAt(t, _itemAt(t, 2)),
      thenMs: 300,
    );
  });

  testWidgets('2. Icon bar 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case02IconBar());
    // 连着点三次：跨格、往回跨、点同一格（最后这次不该起动画）
    await _pick(tester, 4);
    for (var ms = 16; ms <= 700; ms += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      if (e != null) fail('2 号第一段 ${ms}ms 抛了：$e');
    }
    await _pick(tester, 1);
    for (var ms = 16; ms <= 700; ms += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      if (e != null) fail('2 号第二段 ${ms}ms 抛了：$e');
    }
    await _pick(tester, 1);
    for (var ms = 16; ms <= 200; ms += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final e = tester.takeException();
      if (e != null) fail('2 号重复点击 ${ms}ms 抛了：$e');
    }
    await unmountPage(tester);
  });
}
