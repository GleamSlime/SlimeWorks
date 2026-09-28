import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_03_popover_form.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/sv_golden.dart';

/// 3 号表单浮层：按钮长成带灰框的面板，交完表两块表面互相顶替
///
/// 时钟有三条：形变（608ms 落定，末端过冲 0.4%）、换脸（448ms）、翻面（336ms），
/// 外加两个 Timer（1500ms 出成功页、3300ms 整体收起）。读数一律换成相对 box
/// 的量，box 自己在长，绝对坐标没法钉。
void main() {
  // 面板在舞台上的落点：左上角钉死，往右下长
  const origin = Offset(4, 24);
  const panelW = 364.0;
  const panelH = 192.0;
  const btnH = 36.0;
  // 灰框 4（卡描边那 1 在卡片自己里面）
  const cardAt = 4.0;
  const _bw = 1.0;
  // 标题的两个落点：按钮里 (13,8) → 面板里 (16,17)
  const labelFrom = Offset(13, 8);
  const labelTo = Offset(16, 17);
  // 页脚上沿 / 正文原点
  const footTop = 133.0;
  const noteAt = Offset(17, 17);

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect box(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.boxKey));
  Rect form(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.formKey));
  Rect footer(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.footerKey));
  Rect sep(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.sepKey));
  Rect notch(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.notchKey));
  Rect tab(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.tabKey));
  Rect label(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.labelKey));
  Rect note(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.noteKey));
  Rect caret(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.caretKey));
  Rect submit(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.submitKey));
  Rect success(WidgetTester t) => t.getRect(find.byKey(Case03PopoverForm.successKey));

  /// box 坐标（= 面板坐标）：盒子在长，读数得减掉它的原点
  /// 相对 box 原点的落点：盒子一直在长，绝对坐标钉不住（`at` 这个名字让开了，
  /// 好几个用例里 `final at = stageAt(t)` 就是舞台原点）
  Offset rel(WidgetTester t, Rect r) => r.topLeft - box(t).topLeft;

  Color ink(WidgetTester t, Key key) => t.widget<Text>(find.byKey(key)).style!.color!;

  double fade(WidgetTester t, Key key) => t
      .widgetList<Opacity>(find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)))
      .first
      .opacity;

  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) => mountSvCase(t, const Case03PopoverForm());

  /// 展开到落定（形变 608ms，多给一点把过冲也走完）
  Future<void> openIt(WidgetTester t) async {
    await svTap(t);
    await run(t, 700);
  }

  /// 敲两个字再交表：从按下 Submit 那一下开始计时
  Future<void> submitIt(WidgetTester t) async {
    await t.tapAt(submit(t).center);
    await t.pump();
  }

  group('出图', () {
    testWidgets('c03_idle：只有那颗按钮', (t) async {
      await shootSvCase(t, name: 'c03_idle', child: const Case03PopoverForm());
    }, tags: 'golden');

    testWidgets('c03_mid：盒子长到一半，白卡已经按 364 排好了', (t) async {
      await shootSvCase(
        t,
        name: 'c03_mid',
        child: const Case03PopoverForm(),
        act: svTap,
        thenMs: 128,
      );
    }, tags: 'golden');

    testWidgets('c03_open：面板落定，页脚两边各咬一个缺口', (t) async {
      await shootSvCase(
        t,
        name: 'c03_open',
        child: const Case03PopoverForm(),
        act: svTap,
        thenMs: 700,
      );
    }, tags: 'golden');

    testWidgets('c03_typed：正文压在 Label 下面，光标跟着字走', (t) async {
      await shootSvCase(
        t,
        name: 'c03_typed',
        child: const Case03PopoverForm(),
        act: (t) async {
          await openIt(t);
          await svType(t, 'Nice');
        },
      );
    }, tags: 'golden');

    testWidgets('c03_loading：Submit 里翻成转圈的 Loader', (t) async {
      await shootSvCase(
        t,
        name: 'c03_loading',
        child: const Case03PopoverForm(),
        act: (t) async {
          await openIt(t);
          await svType(t, 'Nice');
          await submitIt(t);
        },
        thenMs: 400,
      );
    }, tags: 'golden');

    testWidgets('c03_swap：两块表面同时在，旧的糊着往下、新的落一半', (t) async {
      await shootSvCase(
        t,
        name: 'c03_swap',
        child: const Case03PopoverForm(),
        act: (t) async {
          await openIt(t);
          await svType(t, 'Nice');
          await submitIt(t);
        },
        // 1500ms 起换脸，再走 160ms（行程 448ms）
        thenMs: 1660,
      );
    }, tags: 'golden');

    testWidgets('c03_success：只剩对勾那一张', (t) async {
      await shootSvCase(
        t,
        name: 'c03_success',
        child: const Case03PopoverForm(),
        act: (t) async {
          await openIt(t);
          await svType(t, 'Nice');
          await submitIt(t);
        },
        thenMs: 2200,
      );
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止：36 高的按钮在 (4,24)，面板那几层都没挂', (t) async {
      await mount(t);
      final at = stageAt(t);
      expect(box(t).topLeft, at + origin);
      expect(box(t).height, closeTo(btnH, 0.1));
      // `px-3` 12 + 1 描边 = 13；20 的行盒居中在 36 的边框盒里 → 顶 8
      expect(rel(t, label(t)), labelFrom);
      expect(label(t).height, closeTo(20, 0.2));
      // 按钮里那一档是前景色（`text-sm font-medium`）
      expect(ink(t, Case03PopoverForm.labelKey), const Color(0xFF0A0A0A));
      expect(find.byKey(Case03PopoverForm.formKey), findsNothing);
      expect(find.byKey(Case03PopoverForm.tabKey), findsNothing);
      expect(find.byKey(Case03PopoverForm.noteKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('展开：364×192，灰框 4 圈住 356×184 的白卡', (t) async {
      await mount(t);
      await openIt(t);
      expect(box(t).size, const Size(panelW, panelH));
      expect(box(t).topLeft, stageAt(t) + origin);
      expect(rel(t, form(t)), const Offset(cardAt, cardAt));
      expect(form(t).size, const Size(356, 184));
      // 卡内容盒 354×182：textarea 128 + 页脚 48，剩下 6 空在下面（没给 flex-grow）
      expect(footer(t).size, const Size(354, 48));
      expect(rel(t, footer(t)).dy, closeTo(footTop, 0.2));
      // 6 是卡内容盒里的空档；再往外还有 1 描边 + 4 灰框，离面板底缘是 11
      expect(form(t).bottom - _bw - footer(t).bottom, closeTo(6, 0.2));
      expect(box(t).bottom - footer(t).bottom, closeTo(11, 0.2));
      // 落进面板之后它换了 class：`text-muted-foreground`，一落地就翻，不补间
      expect(ink(t, Case03PopoverForm.labelKey), const Color(0xFF737373));
      await unmountPage(t);
    });

    testWidgets('页脚那条虚线和两个缺口的落点', (t) async {
      await mount(t);
      await openIt(t);
      // `absolute left-0 top-[-1px]`：352 宽的 svg 压在分界上，线画在第 1 行
      expect(sep(t).width, closeTo(352, 0.2));
      expect(sep(t).top - footer(t).top, closeTo(-1, 0.2));
      // 缺口：`-translate-x-[1.5px] -translate-y-1/2` → 6×12 的盒子骑在页脚左上角
      expect(notch(t).size, const Size(6, 12));
      expect(notch(t).left - footer(t).left, closeTo(-1.5, 0.2));
      expect(notch(t).top - footer(t).top, closeTo(-6, 0.2));
      expect(notch(t).center.dy, closeTo(footer(t).top, 0.2), reason: '上下各拖一半');
      await unmountPage(t);
    });

    testWidgets('Submit：104×24 坐在页脚右端，离右边 10', (t) async {
      await mount(t);
      await openIt(t);
      expect(submit(t).size, const Size(104, 24));
      // 面板坐标：卡内容左缘 5 + 页脚 px 10 → 右边 344，宽 104 → 左 240 + 5 = 245
      expect(rel(t, submit(t)), const Offset(245, 145));
      expect(box(t).right - submit(t).right, closeTo(15, 0.2), reason: '`px-[10px]` + 描边 + 灰框');
      // 文字翻给 Loader：静止档文字满不透明、Loader 完全不透明在外
      expect(fade(t, Case03PopoverForm.btnLabelKey), closeTo(1, 1e-9));
      expect(fade(t, Case03PopoverForm.spinnerKey), 0);
      await unmountPage(t);
    });

    testWidgets('飞的只有那行字：横向 3、纵向 9，全程单调', (t) async {
      await mount(t);
      await svTap(t);
      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i < 45; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final p = rel(t, label(t));
        xs.add(p.dx);
        ys.add(p.dy);
      }
      for (final v in ys) {
        expect(v, inInclusiveRange(labelFrom.dy, labelTo.dy + 0.02));
      }
      for (final v in xs) {
        expect(v, inInclusiveRange(labelFrom.dx, labelTo.dx + 0.02));
      }
      expect(xs.first, closeTo(labelFrom.dx, 0.02));
      expect(ys.last, closeTo(labelTo.dy, 0.3));
      expect(xs.last, closeTo(labelTo.dx, 0.3));
      // 行程不是补间出来的等速：进度按弹簧走，前 1/3 时间就该走完一半以上
      expect(ys[10], greaterThan(labelFrom.dy + (labelTo.dy - labelFrom.dy) * 0.5));
      await unmountPage(t);
    });

    testWidgets('形变只长不小的：左上角全程钉在 (4,24)', (t) async {
      await mount(t);
      final at = stageAt(t);
      await svTap(t);
      final hs = <double>[];
      for (var i = 0; i < 45; i++) {
        await t.pump(const Duration(milliseconds: 16));
        expect(box(t).topLeft, at + origin, reason: '面板 absolute 挂在按钮左上角');
        hs.add(box(t).height);
      }
      // ζ=.866 只留 0.43% 的过冲：行程 156 → 顶出去不到 0.7px，然后退回来落定
      final peak = hs.reduce(math.max);
      expect(peak, inInclusiveRange(panelH, panelH + 0.8), reason: '过冲量 ${(peak - panelH)}');
      final top = hs.indexOf(peak);
      for (var i = 1; i <= top; i++) {
        expect(hs[i], greaterThanOrEqualTo(hs[i - 1] - 0.02), reason: '爬到顶点之前不许回头');
      }
      expect(box(t).height, closeTo(panelH, 0.05));
      expect(box(t).width, closeTo(panelW, 0.05));
      await unmountPage(t);
    });

    testWidgets('落定在 608ms 上下（布局动画默认档 stiffness 300 / damping 30）', (t) async {
      await mount(t);
      await svTap(t);
      await t.pump();
      double? last;
      var prev = box(t).height;
      for (var i = 1; i <= 90; i++) {
        await t.pump(const Duration(milliseconds: 8));
        final h = box(t).height;
        if ((h - prev).abs() > 0.02) last = i * 8.0;
        prev = h;
      }
      expect(last, inInclusiveRange(520, 660), reason: '形变在 $last 才收口');
      await unmountPage(t);
    });

    testWidgets('打字：正文原点和 Label 差 1px 叠在一起，光标跟在字尾', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'Hi');
      // 参考稿只在成功页让位（`data-[success]:text-transparent`），打字时不躲
      expect(rel(t, note(t)), noteAt);
      expect(label(t).left - note(t).left, closeTo(-1, 0.2));
      expect(label(t).top, closeTo(note(t).top, 0.2));
      expect(fade(t, Case03PopoverForm.labelKey), 1);
      expect(caret(t).size, const Size(1, 17));
      expect(caret(t).left - note(t).right, closeTo(0, 0.6));
      expect(caret(t).top, closeTo(note(t).top, 0.6));
      await unmountPage(t);
    });

    testWidgets('交表时间轴：转圈 → 1500ms 换脸 → 3300ms 收起', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'Nice');
      await submitIt(t);
      await run(t, 200);
      expect(fade(t, Case03PopoverForm.spinnerKey), greaterThan(0.5), reason: '翻面走了一半以上');
      expect(find.byKey(Case03PopoverForm.successKey), findsNothing, reason: '1500ms 之前不给成功页');
      await run(t, 1400);
      expect(find.byKey(Case03PopoverForm.successKey), findsOneWidget);
      expect(fade(t, Case03PopoverForm.labelKey), 0, reason: '成功页那一档标题不吭声');
      expect(find.byKey(Case03PopoverForm.tabKey), findsNothing, reason: '`showCloseButton` 跟着翻');
      await run(t, 400);
      // 换脸 448ms 落定：旧的整层摘掉，新的满不透明
      expect(find.byKey(Case03PopoverForm.formKey), findsNothing);
      expect(fade(t, Case03PopoverForm.successKey), closeTo(1, 1e-9));
      // 3300ms 那一下自己收：还得再给形变走完 608ms
      await run(t, 2100);
      expect(box(t).height, closeTo(btnH, 0.2), reason: '到点自己收');
      expect(find.byKey(Case03PopoverForm.formKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('两块表面吃的是同一条进度', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'Nice');
      await submitIt(t);
      await run(t, 1560);
      // 旧的往下 8、新的从上面 32 落下来：两个量必须解出同一个 q
      final qf = (form(t).top - box(t).top - cardAt) / 8;
      final qs = 1 + (success(t).top - box(t).top - cardAt) / 32;
      expect(qf, inInclusiveRange(0.05, 0.95), reason: '此刻确实在半路：$qf');
      expect(qs, closeTo(qf, 0.01));
      expect(fade(t, Case03PopoverForm.formKey), closeTo(1 - qf, 0.01));
      expect(fade(t, Case03PopoverForm.successKey), closeTo(qf, 0.01));
      // 正文是卡里的东西，不是面板里的：它跟着旧的那一张一起淡
      expect(fade(t, Case03PopoverForm.noteKey), closeTo(1 - qf, 0.01));
      await unmountPage(t);
    });

    testWidgets('空表点 Submit 不该交', (t) async {
      await mount(t);
      await openIt(t);
      await t.tapAt(submit(t).center);
      await run(t, 2000);
      expect(find.byKey(Case03PopoverForm.successKey), findsNothing);
      expect(fade(t, Case03PopoverForm.spinnerKey), 0, reason: '连翻面都没起跳');
      expect(box(t).height, closeTo(panelH, 0.2));
      await unmountPage(t);
    });

    testWidgets('四种收法：Escape、顶部把手、点外面、交完表自己收', (t) async {
      await mount(t);
      final at = stageAt(t);
      await openIt(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await run(t, 800);
      expect(box(t).height, closeTo(btnH, 0.2), reason: 'Escape 收掉');

      await openIt(t);
      await t.tapAt(tab(t).center);
      await run(t, 800);
      expect(box(t).height, closeTo(btnH, 0.2), reason: '把手收掉');

      await openIt(t);
      // 面板之外、舞台之内：右边那一列空白（面板右缘在 x=368）
      await t.tapAt(at + const Offset(371, 100));
      await run(t, 800);
      expect(box(t).height, closeTo(btnH, 0.2), reason: '点外面收掉');

      await openIt(t);
      await svType(t, 'Nice');
      await t.tapAt(note(t).center);
      await run(t, 100);
      expect(box(t).height, closeTo(panelH, 0.2), reason: '点在面板里不该收');
      await unmountPage(t);
    });

    // 把手只有 12×26、Submit 只有 24 高，指尖按不准，所以两张脸底下各压了一层
    // 透明受理区。这一层必须占一格真实布局：探出宿主盒子的命中压根收不到
    // （`RenderBox.hitTest` 第一句就是 `size.contains(position)`）。
    testWidgets('指尖受理区：把手和 Submit 外扩那一圈点得着', (t) async {
      await mount(t);
      await openIt(t);
      await run(t, 700);

      // 把手左边 8：不在 12 宽的脸上，在 16+12+16 的圈里
      await t.tapAt(tab(t).centerLeft + const Offset(-8, 0));
      await run(t, 800);
      expect(box(t).height, closeTo(btnH, 0.2), reason: '把手左边那一圈没接住');

      await openIt(t);
      await svType(t, 'Nice');
      final s = submit(t);
      // 下边 6：24 高的脸只到 24，圈探到 34 → 这一点落在圈里、不在脸上
      await t.tapAt(Offset(s.center.dx, s.bottom + 6));
      await run(t, 100);
      expect(box(t).height, closeTo(panelH, 0.2), reason: '圈里那点被当成了"点外面"');
      await run(t, 1600);
      expect(success(t).width, closeTo(356.0, 0.2), reason: 'Submit 下面那一圈没交成表');
      await unmountPage(t);
    });

    testWidgets('Cmd+Enter 直接交表', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'Nice');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await run(t, 1600);
      expect(find.byKey(Case03PopoverForm.successKey), findsOneWidget);
      await unmountPage(t);
    });

    testWidgets('收回去清空：再打开是空白的，那行字也翻回按钮', (t) async {
      await mount(t);
      await openIt(t);
      await svType(t, 'Nice');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await run(t, 800);
      expect(find.byKey(Case03PopoverForm.noteKey), findsNothing, reason: '`closePopover` 顺手清空');
      // 收起就是整块摘掉：面板里的东西一个都不该留（连"翻回按钮那行字"都没得看）
      expect(find.byKey(Case03PopoverForm.submitKey), findsNothing);
      expect(find.byKey(Case03PopoverForm.successKey), findsNothing);
      await openIt(t);
      expect(find.byKey(Case03PopoverForm.noteKey), findsNothing);
      expect(rel(t, label(t)), const Offset(16, 17));
      await unmountPage(t);
    });

    testWidgets('逐帧扫 4500ms：开→打字→交表→自己收，全程不抛', (t) async {
      await mount(t);
      await svTap(t);
      for (var i = 0; i < 45; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await svType(t, 'OK');
      await t.tapAt(submit(t).center);
      for (var i = 0; i < 240; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
      expect(box(t).height, closeTo(btnH, 0.2));
      expect(find.byType(SvStage), findsOneWidget);
      await unmountPage(t);
    });
  });
}
