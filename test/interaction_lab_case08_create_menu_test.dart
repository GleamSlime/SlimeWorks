import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_08_create_menu.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 8 号 Create menu：一次按下，四套钟同时起
//
// 断言要证明的六件事：
// 1. **关态宽是量出来的**：药丸 = `26 + "Create" 实测宽 + 34`，高 38；开态钉死 212×166。
// 2. **按下先进 sink 60ms**，到点自己换成展开——这 60ms 里 scale 已经在压、尺寸还没动。
// 3. **宽/高/圆角是同一条弹簧的三个量**：同一帧里三条归一化进度必须**完全相等**，
//    且全程不越过静止位（`{420,30,.5}` 的阻尼比 1.03，本来就是过阻尼）。
// 4. **四行 delay 30/52/74/96**：相邻两行的起步间隔必须是 22ms（±1 帧），
//    关闭时 delay 归零，四行同一帧一起退。
// 5. **药丸淡出是双向不同时长**：开 120ms、关 160ms。
// 6. **两条收回路径**：点行、点面板矩形外 → 收；点在面板矩形内的空白（行间距那 2px）、
//    点在已经淡没的药丸位置 → 不收。
// 7. **悬停点亮两层**：文字色 200ms、行底 8% 水洗进 140ms 出 220ms（进快出慢）。
//
// 坐标（窗口 420×366，舞台 372×256 居中于 (24,55)）：组件根盒 244×244 → 左上角 (88,61)。
// 关态药丸中心 = 舞台中心 (210,183)；开态面板矩形 (104,100)–(316,266)；
// 第 i 行中心 = 舞台中心 +(0, −55+36i)；行间距那 2px 的中心 = 舞台中心 +(0, −37)；
// 面板外的落点 = 舞台中心 −(117, 0)。

final _win = Size(IlSize.cardW() + 24, IlSize.cardH(256) + 24);

final _body = find.byKey(const ValueKey('body'));
final _panel = find.byKey(const ValueKey('panel'));

Offset _pillAt(WidgetTester t) => ilStageCenter(t);
Offset _rowAt(WidgetTester t, int i) => ilStageCenter(t) + Offset(0.0, -55.0 + 36.0 * i);
/// 第 0/1 行之间那 2px（在面板矩形里、又不在任何行上）
Offset _betweenRows(WidgetTester t) => ilStageCenter(t) + const Offset(0, -37);

/// 第 1/2 行之间那 2px，正好也在已经淡没的药丸盒里
Offset _pillSpot(WidgetTester t) => ilStageCenter(t) - const Offset(0, 1);
Offset _outside(WidgetTester t) => ilStageCenter(t) - const Offset(117, 0);

Future<void> _pump(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

/// 按下药丸并等它走完成形（弹簧 + 四行 delay 都收干净）
Future<void> _openAndSettle(WidgetTester t) async {
  await t.tapAt(_pillAt(t));
  await _pump(t, 1300);
}

/// 布局盒尺寸：`Transform.scale` 不改布局，所以这里读到的就是弹簧的三个量之一
Size _bodySize(WidgetTester t) => t.getSize(_body);

/// sink 那道 scale：`Transform.scale` 的矩阵基向量
double _sinkScale(WidgetTester t) =>
    t.widget<Transform>(find.byKey(const ValueKey('sink'))).transform.storage[0];

double _pillFade(WidgetTester t) =>
    t.widget<Opacity>(find.byKey(const ValueKey('pillfade'))).opacity;

double _rowFade(WidgetTester t, int i) =>
    t.widget<Opacity>(find.byKey(ValueKey('row-$i'))).opacity;

/// 相对面板顶边的 y：`11 + 36i + 那 6px 进场位移`
double _rowY(WidgetTester t, int i) {
  final panel = t.renderObject<RenderBox>(_panel);
  return t.renderObject<RenderBox>(find.byKey(ValueKey('row-$i'))).getTransformTo(panel).storage[13];
}

double _rowInk(WidgetTester t, int i) =>
    t.widget<Text>(find.text(_labels[i])).style!.color!.a;

/// 行底水洗的实际不透明度（`:before` 那层 `rgba(ink,.08)`，探针读 alpha）
double _rowWash(WidgetTester t, int i) =>
    (t.widget<DecoratedBox>(find.byKey(ValueKey('wash-$i'))).decoration as BoxDecoration).color!.a;

double _bodyRadius(WidgetTester t) {
  final d = t
      .widget<DecoratedBox>(find.descendant(of: _body, matching: find.byType(DecoratedBox)))
      .decoration as BoxDecoration;
  return (d.borderRadius! as BorderRadius).topLeft.x;
}

/// 关态药丸宽：和组件里同一条公式（26 + 标签实测 + 34）
double _pillW() {
  final tp = TextPainter(
    textDirection: TextDirection.ltr,
    text: const TextSpan(
      text: 'Create',
      style: TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: ['PingFang SC'],
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
      ),
    ),
  )..layout();
  return 26 + tp.width.roundToDouble() + 1 + 34;
}

const _labels = ['Document', 'Spreadsheet', 'Board', 'Folder'];

void main() {
  // ------------------------------------------------------------ 出图

  testWidgets('8. Create menu 静止：一颗药丸', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c08_idle', child: const Case08CreateMenu(), window: _win);
  });

  testWidgets('8. Create menu 按压中：还没展开', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_sink',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async => t.tapAt(_pillAt(t)),
      // 60ms 门槛的前一帧：scale 压到最深（实测 .961），尺寸还钉在 103×38。
      // 再推一帧就跨过门槛开始成形，这张图就什么都证明不了了
      thenMs: 32,
    );
  });

  testWidgets('8. Create menu 成形后段：四行由深到浅、最后一行还没进', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_expand_mid',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async => t.tapAt(_pillAt(t)),
      thenMs: 140,
    );
  });

  testWidgets('8. Create menu 成形途中：白块还在两态之间', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_stagger',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async => t.tapAt(_pillAt(t)),
      thenMs: 92,
    );
  });

  testWidgets('8. Create menu 展开落定', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_open',
      child: const Case08CreateMenu(),
      window: _win,
      act: _openAndSettle,
    );
  });

  testWidgets('8. Create menu 悬停第二行', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_hover',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async {
        await _openAndSettle(t);
        await ilHoverAt(t, _rowAt(t, 1));
        await _pump(t, 220);
      },
    );
  });

  testWidgets('8. Create menu 收回途中', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_close_mid',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async {
        await _openAndSettle(t);
        await t.tapAt(_betweenRows(t)); // 先证"这里不收"
        await t.tapAt(_outside(t));
      },
      thenMs: 40,
    );
  });

  testWidgets('8. Create menu 收回落定', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c08_closed',
      child: const Case08CreateMenu(),
      window: _win,
      act: (t) async {
        await _openAndSettle(t);
        await t.tapAt(_outside(t));
      },
      thenMs: 900,
    );
  });

  // ------------------------------------------------------------ 断言

  testWidgets('关态：药丸 38 高、宽按标签实测；面板挂在树上但不受理指针', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    final size = _bodySize(tester);
    expect(size.height, 38);
    expect(size.width, _pillW());
    expect(_bodyRadius(tester), 19);
    // 关态面板也画在树上（参考稿靠 opacity 0 + pointer-events:none 压住），
    // 所以点它等于没点
    expect(tester.getRect(_panel).size, const Size(212, 166));
    await tester.tapAt(_betweenRows(tester));
    await _pump(tester, 120);
    expect(_bodySize(tester).height, 38, reason: '关态点在面板矩形里不该把菜单叫出来');
    expect(_rowFade(tester, 0), 0);
    // 关态那 6px 位移还压着：行的布局顶边 11，画面位置 17
    expect(_rowY(tester, 0), closeTo(17, 0.01));
    expect(_rowInk(tester, 0), closeTo(0.78, 0.005));
    await unmountPage(tester);
  });

  testWidgets('按下先进 sink 60ms：scale 已经在压、尺寸还没动', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    final closed = _bodySize(tester);
    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 32);
    expect(_sinkScale(tester), inExclusiveRange(0.94, 1.0), reason: '这 60ms 里只有 scale 在动');
    // 上面两帧之内就该展开：按下到展开的门槛是 60ms，`tapAt` 自己吃掉的那几帧另算
    expect(_bodySize(tester), closed, reason: '尺寸弹簧要到 60ms 那一拍才拿到新目标');
    expect(_pillFade(tester), 1);

    await _pump(tester, 64);
    expect(_bodySize(tester).height, greaterThan(38), reason: '过了 60ms 就开始长成菜单');
    expect(_pillFade(tester), lessThan(1));
    await unmountPage(tester);
  });

  testWidgets('宽/高/圆角是同一条弹簧：同一帧三条归一化进度相等、且不过头', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    final from = _bodySize(tester);
    await tester.tapAt(_pillAt(tester));
    var maxH = 38.0;
    double? seen;
    var compared = 0;
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _bodySize(tester);
      if (s.height >= 166) break;
      final pw = (s.width - from.width) / (212 - from.width);
      final ph = (s.height - 38) / (166 - 38);
      final pr = (_bodyRadius(tester) - 19) / (28 - 19);
      expect(s.height, greaterThanOrEqualTo(maxH), reason: '过阻尼：不许越过静止位再回来');
      maxH = s.height;
      seen = ph;
      // 弹簧有 0.02px 的静止阈值，圆角那条跨度只有 9px，会先把剩下的残差当成 0 落定。
      // 一旦哪条先到位，归一化进度就再也对不齐了——只在三条都在路上时比对曲线。
      if (pw >= 1.0 || pr >= 1.0) continue;
      compared++;
      expect(ph, closeTo(pw, 1e-9), reason: '宽和高必须走同一条弹簧曲线');
      expect(pr, closeTo(ph, 1e-9), reason: '圆角也必须走同一条');
    }
    expect(compared, greaterThan(4), reason: '一帧都没比对上就说明这条弹簧根本没同步跑');
    expect(seen, isNotNull, reason: '中途一帧都没拍到就说明形变根本没跑');
    expect(seen, greaterThan(0.2));
    expect(seen, lessThan(1.0));
    await _pump(tester, 700);
    expect(_bodySize(tester), const Size(212, 166));
    expect(_bodyRadius(tester), 28);
    await unmountPage(tester);
  });

  testWidgets('四行 delay 30/52/74/96：相邻两行差 22ms，关闭一起退', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    await tester.tapAt(_pillAt(tester));
    final start = <int, int>{};
    for (var f = 0; f < 60 && start.length < 4; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        // 位移和透明度是同一个 delay 驱动的两条钟，任一条动了就算起步
        if (!_rowStarted(tester, i) || start.containsKey(i)) continue;
        start[i] = f * 16;
      }
    }
    expect(start.keys.toList()..sort(), [0, 1, 2, 3]);
    for (var i = 1; i < 4; i++) {
      final gap = start[i]! - start[i - 1]!;
      // 22ms 落在 16ms 的帧网格上：只能圆成 16 或 32
      expect(gap, inInclusiveRange(16, 32), reason: '第 ${i + 1} 行相对第 $i 行的 delay');
    }

    await _pump(tester, 900);
    for (var i = 0; i < 4; i++) {
      expect(_rowFade(tester, i), 1);
      expect(_rowY(tester, i), closeTo(11.0 + 36.0 * i, 0.01));
    }

    await tester.tapAt(_outside(tester));
    await _pump(tester, 32);
    for (var i = 0; i < 4; i++) {
      // 退场 delay 全是 0：四行在同一帧里一起往下走
      expect(_rowFade(tester, i), lessThan(1), reason: '第 ${i + 1} 行没跟着一起退');
      expect(_rowY(tester, i), greaterThan(11.0 + 36.0 * i));
    }
    await unmountPage(tester);
  });

  testWidgets('药丸淡出：开 120ms、关 160ms', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    await tester.tapAt(_pillAt(tester));
    var first = -1, done = -1;
    for (var f = 0; f < 60 && done < 0; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final v = _pillFade(tester);
      if (v < 1 && first < 0) first = f;
      if (v <= 0) done = f;
    }
    expect(first, greaterThanOrEqualTo(0), reason: '药丸根本没淡出');
    expect((done - first) * 16, inInclusiveRange(112, 144), reason: '开态覆盖规则那条 120ms');

    await _pump(tester, 900);
    await tester.tapAt(_outside(tester));
    var back = -1;
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_pillFade(tester) >= 1) {
        back = (f + 1) * 16;
        break;
      }
    }
    expect(back, inInclusiveRange(160, 192), reason: '回到基础规则那条 160ms');
    await unmountPage(tester);
  });

  testWidgets('收回只有两条路径：点行、点面板外；面板内空白和药丸位置都不收', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    await _openAndSettle(tester);
    expect(_bodySize(tester), const Size(212, 166));

    // 行间距那 2px：在面板矩形内 → 不收
    await tester.tapAt(_betweenRows(tester));
    await _pump(tester, 120);
    expect(_bodySize(tester).height, 166);
    // 药丸的原位：open 之后它 pointer-events:none，点上去等于点在面板里 → 不收
    await tester.tapAt(_pillSpot(tester));
    await _pump(tester, 120);
    expect(_bodySize(tester).height, 166, reason: '点到淡没的药丸上不该重新按下去');

    await tester.tapAt(_outside(tester));
    await _pump(tester, 700);
    expect(_bodySize(tester), Size(_pillW(), 38));
    expect(_pillFade(tester), 1);

    // 再开一次，用"点某一项"收回
    await tester.tapAt(_pillAt(tester));
    await _pump(tester, 1300);
    expect(_bodySize(tester), const Size(212, 166));
    await tester.tapAt(_rowAt(tester, 2));
    await _pump(tester, 700);
    expect(_bodySize(tester).height, 38, reason: '点某一项也要收回');
    await unmountPage(tester);
  });

  testWidgets('悬停点亮两层：文字 .78→1、行底 8% 水洗，别的行不动', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    await _openAndSettle(tester);
    final hold = await ilHoverAt(tester, _rowAt(tester, 1));
    await _pump(tester, 220);
    expect(_rowInk(tester, 1), closeTo(1.0, 0.005));
    expect(_rowWash(tester, 1), closeTo(0.08, 0.002), reason: '水洗是 rgba(ink, .08)，140ms 早该走满');
    for (final i in [0, 2, 3]) {
      expect(_rowInk(tester, i), closeTo(0.78, 0.005));
      expect(_rowWash(tester, i), 0);
    }

    // 移开：水洗按基础规则那条 220ms 退，文字色按 200ms
    await hold.moveTo(const Offset(210, 30));
    await _pump(tester, 100);
    final mid = _rowWash(tester, 1);
    expect(mid, lessThan(0.08), reason: '100ms 只走完退场的一半不到');
    expect(mid, greaterThan(0));
    await _pump(tester, 260);
    expect(_rowInk(tester, 1), closeTo(0.78, 0.005));
    expect(_rowWash(tester, 1), 0);
    await hold.removePointer();
    await tester.pump();
    await unmountPage(tester);
  });

  testWidgets('逐帧扫：一次开合里每一帧都在动，落定之后才停', (tester) async {
    await mountIlCase(tester, const Case08CreateMenu(), window: _win);
    final snaps = <String>[];
    await tester.tapAt(_pillAt(tester));
    for (var f = 0; f < 46; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add('${_fmtSize(_bodySize(tester))}|${_sinkScale(tester).toStringAsFixed(4)}'
          '|${_pillFade(tester).toStringAsFixed(3)}|${_rowFade(tester, 3).toStringAsFixed(3)}');
    }
    expect(_flatCount(snaps), lessThanOrEqualTo(1), reason: '只有起跑那一帧是零时长，其余每帧都得变');
    expect(_lastChange(snaps), greaterThan(15));

    snaps.clear();
    await tester.tapAt(_outside(tester));
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      snaps.add('${_fmtSize(_bodySize(tester))}|${_pillFade(tester).toStringAsFixed(3)}'
          '|${_rowFade(tester, 0).toStringAsFixed(3)}');
    }
    expect(_flatCount(snaps), lessThanOrEqualTo(1));
    expect(_lastChange(snaps), greaterThan(10));

    // 都收干净之后必须彻底静止
    await _pump(tester, 900);
    final rest = '${_fmtSize(_bodySize(tester))}|${_pillFade(tester)}|${_rowFade(tester, 0)}';
    for (var f = 0; f < 10; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect('${_fmtSize(_bodySize(tester))}|${_pillFade(tester)}|${_rowFade(tester, 0)}', rest);
    }
    await unmountPage(tester);
  });
}

/// `Size.toString()` 只留一位小数，会把弹簧尾帧那零点几 px 的位移压成同一行读数，
/// 逐帧扫就会误判成"卡住"。按全精度记。
String _fmtSize(Size s) => '${s.width}/${s.height}';

bool _rowStarted(WidgetTester t, int i) =>
    _rowFade(t, i) > 0 || _rowY(t, i) < 11.0 + 36.0 * i - 0.01;

/// 动画段内和上一帧读数相同的帧数：只数到"最后一次还在动"为止
///
/// 扫的帧数比动画长，尾巴上必然全是静止帧——那是跑完了，不是卡住。
/// 起跑那一帧是零时长（Ticker 重启首拍），所以这一段里只允许 1 帧不变。
int _flatCount(List<String> s) {
  var n = 0;
  for (var i = 1, e = _lastChange(s); i <= e; i++) {
    if (s[i] == s[i - 1]) n++;
  }
  return n;
}

/// 最后一次"还在变"的帧号：它之后必须一路静止
int _lastChange(List<String> s) {
  var last = 0;
  for (var i = 1; i < s.length; i++) {
    if (s[i] != s[i - 1]) last = i;
  }
  return last;
}
