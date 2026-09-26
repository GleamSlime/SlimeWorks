import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show RichText, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_06_pull_refresh.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 6 号 Pull to refresh：真按住整张卡片往下拽
//
// 出图/断言要证明的五件事：
// 1. **表观位移 ≠ 手指位移**。`D = 510c/(510+c)`，拖 30 只走 28.33、拖 80 只走 69.15；
//    阈值 58 落在手指的 65.07px 上——所以 65 那一档不刷新、66 那一档刷新，
//    这两个读数就是橡皮筋存在的直接证据。
// 2. **拖的时候贴手、松手才走弹簧**。位移读数在按住期间每一步都等于公式值，
//    不欠帧；松手回 0 的那条弹簧会冲到 −18，但 `--at` 取 max(0,·) 钳住，
//    负值只在卡片白底上露出来（最薄 0px）。
// 3. **刷新不换图动画**。1150ms 到点整条 series 一次替换：1000ms 还是旧数、
//    1300ms 才是新数，中间没有过渡帧可读。
// 4. **图上横扫是真读数**。悬停即扫（原稿挂的是 pointermove，不按下也算），
//    左端 $57,630.15 / 09:00，右端 17:30，中途线性插值；时间轴按整条 34 点铺。
// 5. **换窗口就是换数据切片**：1H 只取尾部 5 点，涨跌基准跟着换成那 5 点的首点。
//
// 坐标（窗口 420×482，舞台 372×372 居中 → 舞台盒 x 24..396 / y 55..427）：
// 卡片 320 宽坐在 x 50..370，静止时白底占 y 69..338.5；
// 内容层：金额 y 91..124、涨跌行 133..152.5、图盒 174.5..278.5（画线区 180.5..272.5，
// 横向 x 62..358）、时间窗 294.5..326.5；液滴环圆心 (210, 99)。

/// 这一格的舞台单独加高到 372，窗口跟着算
final _win = Size(IlSize.cardW(372) + 24, IlSize.cardH(372) + 24);

/// 按在金额行上——整张卡片都是把手，没有单独的把手
Offset _grabAt(WidgetTester t) => ilStageCenter(t) + const Offset(0, -133);

/// 三个时间窗按钮的中心
Offset _tabAt(WidgetTester t, int i) => ilStageCenter(t) + Offset(-100.0 + 100.0 * i, 69.5);

/// 图上按比例 f 的位置（f=0 左端、1 右端）
///
/// 右端退 0.01px：Flutter 的命中盒是**半开**区间，正好压在右边界的那次 pointer
/// 事件送不进图里（浏览器里 `clientX-left` 是可以等于宽度的）。左端不用退，
/// `dx = 0` 本来就落在盒内。
Offset _plotAt(WidgetTester t, double f) =>
    ilStageCenter(t) + Offset(296 * f - 148 - (f >= 1 ? 0.01 : 0), -14.5);

/// 事件时间戳：盖假时钟，否则弹簧每帧拿到的 dt 都是 0
Duration _vt(WidgetTester t) => t.binding.clock.now().difference(DateTime(2000));

/// 内容层下沉了多少像素：拿时间窗那一行的顶边当尺子
double _sunk(WidgetTester t, double restTop) => t.getRect(find.text('1D')).top - restTop;

/// 大行走 RichText（三个字号同一条基线），只能从 widget 上取字
String _sumOf(WidgetTester t) {
  for (final w in t.widgetList<RichText>(find.byType(RichText))) {
    final s = w.text.toPlainText();
    if (s.startsWith(r'$')) return s;
  }
  return '';
}

Future<void> _pump(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// 按住往下拖 `dy` 再松手
Future<void> _pull(WidgetTester t, double dy, {int steps = 8}) async {
  final at = _grabAt(t);
  final hold = await ilGrab(t, at: at);
  await ilDragTo(t, hold, at + Offset(0, dy), steps: steps);
  await ilDrop(t, hold);
}

/// 拖到 `dy` 就停住不松手（拍途中帧）
Future<void> _pullHold(WidgetTester t, double dy) async {
  final at = _grabAt(t);
  final hold = await ilGrab(t, at: at);
  await ilDragTo(t, hold, at + Offset(0, dy));
}

double _rubber(double c) => 510 * c / (510 + c);

/// 表观阈值（px）：`--at` 到这儿就算够
const _threshold = 58.0;

void main() {
  testWidgets('6. Pull to refresh 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c06_idle', child: const Case06PullRefresh(), window: _win);
  });

  testWidgets('6. Pull to refresh 拖拽中帧（手指 30px）', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_pull',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => _pullHold(t, 30),
    );
  });

  /// 越过阈值那一帧：环收到半径 12、整圈转过 220°、满不透明
  testWidgets('6. Pull to refresh 待触发帧（手指 80px）', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_armed',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => _pullHold(t, 80),
    );
  });

  /// 松手后 200ms：弹簧把 69.15 收到 58 停住，环开始匀速转
  testWidgets('6. Pull to refresh 刷新中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_work',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => _pull(t, 80),
      thenMs: 200,
    );
  });

  /// 1150ms 到点：换的是第二条 series（涨到 59,102.40）
  testWidgets('6. Pull to refresh 刷新完成帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_after',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => _pull(t, 80),
      thenMs: 1400,
    );
  });

  /// 再刷新一次：第三条 series 是跌的——线、涨跌文字一起换橙
  ///
  /// 两趟之间和末尾都要等够：回弹那条弹簧从 58 走回 0 要 800ms，抢拍的话整张
  /// sheet 还沉着的 3~4px 会被当成曲线画歪了。
  testWidgets('6. Pull to refresh 下跌分支帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_down',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) async {
        await _pull(t, 80);
        await _pump(t, 2000);
        await _pull(t, 80);
      },
      thenMs: 2000,
    );
  });

  /// 横扫到区间中点：读数跟着走，竖线显形、提示点放大 1.18
  testWidgets('6. Pull to refresh 扫读帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_scrub',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => ilHoverAt(t, _plotAt(t, 0.5)),
      thenMs: 200,
    );
  });

  /// 换窗口的途中：药丸那条 .38s 带 1.16 过冲
  testWidgets('6. Pull to refresh 换窗途中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_tab_mid',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => t.tapAt(_tabAt(t, 0)),
      thenMs: 150,
    );
  });

  /// 落定：只剩尾部 5 个点，基准换成第 30 个点
  testWidgets('6. Pull to refresh 1H 帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c06_tab_1h',
      window: _win,
      child: const Case06PullRefresh(),
      act: (t) => t.tapAt(_tabAt(t, 0)),
      thenMs: 600,
    );
  });

  /// 58 是**表观**阈值：手指拖 58 只走 52.08，所以这一档松手还是回 0；
  /// 拖 80 才是真的越界——松手不回 0，先停在 58 上转圈，1150ms 到点才走回弹
  testWidgets('6. Pull to refresh 橡皮筋：拖多少不等于走多少', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);
    final rest = tester.getRect(find.text('1D')).top;

    for (final dy in [10.0, 30.0, 58.0]) {
      final at = _grabAt(tester);
      final hold = await ilGrab(tester, at: at);
      await ilDragTo(tester, hold, at + Offset(0, dy));
      expect(_sunk(tester, rest), closeTo(_rubber(dy), 0.7), reason: '拖 $dy 的表观位移');
      await ilDrop(tester, hold);
      await _pump(tester, 400);
      expect(_sunk(tester, rest), closeTo(0, 0.02), reason: '拖 $dy 没越界，松手要回到 0');
    }

    final at = _grabAt(tester);
    final hold = await ilGrab(tester, at: at);
    await ilDragTo(tester, hold, at + Offset(0, 80));
    expect(_sunk(tester, rest), closeTo(_rubber(80), 0.7), reason: '拖 80 的表观位移');
    await ilDrop(tester, hold);
    await _pump(tester, 400);
    expect(_sunk(tester, rest), closeTo(_threshold, 0.5), reason: '越界后松手挂在阈值上转圈');
    await _pump(tester, 1400);
    expect(_sunk(tester, rest), closeTo(0, 0.02), reason: '1150ms 换完数才走回弹');
    await unmountPage(tester);
  });

  /// 65 那一档差 0.07px 不够、66 才够——阈值是表观 58，不是手指 58
  testWidgets('6. Pull to refresh 阈值落在手指的 65.07px 上', (tester) async {
    for (final dy in [65.0, 66.0]) {
      await mountIlCase(tester, const Case06PullRefresh(), window: _win);
      final before = _sumOf(tester);
      await _pull(tester, dy);
      await _pump(tester, 1400);
      final after = _sumOf(tester);
      if (dy == 65.0) {
        expect(after, before, reason: '拖 65 不该触发刷新');
      } else {
        expect(after, isNot(before), reason: '拖 66 该触发刷新');
      }
      await unmountPage(tester);
    }
  });

  /// 刷新期间数据不换、到点一次换完
  testWidgets('6. Pull to refresh 1150ms 整条数据一次替换', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);
    expect(_sumOf(tester), r'$58,834.75');
    await _pull(tester, 80);
    await _pump(tester, 1000);
    expect(_sumOf(tester), r'$58,834.75', reason: '还在转圈，不该提前换数');
    await _pump(tester, 300);
    expect(_sumOf(tester), r'$59,102.40');
    expect(find.text('+267.65 · 0.5%'), findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('6. Pull to refresh 扫读读数与时间轴', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);
    // 静止：停在末点，时间文案是区间名
    expect(_sumOf(tester), r'$58,834.75');
    expect(find.text('today'), findsOneWidget);

    final g = await ilHoverAt(tester, _plotAt(tester, 0));
    await tester.pump(const Duration(milliseconds: 140));
    expect(_sumOf(tester), r'$57,630.15');
    expect(find.text('+0.00 · 0.0%'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);

    Future<void> hover(double f) async {
      await g.moveTo(_plotAt(tester, f), timeStamp: _vt(tester));
      await tester.pump(const Duration(milliseconds: 140));
    }

    await hover(1);
    // 右端只能停在边界内侧 0.01px：钟照旧进位成 17:30，金额差最后那一分
    expect(find.text('17:30'), findsOneWidget);
    expect(_sumOf(tester), startsWith(r'$58,834.'));
    expect(find.textContaining(' · 2.1%'), findsOneWidget);

    // 中点：两端线性插值，时间也跟着走半步
    await hover(0.5);
    expect(_sumOf(tester), r'$58,287.51');
    expect(find.text('+657.36 · 1.1%'), findsOneWidget);
    expect(find.text('13:15'), findsOneWidget);

    // 鼠标离开图：回到区间文案
    await g.moveTo(ilStageCenter(tester) + const Offset(0, -170), timeStamp: _vt(tester));
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.text('today'), findsOneWidget);
    await g.removePointer();
    await unmountPage(tester);
  });

  testWidgets('6. Pull to refresh 键盘 Enter 也触发', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester, 300);
    expect(_sumOf(tester), r'$58,834.75', reason: '1150ms 还没到');
    await _pump(tester, 1200);
    expect(_sumOf(tester), r'$59,102.40');
    await unmountPage(tester);
  });

  /// 时间轴是按整条 34 点铺的：换窗口只换读数窗口，刻度不许跟着切片重铺
  testWidgets('6. Pull to refresh 换窗口就是换切片', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);
    await tester.tapAt(_tabAt(tester, 0));
    await _pump(tester, 500);
    // 尾部 5 点：58682.61 → 58834.75，基准换成切片首点
    expect(find.text('+152.14 · 0.3%'), findsOneWidget);
    expect(find.text('past hour'), findsOneWidget);

    Future<void> ends() async {
      final g = await ilHoverAt(tester, _plotAt(tester, 0));
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('16:28'), findsOneWidget, reason: '1H 切片首点的钟');
      await g.moveTo(_plotAt(tester, 1), timeStamp: _vt(tester));
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('17:30'), findsOneWidget);
      await g.removePointer();
      await tester.pump(const Duration(milliseconds: 140));
    }

    await ends();

    await tester.tapAt(_tabAt(tester, 1));
    await _pump(tester, 500);
    expect(find.text('past 4 hours'), findsOneWidget);
    expect(find.text('+440.03 · 0.8%'), findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('6. Pull to refresh 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case06PullRefresh(), window: _win);

    Future<void> scan(String tag, int ms) async {
      for (var t = 16; t <= ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) fail('6 号 $tag 段 ${t}ms 抛了：$e');
      }
    }

    // 一步步拖过阈值，再松手进刷新
    final at = _grabAt(tester);
    var hold = await ilGrab(tester, at: at);
    for (var dy = 0.0; dy <= 90; dy += 6) {
      hold = await ilDragTo(tester, hold, at + Offset(0, dy), steps: 1);
      await scan('拖拽', 16);
    }
    await ilDrop(tester, hold);
    await scan('刷新中', 1300);
    await scan('回弹落定', 600);

    // 图上横扫一整条
    final g = await ilHoverAt(tester, _plotAt(tester, 0));
    for (var f = 0.0; f <= 1.001; f += 0.05) {
      await g.moveTo(_plotAt(tester, f), timeStamp: _vt(tester));
      await scan('扫读', 16);
    }
    await g.removePointer();
    await scan('离开', 200);

    // 三个窗口轮一遍
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(_tabAt(tester, i));
      await scan('换窗 $i', 500);
    }

    // 上拉与横拖都不该接管手势
    final h2 = await ilGrab(tester, at: _grabAt(tester));
    await ilDragTo(tester, h2, _grabAt(tester) - const Offset(0, 20));
    await ilDrop(tester, h2);
    await scan('上拉', 300);
    final h3 = await ilGrab(tester, at: _grabAt(tester));
    await ilDragTo(tester, h3, _grabAt(tester) + const Offset(30, 2));
    await ilDrop(tester, h3);
    await scan('横拖', 300);

    expect(_sumOf(tester), r'$59,102.40', reason: '中途只刷新过一次');
    await unmountPage(tester);
  });
}
