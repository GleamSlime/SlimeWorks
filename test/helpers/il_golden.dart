import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'page_golden.dart';

export 'page_golden.dart' show unmountPage;

// 交互实验室单格案例的出图铺垫
//
// 和动效实验室那条一样：一帧一个 test。出过图之后同一 test 里后续的点击
// 就不再接到，三态挤在一个 test 里拍到的是同一张静止图。
//
// 差别在触发方式：这一页的案例大多是"按住拖"和"敲键盘"，不是点一下按钮，
// 所以除了 tap/hover 还留了拖动和按键两条通道。

/// 舞台本身 372×232，窗口按 IlSize 算好一圈留白
Size ilWindow() => Size(IlSize.cardW() + 24, IlSize.cardH() + 24);

/// 把一格案例挂上窗口（不出图，逐帧扫的用例用这个）
Future<void> mountIlCase(WidgetTester tester, Widget child, {Size? window}) async {
  await loadAppFonts();
  await pumpAppPage(tester, Center(child: child), size: window ?? ilWindow());
  await advance(tester);
}

/// 拍一格案例的某一帧
Future<void> shootIlCase(
  WidgetTester tester, {
  required String name,
  required Widget child,
  Size? window,
  Future<void> Function(WidgetTester tester)? act,
  int? thenMs,
}) async {
  await mountIlCase(tester, child, window: window);

  if (act != null) {
    await act(tester);
    // 交互之后先推两帧真实时间：一帧给 setState 的 build，一帧给
    // Timer 里才改的目标——零时长 pump 会让刚起跳的钟把这帧当对表帧
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // 剩下的行程按 16ms 一步步推：一次 pump(N ms) 在假异步里只出一帧
    // 末段不足 16ms 时按余数收尾，否则整段会被抬到 16 的整倍数，
    // 要求的"120ms 那一帧"实际拍到的是 128ms
    var left = thenMs ?? 0;
    while (left > 0) {
      final step = left < 16 ? left : 16;
      await tester.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  await expectLater(
    find.byType(IlStage),
    matchesGoldenFile('goldens/il_$name.png'),
  );
  expect(tester.takeException(), isNull);
  await unmountPage(tester);
}

/// 找到可交互的那个元素：这一页一律用光标声明"谁受理指针"
final ilClickable = find.byWidgetPredicate(
  (w) =>
      w is MouseRegion &&
      (w.cursor == SystemMouseCursors.click ||
          w.cursor == SystemMouseCursors.grab ||
          w.cursor == SystemMouseCursors.text),
);

/// 舞台中心（窗口坐标）
///
/// 磁吸、拖拽这类"按离参考点多远来算强度"的交互，指针落点必须相对舞台算，
/// 硬写窗口坐标会连偏移方向都反掉。出图前调用一次拿中心。
Offset ilStageCenter(WidgetTester tester) =>
    tester.getRect(find.byType(IlStage)).center;

/// 把可交互元素声明了手型光标的东西点一下；找不到就点舞台中心
Future<void> ilTap(WidgetTester tester) async {
  if (ilClickable.evaluate().isNotEmpty) {
    await tester.tap(ilClickable.first);
  } else {
    await tester.tapAt(ilStageCenter(tester));
  }
}

/// 悬停到某个坐标，返回手势对象（出图后要 moveAway 才不影响下一帧）
Future<TestGesture> ilHoverAt(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(at);
  await tester.pump();
  return gesture;
}

/// 假时钟上的时刻，换成指针事件要的 `Duration`
///
/// `TestGesture` 默认把所有事件的时间戳写成 0，于是"按帧算速度"的组件
/// （甩长、抛掷）拿到的 dt 永远是 0，只能靠下限兜底。盖成 `pump()` 推进的那个钟，
/// 事件就隔多少帧是多少毫秒。基准取一个固定日期：只有**差值**参与运算，
/// 假时钟的起点在哪一天不影响结果。
final _base = DateTime(2000);

Duration _vt(WidgetTester tester) => tester.binding.clock.now().difference(_base);

/// 按住某个可拖元素，返回"手势 + 当前落点 + 落点的时间戳"
///
/// TestGesture 自己不漏出当前坐标，拖拽途中要按坐标算位移，所以打包带上。
/// `at` 给绝对坐标，用来按在指定偏移上（"按下点离把手很远"那一类用例）。
///
/// 第三个字段是**假时钟**上的时间：`TestGesture` 默认把所有事件的时间戳写成 0，
/// 于是"按帧算速度"的组件（甩长、抛掷）拿到的 dt 永远是 0，只能靠下限兜底。
/// 统一盖 `binding.clock.now()`，`pump(16ms)` 推多少事件就隔多少。
typedef IlHold = (TestGesture gesture, Offset at, Duration at_);

Future<IlHold> ilGrab(WidgetTester tester, {Finder? on, Offset? at}) async {
  final point = at ?? tester.getCenter((on ?? ilClickable).first);
  final t = _vt(tester);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  // addPointer 只是把手指"放到"屏幕上（PointerAdded，等价于悬停进入），
  // 真正的按下是另一步。少了 down 这一句，后面的 moveTo 全是 hover，
  // 识别器根本不会进拖拽态，图拍出来却是静止的
  await gesture.addPointer(location: point, timeStamp: t);
  await gesture.down(point, timeStamp: t);
  await tester.pump();
  return (gesture, point, t);
}

/// 把按住的东西拖到绝对坐标，每 16ms 落一帧（跟手要的是逐位移，不是插值）
///
/// 起点在进函数时就钉死：拿"上一帧的落点"再乘 `i/steps`，每步只走完**剩余**
/// 距离的一成，到末帧已经几乎不动了——静止在末帧上拍，形变量是 0，
/// 而"匀速拖"恰恰是速度驱动那类形变的读数来源。
Future<IlHold> ilDragTo(
  WidgetTester tester,
  IlHold hold,
  Offset to, {
  int steps = 8,
}) async {
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
///
/// 一个 test 里连按两次时必须走这一步：`MouseTracker` 是按**设备**记状态的，
/// 上次的指针没 `PointerRemoved` 就直接 `addPointer`，会撞
/// `(event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)`。
Future<void> ilDrop(WidgetTester tester, IlHold hold) async {
  await hold.$1.up(timeStamp: _vt(tester));
  await tester.pump();
  await hold.$1.removePointer(timeStamp: _vt(tester));
  await tester.pump();
}

/// 敲键盘（这一页的输入类案例没有 TextField，全部自己收 KeyEvent）
Future<void> ilType(WidgetTester tester, String text) async {
  for (final rune in text.runes) {
    // 字母/数字的 logicalKey 码位就是小写 ASCII，跟 Flutter 自己的映射一致
    await tester.sendKeyEvent(LogicalKeyboardKey(rune));
  }
}
