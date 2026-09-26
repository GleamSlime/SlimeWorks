import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/surface_lab/kit.dart';

import 'page_golden.dart';

export 'page_golden.dart' show unmountPage;

// 表面实验室单格案例的出图铺垫
//
// 和交互实验室同一套：一帧一个 test。出过图之后同一 test 里后续的点击就不再接到，
// 三态挤在一个 test 里拍到的是同一张静止图。
//
// `thenMs` 之前先推两帧 16ms（一帧给 setState 的 build，一帧给 Timer 里才改的目标），
// 剩下的行程按 16ms 一步步推：一次 `pump(N ms)` 在假异步里只出一帧，
// 帧模式的弹簧会把整段时长钳成一拍。

/// 舞台默认 372×232，窗口按 SvSize 算好一圈留白
Size svWindow({double stageW = SvSize.stageW, double stageH = SvSize.stageH}) =>
    Size(SvSize.cardW(stageW) + 24, SvSize.cardH(stageH) + 24);

/// 把一格案例挂上窗口（不出图，逐帧扫的用例用这个）
Future<void> mountSvCase(WidgetTester tester, Widget child, {Size? window}) async {
  await loadAppFonts();
  await pumpAppPage(tester, Center(child: child), size: window ?? svWindow());
  await advance(tester);
}

/// 拍一格案例的某一帧
Future<void> shootSvCase(
  WidgetTester tester, {
  required String name,
  required Widget child,
  Size? window,
  Future<void> Function(WidgetTester tester)? act,
  int? thenMs,
}) async {
  await mountSvCase(tester, child, window: window);

  if (act != null) {
    await act(tester);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    var left = thenMs ?? 0;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await tester.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  await expectLater(
    find.byType(SvStage),
    matchesGoldenFile('goldens/sv_$name.png'),
  );
  expect(tester.takeException(), isNull);
  await unmountPage(tester);
}

/// 找到可交互的那个元素：这一页一律用光标声明"谁受理指针"
final svClickable = find.byWidgetPredicate(
  (w) =>
      w is MouseRegion &&
      (w.cursor == SystemMouseCursors.click ||
          w.cursor == SystemMouseCursors.grab ||
          w.cursor == SystemMouseCursors.text),
);

/// 舞台中心（窗口坐标）
Offset svStageCenter(WidgetTester tester) => tester.getRect(find.byType(SvStage)).center;

/// 把可交互元素声明了手型光标的东西点一下；找不到就点舞台中心
Future<void> svTap(WidgetTester tester) async {
  if (svClickable.evaluate().isNotEmpty) {
    await tester.tap(svClickable.first);
  } else {
    await tester.tapAt(svStageCenter(tester));
  }
}

/// 悬停到某个坐标，返回手势对象（出图后要 moveAway 才不影响下一帧）
Future<TestGesture> svHoverAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(at);
  await tester.pump();
  return gesture;
}

// 假时钟上的时刻换成指针事件要的 `Duration`：`TestGesture` 默认把所有事件的
// 时间戳写成 0，按帧算速度的组件拿到的 dt 永远是 0
final _base = DateTime(2000);

Duration _vt(WidgetTester tester) => tester.binding.clock.now().difference(_base);

/// 按住某个可拖元素，返回"手势 + 当前落点 + 落点的时间戳"
typedef SvHold = (TestGesture gesture, Offset at, Duration at_);

Future<SvHold> svGrab(WidgetTester tester, {Finder? on, Offset? at}) async {
  final point = at ?? tester.getCenter((on ?? svClickable).first);
  final t = _vt(tester);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  // addPointer 只是"放到"屏幕上（等价悬停进入），真正的按下是另一步
  await gesture.addPointer(location: point, timeStamp: t);
  await gesture.down(point, timeStamp: t);
  await tester.pump();
  return (gesture, point, t);
}

/// 把按住的东西拖到绝对坐标，每 16ms 落一帧（起点在进函数时就钉死）
Future<SvHold> svDragTo(WidgetTester tester, SvHold hold, Offset to, {int steps = 8}) async {
  final from = hold.$2;
  for (var i = 1; i <= steps; i++) {
    final next = Offset.lerp(from, to, i / steps)!;
    final t = _vt(tester);
    await hold.$1.moveTo(next, timeStamp: t);
    await tester.pump(const Duration(milliseconds: 16));
    hold = (hold.$1, next, t);
  }
  return hold;
}

/// 松手，并把这根手指从鼠标追踪器里注销
Future<void> svDrop(WidgetTester tester, SvHold hold) async {
  await hold.$1.up(timeStamp: _vt(tester));
  await tester.pump();
  await hold.$1.removePointer(timeStamp: _vt(tester));
  await tester.pump();
}

/// 敲键盘（这一页的输入格自己收 KeyEvent，不挂 TextField）
Future<void> svType(WidgetTester tester, String text) async {
  for (final rune in text.runes) {
    // logicalKey 只认小写码位：喂 'H'(0x48) 会撞 event_simulation 的
    // "not found in android keyCode map" 断言。键用 h，字符仍给 H
    final key = rune >= 0x41 && rune <= 0x5A ? rune + 0x20 : rune;
    // character 必须显式给：只喂 logicalKey 时它兜到 `keyLabel`，
    // 而 keyLabel 是键名、字母恒为大写，"Add Note" 会安静地敲成 "ADD NOTE"
    await tester.sendKeyEvent(LogicalKeyboardKey(key), character: String.fromCharCode(rune));
    // 按键回调里只 setState，紧跟的读数还是上一棵树
    await tester.pump(const Duration(milliseconds: 16));
  }
}
