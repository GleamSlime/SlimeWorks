import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_05_inline_confirm.dart';

import 'helpers/il_golden.dart';

// 5 号 Inline confirm：一按就删，只留 4 秒反悔
//
// 出图要证明的四件事，全部靠量像素：
// 1. **压扁只在 idle 有**——悬停 112×.97、按住 112×.94（白药丸跑长），done 态没有；
// 2. **只有背景药丸吃弹簧**——去 `{460,30,.9}`、回 `{420,20,.9}`，回的那条欠阻尼，
//    中段会**短于** idle 的 112；
// 3. **标签是瞬移不是跟着长**——点完 60ms 那帧白底还在路上，字却已经在 done 矩形上淡入；
// 4. **2px 倒计时线性烧 4000ms**，到点自动收回，Undo 提前收回。
//
// 舞台 372×232，井 260×96 坐在正中 → 井心 = 图心 (186, 116)，
// 白药丸 idle 占 x 130..242、y 94..138

/// 药丸中心（也是 `.say-face` 的中心）
Offset _pillAt(WidgetTester t) => ilStageCenter(t);

/// Undo 那颗：done 矩形 x 27..233，Undo 顶到右端留 4 → 井坐标 152..229
Offset _undoAt(WidgetTester t) => ilStageCenter(t) + const Offset(60, 0);

Future<void> _pump(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// 点一下并把指针留在那儿（真机就是这样：点完手不会凭空消失）
Future<void> _click(WidgetTester t, Offset at, {int settle = 32}) async {
  await t.tapAt(at);
  await _pump(t, settle);
}

void main() {
  testWidgets('5. Inline confirm 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c05_idle', child: const Case05InlineConfirm());
  });

  testWidgets('5. Inline confirm 悬停压扁帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_hover',
      child: const Case05InlineConfirm(),
      act: (t) async => ilHoverAt(t, _pillAt(t)),
      thenMs: 220,
    );
  });

  testWidgets('5. Inline confirm 按住压扁帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_press',
      child: const Case05InlineConfirm(),
      act: (t) => ilGrab(t, at: _pillAt(t)),
      thenMs: 220,
    );
  });

  /// 点完 60ms：白底还在 112→206 的路上，`.say-merged` 的淡入还压着 100ms 的延后
  testWidgets('5. Inline confirm 交接帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_mid',
      child: const Case05InlineConfirm(),
      act: (t) => t.tapAt(_pillAt(t)),
      thenMs: 28,
    );
  });

  /// 到位那一帧：done 满宽 206，倒计时条刚从满宽烧掉一点
  testWidgets('5. Inline confirm 完成帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_done',
      child: const Case05InlineConfirm(),
      act: (t) => _click(t, _pillAt(t)),
      thenMs: 500,
    );
  });

  /// 半程：条宽 = 206·(1 - 2000/4000) ≈ 103
  testWidgets('5. Inline confirm 倒计时帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_fuse',
      child: const Case05InlineConfirm(),
      act: (t) => _click(t, _pillAt(t)),
      thenMs: 2000,
    );
  });

  /// 收回的中段：回弹那条欠阻尼，宽度会**短过** idle 的 112
  testWidgets('5. Inline confirm 回送帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_give',
      child: const Case05InlineConfirm(),
      act: (t) async {
        await _click(t, _pillAt(t), settle: 600);
        await t.tapAt(_undoAt(t));
      },
      thenMs: 120,
    );
  });

  testWidgets('5. Inline confirm Undo 后帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_undo',
      child: const Case05InlineConfirm(),
      act: (t) async {
        await _click(t, _pillAt(t), settle: 600);
        await t.tapAt(_undoAt(t));
      },
      thenMs: 600,
    );
  });

  /// 没人碰它：4000ms 到点自己收回 idle
  testWidgets('5. Inline confirm 自动收回帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c05_auto',
      child: const Case05InlineConfirm(),
      act: (t) => _click(t, _pillAt(t)),
      thenMs: 4300,
    );
  });

  /// 透明不等于不存在：idle 态那块 0 透明度的 merged 不许接住指针
  testWidgets('5. Inline confirm 两层标签各自只在有货时受理指针', (tester) async {
    await mountIlCase(tester, const Case05InlineConfirm());
    expect(find.text('Delete').hitTestable(), findsOneWidget);
    expect(find.text('Undo').hitTestable(), findsNothing);

    await _click(tester, _pillAt(tester), settle: 600);
    expect(find.text('Delete').hitTestable(), findsNothing);
    expect(find.text('Undo').hitTestable(), findsOneWidget);

    await _click(tester, _undoAt(tester), settle: 900);
    expect(find.text('Delete').hitTestable(), findsOneWidget);
    expect(find.text('Undo').hitTestable(), findsNothing);
    await unmountPage(tester);
  });

  testWidgets('5. Inline confirm 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case05InlineConfirm());

    Future<void> scan(String tag, int ms) async {
      for (var t = 16; t <= ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) fail('5 号 $tag 段 ${t}ms 抛了：$e');
      }
    }

    // 鼠标按住（走 :active 那一档）→ 松手就是那一下点击 → Undo → 再提交一次放着不管
    final held = await ilGrab(tester, at: _pillAt(tester));
    await scan('按住', 260);
    await ilDrop(tester, held);
    await scan('松手提交', 900);
    await _click(tester, _undoAt(tester));
    await scan('收回', 900);

    await _click(tester, _pillAt(tester));
    await scan('等自动收回', 4400);
    await scan('收回到位', 900);
    expect(find.text('Delete').hitTestable(), findsOneWidget);

    await unmountPage(tester);
  });
}
