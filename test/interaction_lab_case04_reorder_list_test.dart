import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_04_reorder_list.dart';

import 'helpers/il_golden.dart';

// 4 号 Reorder list：真的按住一行拖，不是播一段"看起来像在拖"的动画
//
// 出图要证明的四件事，全部靠量像素而不是肉眼
// （列 x=270 是干净采样列；左端 110 那一档是头像，药丸本体从 115 起）：
// 1. **按下就抓起**：`press` 量到药丸 106..313 = 208 宽、色 (218,218,218)，
//    静止/悬停是 112..307 = 196 宽、色 255/252 —— 抬起只改宽和底色，不改 y；
// 2. **拿起那行钉在指上、其余行让开**：`settled` 里第一行已经是另一个人
//    （文字的游程签名和 `idle` 的第二行逐段相同），原来那行落到 121..164；
//    `letgo`（走完 100ms）量到让开的行停在 70..113 —— 越过目标 1px 再回来，
//    是弹簧不是瞬移；
// 3. **形变只在甩的时候有**：`scaleY = 1+.5·|S|·.12`、`scaleX = 1/scaleY`，S 钳 ±3。
//    静止 196×44；慢拖（每帧 1.5px → S=1.5）量到 190×47；快甩（每帧 30px → S 钳满 3）
//    量到 176×52 —— 面积守恒的拉长，右边缘 298.1→297、190.8→191 都对得上；
// 4. **6px 间隙会熔化**：`goo` 拖 14px（不换序）时两颗药丸重叠 8px，
//    y 84..164 是一整块连着的，中间那道"缝"只是 218→255 路过舞台底色 237 那一行。
//
// 形变那两张图要先"按住不动"等 260ms：`--lift` 弹簧 {220,14,.5} 走完才落到位，
// 抬起后的宽度直接进 `scaleX`，没落定就量不到 208×.917 / 208×.847 这两个数。
//
// 每帧 3px 以上就撞钳位了：`letgo`（16 步拖 60）和 `stretch`（2 步）量到的是同一档形变。
//
// 行中心相对舞台中心：第 i 行 = 50i − 78（列表 200 高、行距 50、药丸 44 高）

IlHold? _hold;

Offset _rowAt(WidgetTester t, int i) => ilStageCenter(t) + Offset(0, 50.0 * i - 78);

/// 按住第 i 行，往下拖 `dy`（steps 越小甩得越猛）
///
/// `settleMs` 在按下之后、起拖之前把钟走完，只留给需要量形变的那两帧。
Future<void> _grab(
  WidgetTester t,
  int i,
  double dy, {
  int steps = 16,
  int settleMs = 0,
}) async {
  final at = _rowAt(t, i);
  var hold = await ilGrab(t, at: at);
  if (settleMs > 0) hold = await _holdFor(t, hold, settleMs);
  if (dy != 0) hold = await ilDragTo(t, hold, at + Offset(0, dy), steps: steps);
  _hold = hold;
}

/// 什么都不做，只按着过 `ms`：把弹簧和补间推到位
Future<IlHold> _holdFor(WidgetTester t, IlHold hold, int ms) async {
  for (var e = 0; e < ms; e += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
  return hold;
}

Future<void> _grabDrop(WidgetTester t, int i, double dy, {int steps = 16}) async {
  await _grab(t, i, dy, steps: steps);
  await ilDrop(t, _hold!);
  _hold = null;
}

void main() {
  tearDown(() => _hold = null);

  testWidgets('4. Reorder list 静止帧', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c04_idle', child: const Case04ReorderList());
  });

  // 悬停只换底色（1.3% 墨混白），不许有位移或缩放——按住才有那两样
  testWidgets('4. Reorder list 悬停帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_hover',
      child: const Case04ReorderList(),
      act: (t) => ilHoverAt(t, _rowAt(t, 1)),
      thenMs: 220,
    );
  });

  testWidgets('4. Reorder list 抓起帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_press',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 0),
      thenMs: 260,
    );
  });

  testWidgets('4. Reorder list 熔化帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_goo',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 14),
    );
  });

  // 每帧 1.5px：S=1.5，形变刚起步（190×48）
  testWidgets('4. Reorder list 慢拖帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_crawl',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 60, steps: 40, settleMs: 260),
    );
  });

  // 每帧 30px：早越过 ±3 的钳位，量到的就是最大一档（176×52）
  testWidgets('4. Reorder list 甩长帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_stretch',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 60, steps: 2, settleMs: 260),
    );
  });

  /// 拖过半步（25px）就换序：其余行开始让位，中途那一帧证明是弹簧不是瞬移
  testWidgets('4. Reorder list 让位帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_letgo',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 60),
      thenMs: 100,
    );
  });

  /// 位置不钳边界：拖出 4 行之外（读数钳到 3），行会被舞台圆角齐齐裁掉
  testWidgets('4. Reorder list 拖出界帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_over',
      child: const Case04ReorderList(),
      act: (t) => _grab(t, 0, 200),
      thenMs: 160,
    );
  });

  testWidgets('4. Reorder list 吸附中帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_snap',
      child: const Case04ReorderList(),
      act: (t) => _grabDrop(t, 0, 60),
      thenMs: 100,
    );
  });

  testWidgets('4. Reorder list 落定帧', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c04_settled',
      child: const Case04ReorderList(),
      act: (t) => _grabDrop(t, 0, 60),
      thenMs: 900,
    );
  });

  testWidgets('4. Reorder list 逐帧扫', (tester) async {
    await mountIlCase(tester, const Case04ReorderList());

    Future<void> scan(String tag, int ms) async {
      for (var t = 16; t <= ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final e = tester.takeException();
        if (e != null) fail('4 号 $tag 段 ${t}ms 抛了：$e');
      }
    }

    // 拖到底 → 一路换序 → 拖出界 → 松手吸附，再倒着拖回去
    await _grab(tester, 0, 60);
    await scan('拖 60', 200);
    await ilDragTo(tester, _hold!, _rowAt(tester, 0) + const Offset(0, 240), steps: 6);
    await scan('甩出界', 200);
    await ilDrop(tester, _hold!);
    _hold = null;
    await scan('吸附', 600);

    await _grabDrop(tester, 3, -40, steps: 8);
    await scan('倒数第二行上提', 600);
    await unmountPage(tester);
  });
}
