import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 45. Swipe to dismiss — 横滑整行，露出的灰条铺满后行高塌陷
///
/// 参考稿是一段 4s 一循环的手机录屏（30fps，段界逐帧量出来的，误差 ±33ms）：
/// 手指把行往左带 f33→f72（≈1300ms，等速 3.6px/帧 ≈ 108px/s，纯跟手谈不上曲线），
/// 松手后**行带着余势继续滑出** f72→f81（270ms，每帧走字 6→11→4：中段比跟手快、
/// 收尾摊平，逐段比下来 `Curves.easeInOut` 最贴，`LabEase.standard` 起手太钝），
/// 灰条原地停 f81→f97（530ms）让人看清那个垃圾桶，
/// 然后**行高塌到 0、下面几行一起补位** f97→f113（530ms），
/// 塌完空档到 f119 —— f120 是循环剪辑的硬切，参考稿里没有"把行放回来"的动画，
/// 这里补 300ms 反向展开，好让 demo 能重复触发。
///
/// 塌陷那一段量到过点：行3 顶 224→143，正好一个**行距** 81（= 行高 67 + 间距 14），
/// t≈0.44 已走完 0.70、t=0.75 到 0.90 —— 起步快、收尾平，`Curves.easeOut` 最贴
/// （本文件默认的 smoothOut 在 t=0.125 就到 0.27，实测只有 0.10，看着像"弹"进去）。
/// 补位也按这个行距算：只减行高会把那 14 的间距漏掉，删完第一道缝宽出一截。
///
/// 灰条不是"整行底色"那一档：它是**比行更深的灰**（行 `#EFEFF2`，灰条 `#DDDDE1`），
/// 而且和行同宽同圆角、一直垫在行底下——行往外退，退出来的就是它。
/// 垃圾桶是**白色描边**，钉在**被揭开那一段的中心**：起手时整枚压在行底下，
/// 行退多少它露多少，行完全滑出后正好落在行中央（量到 f81 之后图标中心 ≈ 行中心）。
///
/// 触屏：整行就是一个 [LabDragZone]，按住期间锁掉页面滚动；指尖点一下（没过 slop）
/// 等于按阈值把这一行甩出去，桌面鼠标拖/点同一条路。
const _flyDur = Duration(milliseconds: 270); // f72→f81 行带余势滑出
const _holdDur = Duration(milliseconds: 530); // f81→f97 图标停在行中央
const _collapseDur = Duration(milliseconds: 530); // f97→f113 塌陷 + 补位
const _restDur = Duration(milliseconds: 700); // 空档，让人看清只剩四行
const _backDur = Duration(milliseconds: 300); // 参考稿是硬切，这里反向展开补回
const _settleDur = Duration(milliseconds: 300); // 没过阈值松手的回弹

/// 脚本总长（跟手那一程不算在内）
final _seqTotal = _flyDur + _holdDur + _collapseDur + _restDur + _backDur;

// 各段在脚本时间线上的位置（ms），和上面几段一一对应
const _flyEnd = 270.0;
const _collapseAt = 800.0;
const _collapseEnd = 1330.0;
const _seqMs = 2330.0;
const _backAt = 2030.0;
const _settleMs = 300.0;

/// 过多少算"要删"：参考稿松手时已经推开七成，这里给到四成半，指尖好触发
const _commitAt = 0.45;

/// 甩动也算 commit（px/s）
const _flingV = -260;

/// 垃圾桶：16 viewBox 描边，只画轮廓；白色压在深灰条上
const _trashPaths = <String>[
  'M2.5 4.2h11',
  'M6.4 4.2V2.6h3.2v1.6',
  'M4.2 4.2l.75 9.2h6.1l.75-9.2',
  'M6.8 6.9v4.2',
  'M9.2 6.9v4.2',
];

/// 参考稿图标约占行高三分之一
const _trashSize = labRowH / 3;

/// 被横滑的是第 2 行（参考稿也是第 2 行），一共 5 行
const _targetIndex = 1;
const _rowCount = 5;

enum _Phase { none, dismiss, settle }

class Case45SwipeToDismiss extends StatefulWidget {
  const Case45SwipeToDismiss({super.key});

  @override
  State<Case45SwipeToDismiss> createState() => _Case45SwipeToDismissState();
}

class _Case45SwipeToDismissState extends State<Case45SwipeToDismiss>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _seqTotal)
        // 脚本跑完要把状态交回给手指，否则第二次就拖不动了
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed && _phase != _Phase.none) {
            _from = 0;
            setState(() => _phase = _Phase.none);
          }
        });

  _Phase _phase = _Phase.none;

  /// 跟手阶段的位移（≤0）；松手后交给脚本，起点记在 [_from]
  double _drag = 0;
  double _from = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _run(_Phase phase, Duration dur, double from) {
    _from = from;
    _drag = 0;
    _c.duration = dur;
    setState(() => _phase = phase);
    _c.forward(from: 0);
  }

  void _onUpdate(Offset total, Offset at) {
    if (_phase != _Phase.none) return;
    setState(() => _drag = math.min(0.0, total.dx).clamp(-labRowW, 0.0));
  }

  void _onEnd(Offset total, Offset velocity) {
    if (_phase != _Phase.none) return;
    final d = math.min(0.0, total.dx).clamp(-labRowW, 0.0);
    if (-d >= labRowW * _commitAt || velocity.dx <= _flingV) {
      _run(_Phase.dismiss, _seqTotal, d);
    } else if (d < 0) {
      _run(_Phase.settle, _settleDur, d);
    } else {
      setState(() => _drag = 0);
    }
  }

  /// 脚本各段进度：段外钉死在 0/1
  double _seg(double ms, double a, double b, Curve curve) {
    if (ms <= a) return 0;
    if (ms >= b) return 1;
    return curve.transform((ms - a) / (b - a));
  }

  /// 当前这一行的位移与高度（高 = 0 表示已经塌没）
  (double dx, double h) _resolve() {
    switch (_phase) {
      case _Phase.none:
        return (_drag, labRowH);
      case _Phase.settle:
        final t = _seg(_c.value * _settleMs, 0, _settleMs, LabEase.smoothOut);
        return (_from * (1 - t), labRowH);
      case _Phase.dismiss:
        final ms = _c.value * _seqMs;
        final fly = _seg(ms, 0, _flyEnd, Curves.easeInOut);
        final collapse = _seg(ms, _collapseAt, _collapseEnd, Curves.easeOut);
        final back = _seg(ms, _backAt, _seqMs, Curves.easeOut);
        final slide = _from + (-labRowW - _from) * fly;
        return (
          back > 0 ? -labRowW * (1 - back) : slide,
          back > 0 ? labRowH * back : labRowH * (1 - collapse),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final (dx, h) = _resolve();
          return Stack(
            children: [
              LabPhoneScreen(
                children: [
                  ...labChrome,
                  for (var i = 0; i < _rowCount; i++)
                    Positioned(
                      left: labPad,
                      top: _rowY(i, h),
                      child: i == _targetIndex
                          ? _swipeRow(dx, h)
                          : const LabSkelRow(),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 第 i 行的 y：被删那行塌陷时，它下面所有行一起往上补位
  ///
  /// 补位量按**行距**（行高 + 间距）算：塌陷进度走到 1 时，下面每行正好上移一格。
  double _rowY(int i, double h) => labRowY(i) -
      (i > _targetIndex ? (labRowH + labRowGap) * (1 - h / labRowH) : 0);

  /// 可横滑的那一行：底下垫一枚同宽同圆角的深灰胶囊，行盖在它上面往外退
  Widget _swipeRow(double dx, double h) {
    final revealed = math.min(-dx, labRowW);
    return SizedBox(
      width: labRowW,
      height: h,
      child: LabDragZone(
        cursor: SystemMouseCursors.grab,
        onTap: (at) => _run(_Phase.dismiss, _seqTotal, -labRowW * (_commitAt + 0.12)),
        onUpdate: _onUpdate,
        onEnd: _onEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: labBarBg,
                  borderRadius: BorderRadius.circular(labRadius),
                ),
              ),
            ),
            // 图标跟着"被揭开那段的中心"走：起手时整枚压在行底下，
            // 行退多少它就露多少，行完全滑出时正好落在行中央
            Positioned(
              left: labRowW - revealed / 2 - _trashSize / 2,
              top: (labRowH - _trashSize) / 2,
              child: LabIcon(
                paths: _trashPaths,
                size: _trashSize,
                strokeWidth: 1.2,
                color: LabColor.card,
              ),
            ),
            Positioned(
              left: dx,
              top: 0,
              child: const LabSkelRow(),
            ),
          ],
        ),
      ),
    );
  }
}
