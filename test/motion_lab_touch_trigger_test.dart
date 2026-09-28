import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/case_44_voice_waveform.dart';
import 'package:slime_works/pages/motion_lab/cases/motion_lab_cases.dart';
import 'package:slime_works/pages/motion_lab/lab_kit.dart';
import 'package:slime_works/pages/motion_lab/motion_lab_screen.dart';

import 'helpers/lab_golden.dart';
import 'helpers/page_golden.dart';

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

  // 20 号是真拖：图块吃 `onPan*`，指尖按住往上划的时候，页面那颗
  // `SingleChildScrollView` 也在同一场竞技场里，而且它的 slop 更短 —— 不锁住
  // 就是"拖图块"变成"滚整页"。锁在 pointer down 这一下就给出，所以拖完读数
  // 必须归还，否则整页永久滚不动
  testWidgets('20. 拖拽投递：指尖拖图块时整页不跟着滚', (tester) async {
    await loadAppFonts();
    await pumpAppPage(tester, const MotionLabScreen());
    await advance(tester);

    // 图块在拖起来之后光标就变成 basic（`canDrag: !_busy`），所以认手势不认光标
    final tile = find.byWidgetPredicate((w) => w is GestureDetector && w.onPanStart != null);
    await tester.ensureVisible(tile);
    await tester.pump();
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final scrolled0 = page.position.pixels;
    final top0 = tester.getTopLeft(tile).dy;
    expect(LabTouchLock.held.value, 0, reason: '起手前锁没归零');

    final g = await tester.startGesture(tester.getCenter(tile));
    await tester.pump();
    expect(LabTouchLock.held.value, 1, reason: '按下没锁住页面滚动');

    // 一次 move 只把拖拽从"待定"推到"起步"，位移要再下一笔才算 update
    for (final dy in const [20.0, 20.0, 30.0]) {
      await g.moveBy(Offset(0, dy));
      await tester.pump();
    }
    expect(page.position.pixels, scrolled0, reason: '拖图块把整页滚走了');
    expect(tester.getTopLeft(tile).dy - top0, greaterThan(10), reason: '图块没跟手');

    await g.up();
    await tester.pump();
    expect(LabTouchLock.held.value, 0, reason: '松手没归还滚动锁');
    await unmountPage(tester);
  });

  // 44 号是"按住说话"：整块舞台就是按下面，上滑进取消档。这一路是裸 `Listener`
  // （不进竞技场），所以锁必须在 down 这一下就给出 —— 否则手指一位移就被页面外层
  // 那颗滚动赢走，"上滑取消"变成"滚整页"。说明文字换档走 `AnimatedSwitcher`，
  // 补间里新旧两份同时在树上，所以只认"出现"不认"消失"
  testWidgets('44. 声波：按住上滑进取消档，松手交还滚动锁', (tester) async {
    await loadAppFonts();
    await pumpAppPage(tester, const MotionLabScreen());
    await advance(tester);

    final stage = find.descendant(
      of: find.byType(Case44VoiceWaveform),
      matching: find.byType(LabStage),
    );
    await tester.ensureVisible(stage);
    await tester.pump();
    final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final scrolled0 = page.position.pixels;
    expect(LabTouchLock.held.value, 0, reason: '起手前锁没归零');

    final g = await tester.startGesture(tester.getCenter(stage));
    await tester.pump();
    expect(LabTouchLock.held.value, 1, reason: '按下没锁住页面滚动');

    await g.moveBy(const Offset(0, -30));
    await _advance(tester, 200);
    expect(find.text('松开取消'), findsWidgets, reason: '上滑没进取消档');
    expect(page.position.pixels, scrolled0, reason: '上滑取消把整页滚走了');

    await g.up();
    await _advance(tester, 200);
    expect(LabTouchLock.held.value, 0, reason: '松手没归还滚动锁');
    await unmountPage(tester);
  });
}
