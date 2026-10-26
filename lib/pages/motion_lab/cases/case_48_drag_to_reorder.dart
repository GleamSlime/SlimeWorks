import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 48. Drag to reorder — 按住一行拎起来浮在列表上拖，别的行被挤开一格
///
/// 同一段手机录屏，4 行、每行右侧一个三线手柄。行的版式和 45/46 号一模一样
/// （首行顶 61、行高 67、间距 14），所以直接复用 [labRowY]。
///
/// 逐帧量到的一手数据：
/// - f22 按住第 3 行的手柄：行**在原地**变白（底色 243 → f28 的 253，200ms 走完），
///   同时放大 1.05 倍（静止行占 x 16..234，抬起行占 x 10..238，中心不变），
///   四周再糊一圈软阴影（边上压到 246，约 10px 散开）。
/// - **原地那一格是空的**：f24 起灰行只剩 60/141/304 三条，223 那一档让出来了。
///   不是"原地留占位 + 一份浮起来的副本"，副本走了，坑留着。
/// - f34→f78 手指匀速上带 137px（3.1px/帧），这一段是手拖的，不是缓动。
/// - **让位**：抬起行的**顶边**一盖过邻行的**中线**，邻行就整行往下滑一格（81 = 行高
///   67 + 间距 14），400ms `Curves.easeOut`。量过两次：f48 行2 顶 142→223，半程
///   （t=0.5）走 61px，实测 61；f73 行1 顶 61→142，t=0.58 走 66，实测 67 —— 两条
///   都对得上 easeOut，所以判定阈值取"顶边过邻行中线"，不是"中心过中心"。
/// - f80 松手（指尖停在 119，行顶 85）→ 落到最近的一格，白再退回灰（270ms）。
///   骨架行彼此长得一样，所以换完序看不出差别，途中那一帧才是这条案例的证据。
///
/// 触屏：整块屏是一个 [LabDragZone]，按在哪一行就拎哪一行；按住期间锁掉页面滚动。
/// 指尖点一下（没有位移）= 拎起来往上挪一格再放下。
const _liftDur = Duration(milliseconds: 200); // f22→f28 原地变白 + 放大
const _travelDur = Duration(milliseconds: 300); // 点发时替代手指那一段匀速
const _putDur = Duration(milliseconds: 270); // 落位后白退回灰
const _giveDur = Duration(milliseconds: 400); // 邻行让开一格

/// 抬起行的放大倍数：228 / 218
const _liftScale = 1.046;

/// 抬起行的软阴影：参考稿在行四周散开约 10 屏像素、边上只压暗 3%（253→246）
const _shadowBlur = 10 * labK;
const _shadowAlpha = 0.14;

const _rowCount = 4;
const _pitch = labRowH + labRowGap;

const _travelMs = 300.0;
const _putMs = 270.0;
const _settleMs = 570.0;

enum _Phase { none, lift, settle }

class Case48DragToReorder extends StatefulWidget {
  const Case48DragToReorder({super.key});

  @override
  State<Case48DragToReorder> createState() => _Case48DragToReorderState();
}

class _Case48DragToReorderState extends State<Case48DragToReorder>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// 每一行各自的让位进度：0 = 原位，1 = 已经挪开一格
  late final List<AnimationController> _give =
      List.generate(_rowCount, (_) => AnimationController(vsync: this, duration: _giveDur));

  _Phase _phase = _Phase.none;

  /// 被拎起来的那一格
  int _slot = 0;

  /// 跟手位移（舞台像素，相对该格原位）
  double _dy = 0;

  /// 吸附段的起点/终点，以及松手那一刻已经拎起到多少
  double _fromDy = 0;
  double _toDy = 0;
  double _liftAt = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      // 吸附段里抬起行是自己在飞的，让位得跟着它当前的位置判，不能只认手指
      if (_phase == _Phase.settle) _syncGive(labRowY(_slot) + _dyNow);
      setState(() {});
    });
    for (final g in _give) {
      g.addListener(() => setState(() {}));
    }
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed || _phase != _Phase.settle) return;
      // 落位：抬起行正好填上那个坑，剩下的行此时已经铺满，归零只是换个说法
      setState(() {
        _phase = _Phase.none;
        _dy = 0;
        for (final g in _give) {
          g.value = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    for (final g in _give) {
      g.dispose();
    }
    super.dispose();
  }

  /// 按住的那一点落在哪一行；落在行间距上就不算
  int _slotAt(Offset at) {
    for (var i = 0; i < _rowCount; i++) {
      if (at.dy >= labRowY(i) && at.dy <= labRowY(i) + labRowH) return i;
    }
    return -1;
  }

  double get _minDy => labRowY(0) - labRowY(_slot);
  double get _maxDy => labRowY(_rowCount - 1) - labRowY(_slot);

  void _onStart(Offset at) {
    if (_phase != _Phase.none) return;
    final i = _slotAt(at);
    if (i < 0) return;
    _slot = i;
    _dy = 0;
    _phase = _Phase.lift;
    _c.duration = _liftDur;
    _c.forward(from: 0);
    setState(() {});
  }

  void _onUpdate(Offset total, Offset at) {
    if (_phase == _Phase.none) return;
    setState(() {
      _dy = total.dy.clamp(_minDy, _maxDy);
      _syncGive(labRowY(_slot) + _dy);
    });
  }

  /// 让位判定：抬起行的顶边盖过上方邻行的中线、或底边盖过下方邻行的中线，那行就挪一格
  ///
  /// 两侧各差半个行高才触发（量过：行顶要走 47.5 屏像素，即一格的 71%，邻行才动）。
  void _syncGive(double top) {
    for (var i = 0; i < _rowCount; i++) {
      if (i == _slot) continue;
      final c = labRowY(i) + labRowH / 2;
      final crossed = i < _slot ? top <= c : top + labRowH >= c;
      final g = _give[i];
      if (crossed && g.value < 1 && g.status != AnimationStatus.forward) g.forward();
      if (!crossed && g.value > 0 && g.status != AnimationStatus.reverse) g.reverse();
    }
  }

  /// 让开的那一格：上方往下、下方往上，各一格
  double _giveY(int i) => (i < _slot ? 1 : -1) *
      _pitch *
      Curves.easeOut.transform(_give[i].value);

  void _onEnd(Offset total, Offset velocity) {
    if (_phase == _Phase.none) return;
    // 没有位移 = 指尖点一下：替他往上挪一格
    final step = total.dy.abs() < labRowGap
        ? (_slot == 0 ? _pitch : -_pitch)
        : ((_slot * _pitch + _dy) / _pitch).round() * _pitch - _slot * _pitch;
    _fromDy = _dy;
    // step 已经是相对该格原位的绝对落点，不能再叠一次跟手位移
    _toDy = step.clamp(_minDy, _maxDy);
    _liftAt = _phase == _Phase.lift ? _c.value : 1;
    _phase = _Phase.settle;
    _c.duration = _travelDur + _putDur;
    _c.forward(from: 0);
    setState(() {});
  }

  /// 吸附段：前半程挪到目标格（顺手把没拎够的补满），后半程白退回灰
  double get _dyNow {
    if (_phase != _Phase.settle) return _dy;
    final ms = _c.value * _settleMs;
    final p = LabEase.smoothOut.transform((ms / _travelMs).clamp(0.0, 1.0));
    return _fromDy + (_toDy - _fromDy) * p;
  }

  double get _liftNow {
    return switch (_phase) {
      _Phase.none => 0.0,
      _Phase.lift => _c.value,
      _Phase.settle => _settleLift(_c.value * _settleMs),
    };
  }

  double _settleLift(double ms) {
    if (ms <= _travelMs) return _liftAt + (1 - _liftAt) * (ms / _travelMs);
    return (1 - (ms - _travelMs) / _putMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final lift = _liftNow;
    return LabStage(
      child: Stack(
        children: [
          LabPhoneScreen(
            children: [
              labHeaderBar,
              for (var i = 0; i < _rowCount; i++)
                if (i != _slot || _phase == _Phase.none)
                  Positioned(
                    left: labPad,
                    top: labRowY(i) + _giveY(i),
                    child: const LabSkelRow(handle: true),
                  ),
              labHomeBar,
              if (_phase != _Phase.none)
                Positioned(
                  left: labPad,
                  top: labRowY(_slot) + _dyNow,
                  child: Transform.scale(
                    scale: 1 + (_liftScale - 1) * lift,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(labRadius),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF000000).withValues(alpha: _shadowAlpha * lift),
                            blurRadius: _shadowBlur,
                            offset: const Offset(0, 3) * labK,
                          ),
                        ],
                      ),
                      child: LabSkelRow(
                        color: Color.lerp(labPillBg, labScreenBg, lift) ?? labScreenBg,
                        handle: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // 整块屏都是拖拽区：按在哪一行就拎哪一行
          Positioned(
            left: labScreenX,
            top: 0,
            child: SizedBox(
              width: labScreenW,
              height: LabSize.stageH,
              child: LabDragZone(
                cursor: SystemMouseCursors.grab,
                onStart: _onStart,
                onUpdate: _onUpdate,
                onEnd: _onEnd,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
