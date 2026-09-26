import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_10_roster.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 10 号 Selection list：底部 54px 被 clip-path 裁住的名单，勾一个才长出 CTA
//
// 断言要证明的八件事：
// 1. **几何全是量出来的**：盒子恒 268×224（裁切不改布局）、行 46 高、间距 4、
//    头像 32 圆坐在 `10+9` 的左边距上、勾 19 见方贴在右内边距、CTA 44 高。
// 2. **收起态三件套钉在 p=54**：CTA opacity 0、y -14、scale .96，而且**点不到**——
//    `RenderClipPath.hitTest` 和 CSS 一样把裁掉的区域挡在外面。
// 3. **三条映射共用一根弹簧**：任意两样都能互相推出 p，中途读数必须满足
//    分段线性 `p∈[27,54] → 0→.15`、`p∈[0,27] → .15→1`。
// 4. **文案是 mode:wait**：先淡出到 0 才换字符串，`count=1` 是 "Send request"。
// 5. **点第 3 行再点第 1 行，行序不变**，CTA 说的是 2 requests。
// 6. **发送后抽屉不收回**：`f = 有选中 || 已发送`，勾全清了但 CTA 还开着、
//    文案变 "Requests sent"，每枚勾的 scale 要退回 1。
// 7. **hover 两个方向时长不同**：进 140ms、出 220ms。
// 8. **goo 层只在选中那一格挂在树上**，σ=4 那层往外扩 24。
//
// 勾的画入比例、环的 100/160ms、60ms 延迟这些长在 CustomPainter 里的量，树上
// 没有读数点：逐帧扫只能证明钟没停，那三处时序交给量像素的脚本一起钉。
//
// CTA 挂在 `Transform` 底下，静止态被缩到 .96 —— 量它的 rect 必须先把抽屉开到位，
// 否则读回来的是变换之后的框。

const _names = {'Nadia Okonkwo', 'Tomas Cardoso', 'Kai Brenner', 'Lukas Lindqvist'};

Rect _boxRect(WidgetTester t) => t.getRect(find.byKey(const ValueKey('clip')));

double _xf(WidgetTester t, String key, int i) =>
    t.widget<Transform>(find.byKey(ValueKey(key))).transform.storage[i];

double _opa(WidgetTester t, String key) => t.widget<Opacity>(find.byKey(ValueKey(key))).opacity;

/// 从 CTA 的 y 反推 p（`y = -14 * p/54`，p 已经被夹在 [0,54]）
double _pFromY(WidgetTester t) => -_xf(t, 'cta-xf', 13) / 14 * 54;

double _labelA(WidgetTester t) => _opa(t, 'label');

Text _ctaText(WidgetTester t) => t.widget<Text>(
  find.descendant(of: find.byKey(const ValueKey('label')), matching: find.byType(Text)),
);

String _labelText(WidgetTester t) => _ctaText(t).data!;

Text _whoText(WidgetTester t, int i, int which) => t.widgetList<Text>(
  find.descendant(of: find.byKey(ValueKey('who-$i')), matching: find.byType(Text)),
).elementAt(which);

Future<void> _pump(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    await t.pump(const Duration(milliseconds: 16));
    left -= 16;
  }
}

Future<void> _tapRow(WidgetTester t, int i) async {
  await t.tap(find.byKey(ValueKey('row-$i')));
  await t.pump(const Duration(milliseconds: 16));
}

Future<void> _tapCta(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('cta')));
  await t.pump(const Duration(milliseconds: 16));
}

/// 名单挂在 transform 里面，量之前先把抽屉开到位
Future<void> _openAndSettle(WidgetTester t, int row) async {
  await _tapRow(t, row);
  await _pump(t, 1200);
}

void main() {
  // ------------------------------------------------------------ 出图

  testWidgets('10. 名单 静止：底部裁掉 54', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c10_idle', child: const Case10Roster());
  });

  testWidgets('10. 名单 悬停：药丸刷上 6% 墨', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_hover',
      child: const Case10Roster(),
      act: (t) => ilHoverAt(t, t.getRect(find.byKey(const ValueKey('row-1'))).center),
      thenMs: 220,
    );
  });

  testWidgets('10. 名单 勾选途中：抽屉半开、勾画了一半', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_pick',
      child: const Case10Roster(),
      act: (t) => _tapRow(t, 0),
      thenMs: 96,
    );
  });

  testWidgets('10. 名单 勾画完那拍：环没了、勾已经画满', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_tick_done',
      child: const Case10Roster(),
      act: (t) => _tapRow(t, 0),
      thenMs: 336,
    );
  });

  testWidgets('10. 名单 展开到位：Send 2 requests', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_two',
      child: const Case10Roster(),
      act: (t) async {
        await _tapRow(t, 0);
        await _pump(t, 800);
        await _tapRow(t, 2);
      },
      thenMs: 900,
    );
  });

  testWidgets('10. 名单 按住 CTA：压到 .975', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_press',
      child: const Case10Roster(),
      act: (t) async {
        await _tapRow(t, 1);
        await _pump(t, 900);
        await ilGrab(t, on: find.byKey(const ValueKey('cta')));
      },
      // 400ms 而不是几十毫秒：按压弹簧 `{500,30}` 的收敛判据是 2e-4，
      // 要 ~320ms 才真的钉在 .975 上，早拍读到的是"正在压下去"的中间值
      thenMs: 400,
    );
  });

  testWidgets('10. 名单 勾画到一半：只画到拐角之前', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_tick_mid',
      child: const Case10Roster(),
      act: (t) => _tapRow(t, 0),
      // 出图铺垫本身吃掉 ~48ms，加上这一档总共 ~88ms：勾的 60ms delay 刚过、
      // 260ms 行程走了个零头，正好停在拐角之前
      thenMs: 40,
    );
  });

  testWidgets('10. 名单 已发送：勾全清、抽屉还开着', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_sent',
      child: const Case10Roster(),
      act: (t) async {
        await _tapRow(t, 0);
        await _pump(t, 700);
        await _tapRow(t, 2);
        await _pump(t, 900);
        await _tapCta(t);
      },
      thenMs: 900,
    );
  });

  testWidgets('10. 名单 收回途中：CTA 前半程几乎不出现', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c10_close',
      child: const Case10Roster(),
      act: (t) async {
        await _tapRow(t, 0);
        await _pump(t, 900);
        await _tapRow(t, 0);
      },
      thenMs: 144,
    );
  });

  // ------------------------------------------------------------ 断言

  testWidgets('几何：盒 268×224、行 46/4、头像 32、勾 19、CTA 44', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _openAndSettle(tester, 0);
    final box = _boxRect(tester);
    expect(box.width, 268);
    // 裁切不改布局：收起态占位也是 224 高
    expect(box.height, 224);

    for (var i = 0; i < 3; i++) {
      final r = tester.getRect(find.byKey(ValueKey('row-$i')));
      expect(r.top, closeTo(box.top + 10 + i * 50, 0.01), reason: 'padding10 + 行46 + gap4');
      expect(r.height, 46);
      expect(r.width, 248);

      final av = tester.getRect(find.byKey(ValueKey('av-${['mara', 'ines', 'kai'][i]}')));
      expect(av.width, 32);
      expect(av.height, 32);
      expect(av.left, closeTo(r.left + 9, 0.01), reason: '行内 padding 0 9px');
      expect(av.center.dy, closeTo(r.center.dy, 0.01));

      final tk = tester.getRect(find.byKey(ValueKey('tick-$i')));
      expect(tk.width, 19);
      expect(tk.height, 19);
      expect(tk.right, closeTo(r.right - 9, 0.01), reason: '行的右内边距 9，不是盒子的 10');
      expect(tk.center.dy, closeTo(r.center.dy, 0.01));
    }

    final cta = tester.getRect(find.byKey(const ValueKey('cta')));
    expect(cta.width, 248);
    expect(cta.height, 44);
    expect(cta.bottom, closeTo(box.bottom - 10, 0.01));
    expect(cta.top - tester.getRect(find.byKey(const ValueKey('row-2'))).bottom, closeTo(14, 0.01),
        reason: 'gap 4 + CTA 的 margin-top 10');
    await unmountPage(tester);
  });

  testWidgets('排版：姓名 13/400 墨色，handle 11.5/字距 0/45% 墨', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    final name = _whoText(tester, 0, 0);
    final handle = _whoText(tester, 0, 1);
    expect(name.data, 'Nadia Okonkwo');
    expect(handle.data, '@nadia');
    expect(name.style!.fontSize, 13);
    expect(name.style!.fontWeight, FontWeight.w400);
    expect(name.style!.color, IlColor.ink);
    expect(handle.style!.fontSize, 11.5);
    expect(handle.style!.letterSpacing, 0);
    expect(handle.style!.color, IlColor.ink.withValues(alpha: 0.45));
    expect(
      tester.getRect(find.byWidget(handle)).top -
          tester.getRect(find.byWidget(name)).bottom,
      closeTo(1, 0.6),
      reason: '.rst-who 的 gap:1px',
    );
    await unmountPage(tester);
  });

  testWidgets('收起态：opacity 0 / y -14 / scale .96，并且点不到 CTA', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    expect(_opa(tester, 'cta-a'), 0);
    expect(_xf(tester, 'cta-xf', 13), -14);
    expect(_xf(tester, 'cta-xf', 0), closeTo(0.96, 1e-9));
    // `initial={false}` → 文案首帧就钉在 animate 值上，也就是 0
    expect(_labelA(tester), 0);
    expect(_labelText(tester), 'Send 0 requests');
    expect(_ctaText(tester).style!.color, IlColor.ink5);
    expect(_ctaText(tester).style!.fontSize, 13.5);
    expect(_ctaText(tester).style!.letterSpacing, closeTo(-0.005 * 13.5, 1e-6));

    await tester.tap(find.byKey(const ValueKey('cta')), warnIfMissed: false);
    await _pump(tester, 200);
    expect(_opa(tester, 'cta-a'), 0, reason: '被 clip 裁掉的区域不该受理点击');

    final dec = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(const ValueKey('cta')), matching: find.byType(DecoratedBox)),
    );
    expect((dec.decoration as BoxDecoration).color, IlColor.ink.withValues(alpha: 0.07));
    await unmountPage(tester);
  });

  testWidgets('展开：三条派生量都从同一根弹簧出来，分段 opacity 对得上', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _tapRow(tester, 0);

    final seen = <double>[];
    for (var f = 0; f < 60; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final p = _pFromY(tester);
      seen.add(p);
      final a = _opa(tester, 'cta-a');
      final want = p >= 54 ? 0.0 : (p > 27 ? (54 - p) / 27 * 0.15 : 0.15 + (27 - p) / 27 * 0.85);
      expect(a, closeTo(want, 1e-6), reason: 'p=$p 那一拍的 opacity');
      expect(_xf(tester, 'cta-xf', 0), closeTo(0.96 + 0.04 * (1 - p / 54), 1e-6));
    }
    expect(seen.first, lessThan(54), reason: 'aim 之后第一帧就该动了');
    expect(seen.first, greaterThan(40));
    // `useTransform` 把输入夹在 [0,54]：弹簧在 22 拍后钻到零以下，读数就全钉在 0 了，
    // 所以"一路有帧"只能数到 22 拍不同的正数——再往后要靠收尾那 10 拍不动来证明走完了
    expect(seen.where((v) => v > 0).length, greaterThan(18), reason: '弹簧得一路有帧');
    expect(seen.last, 0);
    expect(_opa(tester, 'cta-a'), 1);
    expect(_xf(tester, 'cta-xf', 13), 0);
    expect(_xf(tester, 'cta-xf', 0), closeTo(1, 1e-9));
    await unmountPage(tester);
  });

  testWidgets('文案先淡出再换：count=1 是 Send request', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _openAndSettle(tester, 0);
    expect(_labelText(tester), 'Send request');
    expect(_labelA(tester), 1);

    // 从 1 条改到 2 条：淡出没走完之前，挂在树上的还得是老文案
    await _tapRow(tester, 1);
    await tester.pump(const Duration(milliseconds: 64));
    expect(_labelText(tester), 'Send request', reason: 'mode:wait —— 退出没走完不换孩子');
    expect(_labelA(tester), lessThan(0.6));
    await _pump(tester, 320);
    expect(_labelText(tester), 'Send 2 requests');
    expect(_labelA(tester), 1);
    await unmountPage(tester);
  });

  testWidgets('先点第 3 行再点第 1 行：行序不动，计数照加', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _tapRow(tester, 2);
    await _pump(tester, 400);
    await _tapRow(tester, 0);
    await _pump(tester, 1400);

    final onScreen = tester
        .widgetList<Text>(find.byType(Text))
        .map((e) => e.data)
        .where((s) => _names.contains(s))
        .toList();
    expect(onScreen, ['Nadia Okonkwo', 'Tomas Cardoso', 'Kai Brenner']);
    expect(_labelText(tester), 'Send 2 requests');
    // 两枚勾都弹到 1.1，中间那枚（没选）留在 1
    expect(_xf(tester, 'tick-xf-0', 0), closeTo(1.1, 1e-6));
    expect(_xf(tester, 'tick-xf-2', 0), closeTo(1.1, 1e-6));
    expect(_xf(tester, 'tick-xf-1', 0), closeTo(1, 1e-9));
    await unmountPage(tester);
  });

  testWidgets('发送：勾全清但抽屉不收回；再点一行退出已发送', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _tapRow(tester, 0);
    await _pump(tester, 900);
    await _tapCta(tester);
    await _pump(tester, 1400);

    expect(_labelText(tester), 'Requests sent');
    expect(_opa(tester, 'cta-a'), 1, reason: 'f = 有选中 || 已发送 → 抽屉保持展开');
    expect(_xf(tester, 'cta-xf', 13), 0);
    for (var i = 0; i < 3; i++) {
      expect(_xf(tester, 'tick-xf-$i', 0), closeTo(1, 1e-6), reason: '第 $i 行的勾要退回原尺寸');
    }
    expect(find.byKey(const ValueKey('dot-0')), findsNothing, reason: '墨点是 fill 翻过来才有的');

    await _tapRow(tester, 1);
    await _pump(tester, 700);
    expect(_labelText(tester), 'Send request');
    expect(_opa(tester, 'cta-a'), 1);
    await unmountPage(tester);
  });

  testWidgets('取消最后一勾：抽屉收回，皮换回 disabled 那档', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _openAndSettle(tester, 1);
    expect(_opa(tester, 'cta-a'), 1);

    await _tapRow(tester, 1);
    await _pump(tester, 1800);
    expect(_opa(tester, 'cta-a'), 0);
    expect(_xf(tester, 'cta-xf', 13), -14);
    final dec = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(const ValueKey('cta')), matching: find.byType(DecoratedBox)),
    );
    expect((dec.decoration as BoxDecoration).color, IlColor.ink.withValues(alpha: 0.07));
    await unmountPage(tester);
  });

  testWidgets('hover 两个方向时长不同：进 140ms、出 220ms', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    final at = tester.getRect(find.byKey(const ValueKey('row-1'))).center;
    final g = await ilHoverAt(tester, at);
    await _pump(tester, 64);
    final mid = _opa(tester, 'pill-1');
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    await _pump(tester, 96);
    expect(_opa(tester, 'pill-1'), 1, reason: '140ms 该到位');

    await g.moveTo(const Offset(400, 40));
    await _pump(tester, 160);
    expect(_opa(tester, 'pill-1'), greaterThan(0), reason: '220ms 的出场，160ms 不该已经归零');
    await _pump(tester, 96);
    expect(_opa(tester, 'pill-1'), 0);
    await g.removePointer();
    await unmountPage(tester);
  });

  testWidgets('goo 层只在选中那格挂着：σ=4、外扩 24', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    expect(find.byKey(const ValueKey('dot-0')), findsNothing);

    await _tapRow(tester, 0);
    await tester.pump(const Duration(milliseconds: 16));
    final dot = find.byKey(const ValueKey('dot-0'));
    // 两份是 IlGoo 的 `feComposite in=SourceGraphic atop`：一份进模糊，一份原样压在上面
    expect(dot, findsNWidgets(2));
    expect(tester.getSize(dot.first), const Size(19, 19));

    final goo = find.ancestor(of: dot, matching: find.byType(Positioned)).first;
    final pos = tester.widget<Positioned>(goo);
    expect(pos.left, -24);
    expect(pos.width, 67);
    expect(pos.height, 67, reason: '滤镜区不往外留，圆盘会被盒子边切平');
    final filt = find.descendant(of: goo, matching: find.byType(ImageFiltered));
    expect(filt, findsOneWidget);
    expect(tester.widget<ImageFiltered>(filt).imageFilter.toString(), contains('blur(4.0, 4.0'));
    expect(find.descendant(of: goo, matching: find.byType(ColorFiltered)), findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('逐帧扫 1200ms：勾选和抽屉一路有帧在动，收尾钉死', (tester) async {
    await mountIlCase(tester, const Case10Roster());
    await _tapRow(tester, 0);
    final snaps = <String>[];
    for (var f = 0; f < 75; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(
        '${_pFromY(tester).toStringAsFixed(4)}|${_xf(tester, 'tick-xf-0', 0).toStringAsFixed(4)}'
        '|${_labelA(tester).toStringAsFixed(4)}',
      );
    }
    expect(tester.takeException(), isNull);
    // 抽屉那根弹簧 22 拍就被 [0,54] 夹住读数、tick 的 scale 19 拍钉死、文案 140ms 走完：
    // 三条时间线各自都在动，合起来的不同快照不该只有一两拍
    expect(snaps.toSet().length, greaterThan(20));
    // 弹簧过冲：tick 的 scale 一度越过 1.1（`{220,14,.5}`，ζ=0.667）
    final scales = [for (final s in snaps) double.parse(s.split('|').elementAt(1))];
    expect(scales.reduce(math.max), greaterThan(1.1));

    final geo = '${_pFromY(tester)}|${_xf(tester, 'tick-xf-0', 0)}|${_labelA(tester)}';
    for (var f = 0; f < 10; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect('${_pFromY(tester)}|${_xf(tester, 'tick-xf-0', 0)}|${_labelA(tester)}', geo);
    }
    await unmountPage(tester);
  });
}
