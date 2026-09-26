import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/motion_lab_cases.dart';
import 'package:slime_works/pages/motion_lab/lab_kit.dart';

import 'helpers/lab_golden.dart';

// 触屏入口回归。
//
// 这批格子在参考稿里只有 hover 才动，触屏没有 enter/exit，手机上原先点不动。
// 每条都是同一个套路：静止取一张 → 指尖点一下 → 推到位再取，两张必须不同
// （证明指尖真的接得上）；能收回的再点一下，必须回到静止那张。
//
// 出图口径不动这批用例的 hover 路径（`motion_lab_all_cases_test.dart` 里
// 那批 hoverClickable 仍走鼠标），这里只补触屏那半边。

Future<void> _mount(WidgetTester tester, int seq) async {
  await mountLabCase(tester, kLabCases.firstWhere((c) => c.seq == seq).build());
}

/// 整窗口取一张位图（最近的重绘边界就是测试窗口，320×284）
Future<Uint8List> _raster(WidgetTester tester) async {
  late ui.Image image;
  await tester.binding.runAsync(() async {
    image = await captureImage(tester.element(find.byType(LabStage)));
  });
  final data = await tester.binding.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
  );
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 一帧一帧推：一次 pump(大时长) 只出一帧，补间会漏拍
Future<void> _advance(WidgetTester tester, int ms) async {
  var left = ms;
  while (left > 0) {
    final step = left < 16 ? left : 16;
    await tester.pump(Duration(milliseconds: step));
    left -= step;
  }
}

/// 指尖点按：`tap` 走的就是触屏指针（`hoverAt` 那条才是鼠标）
Future<void> _tapWithFinger(WidgetTester tester, Finder target) => tester.tap(target);

Future<void> _tapWithFingerAt(WidgetTester tester, Offset at) => tester.tapAt(at);

/// 可拖的源缩略图：靠 grab 光标认，和出图用例同一个口径
final _grabTile = find.byWidgetPredicate(
  (w) => w is MouseRegion && w.cursor == SystemMouseCursors.grab,
);

void main() {
  testWidgets('13. 头像排：点一颗抬起，再点收回', (tester) async {
    await _mount(tester, 13);
    final idle = await _raster(tester);

    await _tapWithFinger(tester, find.text('A'));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没抬起头像');

    await _tapWithFinger(tester, find.text('A'));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没收回');
    await unmountPage(tester);
  });

  testWidgets('14. 卡片摞：点一张扇开，再点收回', (tester) async {
    await _mount(tester, 14);
    final idle = await _raster(tester);

    await _tapWithFinger(tester, find.byType(LabStage));
    await _advance(tester, 800);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没扇开');

    await _tapWithFinger(tester, find.byType(LabStage));
    await _advance(tester, 800);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没收回');
    await unmountPage(tester);
  });

  testWidgets('20. 拖拽投递：点一下跑完整段演示', (tester) async {
    await _mount(tester, 20);
    final idle = await _raster(tester);

    await _tapWithFinger(tester, _grabTile);
    await _advance(tester, 400);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没启动投递演示');
    await unmountPage(tester);
  });

  testWidgets('23. 气泡：点一下出，再点一下收', (tester) async {
    await _mount(tester, 23);
    final idle = await _raster(tester);

    await _tapWithFinger(tester, find.text('Copy'));
    await _advance(tester, 400);
    final shown = await _raster(tester);
    expect(listEquals(shown, idle), isFalse, reason: '点按没出气泡');

    await _tapWithFinger(tester, find.text('Copy'));
    await _advance(tester, 300);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没收气泡');
    await unmountPage(tester);
  });

  testWidgets('24. 3D 倾斜：按落点倾斜，再点回正', (tester) async {
    await _mount(tester, 24);
    final idle = await _raster(tester);

    await _tapWithFingerAt(tester, const Offset(100, 110));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没倾斜');

    await _tapWithFingerAt(tester, const Offset(100, 110));
    await _advance(tester, 1200);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没回正');
    await unmountPage(tester);
  });

  testWidgets('30. Learn more：点一下箭头张开，再点收回', (tester) async {
    await _mount(tester, 30);
    final idle = await _raster(tester);

    await _tapWithFinger(tester, find.text('Learn more'));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没张开箭头');

    await _tapWithFinger(tester, find.text('Learn more'));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没收回');
    await unmountPage(tester);
  });

  testWidgets('41. 横幅堆叠：点一下摊开，再点收回', (tester) async {
    await _mount(tester, 41);
    // 静止时一条横幅都没有，先戳两条进来才有"堆叠 vs 摊开"可看
    for (var i = 0; i < 2; i++) {
      await _tapWithFinger(tester, find.text('Animate'));
      await _advance(tester, 500);
    }
    final idle = await _raster(tester);

    await _tapWithFingerAt(tester, const Offset(160, 120));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isFalse, reason: '点按没摊开');

    await _tapWithFingerAt(tester, const Offset(160, 120));
    await _advance(tester, 500);
    expect(listEquals(await _raster(tester), idle), isTrue, reason: '再点没收回');
    await unmountPage(tester);
  });
}
