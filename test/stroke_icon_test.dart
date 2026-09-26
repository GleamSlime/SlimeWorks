import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_zone.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';

import 'fixtures/stroke_icons_all.dart';
import 'helpers/page_golden.dart';

/// 描边图标体系：几何校验 + 触发行为 + 全量出图验收
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('几何', () {
    test('映射表里每个图标都能解析出可用笔画', () {
      final seen = <String>{};
      for (final (alias, icon) in kAllStrokeIcons) {
        if (!seen.add(icon.name)) continue;
        final geometry = geometryOf(icon);
        expect(geometry.paths, isNotEmpty, reason: alias);
        expect(
          geometry.totalLength,
          greaterThan(0),
          reason: '$alias（${icon.name}）解析后没有弧长，d 字符串没被正确吃进去',
        );
        expect(geometry.lengths.every((l) => l.isFinite), isTrue, reason: alias);
        expect(
          geometry.lengths.length,
          geometry.paths.length,
          reason: '$alias 的笔画数与度量数不一致',
        );
      }
      // 数量掉下去通常意味着映射表被误删了一批
      expect(seen.length, greaterThan(200));
    });

    test('同一图标二次取几何是同一实例（缓存生效，逐帧不重解析）', () {
      final a = geometryOf(StrokeIcons.close);
      expect(identical(a, geometryOf(StrokeIcons.close)), isTrue);
    });

    test('进度按弧长顺序摊，端点与单调性都成立', () {
      final geometry = geometryOf(StrokeIcons.settings);
      expect(strokeProgressFor(geometry, 1).every((p) => p >= 0.999), isTrue);
      List<double>? previous;
      for (final t in [0.0, 0.2, 0.45, 0.7, 1.0]) {
        final now = strokeProgressFor(geometry, t);
        expect(now.length, geometry.paths.length);
        for (var i = 0; i < now.length; i++) {
          expect(now[i], inInclusiveRange(0, 1));
          if (previous != null) {
            expect(now[i], greaterThanOrEqualTo(previous[i] - 1e-9));
          }
        }
        previous = now;
      }
    });
  });

  group('触发', () {
    test('StrokeSignal 每次 fire 都递增 pulse', () {
      final signal = StrokeSignal();
      expect(signal.pulse, 0);
      signal.fire(fromHover: true);
      expect(signal.pulse, 1);
      expect(signal.lastFromHover, isTrue);
      signal.fire(fromHover: false);
      expect(signal.pulse, 2);
      expect(signal.lastFromHover, isFalse);
      signal.dispose();
    });

    testWidgets('按下 StrokeZone 内的图标会重播描边，且不吃掉点击', (tester) async {
      var taps = 0;
      await pumpAppPage(
        tester,
        Center(
          child: StrokeZone(
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: DrawIcon(StrokeIcons.refresh),
              ),
            ),
          ),
        ),
      );
      await advance(tester, steps: 14, ms: 40);
      expect(_progress(tester), 1, reason: '入场那一下应先画完');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.down(tester.getCenter(find.byType(DrawIcon)));
      await tester.pump();
      expect(_progress(tester), lessThan(1), reason: '按下之后没回到"未画完"就是没重播');

      await gesture.up();
      await advance(tester, steps: 14, ms: 40);
      expect(_progress(tester), 1);
      expect(taps, 1, reason: 'Listener 是 translucent，不该抢走点击');
    });

    testWidgets('没有 StrokeZone 时，按下图标自身也能重播', (tester) async {
      await pumpAppPage(
        tester,
        const Center(child: DrawIcon(StrokeIcons.refresh)),
      );
      await advance(tester, steps: 14, ms: 40);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.down(tester.getCenter(find.byType(DrawIcon)));
      await tester.pump();
      expect(_progress(tester), lessThan(1));
      await gesture.up();
      await unmountPage(tester);
    });

    testWidgets('trigger.appear 按下不重播', (tester) async {
      await pumpAppPage(
        tester,
        Center(
          child: StrokeZone(
            child: const DrawIcon(
              StrokeIcons.refresh,
              trigger: StrokeTrigger.appear,
            ),
          ),
        ),
      );
      await advance(tester, steps: 14, ms: 40);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.down(tester.getCenter(find.byType(DrawIcon)));
      await tester.pump();
      expect(_progress(tester), 1, reason: 'appear 模式下按下不该重播');
      await gesture.up();
      await unmountPage(tester);
    });

    testWidgets('manual 模式由外部进度驱动', (tester) async {
      final controller = StrokeController();
      await pumpAppPage(
        tester,
        Center(
          child: DrawIcon(
            StrokeIcons.refresh,
            trigger: StrokeTrigger.manual,
            controller: controller,
          ),
        ),
      );
      await tester.pump();
      expect(_progress(tester), 0);
      controller.progress = 0.5;
      await tester.pump();
      expect(_progress(tester), greaterThan(0));
      controller.progress = 1;
      await tester.pump();
      expect(_progress(tester), 1);
      controller.dispose();
      await unmountPage(tester);
    });

    testWidgets('macOS 窗口灯：闲置只是纯色圆，悬停才把符号描出来、移开擦回', (tester) async {
      await pumpAppPage(
        tester,
        const Center(child: MacWindowButtons()),
        size: const Size(200, 80),
      );
      await advance(tester, steps: 6, ms: 40);
      expect(_progress(tester), 0, reason: '闲置就画出符号等于改了平台约定');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      final light = tester.getCenter(
        find
            .descendant(
              of: find.byType(DrawIcon),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      await gesture.moveTo(light);
      // onEnter 是在这一帧的 hitTest 里派发、下一帧才建出来的，少一泵就读到 0
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_progress(tester), greaterThan(0), reason: '悬停没起播就是没接上');
      await advance(tester, steps: 4, ms: 40);
      expect(_progress(tester), 1);

      await gesture.moveTo(const Offset(190, 70));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(_progress(tester), lessThan(1), reason: '移开要往回擦，不是留在原地');
      await advance(tester, steps: 4, ms: 40);
      expect(_progress(tester), 0, reason: '擦完要回到纯色圆');
      await unmountPage(tester);
    });

    testWidgets('系统要求减少动效时直接画完成态', (tester) async {
      await pumpAppPage(
        tester,
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(child: DrawIcon(StrokeIcons.refresh)),
        ),
      );
      await tester.pump();
      expect(_progress(tester), 1);
    });
  });

  group('出图', () {
    testWidgets('全量图标图册（亮）', (tester) async {
      await _pumpGallery(tester, dark: false);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/stroke_icons_light.png'),
      );
    });

    testWidgets('全量图标图册（暗）', (tester) async {
      await _pumpGallery(tester, dark: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/stroke_icons_dark.png'),
      );
    });

    testWidgets('draw / blur / flow 的中间态与完成态', (tester) async {
      await pumpAppPage(
        tester,
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DrawIcon(StrokeIcons.settings, size: 40),
              SizedBox(width: 16),
              DrawIcon(
                StrokeIcons.settings,
                size: 40,
                effect: StrokeEffect.blur,
              ),
              SizedBox(width: 16),
              DrawIcon(
                StrokeIcons.settings,
                size: 40,
                effect: StrokeEffect.flow,
              ),
            ],
          ),
        ),
        size: const Size(300, 140),
      );
      // flow 是无限循环的，这里绝对不能 pumpAndSettle
      await advance(tester, steps: 5, ms: 40);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/stroke_effects_mid.png'),
      );
      await advance(tester, steps: 12, ms: 40);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/stroke_effects_done.png'),
      );
      await unmountPage(tester);
    });

    testWidgets('切换图标的擦除过渡中间态', (tester) async {
      var play = true;
      late StateSetter setInner;
      await pumpAppPage(
        tester,
        Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              setInner = setState;
              return DrawIcon(
                play ? StrokeIcons.playArrow : StrokeIcons.pause,
                size: 48,
              );
            },
          ),
        ),
        size: const Size(200, 140),
      );
      await advance(tester, steps: 12, ms: 40);
      setInner(() => play = false);
      await tester.pump();
      await advance(tester, steps: 4, ms: 40);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/stroke_morph_mid.png'),
      );
      await advance(tester, steps: 12, ms: 40);
      await unmountPage(tester);
    });
  });
}

/// 取 DrawIcon 当前的绘制进度
double _progress(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(DrawIcon),
    matching: find.byType(CustomPaint),
  );
  final paint = tester.widget<CustomPaint>(finder.first);
  return (paint.painter as dynamic).debugProgress as double;
}

Future<void> _pumpGallery(WidgetTester tester, {required bool dark}) async {
  final unique = <String, StrokeIcon>{};
  for (final (_, icon) in kAllStrokeIcons) {
    unique.putIfAbsent(icon.name, () => icon);
  }
  final icons = unique.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  await pumpAppPage(
    tester,
    SingleChildScrollView(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final icon in icons)
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: DrawIcon(icon, trigger: StrokeTrigger.none),
                ),
              ),
          ],
        ),
      ),
    dark: dark,
    size: const Size(640, 900),
  );
}
