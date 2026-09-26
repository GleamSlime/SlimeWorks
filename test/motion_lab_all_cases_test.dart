import 'package:flutter/material.dart' show MouseRegion, Offset, SystemMouseCursors;
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/pages/motion_lab/cases/motion_lab_cases.dart';

import 'helpers/lab_golden.dart';

// 43 格逐格出图：静止帧 + 途中帧 + 终态帧。
//
// 一帧一个 test：出过图之后同一 test 里的点击就不再接到（见 lab_golden 的说明）。
// 只看静止帧证明不了动效存在，途中那帧才是时长和曲线接没接上的证据。
//
// 触发方式按各格参考稿写死在 [_acts] 里：按钮点按钮、悬停的压中心、
// 自动循环的什么都不做只推进时间。

enum _Act { animate, toggleModal, togglePanel, play, clickable, hoverClickable, auto }

const Map<int, _Act> _acts = {
  1: _Act.animate,
  2: _Act.animate,
  3: _Act.animate,
  4: _Act.animate,
  5: _Act.animate,
  6: _Act.animate,
  7: _Act.toggleModal,
  8: _Act.togglePanel,
  9: _Act.clickable,
  10: _Act.clickable,
  11: _Act.animate,
  12: _Act.animate,
  13: _Act.hoverClickable,
  14: _Act.hoverClickable,
  15: _Act.animate,
  16: _Act.clickable,
  17: _Act.animate,
  18: _Act.animate,
  19: _Act.clickable,
  20: _Act.hoverClickable,
  21: _Act.play,
  22: _Act.play,
  23: _Act.hoverClickable,
  24: _Act.hoverClickable,
  25: _Act.clickable,
  26: _Act.clickable,
  27: _Act.animate,
  28: _Act.clickable,
  29: _Act.clickable,
  30: _Act.hoverClickable,
  31: _Act.clickable,
  32: _Act.animate,
  33: _Act.animate,
  34: _Act.clickable,
  35: _Act.auto,
  36: _Act.clickable,
  37: _Act.animate,
  38: _Act.animate,
  39: _Act.animate,
  40: _Act.auto,
  41: _Act.animate,
  42: _Act.play,
  43: _Act.auto,
};

/// 舞台在 320×284 的窗口里居中（舞台本身 296×260）
const _stageCenter = Offset(160, 142);

/// 少数格子的默认触发点已经停在选中项上，点它等于没点，指定要点谁
const _labelOverride = {19: 'Ask'};

/// 慢启动的格子：150ms 还在延迟里，拍到的是静止帧，等于没验
///
/// 6 号反过来——纸屑刚炸开还挤成一团，推晚一点才拍得开行迹
const _midOverride = {4: 400, 6: 400, 12: 600, 37: 2500, 38: 600};

String _pad(int seq) => seq.toString().padLeft(2, '0');

/// 没有文字可寻的格子，触发点统一按"手型光标落在谁身上"找：
/// 参考稿里可点/可拖的元素一律 cursor: pointer / grab，比猜坐标可靠
final _clickable = find.byWidgetPredicate(
  (w) =>
      w is MouseRegion &&
      (w.cursor == SystemMouseCursors.click ||
          w.cursor == SystemMouseCursors.grab),
);

Future<void> _trigger(WidgetTester tester, _Act act, int seq) async {
  final label = _labelOverride[seq];
  if (label != null) {
    await tester.tap(find.text(label));
    return;
  }
  switch (act) {
    case _Act.animate:
      await tester.tap(find.text('Animate'));
    case _Act.toggleModal:
      await tester.tap(find.text('Toggle modal'));
    case _Act.togglePanel:
      await tester.tap(find.text('Toggle panel'));
    case _Act.play:
      await tester.tap(find.text('Play'));
    case _Act.clickable:
      if (_clickable.evaluate().isNotEmpty) {
        await tester.tap(_clickable.first);
      } else {
        await tester.tapAt(_stageCenter);
      }
    case _Act.hoverClickable:
      // 手势对象不丢：指针得一直停在那儿，出图时才是悬停态
      await hoverAt(
        tester,
        _clickable.evaluate().isNotEmpty
            ? tester.getCenter(_clickable.first)
            : _stageCenter,
      );
    case _Act.auto:
      break;
  }
}

Future<void> _shoot(
  WidgetTester tester,
  LabCase c, {
  required String frame,
  int? ms,
}) async {
  final act = _acts[c.seq]!;
  await shootLabCase(
    tester,
    name: 'c${_pad(c.seq)}_$frame',
    child: c.build(),
    // 自动循环的格子没有可点的入口，只推进时间就能拍到不同帧
    act: act == _Act.auto ? (_) async {} : (t) => _trigger(t, act, c.seq),
    thenMs: ms,
  );
}

void main() {
  for (final c in kLabCases) {
    final act = _acts[c.seq]!;
    // 悬停的走位慢半拍，150ms 拍过去还是原地
    final midMs = _midOverride[c.seq] ?? (act == _Act.hoverClickable ? 250 : 150);

    testWidgets('${c.seq}. ${c.title} 静止帧', tags: 'golden', (tester) async {
      await shootLabCase(tester, name: 'c${_pad(c.seq)}_idle', child: c.build());
    });

    testWidgets('${c.seq}. ${c.title} 途中帧', tags: 'golden', (tester) async {
      await _shoot(tester, c, frame: 'mid', ms: midMs);
    });

    testWidgets('${c.seq}. ${c.title} 终态帧', tags: 'golden', (tester) async {
      await _shoot(tester, c, frame: 'end', ms: 2000);
    });
  }
}