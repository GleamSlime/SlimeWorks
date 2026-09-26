import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_11_command_bar.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 11 号 Command bar：一条输入框 + 一颗从右端"走出来"的发送钮
//
// 断言要证明的九件事：
// 1. **白色形状一个都不在内容层**：条和钮各自往 goo 层投一块剪影，内容层只有文字/
//    图标（armed 才有底）。goo 层外扩 69、σ=3、alpha 行是 `22a − 8.67`。
// 2. **静默态钮被完全塞进条里**：缝 = 8 − 48 = −40，钮右缘离条右缘还差 2px，
//    所以整块读数是一条干净的 274×56 胶囊。
// 3. **拉丝窗口只有 53ms**：缝从 −40 走到 +8，`0 < 缝 < 5` 那一截才连着；
//    桥一断（t≈204ms）就再也接不回来，末尾过冲到 9.44 再落回 8。
// 4. **四条时长各归各**：位移 520、宽/高 340、钮透明度 160、麦克风 150。
// 5. **armed 只翻色、不缩回**：`激活 = 聚焦 || 有文本`，所以删空文本（还带焦点）
//    钮留在外面，只有底色和箭头走 220ms 颜色补间翻回来。
// 6. **提交不抢焦点**：Enter 清文本，条还是 266、钮还在外面。
// 7. **回程没有拉丝**：缝一下降到 5 以内只用了两帧，因为入场曲线前段极陡。
// 8. **麦克风只有淡入淡出**：hover 换色是瞬时的（CSS 那条 transition 里没 color）。
// 9. **按住钮压到 .92**，剪影跟着一起缩；松手回 1 且带 .003 的过冲。
//
// 读数的口径：全部从树上取，不看像素。
// - 缝用 `slab-go-pos` 的 left 减 `slab-bar` 的 right，**不用 getRect 量钮**：
//   钮那块剪影挂在 `Transform` 底下，按住那 0.92 会把 rect 缩掉 1.85px，读数就假了。
// - `Positioned` 自己不产 RenderObject，`getRect` 拿到的是孩子的（被 Transform 影响），
//   所以位移一律读 `widget<Positioned>(...).left`。

/// 缝 = 钮左缘 − 条右缘（goo 之前两块剪影的几何边）
///
/// 两边都得用**组件栈自己的坐标系**：`Positioned.left` 是相对栈的，`getRect` 是窗口绝对
/// 坐标，直接相减会把 goo 层那 69 的滤镜留白和舞台那 26 的偏移混进来，静默态读成 −21。
double _seam(WidgetTester t) =>
    t.widget<Positioned>(find.byKey(const ValueKey('go-pos'))).left! - _barW(t);

double _barW(WidgetTester t) => t.getRect(find.byKey(const ValueKey('slab-bar'))).width;
double _goW(WidgetTester t) => t.widget<Positioned>(find.byKey(const ValueKey('slab-go-pos'))).width!;
double _goA(WidgetTester t) => t.widget<Opacity>(find.byKey(const ValueKey('go-a'))).opacity;
double _micA(WidgetTester t) => t.widget<Opacity>(find.byKey(const ValueKey('mic-a'))).opacity;

double _slabScale(WidgetTester t) =>
    t.widget<Transform>(find.byKey(const ValueKey('slab-go-xf'))).transform.storage[0];

double _goScale(WidgetTester t) => t.widgetList<Transform>(
  find.descendant(of: find.byKey(const ValueKey('go-pos')), matching: find.byType(Transform)),
).first.transform.storage[0];

Color _goBg(WidgetTester t) =>
    (t.widget<DecoratedBox>(find.byKey(const ValueKey('go-bg'))).decoration as BoxDecoration).color!;

IlIcon _icon(WidgetTester t, String box) => t.widget<IlIcon>(
  find.descendant(of: find.byKey(ValueKey(box)), matching: find.byType(IlIcon)),
);

/// 两色之间取个"到底走了几成"，用来验 220ms 那条颜色补间
double _armP(WidgetTester t) => (255 - _goBg(t).r * 255) / (255 - 0x17);

Future<void> _pump(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    await t.pump(const Duration(milliseconds: 16));
    left -= 16;
  }
}

/// 按 8ms 半步推：整步会把缝跨过 0 到 5 那一截整个跳过去
Future<void> _half(WidgetTester t, int frames) async {
  for (var f = 0; f < frames; f++) {
    await t.pump(const Duration(milliseconds: 8));
  }
}

/// 得把 `character` 显式递进去：只报 logicalKey 时合成事件不带字符，组件会退回键名，
/// 量到的就成了 'HI' —— 和真实敲进来的 'hi' 不是一回事
Future<void> _type(WidgetTester t, String text) async {
  for (final r in text.codeUnits) {
    await t.sendKeyEvent(LogicalKeyboardKey(r), character: String.fromCharCode(r));
  }
}

Future<void> _focus(WidgetTester t) => t.tap(find.byKey(const ValueKey('hit-bar')));

Future<void> _focusAndSettle(WidgetTester t) async {
  await _focus(t);
  await _pump(t, 700);
}

/// 点组件外面：失焦（浏览器由焦点管理器干，这里得自己给个出口）
Future<void> _blur(WidgetTester t) async {
  final at = t.getRect(find.byType(IlStage)).topLeft + const Offset(20, 12);
  await t.tapAt(at);
  await t.pump();
}

void main() {
  // ------------------------------------------------------------ 出图

  testWidgets('11. 命令条 静止：一条干净的胶囊，钮藏在里面', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c11_idle', child: const Case11CommandBar());
  });

  testWidgets('11. 命令条 拉丝那一拍：缝 2~4px，钮还没断', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_bridge',
      child: const Case11CommandBar(),
      act: _focus,
      thenMs: 144,
    );
  });

  testWidgets('11. 命令条 到位：266 + 8 + 46，麦克风没了', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_out',
      child: const Case11CommandBar(),
      act: _focus,
      thenMs: 900,
    );
  });

  testWidgets('11. 命令条 淡出中途：麦克风半透、钮刚冒头', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_mic',
      child: const Case11CommandBar(),
      act: _focus,
      thenMs: 16,
    );
  });

  testWidgets('11. 命令条 armed：深底白箭头 + 输入的字', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_armed',
      child: const Case11CommandBar(),
      act: (t) async {
        await _focusAndSettle(t);
        await _type(t, 'hi');
      },
      thenMs: 320,
    );
  });

  testWidgets('11. 命令条 提交中途：钮不收回，底色正在翻回白', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_unarm',
      child: const Case11CommandBar(),
      act: (t) async {
        await _focusAndSettle(t);
        await _type(t, 'hi');
        await _pump(t, 320);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
      },
      thenMs: 96,
    );
  });

  testWidgets('11. 命令条 按住钮：整块压到 .92', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_press',
      child: const Case11CommandBar(),
      act: (t) async {
        await _focusAndSettle(t);
        await _type(t, 'hi');
        await _pump(t, 320);
        await ilGrab(t, on: find.byKey(const ValueKey('go-bg')));
      },
      thenMs: 400,
    );
  });

  testWidgets('11. 命令条 收回途中：钮正被条吞回去', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c11_back',
      child: const Case11CommandBar(),
      act: (t) async {
        await _focusAndSettle(t);
        await _blur(t);
      },
      thenMs: 96,
    );
  });

  // ------------------------------------------------------------ 断言

  testWidgets('goo 层：外扩 69、σ=3、alpha 行 `22a − 8.67`，静默态两块剪影就位', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());

    final goo = find.byKey(const ValueKey('goo'));
    final pos = tester.widget<Positioned>(goo);
    expect(pos.left, -69, reason: 'ceil(3*3 + 60)：滤镜区不往外留，模糊边会被盒子切掉');
    expect(pos.width, 320 + 138);
    expect(pos.height, 56 + 138);

    final filt = find.descendant(of: goo, matching: find.byType(ImageFiltered));
    expect(tester.widget<ImageFiltered>(filt).imageFilter.toString(), contains('blur(3.0, 3.0'));
    expect(find.descendant(of: goo, matching: find.byType(ColorFiltered)), findsOneWidget,
        reason: 'alpha 行 `22a − 8.67` 是那道硬阈值；够不够得着由量像素那一头钉（缝 ≤5px 才连）');

    // 静默态：条 274×56 圆角 28，钮 38 圆整块藏在条里（右缘还差 2px 才到条边）
    expect(_barW(tester), 274);
    final dec = tester.widget<DecoratedBox>(find.byKey(const ValueKey('slab-bar')));
    final rad = (dec.decoration as BoxDecoration).borderRadius! as BorderRadius;
    expect(rad.topLeft, const Radius.circular(28), reason: '--cmd-r = clamp(28,0,28)，正好是高度一半');
    expect((dec.decoration as BoxDecoration).color, IlColor.pane);
    expect(_goW(tester), 38);
    expect(_seam(tester), -40);
    final goRect = tester.getRect(find.byKey(const ValueKey('slab-go')));
    expect(goRect.right, closeTo(tester.getRect(find.byKey(const ValueKey('slab-bar'))).right - 2, 0.01));
    expect(goRect.height, 38);
    await unmountPage(tester);
  });

  testWidgets('静默态：钮不透明度 0 且点不到，麦克风满格且受理点击', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    expect(_goA(tester), 0);
    expect(_micA(tester), 1);
    expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('go-hit'))).ignoring, isTrue);
    expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('mic-hit'))).ignoring, isFalse,
        reason: '原稿的 tabIndex 互斥：未激活 mic=0 / go=-1');
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('text')), findsNothing);

    // 排版：15px / 字距 −.005em / 占位 #85847E；条内边距 0 8px 0 20px
    final hint = tester.widget<Text>(find.byKey(const ValueKey('placeholder')));
    expect(hint.data, 'Ask anything...');
    expect(hint.style!.fontSize, 15);
    expect(hint.style!.letterSpacing, closeTo(-0.075, 1e-9), reason: '-.005em × 15px');
    expect(hint.style!.color, IlColor.ink5);
    final bar = tester.getRect(find.byKey(const ValueKey('hit-bar')));
    expect(tester.getRect(find.byKey(const ValueKey('placeholder'))).left, closeTo(bar.left + 20, 0.1));
    expect(tester.getRect(find.byKey(const ValueKey('mic-a'))).right, closeTo(bar.right - 8, 0.1));
    expect(tester.getRect(find.byKey(const ValueKey('mic-a'))).height, 36);
    expect(_icon(tester, 'mic-a').size, 18);
    expect(_icon(tester, 'mic-a').strokeWidth, 2);
    expect(_icon(tester, 'mic-a').color, IlColor.ink4);
    expect(_icon(tester, 'go-pos').size, 20, reason: 'arrow-up 比 mic 大两号');
    await unmountPage(tester);
  });

  testWidgets('展开：缝 −40 → 0 → 拉丝 → 过冲 9.4 → 落回 8', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focus(tester);

    final seams = <double>[];
    for (var f = 0; f < 90; f++) {
      await _half(tester, 1);
      seams.add(_seam(tester));
    }
    expect(seams.first, lessThan(-25), reason: '起手钮还在条里面');
    // 桥的判据：σ=3 配 `22a − 8.67`，中点 α = erfc(g/(2σ√2)) 要留到 .394 → g ≤ 5.0px
    final bridging = seams.where((s) => s > 0 && s < 5).toList();
    expect(bridging.length, greaterThan(3), reason: '0<缝<5 那一截就是"拉丝"本身：$seams');
    expect(seams.reduce(math.max), greaterThan(9.0), reason: 'cubic-bezier(.22,1.3,.71,1) 的过冲');
    expect(seams.reduce(math.max), lessThan(9.7));
    expect(seams.last, 8, reason: '到位：gap 恒 8');
    expect(seams.where((s) => s > 8.05).length, greaterThan(10), reason: '过冲得持续几十毫秒才看得出来');

    // 收尾：钟停了，缝和宽度都不再动
    for (var f = 0; f < 10; f++) {
      await _half(tester, 1);
      expect(_seam(tester), 8);
      expect(_barW(tester), 266);
    }
    await unmountPage(tester);
  });

  testWidgets('四条时长各自收表：150 淡出麦克风、160 淡入钮、340 走完宽高、520 才停位移', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focus(tester);

    // 每条线的"最后一次变化"落在哪一拍：CSS 的四个 transition 各是一个 duration，
    // 用读数变化点卡住它们，比卡中途值稳（第一拍的 dt 未必正好 8ms）
    final series = <String, List<double>>{'seam': [], 'barW': [], 'goA': [], 'micA': [], 'goW': []};
    for (var f = 0; f < 90; f++) {
      await _half(tester, 1);
      series['seam']!.add(_seam(tester));
      series['barW']!.add(_barW(tester));
      series['goW']!.add(_goW(tester));
      series['goA']!.add(_goA(tester));
      series['micA']!.add(_micA(tester));
    }
    double lastChange(List<double> s) {
      for (var i = s.length - 1; i > 0; i--) {
        if (s[i] != s[i - 1]) return (i + 1) * 8.0;
      }
      return 0;
    }

    expect(lastChange(series['goA']!), closeTo(160, 24), reason: 'opacity .16s');
    expect(lastChange(series['micA']!), closeTo(150, 24), reason: 'opacity .15s');
    expect(lastChange(series['barW']!), closeTo(340, 24), reason: 'width .34s');
    expect(lastChange(series['goW']!), closeTo(340, 24));
    expect(lastChange(series['seam']!), closeTo(520, 24), reason: 'morph 520ms');

    // 顺序也得对：宽度和位移都还没走完时，透明度早就钉上了
    expect(series['goA']![15], greaterThan(0.9), reason: '128ms 那拍透明度已经快满了');
    expect(series['goA']![22], 1, reason: '160ms 一到就钉住');
    expect(series['seam']![22], lessThan(5), reason: '同一拍位移还没探出条外');
    expect(series['barW']![15], isNot(266.0),
        reason: '宽度这条 128ms 就已经贴着 266 了，真正钉住在 340 —— 中途值看不出来，只能看停表点');

    // 过冲：宽度会走过目标再回来（barW 一度低于 266、goW 高于 46）
    expect(series['barW']!.reduce(math.min), lessThan(266), reason: 'cubic-bezier(.24,1.34,.38,1) y1=1.34');
    expect(series['goW']!.reduce(math.max), greaterThan(46));
    await unmountPage(tester);
  });

  testWidgets('armed：敲字翻深底白箭头，钮留在外面；删空了也只翻色', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focusAndSettle(tester);
    await _type(tester, 'hi');
    // sendKeyEvent 一帧都不推：文本层要 build 才换，读数之前得推真帧
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<Text>(find.byKey(const ValueKey('text'))).data, 'hi');
    expect(find.byKey(const ValueKey('placeholder')), findsNothing);

    // 而且键事件之后的头一帧是这个 tick 的“对表帧”（elapsed 0），补间值原地不动：
    // 想在半路上读到颜色走了一半，至少得推过第二帧
    await _pump(tester, 64);
    final mid = _armP(tester);
    expect(mid, greaterThan(0.1), reason: '220ms 的颜色补间，这几十毫秒只走了一小截');
    expect(mid, lessThan(0.92));

    await _pump(tester, 240);
    expect(_goBg(tester), IlColor.ink);
    expect(_icon(tester, 'go-pos').color, IlColor.pane);
    expect(_seam(tester), 8, reason: '激活 = 聚焦 || 有文本 → 早就激活了，钮不动');
    expect(_barW(tester), 266);

    // 退格删空但还带焦点：文本层换回占位，底色翻回白，钮**不**收回
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await _pump(tester, 320);
    expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);
    expect(_goBg(tester), IlColor.pane);
    expect(_icon(tester, 'go-pos').color, IlColor.ink);
    expect(_seam(tester), 8, reason: 'focused 还在 → active 还在，只有 armed 掉了');
    expect(_goA(tester), 1);
    await unmountPage(tester);
  });

  testWidgets('Enter 提交：清空文本但不失焦，条宽和钮位置都不改', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focusAndSettle(tester);
    await _type(tester, 'run');
    await _pump(tester, 300);
    expect(_goBg(tester), IlColor.ink);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester, 300);
    expect(find.byKey(const ValueKey('text')), findsNothing);
    expect(_goBg(tester), IlColor.pane, reason: '提交 = 清文本，不 blur → 只解除 armed');
    expect(_seam(tester), 8);
    expect(_barW(tester), 266);
    expect(_goA(tester), 1);

    // 失焦才走全套
    await _blur(tester);
    await _pump(tester, 700);
    expect(_seam(tester), -40);
    expect(_barW(tester), 274);
    expect(_goW(tester), 38);
    expect(_goA(tester), 0);
    expect(_micA(tester), 1);
    expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('go-hit'))).ignoring, isTrue);
    await unmountPage(tester);
  });

  testWidgets('回程没有拉丝：两帧之内缝就掉到 5 以内', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focusAndSettle(tester);
    await _blur(tester);

    final seams = <double>[];
    for (var f = 0; f < 80; f++) {
      await _half(tester, 1);
      seams.add(_seam(tester));
    }
    expect(seams[1], lessThan(5), reason: '入场曲线前段陡（x1=.22 → 8ms 就吃掉 .09）：$seams');
    expect(seams[1], greaterThan(-5));
    expect(seams.last, -40, reason: '回程终点还是那条干净的胶囊');
    // 一路单调往回走，中间不该有第二次"探出来"
    expect(seams.where((s) => s > 8.0).isEmpty, isTrue);
    await unmountPage(tester);
  });

  testWidgets('麦克风：只有淡入淡出，hover 换色是瞬时的', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    final micAt = tester.getRect(find.byKey(const ValueKey('mic-a'))).center;
    final g = await ilHoverAt(tester, micAt);
    await tester.pump();
    expect(_icon(tester, 'mic-a').color, IlColor.ink, reason: '.cmd-mic 的 transition 里只有 opacity');
    expect(_micA(tester), 1, reason: 'hover 不碰透明度');
    final box = tester.getRect(find.byKey(const ValueKey('mic-a')));
    expect((box.center - micAt).distance, lessThan(0.01), reason: '不位移');
    expect(box.height, 36, reason: '不缩放');

    await g.moveTo(const Offset(400, 30));
    await tester.pump();
    expect(_icon(tester, 'mic-a').color, IlColor.ink4);
    // 一根鼠标设备只有一个指针：后面还要 tap，这里先注销
    await g.removePointer();
    await tester.pump();

    // 激活后 mic 淡出并被 IgnorePointer 挡掉
    await _focus(tester);
    await _pump(tester, 200);
    expect(_micA(tester), 0);
    expect(tester.widget<IgnorePointer>(find.byKey(const ValueKey('mic-hit'))).ignoring, isTrue);
    await unmountPage(tester);
  });

  testWidgets('按住钮：整块压到 .92，剪影同缩；松手回 1 带过冲', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focusAndSettle(tester);
    await _type(tester, 'hi');
    await _pump(tester, 300);
    final left = tester.widget<Positioned>(find.byKey(const ValueKey('go-pos'))).left;

    final hold = await ilGrab(tester, on: find.byKey(const ValueKey('go-bg')));
    await _pump(tester, 360);
    expect(_slabScale(tester), closeTo(0.92, 1e-9));
    expect(_goScale(tester), closeTo(0.92, 1e-9), reason: '内容层和剪影层同一根 scale');
    expect(tester.widget<Positioned>(find.byKey(const ValueKey('go-pos'))).left, left,
        reason: ':active 只有 scale，位移是 morph 那根 520ms 的补间在管');

    await ilDrop(tester, hold);
    await _half(tester, 4);
    expect(_slabScale(tester), greaterThan(0.92), reason: '320ms 的出场，4 帧才走了一小截');
    var peak = 0.0;
    for (var f = 0; f < 45; f++) {
      await _half(tester, 1);
      peak = math.max(peak, _slabScale(tester));
    }
    expect(peak, greaterThan(1.0), reason: '回弹会越过 1');
    expect(peak, lessThan(1.01));
    expect(_slabScale(tester), closeTo(1, 1e-9));
    await unmountPage(tester);
  });

  testWidgets('逐帧扫 1200ms：四路各自在动，收尾钉死', (tester) async {
    await mountIlCase(tester, const Case11CommandBar());
    await _focus(tester);
    final snaps = <String>[];
    for (var f = 0; f < 45; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(
        '${_seam(tester).toStringAsFixed(4)}|${_barW(tester).toStringAsFixed(4)}'
        '|${_goA(tester).toStringAsFixed(4)}|${_armP(tester).toStringAsFixed(4)}',
      );
    }
    await _type(tester, 'ok');
    for (var f = 0; f < 20; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(
        '${_seam(tester).toStringAsFixed(4)}|${_barW(tester).toStringAsFixed(4)}'
        '|${_goA(tester).toStringAsFixed(4)}|${_armP(tester).toStringAsFixed(4)}',
      );
    }
    expect(tester.takeException(), isNull);
    expect(snaps.toSet().length, greaterThan(40), reason: '四路时间线合起来不该只有一二十拍在动');
    final seams = [for (final s in snaps) double.parse(s.split('|').first)];
    expect(seams.reduce(math.max), greaterThan(9.0));
    expect(seams.where((s) => s > 0 && s < 5).length, greaterThan(1),
        reason: '整步 16ms 的网格上，0<缝<5 那一截也就落在两三拍上');
    expect(seams.last, 8);

    final geo = snaps.last;
    for (var f = 0; f < 12; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        '${_seam(tester).toStringAsFixed(4)}|${_barW(tester).toStringAsFixed(4)}'
        '|${_goA(tester).toStringAsFixed(4)}|${_armP(tester).toStringAsFixed(4)}',
        geo,
        reason: '第 $f 拍还在动 —— 停表条件没满足',
      );
    }
    await unmountPage(tester);
  });
}
