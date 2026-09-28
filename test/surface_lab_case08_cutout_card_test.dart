import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_08_cutout_card.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/page_golden.dart' show advance, loadAppFonts, pumpAppPage;
import 'helpers/sv_golden.dart';

/// 8 号镂空卡：接缝的几何是锚出来的，三层时长是各走各的
///
/// 树上的读数钉三样：**外壳那三档糊光的两个端点**（静止/悬停的偏移·模糊·扩散和描边
/// 透明度）、**接缝的锚**（四块垫角相对标签自己那条边各探出 31/23、回叠 1）、
/// **三层的时长分歧**（500ms 走满时 700ms 那层还在路上）。
/// 图是本地马赛克（实现里的本地例外第 1 条），所以不比像素内容，只比它推近到的 1.05。
void main() {
  const stage = Size(Case08CutoutCard.stageW, Case08CutoutCard.stageH);
  Size win() => svWindow(stageW: stage.width, stageH: stage.height);

  Rect face(WidgetTester t, Key k) => t.getRect(find.byKey(k));

  BoxDecoration shell(WidgetTester t) =>
      t.widget<DecoratedBox>(find.byKey(Case08CutoutCard.cardKey)).decoration as BoxDecoration;

  List<BoxShadow> ring(WidgetTester t) => shell(t).boxShadow!;

  Color stroke(WidgetTester t) => (shell(t).border! as Border).top.color;

  double artScale(WidgetTester t) =>
      t.widget<Transform>(find.byKey(Case08CutoutCard.artKey)).transform.entry(0, 0);

  double actionOpacity(WidgetTester t) => t
      .widget<Opacity>(
          find.ancestor(of: find.byKey(Case08CutoutCard.actionKey), matching: find.byType(Opacity)).first)
      .opacity;

  // 补间的端点不指望原值：模糊半径过了一趟 sigma 往返，描边色过了色彩空间混合
  void expectBlur(WidgetTester t, List<double> blurs) {
    final got = ring(t).map((s) => s.blurRadius).toList();
    for (var i = 0; i < blurs.length; i++) {
      expect(got[i], closeTo(blurs[i], 0.02), reason: '第 $i 档模糊');
    }
  }

  void expectStroke(WidgetTester t, double alpha) {
    final c = stroke(t);
    expect(c.a, closeTo(alpha, 0.004), reason: '描边透明度');
    for (final v in [c.r, c.g, c.b]) {
      expect(v, closeTo(0xE5 / 255, 0.004), reason: '描边还是 --border 那一档灰');
    }
  }

  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) async => mountSvCase(t, const Case08CutoutCard(), window: win());

  /// 把鼠标指针压到某个坐标（出图/断言完要 removePointer 才不影响下一帧）
  Future<TestGesture> hover(WidgetTester t, Offset at) => svHoverAt(t, at);

  /// 卡外面 4px 的那条留白：退场用它，窗口坐标都还是正的
  Offset away(WidgetTester t) => face(t, Case08CutoutCard.cardKey).topLeft - const Offset(4, 4);

  group('出图', () {
    testWidgets('c08_idle：静止档 —— 壳是浅糊光，胶囊还没进来', (t) async {
      await shootSvCase(t, name: 'c08_idle', child: const Case08CutoutCard(), window: win());
    }, tags: 'golden');

    testWidgets('c08_mid：悬停 250ms，三层各在半路上', (t) async {
      late TestGesture g;
      await shootSvCase(
        t,
        name: 'c08_mid',
        child: const Case08CutoutCard(),
        window: win(),
        act: (t) async => g = await hover(t, face(t, Case08CutoutCard.cardKey).center),
        thenMs: 250,
      );
      await g.removePointer();
    }, tags: 'golden');

    testWidgets('c08_hover：悬停走满，壳加深、图推近、胶囊浮进右下角', (t) async {
      late TestGesture g;
      await shootSvCase(
        t,
        name: 'c08_hover',
        child: const Case08CutoutCard(),
        window: win(),
        act: (t) async => g = await hover(t, face(t, Case08CutoutCard.cardKey).center),
        thenMs: 760,
      );
      await g.removePointer();
    }, tags: 'golden');

    testWidgets('c08_touch：指尖点一下当指针进来并停在原地', (t) async {
      await shootSvCase(
        t,
        name: 'c08_touch',
        child: const Case08CutoutCard(),
        window: win(),
        act: (t) async => svTap(t),
        thenMs: 760,
      );
    }, tags: 'golden');

    testWidgets('c08_reduced：减弱动效点一下直接到终态，不演一半', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case08CutoutCard(),
            ),
          ),
        ),
        size: win(),
      );
      await advance(t);
      await svTap(t);
      await t.pump();
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c08_reduced.png'));
      expect(t.takeException(), isNull);
      await unmountPage(t);
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('外框：448×484 含 1px 描边，坐在舞台正中', (t) async {
      await mount(t);
      final card = face(t, Case08CutoutCard.cardKey);
      expect(card.size, const Size(448, 484));
      expect(t.getRect(find.byType(SvStage)).center, card.center);
      // 描边里面那一格 446×482
      final media = face(t, Case08CutoutCard.mediaKey);
      expect(media.size, const Size(446, 288));
      expect(media.topLeft, card.topLeft + const Offset(1, 1));
      // 指尖那一格：整张卡就是受理区，远在 44 以上
      expect(card.shortestSide, greaterThanOrEqualTo(svTapMinSide));
      await unmountPage(t);
    });

    testWidgets('内容区从图的下面一格开始，四段落按量到的落点摆', (t) async {
      await mount(t);
      final card = face(t, Case08CutoutCard.cardKey);
      final title = face(t, Case08CutoutCard.titleKey);
      expect(title.left - card.left, closeTo(25, 0.1), reason: '1 描边 + p-6');
      expect(title.top - card.top, closeTo(1 + 288 + 24, 0.1));
      // 行盒按整像素取整：20/27.5 实测 28.0，所以这里只认落点、不认段落自己多出来的半格
      expect(title.height, closeTo(27.5, 1));
      final body = face(t, Case08CutoutCard.bodyKey);
      expect(body.width, closeTo(398, 0.1));
      expect(body.top - card.top, closeTo(348.5, 0.1), reason: '24 + 27.5 + 8');
      // 正文必须是两行：三行就把内容区顶爆了（194 是量出来的死数）
      expect(body.height, closeTo(45.5, 1));
      final foot = face(t, Case08CutoutCard.footKey);
      expect(foot.top - card.top, closeTo(427, 0.1), reason: '再往下 hairline 1 + 内衬 16');
      expect(foot.height, closeTo(32, 0.1));
      expect(foot.width, closeTo(398, 0.1));
      expect(foot.right - card.right, closeTo(-25, 0.1));
      // 页脚那一行：头像 32、让 12、名字，读数贴右
      final avatar = face(t, Case08CutoutCard.avatarKey);
      expect(avatar.size, const Size(32, 32));
      expect(avatar.left, closeTo(foot.left, 0.1));
      final name = face(t, Case08CutoutCard.nameKey);
      expect(name.left - avatar.right, closeTo(12, 0.1));
      expect(name.center.dy, closeTo(avatar.center.dy, 0.6));
      final time = face(t, Case08CutoutCard.timeKey);
      expect(time.right, closeTo(foot.right, 0.6));
      expect(time.height, closeTo(16, 0.1));
      // 内容区底部还剩 24 的内衬（加那 1px 描边就是 25）
      expect(card.bottom - foot.bottom, closeTo(25, 0.1));
      await unmountPage(t);
    });

    testWidgets('接缝：四块垫角都锚在标签自己的边上，探出 31/23、回叠 1', (t) async {
      await mount(t);
      final media = face(t, Case08CutoutCard.mediaKey);
      final label = face(t, Case08CutoutCard.labelKey);
      // 标签贴着图的下边和左边，只有右上一个角是圆的
      expect(label.left, media.left);
      expect(label.bottom, closeTo(media.bottom, 0.1));
      expect(label.height, closeTo(49.2, 0.1));
      expect(label.width, closeTo(105.1, 3), reason: '内衬撑出来的，字形差一档就算对');
      final top = face(t, Case08CutoutCard.flareKey('label-top'));
      final right = face(t, Case08CutoutCard.flareKey('label-right'));
      expect(top.size, const Size(32, 32));
      expect(right.size, const Size(32, 32));
      expect(top.left - label.left, closeTo(-1, 0.1));
      expect(top.top - label.top, closeTo(-31, 0.1));
      expect(top.bottom - label.top, closeTo(1, 0.1), reason: '下沿只往标签里叠 1px');
      expect(right.left - label.right, closeTo(-1, 0.1));
      expect(right.right - label.right, closeTo(31, 0.1));
      expect(right.bottom - label.bottom, closeTo(1, 0.1));

      // 深的那枚贴着图的上边和右边，两块垫角一块往左铺、一块往下铺
      final pin = face(t, Case08CutoutCard.pinKey);
      expect(pin.top, media.top);
      expect(pin.right, closeTo(media.right, 0.1));
      expect(pin.height, closeTo(36, 0.1));
      expect(pin.width, closeTo(62, 3));
      final left = face(t, Case08CutoutCard.flareKey('pin-left'));
      final bottom = face(t, Case08CutoutCard.flareKey('pin-bottom'));
      expect(left.size, const Size(24, 24));
      expect(bottom.size, const Size(24, 24));
      expect(left.left - pin.left, closeTo(-23, 0.1));
      expect(left.top, pin.top);
      expect(left.right - pin.left, closeTo(1, 0.1));
      expect(bottom.right - pin.right, closeTo(1, 0.1));
      expect(bottom.top - pin.bottom, closeTo(-1, 0.1));
      expect(bottom.bottom - pin.bottom, closeTo(23, 0.1));
      await unmountPage(t);
    });

    testWidgets('外壳两端点：偏移·模糊·扩散和描边一起走，退场原路回来', (t) async {
      await mount(t);
      expect(shell(t).color, const Color(0xFFFFFFFF));
      expectStroke(t, 0xCC / 255);
      expect(ring(t).map((s) => s.offset).toList(), const <Offset>[Offset(0, 1), Offset(0, 4), Offset(0, 8)]);
      expect(ring(t).map((s) => s.spreadRadius).toList(), const <double>[-1, -2, -4]);
      expectBlur(t, <double>[2, 8, 16]);
      expect(ring(t).map((s) => (s.color.a * 255).roundToDouble()).toList(), <double>[20, 15, 13]);

      await svTap(t);
      await run(t, 520);
      expectStroke(t, 1);
      expect(ring(t).map((s) => s.offset).toList(), const <Offset>[Offset(0, 2), Offset(0, 8), Offset(0, 16)]);
      expect(ring(t).map((s) => s.spreadRadius).toList(), const <double>[-1, -4, -8]);
      expectBlur(t, <double>[4, 16, 32]);
      expect(ring(t).map((s) => (s.color.a * 255).roundToDouble()).toList(), <double>[26, 20, 15]);

      await svTap(t);
      await run(t, 520);
      expectBlur(t, <double>[2, 8, 16]);
      expectStroke(t, 0xCC / 255);
      await unmountPage(t);
    });

    testWidgets('三层时长各走各的：500 走满时图还在 700 的路上', (t) async {
      await mount(t);
      final g = await hover(t, face(t, Case08CutoutCard.cardKey).center);
      await run(t, 520);
      expectBlur(t, <double>[4, 16, 32]);
      expect(actionOpacity(t), 1, reason: '胶囊：300ms 早进完了');
      expect(artScale(t), greaterThan(1.0));
      expect(artScale(t), lessThan(1.05), reason: '图：700ms 还在推');
      await run(t, 200);
      expect(artScale(t), closeTo(1.05, 1e-9));
      await g.moveTo(away(t));
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('推近只推画层：图那一格、两枚标签、垫角一步没挪', (t) async {
      await mount(t);
      final keys = <Key>[
        Case08CutoutCard.mediaKey,
        Case08CutoutCard.labelKey,
        Case08CutoutCard.pinKey,
        Case08CutoutCard.flareKey('label-top'),
        Case08CutoutCard.flareKey('label-right'),
        Case08CutoutCard.flareKey('pin-left'),
        Case08CutoutCard.flareKey('pin-bottom'),
        Case08CutoutCard.titleKey,
        Case08CutoutCard.footKey,
      ];
      final before = [for (final k in keys) face(t, k)];
      final g = await hover(t, face(t, Case08CutoutCard.cardKey).center);
      await run(t, 760);
      expect(artScale(t), closeTo(1.05, 1e-9));
      for (var i = 0; i < keys.length; i++) {
        expect(face(t, keys[i]), before[i], reason: '${keys[i]} 不该跟着推近');
      }
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('胶囊：静止淡掉并沉 8，悬停浮到 right20/bottom20 那一格', (t) async {
      await mount(t);
      final card = face(t, Case08CutoutCard.cardKey);
      expect(actionOpacity(t), 0);
      // 沉下去那一档就是参考稿静止时量到的上沿 435
      expect(face(t, Case08CutoutCard.actionKey).top - card.top, closeTo(435, 0.1));
      final g = await hover(t, card.center);
      await run(t, 320);
      expect(actionOpacity(t), 1);
      final at = face(t, Case08CutoutCard.actionKey);
      // 那一格过了一层平移，全局 Rect 的宽是减出来的，所以只认容差不认位相等
      expect(at.width, closeTo(102.6, 0.01));
      expect(at.height, closeTo(36, 0.01));
      expect(card.right - at.right, closeTo(21, 0.1), reason: '描边 1 + right 20');
      expect(card.bottom - at.bottom, closeTo(21, 0.1));
      expect(at.top - card.top, closeTo(427, 0.1));
      // 和页脚那一行同一条上沿，正好压住那行读数
      expect(at.top, closeTo(face(t, Case08CutoutCard.footKey).top, 0.1));
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('减弱动效：点一下三层同时到位，再点一下同时回来', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case08CutoutCard(),
            ),
          ),
        ),
        size: win(),
      );
      await advance(t);
      final card = face(t, Case08CutoutCard.cardKey);
      expectBlur(t, <double>[2, 8, 16]);
      await svTap(t);
      await t.pump();
      expectBlur(t, <double>[4, 16, 32]);
      expectStroke(t, 1);
      expect(artScale(t), closeTo(1.05, 1e-9));
      expect(actionOpacity(t), 1);
      expect(face(t, Case08CutoutCard.actionKey).top - card.top, closeTo(427, 0.1));
      await svTap(t);
      await t.pump();
      expectBlur(t, <double>[2, 8, 16]);
      expect(actionOpacity(t), 0);
      await unmountPage(t);
    });

    testWidgets('鼠标点一下不改悬停语义：按下松手后照样能退场', (t) async {
      await mount(t);
      final card = face(t, Case08CutoutCard.cardKey);
      final g = await hover(t, card.center);
      await run(t, 520);
      expectBlur(t, <double>[4, 16, 32]);
      // 同一根鼠标指针按下再松手：桌面的 click 不能被当成"指尖按住并停在原地"
      await g.down(card.center);
      await g.up();
      await t.pump();
      expectBlur(t, <double>[4, 16, 32]);
      await g.moveTo(away(t));
      await run(t, 520);
      expectBlur(t, <double>[2, 8, 16]);
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('逐帧扫 2s：反复进出悬停，全程不抛', (t) async {
      await mount(t);
      final card = face(t, Case08CutoutCard.cardKey);
      final out = away(t);
      final g = await hover(t, card.center);
      for (var i = 0; i < 30; i++) {
        await g.moveTo(i.isEven ? card.center : out);
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.moveTo(card.center);
      // 最后这一次进场的原点是刚才那一下，700ms 那层得给它走满
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expectBlur(t, <double>[4, 16, 32]);
      expect(artScale(t), closeTo(1.05, 1e-9));
      expect(actionOpacity(t), 1);
      await g.removePointer();
      expect(t.takeException(), isNull);
      await unmountPage(t);
    });
  });
}
