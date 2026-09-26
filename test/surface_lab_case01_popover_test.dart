import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_01_popover.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/sv_golden.dart';

/// 1 号 Popover：按钮 ↔ 面板是同一块表面的两个读数
///
/// 落点一律从舞台的左上角算：磁吸、outside-click 这类判定吃的是舞台坐标，
/// 硬写窗口坐标会连偏移方向都反掉。
void main() {
  // 面板从按钮左上角往右下长，这一点是舞台坐标
  const origin = Offset(4, 24);
  const panelW = 364.0;
  const panelH = 200.0;
  // 展开后各档内缩：Label/textarea `px-4 py-3`，描边再让 1px
  const inset = 17.0; // 1 + 16
  const insetY = 13.0; // 1 + 12

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect box(WidgetTester t) => t.getRect(find.byKey(Case01Popover.boxKey));
  Rect label(WidgetTester t) => t.getRect(find.byKey(Case01Popover.labelKey));
  Rect submit(WidgetTester t) => t.getRect(find.byKey(Case01Popover.submitKey));
  Rect note(WidgetTester t) => t.getRect(find.byKey(Case01Popover.noteKey));
  Rect caret(WidgetTester t) => t.getRect(find.byKey(Case01Popover.caretKey));

  /// 一次 `pump(N ms)` 在假异步里只出一帧，行程一律按 ≤16ms 一步步推
  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) =>
      mountSvCase(t, const Case01Popover(), window: svWindow(stageH: 248));

  Future<void> openIt(WidgetTester t) async {
    await svTap(t);
    await run(t, 420);
  }

  group('出图', () {
    testWidgets('c01_idle：只有那颗按钮', (t) async {
      await shootSvCase(t, name: 'c01_idle', child: const Case01Popover());
    }, tags: 'golden');

    testWidgets('c01_mid：形变中途，盒子既不是 36 也不是 200', (t) async {
      await shootSvCase(
        t,
        name: 'c01_mid',
        child: const Case01Popover(),
        act: svTap,
        thenMs: 46,
      );
    }, tags: 'golden');

    testWidgets('c01_open：面板落定，Label 已经飞到左上角', (t) async {
      await shootSvCase(
        t,
        name: 'c01_open',
        child: const Case01Popover(),
        act: svTap,
        thenMs: 420,
      );
    }, tags: 'golden');

    testWidgets('c01_typed：一有字 Label 就让位', (t) async {
      await shootSvCase(
        t,
        name: 'c01_typed',
        child: const Case01Popover(),
        act: (t) async {
          await svTap(t);
          await run(t, 420);
          await svType(t, 'Reads the thread');
        },
        thenMs: 32,
      );
    }, tags: 'golden');

    // 这一格不能走 `shootSvCase`：它拍完就拆树，按住的那根指针还没松，
    // 拆完之后松手会把 PointerUp 路由给已 dispose 的 Listener → setState after dispose
    testWidgets('c01_press：Submit 被按住，整颗缩到 .98', (t) async {
      await mountSvCase(t, const Case01Popover(), window: svWindow(stageH: 248));
      await svTap(t);
      await run(t, 420);
      final hold = await svGrab(t, on: find.byKey(Case01Popover.submitKey));
      await run(t, 16);
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c01_press.png'));
      expect(t.takeException(), isNull);
      await svDrop(t, hold);
      await unmountPage(t);
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止：36 高的那颗按钮，字在描边内 12/8', (t) async {
      await mount(t);
      final at = stageAt(t);
      expect(box(t).topLeft, at + origin);
      expect(box(t).height, closeTo(36, 0.1));
      // 宽 = 1 + 12 + 文字 + 12 + 1（border-box 里描边也占宽）
      expect(box(t).width, closeTo(label(t).width + 26, 0.6));
      // 描边 1px 把子节点往里让一格，所以文字落在 +13/+8
      expect(label(t).left, closeTo(box(t).left + 13, 0.1));
      expect(label(t).top, closeTo(box(t).top + 8, 0.1));
      // 右边留白和左边等宽：不是靠 padding 硬撑，而是盒子宽度自己算对的
      expect(box(t).right - label(t).right, closeTo(13, 0.6));
      // footer 在盒外：被 overflow:hidden 裁掉，不是淡出
      expect(submit(t).top, greaterThan(box(t).bottom));
      await unmountPage(t);
    });

    testWidgets('展开：364×200 从同一点长出来，Label 落在 left-4 top-3', (t) async {
      await mount(t);
      final at = stageAt(t);
      await openIt(t);
      expect(box(t).topLeft, at + origin);
      expect(box(t).size, const Size(panelW, panelH));
      expect(label(t).left, closeTo(box(t).left + inset, 0.2));
      expect(label(t).top, closeTo(box(t).top + insetY, 0.2));
      // Submit：右下内缩 16/12（footer 的 px-4 py-3），高 32
      expect(submit(t).right, closeTo(box(t).right - inset, 0.2));
      expect(submit(t).bottom, closeTo(box(t).bottom - insetY, 0.2));
      expect(submit(t).height, closeTo(32, 0.2));
      await unmountPage(t);
    });

    testWidgets('形变是同一块在长：中途既不是 36 也不是 200', (t) async {
      await mount(t);
      final at = stageAt(t);
      await svTap(t);
      await run(t, 46);
      final h = box(t).height;
      expect(h, inInclusiveRange(90, 150), reason: '$h：既没贴着 36 也没提前落 200');
      // 左上角全程钉住不动：只有宽高在走
      expect(box(t).topLeft, at + origin);
      // 字跟着走，落在两档之间
      expect(label(t).left, inInclusiveRange(box(t).left + 13, box(t).left + inset));
      await unmountPage(t);
    });

    testWidgets('四条量吃同一条弹簧：8ms 一路采，高度单调爬升', (t) async {
      await mount(t);
      await svTap(t);
      final hs = <double>[];
      for (var i = 0; i < 24; i++) {
        await t.pump(const Duration(milliseconds: 8));
        hs.add(box(t).height);
      }
      for (var i = 1; i < hs.length; i++) {
        expect(hs[i], greaterThanOrEqualTo(hs[i - 1] - 0.5));
      }
      expect(hs.last, lessThan(panelH));
      await unmountPage(t);
    });

    testWidgets('弹簧在 300ms 上下落定（bounce .05 / duration .3）', (t) async {
      await mount(t);
      await svTap(t);
      double? last;
      var prev = box(t).height;
      for (var i = 1; i <= 60; i++) {
        await t.pump(const Duration(milliseconds: 8));
        final h = box(t).height;
        if ((h - prev).abs() > 0.02) last = i * 8.0;
        prev = h;
      }
      expect(last, inInclusiveRange(260, 340));
      expect(box(t).height, closeTo(panelH, 0.2));
      await unmountPage(t);
    });

    testWidgets('打字让 Label 让位，退空又回来', (t) async {
      await mount(t);
      await openIt(t);
      double opacity() => t.widget<Opacity>(
            find.ancestor(of: find.byKey(Case01Popover.labelKey), matching: find.byType(Opacity)),
          ).opacity;
      expect(opacity(), 1);
      await svType(t, 'Hi');
      await run(t, 32);
      expect(opacity(), 0);
      // textarea 的首行和 Label 是同一个落点（参考稿就是叠在一起，靠 opacity 让位）
      expect(note(t).top, closeTo(box(t).top + insetY, 0.2));
      expect(note(t).left, closeTo(box(t).left + inset, 0.2));
      // 光标钉在行的末尾：不是硬写的偏移。落点按整像素取整（1px 头发丝骑在两个
      // 像素上会摊成两根半灰条），所以这里最多差 1px
      expect(caret(t).left - note(t).right, inInclusiveRange(0, 1));
      expect(caret(t).top, closeTo(note(t).top, 0.2));
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pump(const Duration(milliseconds: 16));
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await run(t, 32);
      expect(opacity(), 1);
      expect(find.byKey(Case01Popover.caretKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('Escape 关掉，而且把 note 清空', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'draft');
      await run(t, 32);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await run(t, 420);
      expect(box(t).height, closeTo(36, 0.2));
      expect(find.byKey(Case01Popover.noteKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('点外面关，点里面不关', (t) async {
      await mount(t);
      final at = stageAt(t);
      await openIt(t);
      // 面板内（textarea 那一块，避开 footer 的两个按钮）
      await t.tapAt(at + const Offset(200, 120));
      await run(t, 420);
      expect(box(t).height, closeTo(panelH, 0.2), reason: '面板内部那一下不该关掉');

      // 舞台内、面板外（面板下缘在舞台 y=224）
      await t.tapAt(at + const Offset(200, 240));
      await run(t, 420);
      expect(box(t).height, closeTo(36, 0.2));
      await unmountPage(t);
    });

    testWidgets('X 和 Submit 都能关掉', (t) async {
      await mount(t);
      await openIt(t);
      // X：footer 左端那 16 见方，行内垂直居中
      await t.tapAt(box(t).topLeft + const Offset(inset + 8, 155 + 16));
      await run(t, 420);
      expect(box(t).height, closeTo(36, 0.2));

      await openIt(t);
      await t.tapAt(submit(t).center);
      await run(t, 420);
      expect(box(t).height, closeTo(36, 0.2));
      await unmountPage(t);
    });

    testWidgets('Submit 按下：transform 里读到 0.98', (t) async {
      await mount(t);
      await openIt(t);
      // 别用 `getMaxScaleOnAxis`：它把 z 轴一起算，而 `Transform.scale` 的 z 恒是 1，
      // 于是 0.98 也读成 1.0。这里要的就是 x 轴那一个数
      double scale() => t.widget<Transform>(
            find.ancestor(of: find.byKey(Case01Popover.submitKey), matching: find.byType(Transform)),
          ).transform.entry(0, 0);
      expect(scale(), 1);
      final hold = await svGrab(t, on: find.byKey(Case01Popover.submitKey));
      await run(t, 32);
      expect(scale(), closeTo(0.98, 1e-9));
      await svDrop(t, hold);
      await run(t, 64);
      expect(scale(), 1);
      await unmountPage(t);
    });

    testWidgets('Submit 的 hover 同时换底色和字色', (t) async {
      await mount(t);
      await openIt(t);
      BoxDecoration style() => t.widget<DecoratedBox>(
            find.descendant(
                of: find.byKey(Case01Popover.submitKey), matching: find.byType(DecoratedBox)),
          ).decoration as BoxDecoration;
      Color textColor() => t
          .widget<Text>(
              find.descendant(of: find.byKey(Case01Popover.submitKey), matching: find.byType(Text)))
          .style!
          .color!;
      expect(style().color, isNot(equals(const Color(0xFFF4F4F5))));
      final g = await svHoverAt(t, submit(t).center);
      await run(t, 200);
      expect(style().color, const Color(0xFFF4F4F5));
      expect(textColor(), const Color(0xFF27272A));
      await g.removePointer();
      await run(t, 200);
      expect(style().color, isNot(equals(const Color(0xFFF4F4F5))));
      await unmountPage(t);
    });

    testWidgets('逐帧扫 2000ms：开→打字→收，全程不抛', (t) async {
      await mount(t);
      await svTap(t);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await svType(t, 'abc');
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
      expect(box(t).height, closeTo(36, 0.2));
      await unmountPage(t);
    });
  });
}
