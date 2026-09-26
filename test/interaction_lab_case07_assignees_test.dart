import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_07_assignees.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 7 号 Assignees：四套互不同步的运动挂在同一句"选了几个人"上
//
// 出图/断言要证明的五件事：
// 1. **药丸变宽是定时补间，不是弹簧**。rail 走 300ms `cubic-bezier(.33,.55,.2,1)`，
//    全程无过冲；宽度公式 `28 + (n−1)×18` → 1/2/3/4 个人分别是 28/46/64/82，
//    0 个人归零并冒出 "Unassigned"。
// 2. **靠前者压靠后者**（`zIndex = 4 − 序号`）。Stack 是"后画的在上面"，喂进去的
//    顺序按 z 升序；点选顺序一变，压叠关系整个翻过来。
// 3. **摘掉一张脸，留下的那张横向并过来**——同一帧里一个在退场、一个在让位。
// 4. **浮层从左上角长出来**（`transform-origin:0 0` + scaleX/scaleY 一起弹），
//    里面 4 行按 delay 30/70/110/150ms 逐个进场：早到的已经在动，
//    晚到的还钉在 y −8、透明度 0 上。
// 5. **关掉之后浮层是真的不在树上了**，不是留一层 Opacity(0) 隔着半张卡吞点击。
//
// 坐标（窗口 420×390，舞台 372×280 居中）：组件盒 264×268，左上角 = 舞台中心 −(132,134)。
// 药丸 44 高坐在组件盒顶上（中心 = 舞台中心 −(87,112)）；
// 浮层从组件盒 y 54 起，4 行 48 高，第 i 行中心 = 舞台中心 +(0, −50+48i)。

final _win = Size(IlSize.cardW() + 24, IlSize.cardH(280) + 24);

/// 指针事件的时间戳要盖成假时钟的当前时刻，否则弹簧每帧拿到的 dt 都是 0
Duration _vt(WidgetTester t) => t.binding.clock.now().difference(DateTime(2000));

Offset _pillAt(WidgetTester t) => ilStageCenter(t) - const Offset(87, 112);

Offset _rowAt(WidgetTester t, int i) => ilStageCenter(t) + Offset(0.0, -50.0 + 48.0 * i);

Future<void> _pump(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// 点某一行：勾选/取消
Future<void> _tapRow(WidgetTester t, int i) => t.tapAt(_rowAt(t, i));

/// rail 的当前宽度（药丸宽 = 它 + 8 + 8 + 16 + 12）
double _railW(WidgetTester t) => t.getSize(find.byKey(const ValueKey('rail'))).width;

/// 一张脸被平移到了哪：位移全在 transform 里，`getRect` 读的是布局盒，
/// 只能取"脸 → rail"的相对矩阵再读平移。
double _faceX(WidgetTester t, String id) {
  final rail = t.renderObject<RenderBox>(find.byKey(const ValueKey('rail')));
  return t
      .renderObject<RenderBox>(find.byKey(ValueKey('face-$id')))
      .getTransformTo(rail)
      .storage[12];
}

/// 脸的**画的先后**次序 = 压叠次序（后画的在上面）
List<String> _paintOrder(WidgetTester t) => t
    .widgetList<Opacity>(
        find.descendant(of: find.byKey(const ValueKey('rail')), matching: find.byType(Opacity)))
    .map((o) => (o.key! as ValueKey<String>).value.substring(5))
    .toList();

double _rowFade(WidgetTester t, int i) =>
    t.widget<Opacity>(find.byKey(ValueKey('rowfade$i'))).opacity;

/// 这一行勾没勾上：勾选框的底色 alpha 就是那条 160ms 补间的读数
bool _rowOn(WidgetTester t, int i) {
  final box = t.widget<DecoratedBox>(
    find.descendant(of: find.byKey(ValueKey('mark$i')), matching: find.byType(DecoratedBox)),
  );
  return (box.decoration as BoxDecoration).color!.a > 0.5;
}

/// 箭头的转角：展开转了 180°，取基向量的 x 分量就是 cos(θ)
double _chevBasisX(WidgetTester t) => t
    .renderObject<RenderBox>(find.byKey(const ValueKey('chev')))
    .getTransformTo(null)
    .storage[0];

void main() {
  testWidgets('7. Assignees 静止帧（默认展开、选中两人）', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_idle',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {},
      thenMs: 900,
    );
  });

  /// 关掉浮层途中：整块往上退、缩到 .92/.86、120ms 淡出，箭头还在回转
  testWidgets('7. Assignees 关闭途中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_close_mid',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await t.tapAt(_pillAt(t));
      },
      // 淡出只有 120ms，再晚就什么都看不到了
      thenMs: 60,
    );
  });

  testWidgets('7. Assignees 关闭后帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_closed',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await t.tapAt(_pillAt(t));
      },
      thenMs: 900,
    );
  });

  /// 重开那一瞬的 stagger：第一行已经在动，后面三行还钉在原位
  testWidgets('7. Assignees 逐行进场帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_stagger',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await t.tapAt(_pillAt(t));
        await _pump(t, 900);
        await t.tapAt(_pillAt(t));
      },
      thenMs: 64,
    );
  });

  /// 勾第三行：新脸从 scale .2 / 上方 10px / −22° 弹进来，rail 同时被拉长
  testWidgets('7. Assignees 加人途中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_add_mid',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await _tapRow(t, 2);
      },
      thenMs: 90,
    );
  });

  /// 取消第一行：那张脸往下 6px、+14° 退场，留下的那张同时往左并过来
  testWidgets('7. Assignees 退场与让位帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_remove_mid',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await _tapRow(t, 0);
      },
      // 退场那张的透明度只走 120ms，40ms 这一档才同时看得见它退、又看得见另一张在让位
      thenMs: 40,
    );
  });

  testWidgets('7. Assignees 空态帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_empty',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await _tapRow(t, 0);
        await _pump(t, 500);
        await _tapRow(t, 1);
      },
      thenMs: 600,
    );
  });

  /// 四行勾满：rail 82px，四张脸按 18px 一步首尾相叠
  testWidgets('7. Assignees 四人都选帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_full',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await _tapRow(t, 2);
        await _pump(t, 500);
        await _tapRow(t, 3);
      },
      thenMs: 600,
    );
  });

  /// 悬停第二行：只有那一层底色淡进来，行本身不动
  testWidgets('7. Assignees 悬停行帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c07_hover',
      window: _win,
      child: const Case07Assignees(),
      act: (t) async {
        await _pump(t, 900);
        await ilHoverAt(t, _rowAt(t, 1));
      },
      thenMs: 200,
    );
  });

  /// 宽度是 `28 + (n−1)×18`，不是"每人 28"；0 个人时归零并冒出占位文案
  testWidgets('7. Assignees rail 宽度公式', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    expect(_railW(tester), closeTo(46, 0.02));
    expect(tester.getSize(find.byKey(const ValueKey('pill'))).width, closeTo(90, 0.02),
        reason: '8 + 46 + 8 + 16 + 12');

    await _tapRow(tester, 2);
    await _pump(tester, 500);
    expect(_railW(tester), closeTo(64, 0.02));
    await _tapRow(tester, 3);
    await _pump(tester, 500);
    expect(_railW(tester), closeTo(82, 0.02));
    expect(tester.getSize(find.byKey(const ValueKey('pill'))).width, closeTo(126, 0.02));

    for (var i = 3; i >= 0; i--) {
      await _tapRow(tester, i);
      await _pump(tester, 500);
    }
    expect(_railW(tester), closeTo(0, 0.02));
    expect(find.text('Unassigned'), findsOneWidget);
    await unmountPage(tester);
  });

  /// 摆位和压叠都看点选顺序，不看列表顺序
  testWidgets('7. Assignees 靠前者压靠后者', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    // 默认 [kai, mara]：kai 序号 0 → z=4 最高 → 最后画
    expect(_paintOrder(tester), ['mara', 'kai']);
    expect(_faceX(tester, 'kai'), closeTo(0, 0.02));
    expect(_faceX(tester, 'mara'), closeTo(18, 0.02));

    await _tapRow(tester, 0);
    await _pump(tester, 700);
    expect(_faceX(tester, 'mara'), closeTo(0, 0.02), reason: '摘掉前面那张，剩下的要并过来');
    expect(_paintOrder(tester), ['mara']);

    await _tapRow(tester, 0);
    await _pump(tester, 700);
    // 现在点选顺序是 [mara, kai]：压叠关系整个反过来
    expect(_faceX(tester, 'mara'), closeTo(0, 0.02));
    expect(_faceX(tester, 'kai'), closeTo(18, 0.02));
    expect(_paintOrder(tester), ['kai', 'mara']);
    await unmountPage(tester);
  });

  /// 退场那张走完就真的从树上摘掉，不会一直占着一个位置
  testWidgets('7. Assignees 退场走完就摘掉', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    await _tapRow(tester, 0);
    await _pump(tester, 90);
    expect(find.byKey(const ValueKey('face-kai')), findsOneWidget, reason: '90ms 还在退');
    await _pump(tester, 900);
    expect(find.byKey(const ValueKey('face-kai')), findsNothing);
    expect(_paintOrder(tester), ['mara']);
    await unmountPage(tester);
  });

  /// delay 30/70/110/150ms：64ms 这一刻只有第一行动了
  testWidgets('7. Assignees 四行 stagger 的 delay 边界', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 900);
    expect(find.byKey(const ValueKey('card')), findsNothing, reason: '关完就该从树上摘掉');

    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 64);
    expect(_rowFade(tester, 0), greaterThan(0), reason: 'delay 30ms，64ms 时已经走了 34ms');
    for (var i = 1; i < 4; i++) {
      expect(_rowFade(tester, i), 0, reason: '第 ${i + 1} 行 delay ${30 + 40 * i}ms 还没到');
    }
    await _pump(tester, 900);
    for (var i = 0; i < 4; i++) {
      expect(_rowFade(tester, i), 1);
    }
    await unmountPage(tester);
  });

  /// 箭头是 240ms 定时补间，和浮层那条弹簧不同步
  testWidgets('7. Assignees 箭头随开合翻转', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    expect(_chevBasisX(tester), closeTo(-1, 0.01), reason: '展开时转了 180°');
    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 500);
    expect(_chevBasisX(tester), closeTo(1, 0.01));
    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 500);
    expect(_chevBasisX(tester), closeTo(-1, 0.01));
    await unmountPage(tester);
  });

  /// 追加就是追加到队尾：第 4 个人排在 54px 那一格，压在最下面
  testWidgets('7. Assignees 勾选只往队尾加', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    await _tapRow(tester, 3);
    await _pump(tester, 700);
    expect(_railW(tester), closeTo(64, 0.02));
    expect(_faceX(tester, 'ines'), closeTo(36, 0.02));
    expect(_paintOrder(tester), ['ines', 'mara', 'kai']);
    await _tapRow(tester, 3);
    await _pump(tester, 700);
    expect(_faceX(tester, 'kai'), closeTo(0, 0.02));
    expect(_faceX(tester, 'mara'), closeTo(18, 0.02));
    await unmountPage(tester);
  });

  /// 退场途中重新勾上同一个人：不能凭空多出第二张同 id 的脸
  testWidgets('7. Assignees 退场中途反悔不重复建脸', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);
    await _pump(tester, 900);
    await _tapRow(tester, 0);
    await _pump(tester, 60);
    expect(find.byKey(const ValueKey('face-kai')), findsOneWidget);
    await _tapRow(tester, 0);
    await _pump(tester, 60);
    expect(find.byKey(const ValueKey('face-kai')), findsOneWidget, reason: '捞回来重播进场，不是再建一张');
    await _pump(tester, 800);
    // 反悔等于重新点选：kai 排到了队尾，压叠关系也跟着翻过去
    expect(_paintOrder(tester), ['kai', 'mara']);
    expect(_faceX(tester, 'mara'), closeTo(0, 0.02));
    expect(_faceX(tester, 'kai'), closeTo(18, 0.02));
    await unmountPage(tester);
  });

  testWidgets('7. Assignees 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case07Assignees(), window: _win);

    Future<void> scan(String tag, int ms) async {
      for (var t = 16; t <= ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) fail('7 号 $tag 段 ${t}ms 抛了：$e');
      }
    }

    await scan('首屏进场', 700);

    // 开合两轮，途中把 4 行轮流点了再点回来
    for (var round = 0; round < 2; round++) {
      await tester.tapAt(_pillAt(tester));
      await scan('关闭 $round', 700);
      await tester.tapAt(_pillAt(tester));
      await scan('重开 stagger $round', 700);
      for (var i = 0; i < 4; i++) {
        await _tapRow(tester, i);
        await scan('点行 $i', 300);
        await _tapRow(tester, i);
        await scan('点回 $i', 300);
      }
    }

    // 快速连点：让退场和进场在同一张脸上撞车
    for (var i = 0; i < 12; i++) {
      await _tapRow(tester, i % 4);
      await scan('连点 $i', 40);
    }
    await scan('连点收尾', 900);

    // 摘干净 → 空态 → 补回来
    for (var i = 0; i < 4; i++) {
      if (!_rowOn(tester, i)) continue;
      await _tapRow(tester, i);
      await scan('清空 $i', 300);
    }
    await scan('空态', 600);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(_railW(tester), closeTo(0, 0.02));
    await _tapRow(tester, 0);
    await _pump(tester, 400);
    await _tapRow(tester, 1);
    await scan('补回两人', 600);
    expect(_railW(tester), closeTo(46, 0.02));

    // 悬停扫过药丸和每一行
    final g = await ilHoverAt(tester, _pillAt(tester));
    for (var i = 0; i < 4; i++) {
      await g.moveTo(_rowAt(tester, i), timeStamp: _vt(tester));
      await scan('悬停 $i', 200);
    }
    await g.moveTo(ilStageCenter(tester) + const Offset(0, 136), timeStamp: _vt(tester));
    await scan('移开', 300);
    await g.removePointer();
    await scan('注销指针', 100);

    await unmountPage(tester);
  });
}
