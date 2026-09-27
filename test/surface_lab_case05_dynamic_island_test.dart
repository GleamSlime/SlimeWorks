import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_05_dynamic_island.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/page_golden.dart' show loadAppFonts, pumpAppPage;
import 'helpers/sv_golden.dart';

/// 5 号灵动岛：三条独立弹簧同时走 + 一档内容的进/退场
///
/// 树上的读数钉的是**几何**（`getRect(islandKey)` 拿到的就是弹簧途中的值）和
/// **两枚角标的文字**（逻辑档位）。弹簧轨迹本身是积分出来的，这里只断言它的
/// 三个可观察特征：过冲、三通道同时起步、收敛后正好落在预设终值上。
void main() {
  const stageH = Case05DynamicIsland.stageH;
  final win = svWindow(stageH: stageH);

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect island(WidgetTester t) => t.getRect(find.byKey(Case05DynamicIsland.islandKey));
  String badge(WidgetTester t, Key k) =>
      t.widget<Text>(find.descendant(of: find.byKey(k), matching: find.byType(Text))).data!;

  // 假时钟的当前位置：`mountSvCase` 自带 360ms 铺垫，之后一律按增量推
  int nowMs = 0;

  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      nowMs += step;
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) async {
    nowMs = 360;
    await mountSvCase(t, const Case05DynamicIsland(), window: win);
  }

  /// 推到从挂载算起的绝对时刻；只能往前推
  Future<void> to(WidgetTester t, int absMs) async {
    expect(absMs, greaterThanOrEqualTo(nowMs));
    await run(t, absMs - nowMs);
  }

  Future<void> tapCycle(WidgetTester t) async {
    await t.tap(find.byKey(Case05DynamicIsland.cycleKey));
    await t.pump();
  }

  group('出图', () {
    testWidgets('c05_idle：挂上来的第一档，150×44 的小黑条', (t) async {
      await shootSvCase(t, name: 'c05_idle', child: const Case05DynamicIsland(), window: win);
    }, tags: 'golden');

    testWidgets('c05_mid：开场第一步途中，弹簧正在过冲', (t) async {
      await shootSvCase(
        t,
        name: 'c05_mid',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 890,
      );
    }, tags: 'golden');

    testWidgets('c05_compact：235×44，左边一个气泡右边一行字', (t) async {
      await shootSvCase(
        t,
        name: 'c05_compact',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 1300,
      );
    }, tags: 'golden');

    testWidgets('c05_large：371×84，转圈的 loader + loading', (t) async {
      await shootSvCase(
        t,
        name: 'c05_large',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 2560,
      );
    }, tags: 'golden');

    testWidgets('c05_tall：371×210，两张青色便签压一行大标题', (t) async {
      await shootSvCase(
        t,
        name: 'c05_tall',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 4160,
      );
    }, tags: 'golden');

    testWidgets('c05_long：同样 371×84，换的是内容不是形状', (t) async {
      await shootSvCase(
        t,
        name: 'c05_long',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 5960,
      );
    }, tags: 'golden');

    testWidgets('c05_medium：371×210 但圆角收到 22，底下两枚钮', (t) async {
      await shootSvCase(
        t,
        name: 'c05_medium',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {},
        thenMs: 8160,
      );
    }, tags: 'golden');

    testWidgets('c05_cycle：播完之后点一下，从 medium 绕回圈首', (t) async {
      await shootSvCase(
        t,
        name: 'c05_cycle',
        child: const Case05DynamicIsland(),
        window: win,
        act: (t) async {
          // 出图路径不走 mount()，假时钟从 advance 的 360ms 起算
          await run(t, 9000 - 360);
          await tapCycle(t);
        },
        thenMs: 700,
      );
    }, tags: 'golden');

    testWidgets('c05_reduced：减弱动效，整段开场都不播', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case05DynamicIsland(),
            ),
          ),
        ),
        size: win,
      );
      await run(t, 9000);
      await expectLater(
        find.byType(SvStage),
        matchesGoldenFile('goldens/sv_c05_reduced.png'),
      );
      expect(t.takeException(), isNull);
      await unmountPage(t);
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止几何：150×44 贴在舞台下沿，左右居中', (t) async {
      await mount(t);
      final at = stageAt(t);
      final r = island(t);
      expect(r.size, const Size(150, 44));
      expect(r.bottom, closeTo(at.dy + stageH - Case05DynamicIsland.bottomInset, 0.01));
      expect(r.left - at.dx, closeTo((372 - 150) / 2, 0.01));
      // 角标读的是逻辑档位名
      expect(badge(t, Case05DynamicIsland.prevKey), 'prev - empty');
      expect(badge(t, Case05DynamicIsland.curKey), 'cur - default');
      // 控制带：按钮左上、角标右上。两拨在参考稿里差着 60px 的行距，
      // 横向投影是重叠的 —— 隔开它们的是行，不是列
      final btn = t.getRect(find.byKey(Case05DynamicIsland.cycleKey));
      expect(btn.topLeft - at, const Offset(48, 64));
      expect(btn.height, 36);
      final prev = t.getRect(find.byKey(Case05DynamicIsland.prevKey));
      expect(t.getRect(find.byKey(Case05DynamicIsland.curKey)).right, closeTo(at.dx + 372 - 8, 0.01));
      expect(prev.top - at.dy, 4);
      expect(prev.bottom, lessThanOrEqualTo(btn.top));
      // 舞台高度是给按钮让路的：最高的那挡岛（210）落定也不能压到按钮
      expect(at.dy + stageH - Case05DynamicIsland.bottomInset - 210, greaterThan(btn.bottom));
      // 最高的那挡岛（210）也不能顶到按钮
      expect(at.dy + stageH - Case05DynamicIsland.bottomInset - 210, greaterThan(btn.bottom));
      await unmountPage(t);
    });

    testWidgets('开场队列：五档按绝对时刻落，不是每档各等一个延时', (t) async {
      await mount(t);
      final steps = <int, String>{
        999: 'default',
        1001: 'compact',
        2199: 'compact',
        2201: 'large',
        3801: 'tall',
        5601: 'long',
        7801: 'medium',
      };
      var last = 360;
      for (final e in steps.entries) {
        await run(t, e.key - last);
        last = e.key;
        expect(badge(t, Case05DynamicIsland.curKey), 'cur - ${e.value}', reason: '${e.key}ms');
      }
      // 上一档跟着走：到 medium 时 prev 是 long
      expect(badge(t, Case05DynamicIsland.prevKey), 'prev - long');
      await unmountPage(t);
    });

    testWidgets('弹簧会过冲：途中比目标还宽，落定后正好等于预设', (t) async {
      await mount(t);
      await to(t, 1250);
      // 起步 250ms 正是过冲峰附近：150→235 那一段已经顶过 235
      expect(island(t).width, greaterThan(235));
      await to(t, 2100);
      expect(island(t).size, const Size(235, 44));
      await unmountPage(t);
    });

    testWidgets('宽/高/圆角是三条独立弹簧，但同一帧一起起步', (t) async {
      await mount(t);
      await to(t, 1700);
      expect(island(t).size, const Size(235, 44)); // compact 落定
      await to(t, 2300); // 起步 100ms：三通道都离开原位，且圆角在往下收
      final r = island(t);
      expect(r.width, greaterThan(235));
      expect(r.height, greaterThan(44));
      // 圆角读不出来，用"岛还在路上"这一事实兜住：宽高都没到位就说明没同步落定
      await to(t, 2900);
      expect(island(t).size, const Size(371, 84));
      await unmountPage(t);
    });

    testWidgets('岛永远贴下沿：五档走一遍，下边缘一动不动', (t) async {
      await mount(t);
      final at = stageAt(t);
      final bottom = at.dy + stageH - Case05DynamicIsland.bottomInset;
      for (final ms in [1100, 2400, 4000, 5800, 8000]) {
        await to(t, ms);
        expect(island(t).bottom, closeTo(bottom, 0.01), reason: '$ms ms 那帧');
        // 水平始终居中
        expect(island(t).center.dx, closeTo(at.dx + 372 / 2, 0.01));
      }
      await unmountPage(t);
    });

    testWidgets('换档那一瞬两块内容同时在树里，退场落定后只剩新的', (t) async {
      await mount(t);
      await to(t, 1050);
      expect(find.byKey(Case05DynamicIsland.faceKey(SvIsle.def)), findsOneWidget);
      expect(find.byKey(Case05DynamicIsland.faceKey(SvIsle.compact)), findsOneWidget);
      await to(t, 1900);
      expect(find.byKey(Case05DynamicIsland.faceKey(SvIsle.def)), findsNothing);
      expect(find.byKey(Case05DynamicIsland.faceKey(SvIsle.compact)), findsOneWidget);
      await unmountPage(t);
    });

    testWidgets('自动播放期间那颗按钮不受理，播完才归手点', (t) async {
      await mount(t);
      await to(t, 3000);
      await tapCycle(t);
      expect(badge(t, Case05DynamicIsland.curKey), 'cur - large'); // 没被点动
      await to(t, 9000);
      await tapCycle(t);
      expect(badge(t, Case05DynamicIsland.curKey), 'cur - compact');
      await unmountPage(t);
    });

    testWidgets('cycle 那一圈按参考稿的顺序走，走完回到第一档', (t) async {
      await mount(t);
      await to(t, 9000);
      // 开场停在 medium，再点就回到圈首的 compact
      final want = ['compact', 'large', 'tall', 'long', 'medium'];
      for (final w in want) {
        await tapCycle(t);
        expect(badge(t, Case05DynamicIsland.curKey), 'cur - $w');
        await run(t, 900); // 每档之间留够落定的时间
      }
      await unmountPage(t);
    });

    testWidgets('减弱动效：开场整段跳过，形状直接落位', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case05DynamicIsland(),
            ),
          ),
        ),
        size: win,
      );
      await run(t, 9000);
      expect(badge(t, Case05DynamicIsland.curKey), 'cur - default');
      expect(island(t).size, const Size(150, 44));
      // 手动换档照样受理，只是没有补间
      await t.tap(find.byKey(Case05DynamicIsland.cycleKey));
      await t.pump();
      await run(t, 100);
      expect(island(t).size, const Size(235, 44));
      await unmountPage(t);
    });

    testWidgets('逐帧扫 10s：整段开场 + 手动循环，全程不抛', (t) async {
      await mount(t);
      for (var i = 0; i < 620; i++) {
        await t.pump(const Duration(milliseconds: 16));
        island(t);
        if (i == 500) await tapCycle(t);
      }
      expect(t.takeException(), isNull);
      await unmountPage(t);
    });
  });
}
