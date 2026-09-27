import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/cases/case_04_metal_button.dart';
import 'package:slime_works/pages/surface_lab/kit.dart';

import 'helpers/page_golden.dart' show loadAppFonts, pumpAppPage;
import 'helpers/sv_golden.dart';

/// 4 号金属钮：环带的形状是几何算出来的，颜色是移植过来的
///
/// 树上的读数只钉两样东西：**抽帧后的时钟**（`timeMs` 恒等于拍号 × 66.667ms）和
/// **两条 alpha 通道**（金属吃 `强度 × 预设 shaderOpacity`，光环吃 `明暗档 × 强度`）。
/// 环带里每一个像素的颜色由 `SvMetalPainter` 自己算，形状那部分另出一个脚本量
/// （环宽 1px/2px、外缘贴着盒子描边）。
void main() {
  const frameMs = 1000.0 / 15.0;

  Offset stageAt(WidgetTester t) => t.getRect(find.byType(SvStage)).topLeft;
  Rect face(WidgetTester t, Key host) =>
      t.getRect(find.byKey(Case04MetalButton.ringKey(host)));
  SvMetalPainter ring(WidgetTester t, Key host) =>
      t.widget<CustomPaint>(find.byKey(Case04MetalButton.ringKey(host))).painter! as SvMetalPainter;

  double opacity(WidgetTester t, Key host) => t
      .widgetList<Opacity>(
          find.descendant(of: find.byKey(host), matching: find.byType(Opacity)))
      .first
      .opacity;

  /// 压印的缩放读数：`Transform.scale` 只改 x/y，z 那根轴留成 1
  /// （`getMaxScaleOnAxis` 取的就是它，所以这里直接读 x 列）
  double scaleX(WidgetTester t, Key host) => t
      .widget<Transform>(
          find.descendant(of: find.byKey(host), matching: find.byType(Transform)))
      .transform
      .entry(0, 0);

  Future<void> run(WidgetTester t, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await t.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> mount(WidgetTester t) => mountSvCase(t, const Case04MetalButton());

  Future<void> tapChip(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey<String>(key)));
    await t.pump();
  }

  /// 点某一颗金属面本身（`svTap` 只认手型光标的第一个元素，这里要点的是指定那一个）
  Future<void> tapFace(WidgetTester t, Key host) async {
    await t.tap(find.byKey(host));
    await t.pump();
  }

  group('出图', () {
    testWidgets('c04_idle：白底四颗 + 暗色预览块， Chromatic / 90%', (t) async {
      await shootSvCase(t, name: 'c04_idle', child: const Case04MetalButton());
    }, tags: 'golden');

    testWidgets('c04_frame：时钟往后走了 1s，条纹换了一档', (t) async {
      await shootSvCase(
        t,
        name: 'c04_frame',
        child: const Case04MetalButton(),
        act: (t) async {},
        thenMs: 1000,
      );
    }, tags: 'golden');

    testWidgets('c04_gold：换 Gold 满强度，暗色那两颗跟着翻', (t) async {
      await shootSvCase(
        t,
        name: 'c04_gold',
        child: const Case04MetalButton(),
        act: (t) async {
          await tapChip(t, '${Case04MetalButton.presetPrefix}gold');
          await tapChip(t, '${Case04MetalButton.strengthPrefix}1.0');
        },
        thenMs: 200,
      );
    }, tags: 'golden');

    testWidgets('c04_soft：50% 强度，环带整个淡一档', (t) async {
      await shootSvCase(
        t,
        name: 'c04_soft',
        child: const Case04MetalButton(),
        act: (t) => tapChip(t, '${Case04MetalButton.strengthPrefix}0.5'),
        thenMs: 200,
      );
    }, tags: 'golden');

    testWidgets('c04_silver：Silver 档，第二颗圆钮从头就没有光环', (t) async {
      await shootSvCase(
        t,
        name: 'c04_silver',
        child: const Case04MetalButton(),
        act: (t) => tapChip(t, '${Case04MetalButton.presetPrefix}silver'),
        thenMs: 200,
      );
    }, tags: 'golden');

    testWidgets('c04_hover：指针压在胶囊上，靠指针那头的条纹被压暗', (t) async {
      late TestGesture g;
      await shootSvCase(
        t,
        name: 'c04_hover',
        child: const Case04MetalButton(),
        act: (t) async {
          g = await svHoverAt(t, face(t, Case04MetalButton.pillKey).center);
        },
        thenMs: 200,
      );
      await g.removePointer();
    }, tags: 'golden');

    // 这一格不能走 `shootSvCase`：它拍完就拆树，按住的那根指针还没松，
    // 拆完之后松手会把 PointerUp 路由给已 dispose 的 Listener → setState after dispose
    testWidgets('c04_press：胶囊被按住，整块面压一点、缩一点', (t) async {
      await mount(t);
      final hold = await svGrab(t, on: find.byKey(Case04MetalButton.pillKey));
      await run(t, 160);
      await expectLater(find.byType(SvStage), matchesGoldenFile('goldens/sv_c04_press.png'));
      expect(t.takeException(), isNull);
      await svDrop(t, hold);
      await unmountPage(t);
    }, tags: 'golden');

    testWidgets('c04_paused：暂停在某一帧上，之后再走 1s 也不动', (t) async {
      await shootSvCase(
        t,
        name: 'c04_paused',
        child: const Case04MetalButton(),
        act: (t) => tapFace(t, Case04MetalButton.pauseKey),
        thenMs: 1000,
      );
    }, tags: 'golden');
  });

  group('树上的读数', () {
    testWidgets('静止几何：134×40 的胶囊 + 三颗 32 的圆钮，间距 12，整行居中', (t) async {
      await mount(t);
      final at = stageAt(t);
      final pill = face(t, Case04MetalButton.pillKey);
      expect(pill.size, const Size(134, 40));
      // 整行 134+12+32×3+12×2 = 266，在 372 的舞台里居中 → 左边 53
      expect(pill.left - at.dx, closeTo(53, 0.6));
      expect(pill.top - at.dy, closeTo(5, 0.6), reason: '(232 - 222) / 2');
      final icon = face(t, Case04MetalButton.iconKey);
      expect(icon.size, const Size(32, 32));
      expect(icon.left - pill.right, closeTo(12, 0.6));
      expect(face(t, Case04MetalButton.noGlowKey).left - icon.right, closeTo(12, 0.6));
      expect(face(t, Case04MetalButton.pauseKey).left -
          face(t, Case04MetalButton.noGlowKey).right, closeTo(12, 0.6));
      // 四颗坐在同一条基线上
      for (final k in [Case04MetalButton.iconKey, Case04MetalButton.noGlowKey, Case04MetalButton.pauseKey]) {
        expect(face(t, k).center.dy, closeTo(pill.center.dy, 0.1), reason: 'Row 把它们竖着居中');
      }
      // 舞台右缘到整行的空白和左缘等宽
      expect(at.dx + 372 - face(t, Case04MetalButton.pauseKey).right, closeTo(53, 0.6));
      // 暗色预览块 340×64，两颗暗面全在它里面
      final swatch = t.getRect(find.byKey(Case04MetalButton.swatchKey));
      expect(swatch.size, const Size(340, 64));
      for (final k in [Case04MetalButton.darkPillKey, Case04MetalButton.darkIconKey]) {
        final r = face(t, k);
        expect(swatch.contains(r.topLeft) && swatch.contains(r.bottomRight), isTrue);
      }
      // 整行的中点（不是胶囊的中点）和暗色块的中点都钉在舞台中轴上
      final rowMid = (pill.left + face(t, Case04MetalButton.pauseKey).right) / 2;
      expect(swatch.center.dx - rowMid, closeTo(0, 0.6));
      expect(swatch.center.dx - (at.dx + 372 / 2), closeTo(0, 0.6));
      await unmountPage(t);
    });

    testWidgets('每一档画层读到的都是同一条时钟', (t) async {
      await mount(t);
      await run(t, 500);
      final keys = [
        Case04MetalButton.pillKey,
        Case04MetalButton.iconKey,
        Case04MetalButton.noGlowKey,
        Case04MetalButton.pauseKey,
        Case04MetalButton.darkPillKey,
        Case04MetalButton.darkIconKey,
      ];
      final times = keys.map((k) => ring(t, k).timeMs).toSet();
      expect(times.length, 1, reason: '参考稿就一个 GL 上下文：$times');
      await unmountPage(t);
    });

    testWidgets('时间按 15fps 取整：timeMs 恒等于拍号 × 66.667ms', (t) async {
      await mount(t);
      // `mountSvCase` 垫了 12×30ms：静止出图钉在第 5 拍
      expect(ring(t, Case04MetalButton.pillKey).frame, 5);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final timeMs = ring(t, Case04MetalButton.pillKey).timeMs;
        final q = timeMs / frameMs;
        expect((q - q.roundToDouble()).abs(), lessThan(1e-9), reason: '$timeMs 不在拍上');
      }
      await unmountPage(t);
    });

    testWidgets('16ms 的推进攒不满一拍：960ms 只亮出去 14 拍', (t) async {
      await mount(t);
      final f0 = ring(t, Case04MetalButton.pillKey).frame;
      final seen = <int>{f0};
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 16));
        seen.add(ring(t, Case04MetalButton.pillKey).frame);
      }
      // 60 帧里只换了 15 档：抽帧是真的在抽，不是每帧都重画
      expect(seen.length, 15);
      final frames = seen.toList()..sort();
      expect(frames.last - frames.first, 14);
      await unmountPage(t);
    });

    testWidgets('强度同时喂金属和光环，暗档另算一层 shaderOpacity', (t) async {
      await mount(t);
      final pill = ring(t, Case04MetalButton.pillKey);
      final dark = ring(t, Case04MetalButton.darkPillKey);
      // Chromatic 的 shaderOpacity 两档都是 1 → 金属 alpha 就等于强度
      expect(pill.strength, closeTo(0.9, 1e-9));
      expect(pill.opacityMul, closeTo(0.9, 1e-9));
      expect(dark.opacityMul, closeTo(0.9, 1e-9));
      expect(pill.glowOpacity, closeTo(0.2746 * 0.9, 1e-9));
      expect(dark.glowOpacity, closeTo(0.7 * 0.9, 1e-9));

      await tapChip(t, '${Case04MetalButton.strengthPrefix}0.5');
      expect(ring(t, Case04MetalButton.pillKey).opacityMul, closeTo(0.5, 1e-9));
      expect(ring(t, Case04MetalButton.darkIconKey).glowOpacity, closeTo(0.7 * 0.5, 1e-9));

      // Silver / Gold 的暗档各带一层 shaderOpacity（.88 / .92），浅档都是 1
      await tapChip(t, '${Case04MetalButton.presetPrefix}silver');
      expect(ring(t, Case04MetalButton.darkPillKey).opacityMul, closeTo(0.5 * 0.88, 1e-9));
      expect(ring(t, Case04MetalButton.pillKey).opacityMul, closeTo(0.5, 1e-9));
      await tapChip(t, '${Case04MetalButton.presetPrefix}gold');
      expect(ring(t, Case04MetalButton.darkPillKey).opacityMul, closeTo(0.5 * 0.92, 1e-9));
      expect(ring(t, Case04MetalButton.darkPillKey).preset, SvMetalPreset.gold);
      await unmountPage(t);
    });

    testWidgets('换预设换的是染色不是形状', (t) async {
      await mount(t);
      final before = [
        face(t, Case04MetalButton.pillKey),
        face(t, Case04MetalButton.iconKey),
        ring(t, Case04MetalButton.pillKey).ringPx,
        ring(t, Case04MetalButton.iconKey).ringPx,
        ring(t, Case04MetalButton.pillKey).radius,
        ring(t, Case04MetalButton.pillKey).shaderScale,
      ];
      expect(before[3], 2, reason: '圆钮那圈 2px');
      expect(before[2], 1, reason: '胶囊那圈 1px');
      await tapChip(t, '${Case04MetalButton.presetPrefix}gold');
      await run(t, 200);
      final after = [
        face(t, Case04MetalButton.pillKey),
        face(t, Case04MetalButton.iconKey),
        ring(t, Case04MetalButton.pillKey).ringPx,
        ring(t, Case04MetalButton.iconKey).ringPx,
        ring(t, Case04MetalButton.pillKey).radius,
        ring(t, Case04MetalButton.pillKey).shaderScale,
      ];
      expect(after, before);
      // 预设自己那三档参数确实翻了
      final g = ring(t, Case04MetalButton.pillKey).preset;
      expect(g.repetition, 1.5);
      expect(g.softness, 0.05);
      expect(g.shift(true), closeTo(0.3, 1e-9));
      expect(g.tint(false), const Color(0xFFF7D488));
      await unmountPage(t);
    });

    testWidgets('disableGlow 只砍光环那一层', (t) async {
      await mount(t);
      expect(ring(t, Case04MetalButton.noGlowKey).glow, isFalse);
      expect(ring(t, Case04MetalButton.iconKey).glow, isTrue);
      expect(ring(t, Case04MetalButton.darkIconKey).glow, isTrue);
      // 金属那一路不受影响
      expect(ring(t, Case04MetalButton.noGlowKey).opacityMul,
          closeTo(ring(t, Case04MetalButton.iconKey).opacityMul, 1e-9));
      await unmountPage(t);
    });

    testWidgets('光环只许往盒子外爬 4px：爬过半条间距就成了漏光', (t) async {
      await mount(t);
      // 钮与钮的间距是 12：两侧的外扩量之和必须小于它，缝里才留得住干净的一条
      for (final k in [
        Case04MetalButton.pillKey,
        Case04MetalButton.iconKey,
        Case04MetalButton.darkPillKey,
        Case04MetalButton.darkIconKey,
      ]) {
        final s = face(t, k);
        final spread = SvMetalPainter.haloSpread(s.width, s.height);
        expect(spread, lessThanOrEqualTo(4), reason: '${k.value} 外扩 ${spread * 2} ≥ 间距一半');
        expect(spread * 2, lessThan(12), reason: k.value);
      }
      await unmountPage(t);
    });

    testWidgets('暂停冻住画面，但按钮照旧能点', (t) async {
      await mount(t);
      await run(t, 300);
      final frozen = ring(t, Case04MetalButton.pillKey).timeMs;
      expect(frozen, greaterThan(0));
      await tapFace(t, Case04MetalButton.pauseKey);
      await run(t, 1000);
      expect(ring(t, Case04MetalButton.pillKey).timeMs, frozen, reason: '时基停在这里');
      // 图标翻成播放：整组面都停在最后一帧，但树还在
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(face(t, Case04MetalButton.pillKey).size, const Size(134, 40));
      // 暂停中照样能换预设 —— 冻的是时钟不是交互
      await tapChip(t, '${Case04MetalButton.presetPrefix}gold');
      expect(ring(t, Case04MetalButton.pillKey).timeMs, frozen);
      expect(ring(t, Case04MetalButton.pillKey).preset, SvMetalPreset.gold);
      await tapFace(t, Case04MetalButton.pauseKey);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await run(t, 200);
      expect(ring(t, Case04MetalButton.pillKey).timeMs, greaterThan(frozen), reason: '接着走');
      await unmountPage(t);
    });

    testWidgets('减弱动效：从头就没有一拍', (t) async {
      await loadAppFonts();
      await pumpAppPage(
        t,
        Center(
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Case04MetalButton(),
            ),
          ),
        ),
        size: svWindow(),
      );
      await run(t, 800);
      expect(ring(t, Case04MetalButton.pillKey).timeMs, 0);
      expect(ring(t, Case04MetalButton.darkIconKey).timeMs, 0);
      // 提示行翻成 amber 那一档
      final hint = t.widget<Text>(find.byKey(Case04MetalButton.hintKey));
      expect(hint.style!.color, const Color(0xFFD97706));
      // 静止档是灰的：读一下非减弱版做对照
      await mount(t);
      expect(
        t.widget<Text>(find.byKey(Case04MetalButton.hintKey)).style!.color,
        const Color(0xFF737373),
      );
      await unmountPage(t);
    });

    testWidgets('指针进/退：亮度立刻拉满，离开时冻在最后那个点再淡掉', (t) async {
      await mount(t);
      final pill = face(t, Case04MetalButton.pillKey);
      final at = pill.topLeft + const Offset(20, 20);
      final g = await svHoverAt(t, at);
      await run(t, 50);
      var p = ring(t, Case04MetalButton.pillKey);
      expect(p.hotAmt, closeTo(1, 1e-9));
      expect(p.hot, const Offset(20, 20), reason: '喂给画层的是面上的局部坐标');
      // 挪一步：跟手
      await g.moveTo(at + const Offset(40, 0));
      await run(t, 20);
      expect(ring(t, Case04MetalButton.pillKey).hot, const Offset(60, 20));
      // 退到左上角外 2px：淡出期间位置钉在出口
      await g.moveTo(pill.topLeft - const Offset(2, 2));
      await run(t, 20);
      p = ring(t, Case04MetalButton.pillKey);
      expect(p.hot, const Offset(-2, -2), reason: '淡出期间位置冻住');
      expect(p.hotAmt, lessThan(1));
      expect(p.hotAmt, greaterThan(0));
      await run(t, 200);
      expect(ring(t, Case04MetalButton.pillKey).hotAmt, 0);
      expect(ring(t, Case04MetalButton.pillKey).hot, isNull, reason: '淡完就不再喂坐标');
      await g.removePointer();
      await unmountPage(t);
    });

    testWidgets('按下的压印：110ms 走到 opacity .82 / scale .985', (t) async {
      await mount(t);
      final hold = await svGrab(t, on: find.byKey(Case04MetalButton.pillKey));
      await run(t, 16);
      expect(opacity(t, Case04MetalButton.pillKey), lessThan(1), reason: '压印已经起跳');
      await run(t, 160);
      expect(opacity(t, Case04MetalButton.pillKey), closeTo(0.82, 0.01));
      expect(scaleX(t, Case04MetalButton.pillKey), closeTo(0.985, 0.002));
      // 别的几颗不受影响
      expect(opacity(t, Case04MetalButton.iconKey), 1);
      await svDrop(t, hold);
      await run(t, 200);
      expect(opacity(t, Case04MetalButton.pillKey), closeTo(1, 1e-9));
      expect(scaleX(t, Case04MetalButton.pillKey), closeTo(1, 1e-9));
      await unmountPage(t);
    });

    testWidgets('明暗两档的表面色与描边色', (t) async {
      await mount(t);
      expect(ring(t, Case04MetalButton.pillKey).surfaceColor, const Color(0xFFFFFFFF));
      expect(ring(t, Case04MetalButton.darkPillKey).surfaceColor, const Color(0xFF272727));
      expect(ring(t, Case04MetalButton.darkPillKey).dark, isTrue);
      expect(ring(t, Case04MetalButton.darkPillKey).innerInset, 3);
      expect(ring(t, Case04MetalButton.iconKey).innerInset, 0);
      await unmountPage(t);
    });

    testWidgets('逐帧扫 2s：换预设、改强度、暂停再放开，全程不抛', (t) async {
      await mount(t);
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await tapChip(t, '${Case04MetalButton.presetPrefix}gold');
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      await tapChip(t, '${Case04MetalButton.strengthPrefix}0.5');
      await tapFace(t, Case04MetalButton.pauseKey);
      await run(t, 300);
      await tapFace(t, Case04MetalButton.pauseKey);
      for (var i = 0; i < 60; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(t.takeException(), isNull);
      expect(find.byType(SvStage), findsOneWidget);
      expect(ring(t, Case04MetalButton.pillKey).timeMs, greaterThan(0));
      await unmountPage(t);
    });
  });
}
