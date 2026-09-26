import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_13_action_node.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 13 号 Action node：四个圆钮藏在卡片右上角底下，指针一进整块就沿
// "贴着圆角外侧 30px"的那条倒角线甩出来
//
// 断言要证明的九件事：
// 1. **取点公式**：四个目标圆心 = 参考稿表里那四个读数，弧长的三段（上沿直线 /
//    1/4 圆弧 / 右沿直线）各自对得上，整排对称压在角平分线两侧。
// 2. **停靠位**：收起态四颗的圆心都在 (-20,20)，而且整颗都在卡片盒里 ——
//    这个块没有透明度通道，藏全靠层叠。
// 3. **一根弹簧两个上限**：位移沿"停靠位→目标"那条射线冲到 1.4 倍，缩放只到 1。
// 4. **错拍改的是起跳时刻**：49.5ms 一个，四条曲线形状一样、只是平移。
// 5. **离开按倒序收**：3 号先进。
// 6. **悬停区**：卡片盒外 40px、纵向还在 reach 里那点算命中；比 reach 下缘还低的
//    那块死角不算 —— 收着的时候 hover 过去也不开（`.nod-reach{pointer-events:none}`）。
// 7. **卡片抬起 1px**，260ms 带过冲；扇出不跟着抬。
// 8. 版式：272 宽 / 圆角 20 / mark 30（圆角 9.4）/ 头像 24 且后一个压前一个 6px。
// 9. 逐帧扫不抛、收尾钉死。
//
// 读数口径：圆心一律按**未抬起时**的卡片右上角算（`translate:0 -1px` 只抬卡片，
// 扇出层不抬），所以进悬停之前先抓一次角点，后面全都对着它比。

final _win = Size(IlSize.cardW() + 24, IlSize.cardH(328) + 24);

const _card = ValueKey<String>('card');
const _mark = ValueKey<String>('mark');
const _chain = ValueKey<String>('chain');
const _link0 = ValueKey<String>('link-0');
const _link1 = ValueKey<String>('link-1');

const _ids = <String>['connect', 'add', 'duplicate', 'settings'];

/// 参考稿默认档（corner 20 / count 4 / reach 25）的四个圆心，逐字抄自规格表
const _targets = <Offset>[
  Offset(-52.7301, -30.0000),
  Offset(-4.9664, -27.6864),
  Offset(27.6864, 4.9664),
  Offset(30.0000, 52.7301),
];

const _home = Offset(-20, 20);

/// 卡片宽（版式那条已经实测过）
const _cardW = 272.0;

/// 悬停盒比根盒多出去的量：reach 右探 54、上探 2
const _overX = 54.0;
const _overY = 2.0;

void main() {
  group('取点公式', () {
    test('inset / 停靠位 / 四个目标圆心和参考稿的表一分不差', () {
      // ly(25) + ay = 12 + 18
      expect(IlNodeFan.inset(25), closeTo(30, 1e-9));
      expect(IlNodeFan.home(20), _near(_home, 1e-9));
      for (var i = 0; i < 4; i++) {
        expect(
          IlNodeFan.target(i, 4, 20, IlNodeFan.inset(25)),
          _near(_targets[i], 1e-4),
          reason: '第 $i 号钮',
        );
      }
      // 整排关于角平分线互为镜像
      expect(_targets[0].dx, closeTo(-_targets[3].dy, 1e-4));
      expect(_targets[0].dy, closeTo(-_targets[3].dx, 1e-4));
      // 四条射线也互为镜像 —— 但**不是** 45°：钮贴在圆角外侧走，上沿那颗偏横、
      // 右沿那颗偏竖，中间两颗才接近对角
      final v0 = _targets[0] - _home, v3 = _targets[3] - _home;
      expect(v0.dx, closeTo(-v3.dy, 1e-4));
      expect(v0.dy, closeTo(-v3.dx, 1e-4));
      expect(v0.dx / v0.dy, closeTo(0.654602, 1e-4));
    });

    test('corner 决定绕着多大的角走，count 是整排对称重排而不是截断', () {
      // corner < 20 时停靠位走的是另一支换算：cy(m)=max(ay·√2+2, …) 再除以 √2
      final h0 = IlNodeFan.home(0);
      expect(h0.dx, closeTo(-h0.dy, 1e-9));
      expect(-h0.dx, closeTo(IlNodeFan.half + 2 / math.sqrt2, 1e-9));
      expect(IlNodeFan.home(20), _near(_home, 1e-9));
      expect(IlNodeFan.home(32), _near(const Offset(-32, 32), 1e-9));
      // count=2 时两颗粒子分居角平分线两侧，弧长间距 48（不是欧氏距离 48 ——
      // 两颗都在弧上，弦长比弧长短）
      final two = <Offset>[
        for (var i = 0; i < 2; i++) IlNodeFan.target(i, 2, 20, 30),
      ];
      expect(two[1].dx, closeTo(-two[0].dy, 1e-9));
      expect(two[1].dy, closeTo(-two[0].dx, 1e-9));
      for (final p in two) {
        expect(Offset(p.dx + 20, p.dy - 20).distance, closeTo(50, 1e-9));
      }
      // 弧长 48 在半径 50 的弧上对应的弦长 = 2R·sin(48/2R)，比 48 短
      expect((two[1] - two[0]).distance, closeTo(2 * 50 * math.sin(48 / 50 / 2), 1e-6));
      // count=3 时中间那颗正好在角平分线那一档
      final three = <Offset>[
        for (var i = 0; i < 3; i++) IlNodeFan.target(i, 3, 20, 30),
      ];
      expect(
        three[1],
        _near(IlNodeFan.along((20 + 30) * math.pi / 4, 20, 30), 1e-9),
      );
    });

    test('弧长取点：上沿直线 → 1/4 圆弧 → 右沿直线', () {
      const m = 20.0, h = 30.0;
      final arc = (m + h) * math.pi / 2;
      // 上沿直线：y 恒等于 -h，弧长走 1px 就推进 1px
      expect(IlNodeFan.along(-10, m, h), _near(const Offset(-30, -30), 1e-9));
      expect(IlNodeFan.along(0, m, h), _near(const Offset(-20, -30), 1e-9));
      expect(
        IlNodeFan.along(-58, m, h) - IlNodeFan.along(-10, m, h),
        _near(const Offset(-48, 0), 1e-9),
      );
      // 弧上任意一点都在半径 m+h 的圆上（圆心 (-m, m)）
      final mid = IlNodeFan.along(arc * 0.37, m, h);
      expect(Offset(mid.dx + m, mid.dy - m).distance, closeTo(m + h, 1e-9));
      // 弧走完接上右沿直线：x 恒等于 h，间距同样按弧长 1:1
      expect(IlNodeFan.along(arc, m, h), _near(const Offset(30, 20), 1e-6));
      expect(
        IlNodeFan.along(arc + 48, m, h) - IlNodeFan.along(arc, m, h),
        _near(const Offset(0, 48), 1e-5),
      );
      // 相邻两钮隔的是弧长 48 而不是角度：直线上间距正好 48，弧上就短一点
      final gap = _targets[1] - _targets[0];
      expect(gap.distance, lessThan(48));
      expect(gap.dx, closeTo(47.7637, 1e-3));
      expect(gap.dy, closeTo(2.3136, 1e-3));
    });

    test('reach 包围盒与切口 = 钮的盒外扩 24，再切掉卡片自己占的那块', () {
      final box = IlNodeFan.reachBox(<Offset>[
        for (var i = 0; i < 4; i++) IlNodeFan.target(i, 4, 20, 30),
      ]);
      expect(box.left, closeTo(-76.7301, 1e-4));
      expect(box.top, closeTo(-54, 1e-4));
      expect(box.width, closeTo(130.7301, 1e-4));
      expect(box.height, closeTo(130.7301, 1e-4));
      final (t, e) = IlNodeFan.reachNotch(box, 20);
      expect(t, closeTo(56.7301, 1e-4));
      expect(e, closeTo(74, 1e-4));
      final p = IlNodeFan.reachPath(box, t, e);
      // 切口里（卡片角那块）不算命中，钮那边算
      expect(p.contains(Offset(t - 40, e + 40)), isFalse);
      expect(p.contains(Offset(t - 40, e - 40)), isTrue);
      expect(p.contains(Offset(box.width - 4, box.height - 4)), isTrue);
      // 悬停盒比根盒向右/向上多出去的量
      expect(box.right, closeTo(_overX, 1e-4));
      expect(-(IlNodeFan.band + box.top), closeTo(_overY, 1e-4));
      // 最右的钮右缘在卡片右缘外 48（30+18），最上的钮上缘在卡片上缘外 48
      expect(_targets[3].dx + IlNodeFan.half, closeTo(48, 1e-9));
      expect(-(_targets[0].dy - IlNodeFan.half), closeTo(48, 1e-9));
    });
  });

  testWidgets('13. Action node 静止帧：四颗全在角底下', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c13_idle', child: const Case13ActionNode(), window: _win);
  });

  testWidgets('13. Action node 飞行中帧：0 号已甩出、3 号还没动', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c13_mid',
      child: const Case13ActionNode(),
      window: _win,
      act: (t) => ilHoverAt(t, _cardCenter(t)),
      thenMs: 96,
    );
  });

  testWidgets('13. Action node 展开完成帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c13_open',
      child: const Case13ActionNode(),
      window: _win,
      act: (t) => ilHoverAt(t, _cardCenter(t)),
      thenMs: 900,
    );
  });

  testWidgets('13. Action node 钮悬停帧：只有被指到的那颗再放大 12%', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c13_zoom',
      child: const Case13ActionNode(),
      window: _win,
      act: (t) async {
        final g = await ilHoverAt(t, _cardCenter(t));
        await _run(t, 900);
        await g.moveTo(_boxRect(t, 'add').center);
      },
      thenMs: 200,
    );
  });

  testWidgets('13. Action node 收回中帧：3 号先进', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c13_back',
      child: const Case13ActionNode(),
      window: _win,
      act: (t) async {
        final g = await ilHoverAt(t, _cardCenter(t));
        await _run(t, 900);
        await g.moveTo(const Offset(2, 2));
        await t.pump();
        await g.removePointer();
        await t.pump();
      },
      thenMs: 110,
    );
  });

  group('树上的读数', () {
    testWidgets('版式：272 宽 / 圆角 20 / mark 30（圆角 9.4）/ 头像互相压 6px', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final card = tester.getRect(find.byKey(_card));
      expect(card.width, closeTo(272, 0.01));
      // 参考稿实测：18 + 30 + 13 + 60.75 + 16 + 24 + 18 = 179.75
      // 这里正文三行只能拿到 60.0（Flutter 把 20.25 的行盒摊成整像素），
      // 于是整张卡 179.0 —— 差的 0.75px 是引擎的，不是排版的
      expect(
        tester.getRect(find.byKey(const ValueKey<String>('say'))).height,
        closeTo(60.0, 0.01),
        reason: '三行 × 20.25 被引擎落成三行 × 20',
      );
      expect(card.height, closeTo(179.0, 0.01));
      expect(_radius(tester, _card), closeTo(20, 0.01));
      final mark = tester.getRect(find.byKey(_mark));
      expect(mark.width, closeTo(30, 0.01));
      expect(mark.height, closeTo(30, 0.01));
      expect(_radius(tester, _mark), closeTo(9.4, 0.01));
      // 内可用宽 236：mark 从左上 18 起，头像链的底贴着下内边距
      expect(mark.left - card.left, closeTo(18, 0.01));
      expect(mark.top - card.top, closeTo(18, 0.01));
      expect(tester.getRect(find.byKey(_chain)).bottom, closeTo(card.bottom - 18, 0.01));
      // 头像：24 见方，后一个的左缘在前一个右缘内侧 6px
      final l0 = tester.getRect(find.byKey(_link0));
      final l1 = tester.getRect(find.byKey(_link1));
      expect(l0.width, closeTo(24, 0.01));
      expect(l1.top, closeTo(l0.top, 0.01));
      expect(l1.left - l0.left, closeTo(18, 0.01));
      await unmountPage(tester);
    });

    testWidgets('收起态：四颗圆心都在停靠位，而且整颗被卡片盖住', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final card = tester.getRect(find.byKey(_card));
      final corner = card.topRight;
      for (final id in _ids) {
        final box = _boxRect(tester, id);
        expect(box.center, _near(corner + _home), reason: '$id 该钉在卡片角底下');
        expect(box.width / IlNodeFan.btn, closeTo(0.82, 0.01), reason: '$id 收起态缩到 .82');
        // 没有透明度通道：靠"整颗在卡片盒里 + 卡片后画"藏住
        expect(box.right, lessThanOrEqualTo(corner.dx + 0.6));
        expect(box.bottom, lessThanOrEqualTo(card.bottom + 0.6));
      }
      await unmountPage(tester);
    });

    testWidgets('展开态：圆心 = 卡片右上角 + 目标位，缩放回到 1，卡片只抬 1px', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final corner = _fanOrigin(tester);
      final g = await _hoverCard(tester);
      for (var i = 0; i < _ids.length; i++) {
        expect(
          _boxRect(tester, _ids[i]).center,
          _near(corner + _targets[i]),
          reason: '展开后第 $i 号',
        );
        expect(_boxRect(tester, _ids[i]).width, closeTo(IlNodeFan.btn, 0.02));
      }
      // 抬的只有卡片自己：扇出原点（`_fanOrigin`）不动，卡片顶动 1px
      expect(tester.getRect(find.byKey(_card)).top, closeTo(corner.dy - 1, 0.02));
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('错拍是起跳时刻错开：96ms 那拍只有 0 号走了 3 拍', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final home = _fanOrigin(tester) + _home;
      final g = await ilHoverAt(tester, _cardCenter(tester));
      await _run(tester, 96);
      final d = <double>[
        for (final id in _ids) (_boxRect(tester, id).center - home).distance,
      ];
      expect(d[0], greaterThan(4));
      expect(d[1], greaterThan(0));
      expect(d[1], lessThan(d[0] / 2));
      expect(d[2], 0);
      expect(d[3], 0);
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('位移能冲到 1.4 倍，缩放只到 1.0', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final corner = _fanOrigin(tester);
      final g = await ilHoverAt(tester, _cardCenter(tester));
      final dir = _targets[0] - _home;
      var sawOver = 0.0;
      for (var f = 0; f < 60; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final box = _boxRect(tester, 'connect');
        final off = box.center - (corner + _home);
        if (off.distance / dir.distance > 1.001) {
          sawOver = math.max(sawOver, off.distance / dir.distance);
          // 过冲沿那条射线往外，不是斜着跑
          expect(off.dx / off.dy, closeTo(dir.dx / dir.dy, 0.02));
          // --pop 在 n>=1 就钉住：过冲那几帧钮不跟着变大
          expect(box.width, closeTo(IlNodeFan.btn, 0.05));
        }
      }
      expect(sawOver, greaterThan(1.05), reason: '弹簧必须真的冲过头，这条通道才算验到');
      expect(_boxRect(tester, 'connect').center, _near(corner + _targets[0]));
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('钮的 hover 只放大被指到的那颗，180ms 到位 1.12', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final g = await ilHoverAt(tester, _cardCenter(tester));
      await _run(tester, 900);
      final rest = _boxRect(tester, 'add').width;
      await g.moveTo(_boxRect(tester, 'add').center);
      await _run(tester, 90);
      expect(_boxRect(tester, 'add').width / rest, greaterThan(1.05));
      expect(_boxRect(tester, 'connect').width, closeTo(rest, 0.01));
      await _run(tester, 120);
      expect(_boxRect(tester, 'add').width, closeTo(IlNodeFan.btn * 1.12, 0.05));
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('悬停区：盒外 40px 那点算命中，比 reach 下缘还低的不算', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final corner = _fanOrigin(tester);
      // 卡片右缘外 40px、纵向还在 reach 里：参考稿靠那块 L 接住
      final inFan = corner + const Offset(40, 20);
      // 同一条竖线上，已经低过 reach 的下缘（下缘在角下 76.73）
      final dead = corner + const Offset(40, 130);
      final g = await ilHoverAt(tester, inFan);
      await _run(tester, 900);
      expect(
        _boxRect(tester, 'connect').center,
        _near(corner + _home),
        reason: '收着的时候 reach 是死的（pointer-events:none），hover 过去不该开',
      );
      await g.moveTo(_cardCenter(tester));
      await _run(tester, 900);
      expect(_boxRect(tester, 'connect').center, _near(corner + _targets[0]));
      // 走到钮上那截（卡片盒外）不算离开
      await g.moveTo(inFan);
      for (var f = 0; f < 45; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        _boxRect(tester, 'settings').center,
        _near(corner + _targets[3]),
        reason: '指针一出卡片盒就收回 —— reach 没接住',
      );
      // 死角：卡片右外 40，但低于 reach 下缘
      await g.moveTo(dead);
      await _run(tester, 900);
      expect(
        _boxRect(tester, 'settings').center,
        _near(corner + _home),
        reason: '那块参考稿不算命中，这里不该还开着',
      );
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('离开按倒序收：3 号先进', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final home = _fanOrigin(tester) + _home;
      final g = await ilHoverAt(tester, _cardCenter(tester));
      await _run(tester, 900);
      await g.moveTo(const Offset(2, 2));
      await _run(tester, 96);
      final d = <double>[
        for (final id in _ids) (_boxRect(tester, id).center - home).distance,
      ];
      expect(d[3], lessThan(d[2]));
      expect(d[2], lessThan(d[1]));
      expect(d[1], lessThan(d[0]));
      await _park(tester, g);
      await unmountPage(tester);
    });

    testWidgets('逐帧扫 2000ms：开→走→收→停，全程不抛', (tester) async {
      await mountIlCase(tester, const Case13ActionNode(), window: _win);
      final corner = _fanOrigin(tester);
      final g = await ilHoverAt(tester, _cardCenter(tester));
      final snaps = <String>[];
      for (var f = 0; f < 57; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        snaps.add(_snap(tester));
      }
      expect(snaps.toSet().length, greaterThan(30), reason: '错拍 + 过冲，静止帧不该占多数');
      final settled = snaps.last;
      expect(snaps[snaps.length - 2], settled, reason: '900ms 该全部收敛');
      // 指针在扇区里走一圈：每一步走完都该回到同一个静止读数，一次都不许重播错拍
      for (final at in <Offset>[
        corner + const Offset(40, 20),
        corner + const Offset(-40, -30),
        corner + const Offset(20, 60),
        corner + const Offset(0, -50),
      ]) {
        await g.moveTo(at);
        for (var f = 0; f < 20; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(_snap(tester), settled, reason: '指针停在 $at 时扇出不该动');
      }
      await g.moveTo(const Offset(2, 2));
      for (var f = 0; f < 60; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (final id in _ids) {
        expect(_boxRect(tester, id).center, _near(corner + _home));
      }
      expect(tester.takeException(), isNull);
      await _park(tester, g);
      await unmountPage(tester);
    });
  });
}

// ---------------------------------------------------------------- 读数小工具

/// 按 16ms 一格把假时钟推进 `ms`
///
/// 不能直接 `pump(900ms)`：一次 pump 只出**一帧**，弹簧那一帧拿到的 dt 会被
/// clamp 到 2.5，等于把 900ms 的行程压成 2.5 帧的积分 —— 读数是静止的，
/// 图也是静止的。逐帧才是这条时间轴原本的走法。
Future<void> _run(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    final step = left < 16 ? left : 16;
    await t.pump(Duration(milliseconds: step));
    left -= step;
  }
}

Finder _act(WidgetTester t, String id) => find.byKey(ValueKey<String>('act-$id'));

/// 钮的**视觉**盒：圆心从 `Positioned` 的布局参数算，边长从 `Transform` 的矩阵读
///
/// 不能用 `tester.getRect` —— 它把"已经过变换的左上角"和"没变换的 36×36"拼在一起，
/// 缩放过的盒会整体偏掉 `(1-scale)·18`（收起态 scale=.82 就是 3.2px，正好把
/// "圆心在不在停靠位"这条判据整个带歪）。
/// 扇出原点（没抬起时的卡片右上角）
///
/// 参考稿的 `.nod-fan`/`.nod-reach` 钉在不动的 `.nod` 根盒上，`[data-on]` 那 1px
/// 只抬 `.nod-card` —— 直接读卡片矩形会跟着一起抬，读数处处差 1px。
/// 根盒坐在舞台正中、卡片正好占满它，所以原点从舞台中心反推。
Offset _fanOrigin(WidgetTester t) {
  final s = t.getRect(find.byType(IlStage));
  final h = t.getRect(find.byKey(_card)).height;
  return Offset(s.center.dx + _cardW / 2, s.center.dy - h / 2);
}

Rect _boxRect(WidgetTester t, String id) {
  final p = t.widget<Positioned>(find.ancestor(of: _act(t, id), matching: find.byType(Positioned)));
  // Stack 原点 = 扇出原点往上 52（根盒的 padding-block），Positioned 也是 Stack 坐标
  final origin = _fanOrigin(t) - const Offset(_cardW, IlNodeFan.band);
  final half = IlNodeFan.btn * _scale(t, id) / 2;
  final c = origin + Offset(p.left! + IlNodeFan.half, p.top! + IlNodeFan.half);
  return Rect.fromCenter(center: c, width: half * 2, height: half * 2);
}

/// 钮当前缩放 = `--pop × --zoom`（矩阵左上角那一格）
double _scale(WidgetTester t, String id) =>
    t.widget<Transform>(find.byKey(ValueKey<String>('act-xf-$id'))).transform.storage[0];

/// 卡片中心（窗口坐标）：受理区就在这块里
Offset _cardCenter(WidgetTester t) => t.getRect(find.byKey(_card)).center;

/// 悬停到卡片中心并等整块展开（弹簧 + 错拍 + 那 1px 抬起全走完）
Future<TestGesture> _hoverCard(WidgetTester t) async {
  final g = await ilHoverAt(t, _cardCenter(t));
  await _run(t, 900);
  return g;
}

/// 把指针挪出整块并注销：一个 test 里只留一根手指，第二次 addPointer 才不撞断言
Future<void> _park(WidgetTester t, TestGesture g) async {
  await g.moveTo(const Offset(3, 3));
  await t.pump();
  await g.removePointer();
  await t.pump();
}

String _snap(WidgetTester t) => <String>[
      for (final id in _ids)
        '${_boxRect(t, id).center.dx.toStringAsFixed(3)},'
            '${_boxRect(t, id).center.dy.toStringAsFixed(3)}',
    ].join('|');

double _radius(WidgetTester t, ValueKey<String> key) {
  final box = t.widget<Container>(find.byKey(key));
  return (((box.decoration! as BoxDecoration).borderRadius)! as BorderRadius).topLeft.x;
}

/// 逐轴比对的 Offset 判等：`closeTo` 只管标量，圆心要的是"x 差多少、y 差多少"
Matcher _near(Offset want, [double tol = 0.6]) => _Near(want, tol);

class _Near extends Matcher {
  const _Near(this.want, this.tol);

  final Offset want;
  final double tol;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is Offset && (item.dx - want.dx).abs() <= tol && (item.dy - want.dy).abs() <= tol;

  @override
  Description describe(Description d) => d.add(
        '在 (${want.dx.toStringAsFixed(2)}, ${want.dy.toStringAsFixed(2)}) ±$tol 内',
      );
}
