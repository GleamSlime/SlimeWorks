import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_06_expandable.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/page_golden.dart' show loadAppFonts, pumpAppPage;
import 'helpers/sv_golden.dart';

/// 6 号折叠区：外壳两条弹簧 + 里面三段各自量自然高
///
/// 钉的都是树上的几何：卡片盒在两头正好是 320×240 / 420×480，三段内容的高
/// 是量尺量出来的自然高，页眉那几枚的落点全部按参考稿的 padding 层级推。
/// 动效只断言三个可观察特征：外壳会过冲、五个通道同帧起步、stagger 那一路
/// 按 .2s 一档错开（退场没有 stagger，三档一起淡）。
void main() {
  const sw = Case06Expandable.stageW;
  const sh = Case06Expandable.stageH;
  final win = svWindow(stageW: sw, stageH: sh);

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect card(WidgetTester t) => t.getRect(find.byKey(Case06Expandable.cardKey));
  Rect box(WidgetTester t, Key k) => t.getRect(find.byKey(k));

  /// 卡片内容盒（白卡本体 C 的内沿）左上角：参考稿是 A(0) > B(p-2) > C(p-4)
  Offset contentAt(WidgetTester t) => card(t).topLeft + const Offset(8 + 16, 8 + 16);

  /// 按 16ms 一步步推：一次 `pump(N)` 在假异步里只出一帧，弹簧会把整段时长钳成一拍
  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) async {
    await mountSvCase(t, const Case06Expandable(), window: win);
  }

  Future<void> toggle(WidgetTester t) async {
    await t.tap(find.byKey(Case06Expandable.triggerKey));
    await t.pump();
  }

  /// detail 那一路的 Opacity：深度优先的顺序就是 块本身 + 三档孩子
  List<double> fades(WidgetTester t) => t
      .widgetList<Opacity>(find.descendant(of: find.byKey(Case06Expandable.detailKey), matching: find.byType(Opacity)))
      .map((o) => double.parse(o.opacity.toStringAsFixed(4)))
      .toList();

  group('出图', () {
    testWidgets('c06_collapsed：320×240，只到时间那行', (t) async {
      await shootSvCase(t, name: 'c06_collapsed', child: const Case06Expandable(), window: win);
    }, tags: 'golden');

    testWidgets('c06_mid：展开途中，外壳已经顶过 480，里面三段还在长', (t) async {
      await shootSvCase(
        t,
        name: 'c06_mid',
        child: const Case06Expandable(),
        window: win,
        act: (t) async => await toggle(t),
        thenMs: 320,
      );
    }, tags: 'golden');

    testWidgets('c06_stagger：三档孩子各差 .2s，最后一档刚起步', (t) async {
      await shootSvCase(
        t,
        name: 'c06_stagger',
        child: const Case06Expandable(),
        window: win,
        act: (t) async => await toggle(t),
        thenMs: 460,
      );
    }, tags: 'golden');

    testWidgets('c06_expanded：420×480 落定，全部内容就位', (t) async {
      await shootSvCase(
        t,
        name: 'c06_expanded',
        child: const Case06Expandable(),
        window: win,
        act: (t) async => await toggle(t),
        thenMs: 2400,
      );
    }, tags: 'golden');

    testWidgets('c06_tip：悬停日历钮，tooltip 悬在正上方', (t) async {
      TestGesture? g;
      await shootSvCase(
        t,
        name: 'c06_tip',
        child: const Case06Expandable(),
        window: win,
        act: (t) async {
          await toggle(t);
          await run(t, 2200);
          g = await svHoverAt(t, box(t, Case06Expandable.calKey).center);
        },
        thenMs: 200,
      );
      await g!.removePointer();
    }, tags: 'golden');

    testWidgets('c06_collapse：收回去那一路三档一起淡，不错开', (t) async {
      await shootSvCase(
        t,
        name: 'c06_collapse',
        child: const Case06Expandable(),
        window: win,
        act: (t) async {
          await toggle(t);
          await run(t, 2000);
          await toggle(t);
        },
        thenMs: 160,
      );
    }, tags: 'golden');

    testWidgets('c06_reduced：减弱动效，切换就在这一帧', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case06Expandable(),
            ),
          ),
        ),
        size: win,
      );
      await run(t, 200);
      await toggle(t);
      await run(t, 400);
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c06_reduced.png'));
      expect(t.takeException(), isNull);
      await unmountPage(t);
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止：320×240 居中，三段内容高度全 0', (t) async {
      await mount(t);
      expect(card(t).size, const Size(320, 240));
      final at = stageAt(t);
      expect(card(t).center - at, const Offset(sw / 2, sh / 2));
      // 页眉：p-6 让开 24，badge 是 16 字 + py-0.5 + 1px 透明描边 = 22 高
      expect(box(t, Case06Expandable.badgeKey).topLeft - contentAt(t), const Offset(24, 24));
      expect(box(t, Case06Expandable.badgeKey).height, 22);
      expect(box(t, Case06Expandable.titleKey).top, box(t, Case06Expandable.badgeKey).top);
      // 32×32 的图标钮贴在页眉右沿
      final cal = box(t, Case06Expandable.calKey);
      expect(cal.size, const Size(32, 32));
      expect(cal.right, contentAt(t).dx + Case06Expandable.innerW(320) - 24);
      // 内容盒宽 = 卡片宽 - 2×(8+16)；Content 自己再让 16
      expect(box(t, Case06Expandable.timeKey).left - card(t).left, 8 + 16 + 16);
      for (final k in [Case06Expandable.roomKey, Case06Expandable.detailKey, Case06Expandable.footKey]) {
        expect(box(t, k).height, 0);
      }
      // 页脚那一段贴在白卡内沿的底上
      expect(box(t, Case06Expandable.footKey).top, card(t).bottom - 8 - 16);
      await unmountPage(t);
    });

    testWidgets('展开落定：420×480，三段各自长到量出来的自然高', (t) async {
      await mount(t);
      await toggle(t);
      await run(t, 2400);
      expect(card(t).size, const Size(420, 480));
      expect(box(t, Case06Expandable.roomKey).height, 20);
      // 说明(3 行 60 + 16) + 与会人(20 + 8 + 32 + 16) + 两枚钮(36 + 8 + 36)
      expect(box(t, Case06Expandable.detailKey).height, 232);
      expect(box(t, Case06Expandable.footKey).height, 36);
      // 页脚自己 p-4 pt-0：文字 20 高，底让 16
      expect(box(t, Case06Expandable.footKey).bottom, card(t).bottom - 24);
      // -space-x-2：四枚 32 的圆每枚叠掉 8，一排 104 宽
      expect(box(t, Case06Expandable.avatarKey(3)).left - box(t, Case06Expandable.avatarKey(0)).left, 72);
      expect(box(t, Case06Expandable.avatarKey(0)).size, const Size(32, 32));
      // Open Chat 只在展开态挂着
      expect(find.byKey(Case06Expandable.chatKey), findsOneWidget);
      await unmountPage(t);
    });

    testWidgets('外壳是弹簧不是补间：途中顶过 480，落定正好回到 480', (t) async {
      await mount(t);
      await toggle(t);
      var peak = 240.0;
      for (var i = 0; i < 40; i++) {
        await run(t, 16);
        peak = peak > card(t).height ? peak : card(t).height;
      }
      await run(t, 1600);
      // ζ = 20/(2√200) = .707 → 过冲约 4.3%（240 的行程 ≈ 10px），但不该跑到 520
      expect(peak, greaterThan(480));
      expect(peak, lessThan(520));
      expect(card(t).height, closeTo(480, 0.01));
      await unmountPage(t);
    });

    testWidgets('五条通道同一帧一起起步', (t) async {
      await mount(t);
      await toggle(t);
      await run(t, 48);
      expect(card(t).height, greaterThan(240));
      expect(card(t).width, greaterThan(320));
      for (final k in [Case06Expandable.roomKey, Case06Expandable.detailKey, Case06Expandable.footKey]) {
        expect(box(t, k).height, greaterThan(0), reason: '$k 和外壳一起动');
      }
      await unmountPage(t);
    });

    testWidgets('stagger：三档各差 .2s，一档走完才轮到下一档', (t) async {
      await mount(t);
      await toggle(t);
      // 块自己的淡入(0~300)已经走完：fades = [块, 说明, 与会人, 钮]
      await run(t, 460);
      final f = fades(t);
      expect(f.length, greaterThanOrEqualTo(4));
      expect(f.first, 1.0);
      expect(f[1], 1.0); // 0ms 起
      expect(f[2], allOf(greaterThan(0), lessThan(1))); // 200ms 起
      expect(f[3], lessThan(f[2])); // 400ms 起
      await run(t, 700);
      expect(fades(t).skip(1).every((v) => v == 1.0), isTrue);
      await unmountPage(t);
    });

    testWidgets('退场没有 stagger：三档一起淡，只有外壳在缩', (t) async {
      await mount(t);
      await toggle(t);
      await run(t, 2400);
      await toggle(t);
      await run(t, 150);
      final f = fades(t);
      // 参考稿的孩子只有 hidden/visible 两个 variant，没写 exit —— 收回去时
      // 三档全是 1，淡的是块自己（糊和淡都挂在块那一层）
      expect(f.first, lessThan(1));
      expect(f.skip(1).every((v) => v == 1.0), isTrue);
      await run(t, 2400);
      expect(card(t).size, const Size(320, 240));
      expect(find.byKey(Case06Expandable.chatKey), findsNothing);
      await unmountPage(t);
    });

    testWidgets('tooltip：悬停才出现，落在锚点上方让 4px', (t) async {
      await mount(t);
      final g = await svHoverAt(t, t.getCenter(find.byKey(Case06Expandable.calKey)));
      await run(t, 200);
      final tip = find.byKey(const ValueKey<String>('${Case06Expandable.tipPrefix}calendar'));
      expect(tip, findsOneWidget);
      final cal = box(t, Case06Expandable.calKey);
      expect(box(t, const ValueKey<String>('${Case06Expandable.tipPrefix}calendar')).bottom, closeTo(cal.top - 4, 0.01));
      // 移出锚点：tooltip 走的是 onExit，和它自己那 150ms 的淡出是两件事
      await g.moveTo(Offset.zero);
      await run(t, 200);
      expect(tip, findsNothing);
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('键盘：点一下拿到焦点，Enter 和 Space 都切换', (t) async {
      await mount(t);
      await toggle(t);
      await run(t, 2400);
      expect(card(t).height, closeTo(480, 0.01));
      await t.sendKeyDownEvent(LogicalKeyboardKey.space);
      await run(t, 2400);
      expect(card(t).height, closeTo(240, 0.01));
      await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await run(t, 2400);
      expect(card(t).height, closeTo(480, 0.01));
      await unmountPage(t);
    });

    testWidgets('减弱动效：切换没有补间，直接落位', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case06Expandable(),
            ),
          ),
        ),
        size: win,
      );
      await run(t, 200);
      await toggle(t);
      await t.pump();
      expect(card(t).size, const Size(420, 480));
      expect(box(t, Case06Expandable.detailKey).height, 232);
      expect(fades(t).skip(1).every((v) => v == 1.0), isTrue);
      await toggle(t);
      await t.pump();
      expect(card(t).size, const Size(320, 240));
      await unmountPage(t);
    });

    testWidgets('逐帧扫：来回切四次，全程不抛', (t) async {
      await mount(t);
      for (var i = 0; i < 480; i++) {
        await t.pump(const Duration(milliseconds: 16));
        card(t);
        if (i % 120 == 60) await toggle(t);
      }
      expect(t.takeException(), isNull);
      await unmountPage(t);
    });
  });
}
