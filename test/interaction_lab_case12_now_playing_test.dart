import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_12_now_playing.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 12 号 Now playing：一条 78 高的播放条，展开成 189 的完整播放器
//
// 断言要证明的十件事：
// 1. **只有一个状态数**：盒高、圆角、封面、文字、进度条、热区、操作组圆心、按钮边长、
//    图标尺寸——19 个读数全部等于 `mix(折叠值, 展开值, v)`，v 由盒高反解。
// 2. **v 走 quart-out**：`1-(1-u)⁴`，460ms 整点停表。
// 3. **晚到内容只走最后 40%**：`k = clamp((v-.6)/.4,0,1)`，喜欢还要再过 `k>.9` 那道点击门。
// 4. **回弹只给折叠方向**：展开时 scale 恒等于 1，收回时最低 .965、峰值落在 37% 那一拍。
// 5. **播放/暂停是画出来的形变**：300ms in-out cubic，一条 `sin(πr)` 包络同时管旋转、
//    横压纵长和两半靠拢，两端精确归位。
// 6. **喜欢三帧关键**：1 → 1.34 @38% → 1，340ms；填色层只在喜欢时存在，取消不重播。
// 7. **进度是 1Hz 阶跃**：秒与秒之间纹丝不动，214 归零。
// 8. **点外面收起、点盒子下半截不收**。
// 9. **hover/press 各走各的 .16s / .13s**。
// 10. 逐帧扫不抛、收尾钉死。
//
// 读数口径：一律从树上取**布局参数**（`SizedBox.height` / `Positioned.left`），不走
// `getRect`——盒子外面那层回弹 `Transform` 会把整棵子树的 rect 一起缩掉 3.5%，
// 量到的就成了"哪哪都短一点"。只有确认 scale=1 的档才用 rect。

const _box = ValueKey('box');
const _boxH = ValueKey('box-h');
const _boxXf = ValueKey('box-xf');
const _art = ValueKey('art');
const _artXf = ValueKey('art-xf');
const _say = ValueKey('say');
const _bar = ValueKey('bar');
const _run = ValueKey('run');
const _clock = ValueKey('clock');
const _tap = ValueKey('tap');
const _ops = ValueKey('ops');
const _like = ValueKey('like');
const _likeA = ValueKey('like-a');
const _likeHit = ValueKey('like-hit');
const _beat = ValueKey('beat');
const _pp = ValueKey('pp');

double _sized(WidgetTester t, ValueKey<String> key) {
  final w = t.widget<SizedBox>(find.byKey(key));
  return w.height ?? w.width!;
}

/// 主进度：从盒高反解。盒高是 v 的仿射函数，而且读的是布局参数，不受回弹 scale 影响
double _v(WidgetTester t) => (_sized(t, _boxH) - 78) / (189 - 78);

double _pos(WidgetTester t, ValueKey<String> key, {String prop = 'left'}) =>
    switch (prop) {
      'left' => t.widget<Positioned>(find.byKey(key)).left!,
      'top' => t.widget<Positioned>(find.byKey(key)).top!,
      'width' => t.widget<Positioned>(find.byKey(key)).width!,
      'height' => t.widget<Positioned>(find.byKey(key)).height!,
      _ => throw ArgumentError(prop),
    };

double _radius(WidgetTester t, ValueKey<String> key) {
  final w = t.widget<DecoratedBox>(find.byKey(key));
  return ((w.decoration as BoxDecoration).borderRadius! as BorderRadius).topLeft.x;
}

double _clipRadius(WidgetTester t, ValueKey<String> key) {
  final clip = find.descendant(of: find.byKey(key), matching: find.byType(ClipRRect)).first;
  return (t.widget<ClipRRect>(clip).borderRadius as BorderRadius).topLeft.x;
}

/// 回弹那层 scale
double _scale(WidgetTester t) => t.widget<Transform>(find.byKey(_boxXf)).transform.storage[0];

double _xf(WidgetTester t, ValueKey<String> key) =>
    t.widget<Transform>(find.byKey(key)).transform.storage[0];

double _opacity(WidgetTester t, ValueKey<String> key) => t.widget<Opacity>(find.byKey(key)).opacity;

double _runW(WidgetTester t) => t.widget<SizedBox>(find.byKey(_run)).width!;

PlayPauseGlyph _glyph(WidgetTester t) => t.widget<PlayPauseGlyph>(find.byKey(_pp));

IlIcon _icon(WidgetTester t, String box) => t.widget<IlIcon>(
  find.descendant(of: find.byKey(ValueKey(box)), matching: find.byType(IlIcon)).last,
);

double _fs(WidgetTester t, ValueKey<String> key) => t.widget<Text>(find.byKey(key)).style!.fontSize!;

/// 操作组圆心：**换算到盒子自己的坐标系**（盒左上角为原点）
///
/// `getRect` 给的是窗口绝对坐标，直接和 `_opsX0` 这类组件内常量比会把
/// 舞台那圈留白也算进去。只在 scale=1 的档读——展开方向恒为 1，收回方向不读它。
Offset _opsCenter(WidgetTester t) {
  final origin = t.getRect(find.byKey(_boxH)).topLeft;
  final row = t.getRect(find.descendant(of: find.byKey(_ops), matching: find.byType(Row)));
  return row.center - origin;
}

double _mix(double a, double b, double t) => a + (b - a) * t;

double _quartOut(double u) => 1 - math.pow(1 - u, 4).toDouble();

/// 和组件同口径的包络：两端钉死为 0，不然 `sin(π)` 那 1.2e-16 会冒充"还没归位"
double _env(double r) => (r <= 0 || r >= 1) ? 0 : math.sin(math.pi * r);

Future<void> _pump(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    await t.pump(const Duration(milliseconds: 16));
    left -= 16;
  }
}

/// 按 8ms 半步推：460ms 的 quart-out 起手极陡，整步会把 k 跨过 0→1 那一截跳过去
Future<void> _half(WidgetTester t, int frames) async {
  for (var f = 0; f < frames; f++) {
    await t.pump(const Duration(milliseconds: 8));
  }
}

Future<void> _openTap(WidgetTester t) => t.tap(find.byKey(_tap));

Future<void> _openAndSettle(WidgetTester t) async {
  await _openTap(t);
  await _pump(t, 700);
}

Future<void> _playTap(WidgetTester t) => t.tap(find.byKey(const ValueKey('op-lead')));

Future<void> _likeTap(WidgetTester t) => t.tap(find.byKey(_like));

/// 点盒子外面：展开时盒子占满 260 宽，只剩舞台左右两条 56 的边
Future<void> _outsideTap(WidgetTester t) async {
  final r = t.getRect(find.byType(IlStage));
  await t.tapAt(r.topLeft + const Offset(20, 100));
  await t.pump();
}

Finder get _heartIcons => find.descendant(of: find.byKey(_like), matching: find.byType(IlIcon));

void main() {
  // ------------------------------------------------------------ 出图

  testWidgets('12. 播放卡 静止：一条 78 高的播放条', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c12_idle', child: const Case12NowPlaying());
  });

  testWidgets('12. 播放卡 展开到位：封面 64、操作组落到中轴', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_open',
      child: const Case12NowPlaying(),
      act: _openTap,
      thenMs: 900,
    );
  });

  testWidgets('12. 播放卡 途中：形状快到位、晚到的刚要进来', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_morph',
      child: const Case12NowPlaying(),
      act: _openTap,
      thenMs: 32,
    );
  });

  testWidgets('12. 播放卡 收回：整块压到 .965 那一拍', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_back',
      child: const Case12NowPlaying(),
      act: (t) async {
        await _openAndSettle(t);
        await _openTap(t);
      },
      thenMs: 140,
    );
  });

  testWidgets('12. 播放卡 播放中：暂停双竖条 + 跳了一格的进度', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_playing',
      child: const Case12NowPlaying(),
      act: (t) async {
        await _openAndSettle(t);
        await _playTap(t);
      },
      thenMs: 1100,
    );
  });

  testWidgets('12. 播放卡 形变中途：双竖条正在长成三角', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_pp_mid',
      child: const Case12NowPlaying(),
      act: (t) async {
        await _openAndSettle(t);
        await _playTap(t);
        await _pump(t, 400);
        await _playTap(t);
      },
      thenMs: 128,
    );
  });

  testWidgets('12. 播放卡 喜欢：心跳那一拍', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_beat',
      child: const Case12NowPlaying(),
      act: (t) async {
        await _openAndSettle(t);
        await _likeTap(t);
      },
      thenMs: 72,
    );
  });

  testWidgets('12. 播放卡 按住整条：封面压到 .96', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c12_press',
      child: const Case12NowPlaying(),
      act: (t) async {
        await ilGrab(t, on: find.byKey(_tap));
      },
      thenMs: 200,
    );
  });

  // ------------------------------------------------------------ 断言

  testWidgets('静止态：260×78 的条、40 封面、操作组圆心 (206,30)、晚到的还没进来', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());

    expect(_sized(tester, _boxH), 78);
    expect(_radius(tester, _box), 20, reason: '盒圆角 = 封面圆角 + 同心偏移 10');
    expect(_pos(tester, _art, prop: 'width'), 40);
    expect(_pos(tester, _art), 10, reason: '封面钉在 (10,10)，只有边长在补间');
    expect(_clipRadius(tester, _art), 10);
    expect(_pos(tester, _say), 60, reason: '10 + 40 + 10：紧跟封面');
    expect(_pos(tester, _say, prop: 'width'), 94);
    expect(_pos(tester, _bar, prop: 'top'), 65, reason: '轨道在 65..68 可见，时钟 76 起被 78 的盒底切掉');
    expect(_pos(tester, _tap, prop: 'width'), 260, reason: '折叠时热区盖住整条');
    expect(_pos(tester, _tap), 0);
    expect(_pos(tester, _like), 220, reason: '喜欢的位置恒定，不参与补间');
    expect(_opacity(tester, _clock), 0);
    expect(_opacity(tester, _likeA), 0);
    expect(tester.widget<IgnorePointer>(find.byKey(_likeHit)).ignoring, isTrue);
    expect(_fs(tester, const ValueKey('title')), 13);
    expect(_fs(tester, const ValueKey('by')), 11);
    expect(_icon(tester, 'op-prev').size, 13);
    expect(_glyph(tester).size, 14);
    expect(_glyph(tester).r, 1, reason: '没在播 → 显示播放三角');
    expect(_runW(tester), closeTo(240 * 52 / 214, 0.01), reason: '进度没有补间，就是一格 240/214');

    // 操作组：24 + 5 + 30 + 5 + 24 = 88 宽，圆心 (206,30)
    expect(tester.getRect(find.byKey(const ValueKey('op-prev'))).width, 24);
    expect(tester.getRect(find.byKey(const ValueKey('op-lead'))).width, 30);
    final c0 = _opsCenter(tester);
    expect(c0.dx, closeTo(206, 0.01));
    expect(c0.dy, closeTo(30, 0.01));
    await unmountPage(tester);
  });

  testWidgets('一根 quart-out 驱动全部：19 个读数全等于 mix(折叠, 展开, v)', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openTap(tester);

    // 8ms 半步扫全程：每一拍都把当时那个 v 代进 19 条公式对一遍
    for (var f = 0; f < 70; f++) {
      await _half(tester, 1);
      final v = _v(tester);
      expect(_sized(tester, _boxH), closeTo(_mix(78, 189, v), 1e-9));
      expect(_radius(tester, _box), closeTo(_mix(20, 26, v), 1e-9));
      expect(_pos(tester, _art, prop: 'width'), closeTo(_mix(40, 64, v), 1e-9));
      expect(_clipRadius(tester, _art), closeTo(_mix(10, 16, v), 1e-9));
      expect(_pos(tester, _say), closeTo(_mix(60, 84, v), 1e-9));
      expect(_pos(tester, _say, prop: 'width'), closeTo(_mix(94, 126, v), 1e-9));
      expect(_pos(tester, _say, prop: 'height'), closeTo(_mix(40, 64, v), 1e-9),
          reason: '文字块的高度恒等于封面边长');
      expect(_fs(tester, const ValueKey('title')), closeTo(_mix(13, 15.5, v), 1e-9));
      expect(_fs(tester, const ValueKey('by')), closeTo(_mix(11, 12, v), 1e-9));
      expect(_pos(tester, _bar, prop: 'top'), closeTo(_mix(65, 96, v), 1e-9));
      expect(_pos(tester, _bar, prop: 'width'), 240, reason: '进度条宽度不参与补间');
      expect(_pos(tester, _tap), closeTo(_mix(0, 10, v), 1e-9));
      expect(_pos(tester, _tap, prop: 'width'), closeTo(_mix(260, 240, v), 1e-9));
      expect(_pos(tester, _tap, prop: 'height'), closeTo(_mix(78, 64, v), 1e-9));
      expect(_icon(tester, 'op-prev').size, closeTo(_mix(13, 16, v), 1e-9));
      expect(_glyph(tester).size, closeTo(_mix(14, 18, v), 1e-9));
      expect(_opacity(tester, _clock), closeTo(((v - 0.6) / 0.4).clamp(0.0, 1.0), 1e-9),
          reason: '晚到内容只吃最后 40%');
      final c = _opsCenter(tester);
      expect(c.dx, closeTo(_mix(206, 130, v), 0.01));
      expect(c.dy, closeTo(_mix(30, 156, v), 0.01));
      expect(tester.getRect(find.byKey(const ValueKey('op-prev'))).width,
          closeTo(_mix(24, 34, v), 0.01));
      expect(tester.getRect(find.byKey(const ValueKey('op-lead'))).width,
          closeTo(_mix(30, 46, v), 0.01));
    }

    expect(_v(tester), 1, reason: '70 拍 = 560ms，早就到了');
    final end = _opsCenter(tester);
    expect(end.dx, closeTo(130, 0.01), reason: '圆心从右上角走到中轴下方');
    expect(end.dy, closeTo(156, 0.01));
    await unmountPage(tester);
  });

  testWidgets('曲线与停表：v 就是 quart-out，460ms 整点钉死', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openTap(tester);

    final vs = <double>[];
    for (var f = 0; f < 80; f++) {
      await _half(tester, 1);
      vs.add(_v(tester));
    }
    var lastChange = 0;
    for (var i = vs.length - 1; i > 0; i--) {
      if (vs[i] != vs[i - 1]) {
        lastChange = (i + 1) * 8;
        break;
      }
    }
    expect(lastChange, closeTo(460, 24), reason: '460 × (1.6 - morph/100×1.2)，morph 默认 50');

    // 起钟那一拍是"对表帧"（dt=0），所以时间轴整体错一拍：±1 拍里取最贴合的那个
    double fit(double u) {
      final i = (u * lastChange / 8).round();
      var best = 1.0;
      for (final j in [i - 1, i, i + 1]) {
        if (j >= 0 && j < vs.length) best = math.min(best, (vs[j] - _quartOut(u)).abs());
      }
      return best;
    }

    for (final u in [0.25, 0.5, 0.75, 0.9]) {
      expect(fit(u), lessThan(0.03), reason: 'u=$u 处和 1-(1-u)⁴ 对不上：$vs');
    }
    expect(vs[8], greaterThan(0.4), reason: '起手极陡：72ms（15% 时长）已经吃掉四成行程');
    expect(vs[8], lessThan(0.55));
    expect(vs.last, 1);
    expect(vs.every((x) => x <= 1.0), isTrue, reason: 'quart-out 单调，全程不过冲');
    await unmountPage(tester);
  });

  testWidgets('晚到内容：v 过 .6 才开始出现，like 要等 k>.9 才点得到', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openTap(tester);

    final curve = <(double, double)>[];
    for (var f = 0; f < 60; f++) {
      await _half(tester, 1);
      curve.add((_v(tester), _opacity(tester, _clock)));
    }
    expect(curve.where((e) => e.$1 < 0.6 && e.$2 > 0), isEmpty, reason: '.6 之前一点都没进来');
    final onset = curve.firstWhere((e) => e.$2 > 0);
    expect(onset.$1, greaterThan(0.6));
    expect(curve.last.$2, 1);
    expect(_opacity(tester, _likeA), 1);

    // 门限 `k > .9` ⇔ `v > .96`：拿"第一次放开点击"那一拍的 k 卡住
    final gated = <(double, bool)>[];
    for (var f = 0; f < 20; f++) {
      await _half(tester, 1);
      gated.add((_opacity(tester, _likeA),
          tester.widget<IgnorePointer>(find.byKey(_likeHit)).ignoring));
    }
    expect(gated.where((e) => e.$1 > 0.9 && e.$2), isEmpty);
    expect(gated.where((e) => e.$1 <= 0.9 && !e.$2), isEmpty);
    expect(tester.widget<IgnorePointer>(find.byKey(_likeHit)).ignoring, isFalse);
    await unmountPage(tester);
  });

  testWidgets('回弹只给折叠方向：展开 scale 恒 1，收回最低 .965、峰值在 37%', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openTap(tester);
    final up = <double>[];
    for (var f = 0; f < 60; f++) {
      await _half(tester, 1);
      up.add(_scale(tester));
    }
    expect(up.every((s) => s == 1.0), isTrue, reason: '展开时盒子从 78 长到 189 本身就是事件');

    await _openTap(tester);
    final down = <double>[];
    for (var f = 0; f < 60; f++) {
      await _half(tester, 1);
      down.add(_scale(tester));
    }
    final min = down.reduce(math.min);
    expect(min, closeTo(0.965, 0.002), reason: '1 - .035·sin(π·y^1.5)');
    expect(down.indexOf(min) * 8, closeTo(460 * 0.37, 40), reason: 'y^1.5 把峰值推到靠后');
    expect(down.first, greaterThan(0.99));
    expect(down.last, 1, reason: 'y 到 0 时包络回 0');
    await unmountPage(tester);
  });

  testWidgets('播放/暂停形变：300ms、一条包络、两端精确归位', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openAndSettle(tester);
    expect(_glyph(tester).r, 1, reason: '静止在播放三角');

    await _playTap(tester);
    final rs = <double>[];
    // 42 半步 = 336ms，比 300ms 那段形变多出一截余量（30 拍只到 240ms，读不到终点）
    for (var f = 0; f < 42; f++) {
      await _half(tester, 1);
      final g = _glyph(tester);
      rs.add(g.r);
      // 旋转/横压纵长/两半靠拢全吃同一条 `sin(πr)`：逐拍核对恒等式
      expect(g.rotDeg, closeTo(-9 * _env(g.r), 1e-9),
          reason: '正在开播 → 往 -9° 那边走');
    }
    expect(rs[1], lessThan(1), reason: '起钟那拍 dt=0，第二拍才离开三角');
    expect(rs.last, 0, reason: '落在双竖条，一格不差');
    expect(_glyph(tester).rotDeg, 0);
    var lastChange = 0;
    for (var i = 1; i < rs.length; i++) {
      if (rs[i] != rs[i - 1]) lastChange = (i + 1) * 8;
    }
    expect(lastChange, closeTo(300, 24), reason: '图标形变是一条独立的 300ms，不跟主补间');

    // 再点一次：方向反过来，而且落回原值
    await _playTap(tester);
    final back = <double>[];
    for (var f = 0; f < 42; f++) {
      await _half(tester, 1);
      final g = _glyph(tester);
      back.add(g.r);
      expect(g.rotDeg, closeTo(9 * _env(g.r), 1e-9));
    }
    expect(back.last, 1);
    expect(_glyph(tester).rotDeg, 0, reason: '连点两次落回原样');
    await unmountPage(tester);
  });

  testWidgets('喜欢：340ms 三帧关键、填色层跟着出现、取消不重播', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openAndSettle(tester);
    expect(_heartIcons, findsOneWidget, reason: '没喜欢 → 只有描边那层');

    await _likeTap(tester);
    var peak = 0.0;
    var atPeak = 0;
    final scales = <double>[];
    for (var f = 0; f < 45; f++) {
      await _half(tester, 1);
      final s = _xf(tester, _beat);
      scales.add(s);
      if (s > peak) {
        peak = s;
        atPeak = (f + 1) * 8;
      }
    }
    expect(_heartIcons, findsNWidgets(2), reason: '喜欢 → 填色层垫在描边层下面');
    expect(peak, greaterThan(1.34), reason: 'cubic-bezier(.3,1.4,.5,1) 的 y1=1.4 会越过 1.34');
    expect(peak, lessThan(1.42));
    expect(atPeak, allOf(greaterThan(40), lessThan(140)),
        reason: '曲线前段冲得猛，峰值比 38% 那个关键帧更早到');
    expect(scales.last, 1);

    // 取消喜欢：颜色翻回去，动画不重播
    await _likeTap(tester);
    var moved = false;
    for (var f = 0; f < 45; f++) {
      await _half(tester, 1);
      if (_xf(tester, _beat) != 1) moved = true;
    }
    expect(moved, isFalse);
    await _pump(tester, 200);
    expect(_heartIcons, findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('进度：1Hz 阶跃，秒与秒之间纹丝不动，214 归零', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openAndSettle(tester);
    await _playTap(tester);

    final step = 240 / 214;
    var prev = _runW(tester);
    // 一秒之内一跳都不该有：这不是补间
    for (var f = 0; f < 60; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_runW(tester), prev, reason: '第 $f 拍就跳了 —— 中间不该有插值');
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(_runW(tester), closeTo(prev + step, 1e-6));
    prev = _runW(tester);

    // 一路推到 214 再跳一次：归零
    for (var i = 0; i < 161; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(_runW(tester), closeTo(240, 1e-6), reason: 'sec=214 → 满轨');
    await tester.pump(const Duration(seconds: 1));
    expect(_runW(tester), 0, reason: '过界归零，不是停住');

    // Next 也只是归零：bundle 里只有一首歌的数据
    await tester.pump(const Duration(seconds: 3));
    expect(_runW(tester), closeTo(3 * step, 1e-6));
    await tester.tap(find.byKey(const ValueKey('op-next')));
    // tap 自己不推帧：setState 之后得排一帧 build，读数才换得过来
    await tester.pump();
    expect(_runW(tester), 0);
    expect(tester.widget<Text>(find.byKey(const ValueKey('title'))).data, 'Cabra Field');
    await unmountPage(tester);
  });

  testWidgets('点外面收起，点盒子下半截不收', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openAndSettle(tester);
    expect(_v(tester), 1);

    // 盒子的下半截（操作组以下）：原稿判据是 `!box.contains(target)`
    final boxRect = tester.getRect(find.byKey(_box));
    await tester.tapAt(Offset(boxRect.center.dx, boxRect.bottom - 5));
    await tester.pump();
    await _pump(tester, 64);
    expect(_v(tester), 1, reason: '点在盒子里 → 什么都不做');

    await _outsideTap(tester);
    await _pump(tester, 700);
    expect(_v(tester), 0);
    expect(_scale(tester), 1);

    // 折叠态整条都是热区：再点一下又展开
    await tester.tap(find.byKey(_tap));
    await _pump(tester, 700);
    expect(_v(tester), 1);
    await unmountPage(tester);
  });

  // 折叠态那三颗圆钮只有 24/30，指尖按不准，所以脸外面压了一圈透明受理区。
  // 横向不能随便探：相邻两颗圆心只隔 32，探过中线就互相抢了。
  testWidgets('折叠态小钮：外扩那一圈点得着，也不跟整条的热区抢', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    final lead = tester.getRect(find.byKey(const ValueKey('op-lead')));
    final prev = tester.getRect(find.byKey(const ValueKey('op-prev')));
    expect(lead.width, 30);
    expect(_v(tester), 0, reason: '起手是折叠条');
    expect(_glyph(tester).r, 1, reason: '还没点过，静止在播放三角');

    // 脸上方 5px：既在受理区里、也在整条的展开热区里 —— 小钮要赢
    await tester.tapAt(Offset(lead.center.dx, lead.top - 5));
    await _pump(tester, 340);
    expect(_v(tester), 0, reason: '这一笔被整条抢去展开了');
    expect(_glyph(tester).r, 0, reason: '受理区上面那一圈没接住');

    // 下面同理，顺带把播放翻回去
    await tester.tapAt(Offset(lead.center.dx, lead.bottom + 5));
    await _pump(tester, 340);
    expect(_v(tester), 0);
    expect(_glyph(tester).r, 1, reason: '受理区下面那一圈没接住');

    // 左边 17：出了 prev 的脸（12）但还在它的受理区（16）里 → 归 prev，不是 lead
    await tester.tapAt(Offset(lead.center.dx - 17, lead.center.dy));
    await _pump(tester, 340);
    expect(_v(tester), 0);
    expect(_glyph(tester).r, 1, reason: '两圈的边界漏过了中线，lead 被 prev 的位置点着了');
    expect(prev.width, 24);
    await unmountPage(tester);
  });

  testWidgets('hover / press：颜色 .16s、底色 .16s、缩放 .13s', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openAndSettle(tester);

    final g = await ilHoverAt(tester, tester.getCenter(find.byKey(const ValueKey('op-lead'))));
    final opacities = <double>[];
    for (var f = 0; f < 25; f++) {
      await _half(tester, 1);
      opacities.add(_opacity(tester, const ValueKey('op-lead-a')));
    }
    expect(opacities.last, closeTo(0.88, 1e-9), reason: '主按钮 hover = 整颗 opacity .88');
    var lastChange = 0;
    for (var i = 1; i < opacities.length; i++) {
      if (opacities[i] != opacities[i - 1]) lastChange = (i + 1) * 8;
    }
    expect(lastChange, closeTo(160, 24));

    // 小按钮 hover 换的是字色 + 底色水洗
    expect(_icon(tester, 'op-prev').color, IlColor.ink3);
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('op-prev'))));
    for (var f = 0; f < 25; f++) {
      await _half(tester, 1);
    }
    expect(_icon(tester, 'op-prev').color, IlColor.ink);
    final bg =
        (tester.widget<DecoratedBox>(find.byKey(const ValueKey('op-prev'))).decoration
                as BoxDecoration)
            .color!;
    expect(bg.a, closeTo(0.07, 0.002));

    await g.removePointer();
    await tester.pump();

    // 按住小钮：130ms 走到 .9
    final hold = await ilGrab(tester, on: find.byKey(const ValueKey('op-next')));
    for (var f = 0; f < 20; f++) {
      await _half(tester, 1);
    }
    expect(_xf(tester, const ValueKey('op-next-xf')), closeTo(0.9, 1e-9));
    await ilDrop(tester, hold);
    for (var f = 0; f < 20; f++) {
      await _half(tester, 1);
    }
    expect(_xf(tester, const ValueKey('op-next-xf')), closeTo(1, 1e-9));

    // 按住整条：封面 .96，开合状态不动
    final grab = await ilGrab(tester, on: find.byKey(_tap));
    for (var f = 0; f < 20; f++) {
      await _half(tester, 1);
    }
    expect(_xf(tester, _artXf), closeTo(0.96, 1e-9));
    expect(_v(tester), 1, reason: ':active 只碰 scale，开合是 click 的事');
    await ilDrop(tester, grab);
    await unmountPage(tester);
  });

  testWidgets('逐帧扫 1400ms：四路时间线合起来一直在动，收尾钉死', (tester) async {
    await mountIlCase(tester, const Case12NowPlaying());
    await _openTap(tester);
    String snap() =>
        '${_v(tester).toStringAsFixed(4)}|${_scale(tester).toStringAsFixed(4)}'
        '|${_opacity(tester, _clock).toStringAsFixed(4)}|${_glyph(tester).r.toStringAsFixed(4)}'
        '|${_xf(tester, _beat).toStringAsFixed(4)}';
    final snaps = <String>[];
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(snap());
    }
    await _playTap(tester);
    for (var f = 0; f < 25; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(snap());
    }
    await _likeTap(tester);
    for (var f = 0; f < 25; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add(snap());
    }
    expect(tester.takeException(), isNull);
    expect(snaps.toSet().length, greaterThan(60));
    final tail = snaps.last;
    for (var f = 0; f < 12; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(snap(), tail, reason: '第 $f 拍还在动 —— 停表条件没满足');
    }
    await unmountPage(tester);
  });
}
