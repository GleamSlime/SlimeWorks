import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_02_floating_panel.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/sv_golden.dart';

/// 2 号悬浮面板：面板落在按钮下面，只有那一行字飞过去
///
/// 这一格的三个动作各有各的时钟（面板 t=0、正文 t=200、页脚 t=300），
/// 读数一律换成舞台坐标：outside-click 吃的是舞台坐标，硬写窗口坐标会连
/// 偏移方向都反掉。
void main() {
  // 按钮左缘 = 面板左缘（`left: triggerRect.left`），面板挂在按钮下缘再往下 8
  const origin = Offset(58, 8);
  const panelTop = 52.0;
  const panelW = 256.0;
  const panelH = 214.0;
  // 那行字的两个落点：x 同轨（都是"左缘 + 1 描边 + 16 px-4"），行程纯竖直 45
  const textX = 75.0;
  const textFromY = 16.0;
  const textToY = 61.0;

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect btn(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.btnKey));
  Rect panel(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.panelKey));
  Rect title(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.titleKey));
  Rect body(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.bodyKey));
  Rect footer(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.footerKey));
  Rect arrow(WidgetTester t) => t.getRect(find.byKey(Case02FloatingPanel.arrowKey));
  Rect swatch(WidgetTester t, int i) => t.getRect(find.byKey(Case02FloatingPanel.swatchKey(i)));
  Rect btnText(WidgetTester t) => t.getRect(
        find.descendant(of: find.byKey(Case02FloatingPanel.btnKey), matching: find.byType(Text)),
      );

  /// 最近的那一层 `Opacity`：面板自己那层在更外面，所以要 `first` 不能 `single`
  double fade(WidgetTester t, Key key) => t
      .widgetList<Opacity>(find.ancestor(of: find.byKey(key), matching: find.byType(Opacity)))
      .first
      .opacity;

  /// 按钮那一份字：`Opacity` 在 `btnKey` 里面（它包着 `Text`），所以走 descendant
  double btnFade(WidgetTester t) => t.widget<Opacity>(
        find.descendant(of: find.byKey(Case02FloatingPanel.btnKey), matching: find.byType(Opacity)),
      ).opacity;

  /// 面板此刻"还差多少没落到位"：它就是 `_u.value`，10 → 0
  double off(WidgetTester t) => panel(t).top - stageAt(t).dy - panelTop;

  /// 一次 `pump(N ms)` 在假异步里只出一帧，行程一律按 ≤16ms 一步步推。
  /// 一次 `pump(N ms)` 在假异步里只出一帧，行程一律按 ≤16ms 一步步推。
  /// 另外 `aim()` 只把树标脏：动手之后要先 `pump()` 一帧，那棵树才长出来
  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) =>
      mountSvCase(t, const Case02FloatingPanel(), window: svWindow(stageH: 288));

  Future<void> openIt(WidgetTester t) async {
    await svTap(t);
    // 最晚起跳的是页脚（300ms），它自己的行程还要再走 400ms
    await run(t, 820);
  }

  group('出图', () {
    testWidgets('c02_idle：只有那颗按钮', (t) async {
      await shootSvCase(t, name: 'c02_idle', child: const Case02FloatingPanel());
    }, tags: 'golden');

    testWidgets('c02_mid：面板落了一半，正文和页脚还没轮到', (t) async {
      await shootSvCase(
        t,
        name: 'c02_mid',
        child: const Case02FloatingPanel(),
        act: svTap,
        thenMs: 64,
      );
    }, tags: 'golden');

    testWidgets('c02_stagger：正文进来了，页脚还压在下面', (t) async {
      await shootSvCase(
        t,
        name: 'c02_stagger',
        child: const Case02FloatingPanel(),
        act: svTap,
        thenMs: 256,
      );
    }, tags: 'golden');

    testWidgets('c02_open：全部落定，那行字已经在面板里了', (t) async {
      await shootSvCase(
        t,
        name: 'c02_open',
        child: const Case02FloatingPanel(),
        act: svTap,
        thenMs: 820,
      );
    }, tags: 'golden');

    testWidgets('c02_hover：一颗色块被放大到 1.1', (t) async {
      await mountSvCase(t, const Case02FloatingPanel(), window: svWindow(stageH: 288));
      await openIt(t);
      final g = await svHoverAt(t, swatch(t, 1).center);
      await run(t, 460);
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c02_hover.png'));
      expect(t.takeException(), isNull);
      await g.removePointer();
      await unmountPage(t);
    }, tags: 'golden');

    // 这一格不能走 `shootSvCase`：它拍完就拆树，按住的那根指针还没松，
    // 拆完之后松手会把 PointerUp 路由给已 dispose 的 Listener → setState after dispose
    testWidgets('c02_press：色块按住 0.9，背景整片糊掉', (t) async {
      await mountSvCase(t, const Case02FloatingPanel(), window: svWindow(stageH: 288));
      await openIt(t);
      final hold = await svGrab(t, on: find.byKey(Case02FloatingPanel.swatchKey(4)));
      await run(t, 460);
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c02_press.png'));
      expect(t.takeException(), isNull);
      await svDrop(t, hold);
      await unmountPage(t);
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止：36 高的按钮在 (58,8)，没有面板也没有糊', (t) async {
      await mount(t);
      final at = stageAt(t);
      expect(btn(t).topLeft, at + origin);
      expect(btn(t).height, closeTo(36, 0.1));
      // 描边 1px 把字往里让一格，`px-4` 是 16 → 字面左缘 +17；行高 20 在 34 里居中 +8
      expect(btnText(t).topLeft, at + const Offset(textX, textFromY));
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('展开：256×214 挂在按钮下缘 +8，左缘对齐', (t) async {
      await mount(t);
      final at = stageAt(t);
      await openIt(t);
      expect(panel(t).topLeft, at + Offset(origin.dx, panelTop));
      expect(panel(t).size, const Size(panelW, panelH));
      expect(panel(t).left, closeTo(btn(t).left, 0.2), reason: '`left: triggerRect.left`');
      expect(panel(t).top - btn(t).bottom, closeTo(8, 0.2));
      // 三段内容盒：标题 36、正文 136、页脚 40，描边各让 1
      expect(body(t).top - panel(t).top, closeTo(37, 0.2));
      expect(body(t).size, const Size(254, 136));
      expect(footer(t).size, const Size(254, 40));
      expect(panel(t).bottom - footer(t).bottom, closeTo(1, 0.2));
      await unmountPage(t);
    });

    testWidgets('那行字落在 75/61，按钮那一份只是被藏起来', (t) async {
      await mount(t);
      final at = stageAt(t);
      final wide = btn(t).width;
      expect(btnText(t).topLeft, at + const Offset(textX, textFromY));
      await openIt(t);
      expect(title(t).topLeft, at + const Offset(textX, textToY));
      expect(title(t).height, closeTo(20, 0.2));
      // 交接：按钮那一份按 opacity 0 收起来，但格子还占着位（按钮不会缩成一小条）
      expect(btnFade(t), 0);
      expect(btn(t).width, closeTo(wide, 0.2));
      await unmountPage(t);
    });

    testWidgets('飞的是纯竖直的一程：横漂为零，纵走满 45', (t) async {
      await mount(t);
      final at = stageAt(t);
      await svTap(t);
      final ys = <double>[];
      for (var i = 0; i < 26; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final r = title(t);
        // 共享元素走的是屏幕插值：两个落点 x 同轨，全程不该有一横向的分毫
        expect(r.left - at.dx, closeTo(textX, 0.2));
        ys.add(r.top - at.dy);
      }
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThanOrEqualTo(ys[i - 1] - 0.02));
      }
      expect(ys.first, inInclusiveRange(textFromY, textToY));
      expect(ys.last, closeTo(textToY, 0.3));
      await unmountPage(t);
    });

    testWidgets('面板自己是绕左上角缩放的：落位前左上角不动', (t) async {
      await mount(t);
      final at = stageAt(t);
      await svTap(t);
      await run(t, 32);
      // `transformOrigin: top left` + `y:10`：位移和缩放吃的是同一条进度，
      // 所以不钉死在第几帧，只钉死这两个量之间的换算
      final u = panel(t).top - at.dy - panelTop;
      expect(u, inInclusiveRange(8.0, 10.0), reason: '此刻还在起点附近：$u');
      final s = 0.9 + 0.1 * (1 - u / 10);
      expect(panel(t).width / panelW, closeTo(s, 0.01));
      expect(panel(t).height / panelH, closeTo(s, 0.01));
      expect(panel(t).left, closeTo(at.dx + origin.dx, 0.2), reason: '缩放原点在左上角，左缘不动');
      // 那行字走的是屏幕坐标：面板缩到多少倍都不影响它，起点就是按钮那一档
      expect(title(t).top - at.dy, closeTo(textFromY + 45 * (1 - u / 10), 0.3));
      expect(title(t).left - at.dx, closeTo(textX, 0.2));
      await unmountPage(t);
    });

    testWidgets('分段入场按 200/300 起跳：不是慢一点走，是晚一点走', (t) async {
      await mount(t);
      await svTap(t);
      await run(t, 96);
      // 面板已经落了一半，正文和页脚还压在起点上
      expect(fade(t, Case02FloatingPanel.bodyKey), 0);
      expect(fade(t, Case02FloatingPanel.footerKey), 0);
      await run(t, 192);
      expect(
        fade(t, Case02FloatingPanel.bodyKey),
        inInclusiveRange(0.2, 0.95),
        reason: '正文起跳了',
      );
      expect(fade(t, Case02FloatingPanel.footerKey), 0, reason: '页脚此刻还没起跳');
      await run(t, 640);
      expect(fade(t, Case02FloatingPanel.footerKey), closeTo(1, 0.001));
      await unmountPage(t);
    });

    testWidgets('整块落定在 400ms 上下（bounce .1 / duration .4）', (t) async {
      await mount(t);
      await svTap(t);
      // 面板得先长出来才读得到顶边：`aim()` 只把树标脏，不建帧
      await t.pump();
      double? last;
      var prev = panel(t).top;
      for (var i = 1; i <= 60; i++) {
        await t.pump(const Duration(milliseconds: 8));
        final y = panel(t).top;
        if ((y - prev).abs() > 0.02) last = i * 8.0;
        prev = y;
      }
      expect(last, inInclusiveRange(340, 450), reason: '面板那一落 $last 才收口');
      expect(panel(t).top, closeTo(stageAt(t).dy + panelTop, 0.2));
      await unmountPage(t);
    });

    testWidgets('糊层只在面板活着的那一段挂上：`σ = 4p` 由出图复核', (t) async {
      await mount(t);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsNothing);
      await svTap(t);
      await t.pump();
      // 面板挂上了，可这一帧的钟还没走：σ 仍是 0，被 `>0.01` 那道闸拦在门外
      expect(find.byKey(Case02FloatingPanel.panelKey), findsOneWidget);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsNothing);
      await run(t, 48);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsOneWidget);
      await run(t, 800);
      // `fixed inset-0`：糊的是整块舞台底，不是面板那一小块
      expect(
        t.getRect(find.byKey(Case02FloatingPanel.blurKey)),
        t.getRect(find.byType(SvStage)),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      // 落回途中还挂着（面板还看得见），静止位才连糊层一起摘掉
      await run(t, 200);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsOneWidget);
      await run(t, 400);
      expect(find.byKey(Case02FloatingPanel.blurKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('三种收法：Escape、页脚那颗箭头、点外面', (t) async {
      await mount(t);
      final at = stageAt(t);
      await openIt(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await run(t, 500);
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing, reason: 'Escape 收掉');

      await openIt(t);
      await t.tapAt(arrow(t).center);
      await run(t, 500);
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing, reason: '箭头收掉');

      await openIt(t);
      // 面板之外、舞台之内：那一下落在 y=278，面板底在 266
      await t.tapAt(at + const Offset(200, 278));
      await run(t, 500);
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing, reason: '点外面收掉');

      await openIt(t);
      // 面板之内那一下不该收（`contains(target)` 直接 return）
      await t.tapAt(body(t).center);
      await run(t, 500);
      expect(panel(t).size, const Size(panelW, panelH), reason: '点在正文里不该收');
      await unmountPage(t);
    });

    testWidgets('收起只有面板在退：正文/页脚没有 exit 档，自己的透明度一直是 1', (t) async {
      await mount(t);
      await openIt(t);
      final openedTop = title(t).top;
      final bodyIn = body(t).top - panel(t).top;
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await run(t, 96);
      // 整块在往下坠（`y:10` 是倒着走的），但正文相对面板没挪：
      // 它的位移弹簧此刻还停在 0，只是被父级的 transform 一起带着走
      expect(body(t).top - panel(t).top, closeTo(bodyIn * (0.9 + 0.1 * (1 - off(t) / 10)), 0.6));
      // 各自那层 opacity 全程是 1：淡出只有面板那一份在演
      expect(fade(t, Case02FloatingPanel.bodyKey), closeTo(1, 1e-9));
      expect(fade(t, Case02FloatingPanel.footerKey), closeTo(1, 1e-9));
      expect(fade(t, Case02FloatingPanel.panelKey), lessThan(1));
      expect(title(t).top, lessThan(openedTop - 1), reason: '那行字正往按钮那一档退');
      await run(t, 400);
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing);
      expect(btnFade(t), 1);
      expect(btnText(t).top, closeTo(stageAt(t).dy + textFromY, 0.2));
      await unmountPage(t);
    });

    testWidgets('按钮 hover 1.05 / 按下 0.95，色块 1.1 / 0.9 且只动被指的那颗', (t) async {
      await mount(t);
      final g = await svHoverAt(t, btn(t).center);
      await run(t, 500);
      expect(btn(t).height, closeTo(36 * 1.05, 0.3));
      await g.removePointer();
      await run(t, 500);
      expect(btn(t).height, closeTo(36, 0.2));

      await openIt(t);
      final s1 = await svHoverAt(t, swatch(t, 2).center);
      await run(t, 500);
      expect(swatch(t, 2).width, closeTo(48 * 1.1, 0.3));
      // 一颗一条弹簧：合用一条会在"从 A 移到 B"的那几帧里让 A 跟着 B 一起变大
      expect(swatch(t, 1).width, closeTo(48, 0.2));
      expect(swatch(t, 3).width, closeTo(48, 0.2));
      await s1.removePointer();
      await run(t, 500);
      expect(swatch(t, 2).width, closeTo(48, 0.2));
      await unmountPage(t);
    });

    testWidgets('色块坐的是三列等宽轨道，轨道之间还夹着 gap', (t) async {
      await mount(t);
      await openIt(t);
      final at = stageAt(t);
      // `grid-cols-3 gap-2`：轨道 = (222−2×8)/3 = 68.67，圆点 48 靠左坐在轨道里，
      // 轨道之间再夹 8 的 gap —— 于是两颗圆点之间空的是 28.67 而不是 8，
      // 而最后一列右边余 20.67。参考稿就是这副"没填满"的样子
      expect(swatch(t, 0).left, closeTo(at.dx + textX, 0.2));
      expect(swatch(t, 0).size, const Size(48, 48));
      expect(swatch(t, 1).left - swatch(t, 0).left, closeTo(Case02FloatingPanel.track + 8, 0.2));
      expect(Case02FloatingPanel.track, closeTo((222 - 16) / 3, 0.01));
      expect(swatch(t, 1).left - swatch(t, 0).right, closeTo(28.67, 0.4));
      expect(swatch(t, 3).top - swatch(t, 0).bottom, closeTo(8, 0.2));
      expect(body(t).right - 16 - swatch(t, 2).right, closeTo(20.67, 0.4));
      await unmountPage(t);
    });

    testWidgets('逐帧扫 2400ms：开→悬停→收，全程不抛', (t) async {
      await mount(t);
      await svTap(t);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      final g = await svHoverAt(t, swatch(t, 0).center);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.removePointer();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
      expect(find.byKey(Case02FloatingPanel.panelKey), findsNothing);
      expect(btn(t).height, closeTo(36, 0.2));
      await unmountPage(t);
    });
  });
}
