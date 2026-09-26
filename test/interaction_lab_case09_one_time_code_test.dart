import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/interaction_lab/cases/case_09_one_time_code.dart';
import 'package:slime_works/pages/interaction_lab/kit.dart';

import 'helpers/il_golden.dart';

// 9 号 One-time code：四格和胶囊共用一层 goo，状态机 type → check → ok|no → type
//
// 断言要证明的九件事：
// 1. **静止几何是量出来的**：格 36×44、格心 X = 0/43/86/129、圆角 12；没有焦点不画光标。
// 2. **没焦点敲键盘不收录**：参考稿的焦点在真 input 身上。
// 3. **光标追赶是欠阻尼弹簧**：落点 18/61/104/147，追的时候 scaleX 顶到 5 倍以上（封顶 6），
//    往回收时会**越过**落点（实测最低 5.55，目标 18）。
// 4. **逐字入场只给换了字符的那一格**：300ms 里多一层带 blur 的 Opacity，走完整个消失。
// 5. **check 期呼吸波压到 0.93 就回弹**，且不越过 0.93；结论要等满 420ms。
// 6. **Accept 融合弹簧有量级**：约 52 帧到位、峰值 146 宽、scaleY 最低 0.913，
//    终点钉死 pill=128 / 格心 64.5 / 圆角 22。
// 7. **Reject 两段**：620ms 抖动（封顶 5px、跨零点、到点精确归位）+ 右→左依次晚 45ms
//    的 8px 掉落，**掉落只有位移没有淡出**。
// 8. **变红 160ms、960ms 整串清空**回 type。
// 9. **已验证态点一下回收**：光标在 ok 态是 click，点下去融合倒回 0。

final _cells = [for (var i = 0; i < 4; i++) find.byKey(ValueKey('cell-$i'))];
final _pill = find.byKey(const ValueKey('pill'));

double _xf(WidgetTester t, String key, int i) =>
    t.widget<Transform>(find.byKey(ValueKey(key))).transform.storage[i];

/// 有的层只在动画途中挂在树上：缺席时按各自的静止值报，免得读取本身炸掉
double _xfOr(WidgetTester t, String key, int i, double absent) =>
    find.byKey(ValueKey(key)).evaluate().isEmpty ? absent : _xf(t, key, i);

/// 某一格画面上的 X（transform 的平移列）
double _cellX(WidgetTester t, int i) => _xf(t, 'cell-xf-$i', 12);

double _cellScale(WidgetTester t, int i) => _xf(t, 'cell-xf-$i', 0);

double _slotA(WidgetTester t, int i) => t.widget<Opacity>(find.byKey(ValueKey('slot-$i'))).opacity;

/// 光标：`caret-xf` 的平移列写的是 `x-1`，读回来要 +1 才是格内坐标
double _caretX(WidgetTester t) => _xf(t, 'caret-xf', 12) + 1;

double _caretA(WidgetTester t) => t.widget<Opacity>(find.byKey(const ValueKey('caret'))).opacity;

double _okA(WidgetTester t) => t.widget<Opacity>(find.byKey(const ValueKey('ok'))).opacity;

double _pillW(WidgetTester t) => _pill.evaluate().isEmpty ? 0 : t.getSize(_pill).width;

double _pillScaleY(WidgetTester t) => _xfOr(t, 'pill-xf', 5, 1);

double _dropY(WidgetTester t, int i) => _xfOr(t, 'drop-xf-$i', 13, 0);

Color _digitColor(WidgetTester t, int i) =>
    t.widget<Text>(find.byKey(ValueKey('digit-$i'))).style!.color!;

/// 通道按 8 位精度比：lerp 用 double 逐位算，末位不保证复现
void _expectColor(Color got, Color want) {
  expect(got.r, closeTo(want.r, 1 / 512), reason: '$got vs $want');
  expect(got.g, closeTo(want.g, 1 / 512), reason: '$got vs $want');
  expect(got.b, closeTo(want.b, 1 / 512), reason: '$got vs $want');
  expect(got.a, closeTo(want.a, 1 / 512), reason: '$got vs $want');
}

double _radius(WidgetTester t) {
  final d = t.widget<DecoratedBox>(_cells[0]).decoration as BoxDecoration;
  return (d.borderRadius! as BorderRadius).topLeft.x;
}

MouseCursor _hitCursor(WidgetTester t) => t.widget<MouseRegion>(find.byKey(const ValueKey('hit'))).cursor;

Future<void> _pump(WidgetTester t, int ms) async {
  var left = ms;
  while (left > 0) {
    await t.pump(const Duration(milliseconds: 16));
    left -= 16;
  }
}

/// 拿焦点后逐位敲，位间隔 [gapMs]
Future<void> _focusAndType(WidgetTester t, String s, {int gapMs = 0}) async {
  await t.tapAt(ilStageCenter(t));
  await _pump(t, 32);
  debugPrint('DBG caretA=${_caretA(t)} hasDigit0=${find.byKey(const ValueKey('digit-0')).evaluate().isNotEmpty}');
  for (final ch in s.split('')) {
    await ilType(t, ch);
    debugPrint('DBG after $ch digit0=${find.byKey(const ValueKey('digit-0')).evaluate().isNotEmpty} caret=${_caretX(t)}');
    if (gapMs > 0) await _pump(t, gapMs);
  }
}

/// 敲满四位并跨过 420ms 的结论拍
Future<void> _fillToVerdict(WidgetTester t) async {
  await _focusAndType(t, '1234');
  await _pump(t, 448);
}

Future<void> _fillToReject(WidgetTester t) async {
  await _focusAndType(t, '4678');
  await _pump(t, 448);
}

void main() {
  // ------------------------------------------------------------ 出图

  testWidgets('9. OTP 静止：四格白药丸', tags: 'golden', (tester) async {
    await shootIlCase(tester, name: 'c09_idle', child: const Case09OneTimeCode());
  });

  testWidgets('9. OTP 拿到焦点：光标立在第一格', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_focus',
      child: const Case09OneTimeCode(),
      act: (t) => t.tapAt(ilStageCenter(t)),
      thenMs: 64,
    );
  });

  testWidgets('9. OTP 逐字入场：第二格还糊着', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_entry',
      child: const Case09OneTimeCode(),
      // 第一位走完 300ms 入场再敲第二位，图里才同时有"稳的"和"在进的"
      act: (t) => _focusAndType(t, '12', gapMs: 320),
      thenMs: 64,
    );
  });

  testWidgets('9. OTP 呼吸波：格子被压扁', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_check',
      child: const Case09OneTimeCode(),
      act: (t) => _focusAndType(t, '1234'),
      thenMs: 256,
    );
  });

  testWidgets('9. OTP 融合途中：拉丝接上了', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_merge',
      child: const Case09OneTimeCode(),
      act: (t) => _focusAndType(t, '1234'),
      thenMs: 512,
    );
  });

  testWidgets('9. OTP 过冲峰：窄一点高一点', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_overshoot',
      child: const Case09OneTimeCode(),
      act: (t) => _focusAndType(t, '1234'),
      thenMs: 624,
    );
  });

  testWidgets('9. OTP 已验证：一颗胶囊', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_ok',
      child: const Case09OneTimeCode(),
      act: (t) => _focusAndType(t, '1234'),
      thenMs: 1400,
    );
  });

  testWidgets('9. OTP 点击回收途中', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_unmerge',
      child: const Case09OneTimeCode(),
      act: (t) async {
        await _fillToVerdict(t);
        await _pump(t, 900);
        await t.tapAt(ilStageCenter(t));
      },
      thenMs: 48,
    );
  });

  testWidgets('9. OTP 判错抖动', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_reject_shake',
      child: const Case09OneTimeCode(reject: true),
      act: (t) => _focusAndType(t, '4678'),
      thenMs: 480,
    );
  });

  testWidgets('9. OTP 判错掉落：右边几格已经掉下去', tags: 'golden', (tester) async {
    await shootIlCase(
      tester,
      name: 'c09_reject_drop',
      child: const Case09OneTimeCode(reject: true),
      act: (t) => _focusAndType(t, '4678'),
      thenMs: 868,
    );
  });

  // ------------------------------------------------------------ 断言

  testWidgets('静止：格 36×44、格心 0/43/86/129、圆角 12、无光标', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    for (var i = 0; i < 4; i++) {
      expect(tester.getSize(_cells[i]), const Size(36, 44));
      expect(_cellX(tester, i), closeTo(43.0 * i, 1e-9));
      expect(_cellScale(tester, i), 1);
      expect(_slotA(tester, i), 1);
    }
    expect(_radius(tester), 12);
    expect(_pill, findsNothing);
    expect(_caretA(tester), 0);
    expect(_xf(tester, 'ok-xf', 0), 0.92);
    expect(find.text('Verified'), findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('没焦点时敲键盘不收录；点一下才立光标', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await ilType(tester, '12');
    await _pump(tester, 64);
    expect(find.byKey(const ValueKey('digit-0')), findsNothing);
    expect(_caretA(tester), 0);

    await tester.tapAt(ilStageCenter(tester));
    await _pump(tester, 32);
    expect(_caretX(tester), closeTo(18, 1e-6));
    expect(_caretA(tester), greaterThan(0.9), reason: '呼吸从 1 起跳');
    expect(_xf(tester, 'caret-xf', 0), closeTo(1, 1e-6), reason: '没在追就按 1 倍宽画');
    expect(_hitCursor(tester), SystemMouseCursors.text);
    await unmountPage(tester);
  });

  testWidgets('光标追赶：落点 18/61/104/147、途中拉宽封顶 6、回收会越过', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await tester.tapAt(ilStageCenter(tester));
    await _pump(tester, 32);

    final landed = <double>[];
    var maxStretch = 1.0;
    for (final ch in ['1', '2', '3', '4']) {
      await ilType(tester, ch);
      for (var f = 0; f < 25; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        maxStretch = math.max(maxStretch, _xf(tester, 'caret-xf', 0));
      }
      landed.add(_caretX(tester));
    }
    for (var i = 0; i < 4; i++) {
      expect(landed[i], closeTo(18.0 + 43.0 * i, 0.06), reason: '第 ${i + 1} 格的光标落点');
    }
    expect(maxStretch, greaterThan(5), reason: '甩到 5 倍宽才看得出"追"这件事');
    expect(maxStretch, lessThanOrEqualTo(6 + 1e-9), reason: 'scaleX 有 min(5,…) 封顶');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    var lowest = _caretX(tester);
    for (var f = 0; f < 45; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      lowest = math.min(lowest, _caretX(tester));
    }
    expect(lowest, lessThan(15), reason: '从 146 收回 18：实测最低 5.55，越过落点才叫欠阻尼');
    expect(_caretX(tester), closeTo(104, 0.06));
    await unmountPage(tester);
  });

  testWidgets('退格只回删一位，非数字键一概不吃', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await _focusAndType(tester, '129');
    debugPrint('DBG keys=' + [0,1,2,3].map((i)=>find.byKey(ValueKey('digit-$i')).evaluate().isNotEmpty?'Y':'.').join());
    expect(find.byKey(const ValueKey('digit-2')), findsOneWidget);
    expect(_caretX(tester), closeTo(104, 0.06));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await _pump(tester, 48);
    expect(find.byKey(const ValueKey('digit-2')), findsOneWidget, reason: 'a 不占位');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await _pump(tester, 480);
    expect(find.byKey(const ValueKey('digit-2')), findsNothing);
    expect(find.byKey(const ValueKey('digit-1')), findsOneWidget);
    await unmountPage(tester);
  });

  testWidgets('逐字入场只给换了字符的那格：300ms 后那层整个消失', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await tester.tapAt(ilStageCenter(tester));
    await _pump(tester, 32);
    await ilType(tester, '1');
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('in-0')), findsOneWidget, reason: '入场期多一层 Opacity');
    // 首帧已经吃到 p=16/300：(.22,1,.36,1) 一开头就冲掉两成，所以读数在 .86 之上
    expect(_xf(tester, 'in-0-xf', 0), inInclusiveRange(0.86, 0.95));
    expect(_xf(tester, 'in-0-xf', 13), inInclusiveRange(0, 8.55), reason: '45% 行高往下探');
    expect(
      find.descendant(of: find.byKey(const ValueKey('in-0')), matching: find.byType(ImageFiltered)),
      findsOneWidget,
      reason: 'blur(3px) 起步',
    );
    final startA = tester.widget<Opacity>(find.byKey(const ValueKey('in-0'))).opacity;
    expect(startA, lessThan(1));

    await _pump(tester, 320);
    expect(find.byKey(const ValueKey('in-0')), findsNothing, reason: '钉住终值后这层不再挂');

    await ilType(tester, '2');
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('in-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('in-0')), findsNothing, reason: '第一格字符没换，不许重播');
    await _pump(tester, 400);
    expect(find.byKey(const ValueKey('in-1')), findsNothing);
    await unmountPage(tester);
  });

  testWidgets('填满先进 check：420ms 才出结论，期间呼吸波压到 0.93', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await _focusAndType(tester, '1234');

    var minScale = 1.0;
    var pressed = 0;
    for (var f = 0; f < 26; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        final s = _cellScale(tester, i);
        expect(s, greaterThanOrEqualTo(0.93 - 1e-9), reason: '波谷就是 .93，不许越过去');
        minScale = math.min(minScale, s);
        if (s < 0.99) pressed++;
      }
      if (f == 20) {
        expect(_pill, findsNothing, reason: '420ms 之前不该有胶囊');
        expect(_slotA(tester, 0), 1);
        expect(_cellX(tester, 0), closeTo(0, 1e-9), reason: 'check 期格子不许先挪');
      }
    }
    expect(minScale, lessThan(0.95), reason: '一格都没被压说明波没扫');
    expect(pressed, greaterThan(4));

    // 结论拍之后还要走完 `ss(.3,1,k)` 那半段才画得出胶囊：实测 +496 才露头
    await _pump(tester, 96);
    expect(_pill, findsOneWidget);
    expect(_pillW(tester), inInclusiveRange(1, 145));
    await unmountPage(tester);
  });

  testWidgets('Accept 融合弹簧：约 52 帧到位、峰值 146、终点钉死 128/64.5/22', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await _fillToVerdict(tester);

    var peakW = 0.0;
    var minY = 1.0;
    var frames = 0;
    debugPrint('DBG enter pill=${_pillW(tester)} cx0=${_cellX(tester,0)}');
    while (_pillW(tester) < 127.999 && frames < 120) {
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      debugPrint('DBG f$frames pill=${_pillW(tester)} cx0=${_cellX(tester,0)} sy=${_pillScaleY(tester)}');
      peakW = math.max(peakW, _pillW(tester));
      minY = math.min(minY, _pillScaleY(tester));
    }
    expect(frames, inInclusiveRange(44, 60), reason: 'k=.075 那条离散弹簧在 60fps 下约 52 帧');
    expect(peakW, greaterThan(145), reason: '未截断的 m-1 让胶囊先冲过头（实测 146.20）');
    expect(minY, lessThan(0.92), reason: '同一时刻 scaleY 反过来压到 .9131');
    expect(_pillW(tester), 128.0);
    expect(_pillScaleY(tester), 1.0);
    for (var i = 0; i < 4; i++) {
      expect(_cellX(tester, i), closeTo(64.5, 1e-9), reason: '四格融成一颗：共同左边距 64.5');
    }
    expect(_radius(tester), 22);
    expect(_slotA(tester, 0), 0, reason: '数字层整层淡掉');
    expect(_okA(tester), 1);
    expect(_caretA(tester), 0, reason: 'data-on 要求融合进度还没起步');
    expect(_hitCursor(tester), SystemMouseCursors.click, reason: '已验证态的光标变了');
    await unmountPage(tester);
  });

  testWidgets('胶囊落点：宽 128 时左边缘在 (165-128)/2', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await _fillToVerdict(tester);
    await _pump(tester, 700);
    final c = ilStageCenter(tester);
    final rowLeft = c.dx - 82.5;
    final rowTop = c.dy - 22;
    expect(tester.getTopLeft(_pill).dx - rowLeft + _pillW(tester) / 2, closeTo(82.5, 0.02));
    expect(tester.getTopLeft(_pill).dy, closeTo(rowTop, 0.02));
    await unmountPage(tester);
  });

  testWidgets('已验证态点一下：融合倒回 0、四格归位', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    await _fillToVerdict(tester);
    await _pump(tester, 700);
    expect(_pillW(tester), 128);

    await tester.tapAt(ilStageCenter(tester));
    expect(_caretA(tester), greaterThan(0), reason: '回收即把光标叫回来');
    await _pump(tester, 900);
    expect(_pill, findsNothing, reason: 'k 退到 .3 以下就不画胶囊了');
    for (var i = 0; i < 4; i++) {
      expect(_cellX(tester, i), closeTo(43.0 * i, 1e-9));
      expect(_slotA(tester, i), 1);
    }
    expect(_radius(tester), 12);
    expect(_okA(tester), 0);
    expect(_hitCursor(tester), SystemMouseCursors.text);
    expect(find.byKey(const ValueKey('digit-0')), findsNothing, reason: '点一下是重来不是编辑');
    await unmountPage(tester);
  });

  testWidgets('Reject 抖动：封顶 5px、跨零点、620ms 精确归位', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode(reject: true));
    await _fillToReject(tester);

    var maxAmp = 0.0;
    var crosses = false;
    var prevSign = 0.0;
    for (var f = 0; f < 34; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final x = _cellX(tester, 0);
      maxAmp = math.max(maxAmp, x.abs());
      final sign = x.sign;
      if (prevSign != 0 && sign != 0 && sign != prevSign) crosses = true;
      if (sign != 0) prevSign = sign;
    }
    expect(maxAmp, inInclusiveRange(1.5, 5.0), reason: 'τ=190ms 的衰减正弦，振幅 5*exp(-t/190)');
    expect(crosses, isTrue, reason: '10Hz 的抖，只朝一个方向偏就不叫抖');

    await _pump(tester, 112);
    for (var i = 0; i < 4; i++) {
      expect(_cellX(tester, i), closeTo(43.0 * i, 1e-6), reason: '过了 620ms 位移必须干净归零');
    }
    await unmountPage(tester);
  });

  testWidgets('Reject 掉落：右→左依次晚 45ms、走满 8px、只掉不淡', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode(reject: true));
    await _focusAndType(tester, '4678');

    final start = <int, int>{};
    final peak = <int, double>{};
    for (var f = 0; f < 70; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        final d = _dropY(tester, i);
        if (d > 0.001) {
          start.putIfAbsent(i, () => f);
          peak[i] = math.max(peak[i] ?? 0, d);
          // 这就是 fill:both 那一手：数字层只有位移，透明度一路是 1
          expect(_slotA(tester, i), 1);
          expect(find.byKey(ValueKey('in-$i')), findsNothing);
        }
      }
    }
    expect(start.keys.toList()..sort(), [3, 2, 1, 0], reason: '最右那格先掉');
    for (final i in [2, 1, 0]) {
      final gap = (start[i]! - start[i + 1]!) * 16;
      expect(gap, inInclusiveRange(32, 64), reason: '45ms 的错开落在 16ms 帧网格上');
    }
    for (var i = 0; i < 4; i++) {
      expect(peak[i], closeTo(8.0, 1e-9), reason: '掉 8px 就停，不加速下坠');
    }
    await unmountPage(tester);
  });

  testWidgets('Reject 变红 160ms、960ms 整串清空回 type', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode(reject: true));
    await _fillToReject(tester);

    var ms = 0;
    while (ms < 400 && _digitColor(tester, 0).r < 0.89) {
      await tester.pump(const Duration(milliseconds: 16));
      ms += 16;
    }
    _expectColor(_digitColor(tester, 0), const Color(0xFFE5484D));
    expect(ms, inInclusiveRange(128, 192), reason: 'transition:color .16s');

    await _pump(tester, 1008);
    expect(find.byKey(const ValueKey('digit-0')), findsNothing, reason: '960ms 一到整串清空');
    expect(_slotA(tester, 0), 1);
    await _pump(tester, 64);
    expect(_caretA(tester), greaterThan(0), reason: '回到 type 态光标重新呼吸');

    var lowest = _caretX(tester);
    for (var f = 0; f < 45; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      lowest = math.min(lowest, _caretX(tester));
    }
    expect(lowest, lessThan(15), reason: '从 146 追回 18 必然过冲');
    expect(_caretX(tester), closeTo(18, 0.06));

    await ilType(tester, '5');
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('digit-0')), findsOneWidget);
    _expectColor(_digitColor(tester, 0), IlColor.ink);
    await unmountPage(tester);
  });

  testWidgets('goo 是硬阈值那层：区域比 165×44 外扩 24，滤镜两连', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode());
    final goo = tester.widget<Positioned>(find.byKey(const ValueKey('goo')));
    expect(goo.left, -24);
    expect(goo.width, 213);
    expect(goo.height, 92);
    final gooBox = find.byKey(const ValueKey('goo'));
    expect(
      find.descendant(of: gooBox, matching: find.byType(ImageFiltered)),
      findsOneWidget,
      reason: 'blur σ=3',
    );
    expect(
      find.descendant(of: gooBox, matching: find.byType(ColorFiltered)),
      findsOneWidget,
      reason: 'alpha 走 24a-12 的硬阈值',
    );
    final filt = tester.widget<ImageFiltered>(
      find.descendant(of: gooBox, matching: find.byType(ImageFiltered)),
    );
    expect(filt.imageFilter.toString(), contains('BlurImageFilter'));
    await unmountPage(tester);
  });

  testWidgets('逐帧扫 4000ms：判错那条长链一路有帧在动、收尾静止', (tester) async {
    await mountIlCase(tester, const Case09OneTimeCode(reject: true));
    await _focusAndType(tester, '4678');
    final snaps = <String>[];
    for (var f = 0; f < 250; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      final dg = find.byKey(const ValueKey('digit-0')).evaluate().isEmpty
          ? 'none'
          : _digitColor(tester, 0).a.toStringAsFixed(4);
      snaps.add('${_cellX(tester, 0).toStringAsFixed(4)}|${_dropY(tester, 0).toStringAsFixed(4)}'
          '|${_caretA(tester).toStringAsFixed(4)}|${_caretX(tester).toStringAsFixed(4)}|$dg');
    }
    expect(tester.takeException(), isNull);
    expect(snaps.toSet().length, greaterThan(80), reason: '一条都不变说明钟停半路上了');

    // 落回 type 之后几何必须钉住（光标呼吸是原稿的常驻动画，不算几何变化）
    final geo = '${_cellX(tester, 0)}|${_radius(tester)}|${_slotA(tester, 0)}';
    for (var f = 0; f < 10; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect('${_cellX(tester, 0)}|${_radius(tester)}|${_slotA(tester, 0)}', geo);
    }
    await unmountPage(tester);
  });
}
