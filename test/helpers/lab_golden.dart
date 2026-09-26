import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/lab_kit.dart';

import 'page_golden.dart';

// 动效实验室单格案例的出图铺垫
//
// 每一帧都单开一个 test：`matchesGoldenFile` 出过图之后，同一个 test 里后续
// 的点击就不再接到（实测 tap 后状态纹丝不动）。三态挤在一个 test 里看着省，
// 实际拍到的是同一张静止图，等于没验。
//
// 三态的含义：idle = 和参考稿对静的静止样，mid = 途中一帧（时长/曲线接没接上
// 只有这一帧能看出来），end = 走完的终态。

/// 拍一格案例的某一帧
///
/// [act] 是要在拍照前做的交互（点 Animate、悬停某个文字…），[thenMs] 是交互
/// 之后再推进多少毫秒——不推进就只会拍到 t=0 的静止帧。
Future<void> shootLabCase(
  WidgetTester tester, {
  required String name,
  required Widget child,
  Size window = const Size(320, 284),
  Future<void> Function(WidgetTester tester)? act,
  int? thenMs,
}) async {
  await loadAppFonts();
  await pumpAppPage(tester, Center(child: child), size: window);
  await advance(tester);

  if (act != null) {
    await act(tester);
    // 交互之后先推两帧真实时间：一帧给 setState 的 build，一帧给
    // addPostFrameCallback 里改的目标——零时长 pump 会让刚起跳的钟把
    // 这一帧当成对表帧，进度停在 0；只推一帧则目标还没换，钟晚一帧才起
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    if (thenMs != null) await tester.pump(Duration(milliseconds: thenMs));
  }

  await expectLater(
    find.byType(LabStage),
    matchesGoldenFile('goldens/lab_$name.png'),
  );
  expect(tester.takeException(), isNull);
  await unmountPage(tester);
}

/// 点舞台上那颗 "Animate"
Future<void> tapAnimate(WidgetTester tester) async {
  await tester.tap(find.text('Animate'));
}

/// 把指针挪到某个文字上（悬停类案例的触发方式）
///
/// 手势对象别丢：指针一直停在原地，出图后还要它移开才不会影响下一帧。
Future<TestGesture> hoverText(WidgetTester tester, String label) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.text(label)));
  await tester.pump();
  return gesture;
}

/// 悬停到舞台上的某个坐标（没有可寻址文字的悬停案例用这个）
Future<TestGesture> hoverAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(at);
  await tester.pump();
  return gesture;
}
