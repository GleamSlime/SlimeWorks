import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_03_slide_confirm.dart';

import 'helpers/il_golden.dart';

// 3 号 Slide to confirm：这一格是"按住拖"，不是播一段动画
//
// 出图要卡的三件事：拖的时候把手 1:1 跟手且没有补间；松手够到底才提交，
// 提交后把手的**右边缘钉在轨道右内衬**（位移和宽度同增同减），所以只能靠
// 中段那一帧证明它不是"整块缩回去"；没到阈值弹回时会向左过冲，那一帧才
// 有挤压。
//
// 位移一律用"相对按下点拖了多少"来表达：偏移是在第一次移动时取的，所以
// 末位移 = 总位移 ×(1 - 1/steps)，`steps` 越大越接近目标值。
//
// 出图后量过的像素（`test/goldens`，轨道左内衬在 x=74、右内衬在 x=346）：
//   idle / press_far / reset   黑块 74..121、y 147..194 —— 远端按下那张和静止逐像素相同
//   drag(拖 70)                74..187 = 48 + 65.6 —— 1:1 跟手
//   far(拖到底) / morph / done 74..345 —— 摊开中段右边缘仍钉在 345
//   bounce(128ms)              74..135、y 145..196 —— 向左过冲时进度条顶宽
//                              14px、竖向鼓 2px；横向挤压被压在填充条下面，
//                              和参考稿一样（填充条不吃把手的 scale）

IlHold? _hold;

/// 把手按住并从按下点拖 `d`
Future<void> _drag(WidgetTester t, double d, {int steps = 16, Offset? from}) async {
  final at = from ?? ilStageCenter(t);
  var hold = await ilGrab(t, at: at);
  hold = await ilDragTo(t, hold, at + Offset(d, 0), steps: steps);
  _hold = hold;
}

Future<void> _dragDrop(WidgetTester t, double d, {int steps = 16, Offset? from}) async {
  await _drag(t, d, steps: steps, from: from);
  await ilDrop(t, _hold!);
  _hold = null;
}

void main() {
  tearDown(() => _hold = null);

  testWidgets('3. Slide to confirm 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c03_idle', child: const Case03SlideConfirm());
  });

  // 在轨道右端（离把手 244px）按下、只挪一次 24px：那一次移动只用来"取偏移"，
  // 位移一格都不给。所以这张图必须和 c03_idle 逐像素相同——要是按下时就把
  // 把手拽过去，这里会是一根拖到最右的黑条
  testWidgets('3. Slide to confirm 远端按下不传送帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_press_far',
      child: const Case03SlideConfirm(),
      act: (t) => _drag(t, 24, steps: 1, from: ilStageCenter(t) + const Offset(116, 0)),
    );
  });

  testWidgets('3. Slide to confirm 悬停帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_hover',
      child: const Case03SlideConfirm(),
      act: (t) => ilHoverAt(t, ilStageCenter(t) + const Offset(-112, 0)),
      thenMs: 60,
    );
  });

  testWidgets('3. Slide to confirm 拖拽中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_drag',
      child: const Case03SlideConfirm(),
      act: (t) => _drag(t, 70),
    );
  });

  testWidgets('3. Slide to confirm 拖到底帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_far',
      child: const Case03SlideConfirm(),
      act: (t) => _drag(t, 300),
    );
  });

  testWidgets('3. Slide to confirm 摊开帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_morph',
      child: const Case03SlideConfirm(),
      act: (t) => _dragDrop(t, 300),
      thenMs: 48,
    );
  });

  testWidgets('3. Slide to confirm 已确认帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_done',
      child: const Case03SlideConfirm(),
      act: (t) => _dragDrop(t, 300),
      thenMs: 600,
    );
  });

  testWidgets('3. Slide to confirm 自动收回帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_reset',
      child: const Case03SlideConfirm(),
      act: (t) => _dragDrop(t, 300),
      thenMs: 2600,
    );
  });

  testWidgets('3. Slide to confirm 回弹挤压帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c03_bounce',
      child: const Case03SlideConfirm(),
      act: (t) => _dragDrop(t, 210),
      thenMs: 128,
    );
  });

  testWidgets('3. Slide to confirm 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case03SlideConfirm());

    Future<void> scan(String tag, int ms) async {
      for (var t = 16; t <= ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) fail('3 号 $tag 段 ${t}ms 抛了：$e');
      }
    }

    // 拖到底 → 提交 → 1500ms 自动收回，全程不能有异常也不能留下挂着的钟
    await _drag(tester, 300);
    await scan('拖拽', 200);
    await ilDrop(tester, _hold!);
    await scan('提交+收回', 2800);

    // 半程松手：走弹回那条更弹的阻尼，会向左过冲
    await _dragDrop(tester, 210);
    await scan('弹回', 900);
    await unmountPage(tester);
  });
}
