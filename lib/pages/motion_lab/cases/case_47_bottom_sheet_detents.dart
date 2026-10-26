import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 47. Bottom sheet detents — 面板挂在三档高度上，松手吸附到最近的一档
///
/// 同一段手机录屏。三档的**面板顶边**逐帧量到（屏内坐标，屏高 548）：
/// 低档 375、中档 235、高档 29。
/// 面板里的东西全是参考稿原值：手柄 53×7 在顶下 12，标题条 123×12 在 +53，
/// 副标题 75×9 在 +74，三块 211×87 的内容块从 +97 起、块间距 16、圆角 22。
///
/// 换档不是匀速：往上走之前先**往下压一口**（f11 388 → f13 449，60px 蓄势），
/// 再花 470ms 抬到位；往下走 570ms 且落点带过冲（f94 381 → f96 350 → f101 387
/// 在目标上下晃了一圈）。参考稿那是一根弹簧在解算，这里只复现它最显眼的那一下：
/// 上行拆成"蓄势 + `LabEase.smoothOut`"两段，下行用 `LabEase.pop` 顶出过冲，
/// 第二圈回弹不追。
///
/// 遮罩跟着面板高度线性给：低档时背景清清楚楚，高档时压到 `#000000` 17%
/// （量到面板上方那条白底变成 `#D1D1D1`）。
///
/// 触屏：面板整体是一个 [LabDragZone]，按住期间锁掉页面滚动；指尖点一下循环到下一档，
/// 桌面鼠标拖/点同一条路。
const _windupDur = Duration(milliseconds: 130); // f11→f13 抬手前那口下压
const _riseDur = Duration(milliseconds: 470); // f13→f29 抬到中档
const _fallDur = Duration(milliseconds: 570); // f77→f94 落回低档

/// 蓄势的幅度：参考稿 60px
const _windupPx = 60 * labK;

/// 三档的面板顶边（屏内原值 × 系数），下标即档位：0 低 / 1 中 / 2 高
const _detents = <double>[375 * labK, 235 * labK, 29 * labK];

/// 甩动过档的速度阈值（px/s）
const _flingV = 240;

/// 遮罩压到最深时的黑度
const _scrimMax = 0.17;

/// 面板内版式（屏内原值 × 系数）
const _sheetPadX = 19 * labK;
const _sheetRadius = 22 * labK;
const _handleW = 53 * labK;
const _handleH = 7 * labK;
const _handleTop = 12 * labK;
const _titleW = 123 * labK;
const _titleH = 12 * labK;
const _titleTop = 53 * labK;
const _subW = 75 * labK;
const _subH = 9 * labK;
const _subTop = 74 * labK;
const _blockTop = 97 * labK;
const _blockW = 211 * labK;
const _blockH = 87 * labK;
const _blockGap = 16 * labK;

/// 背景页：一张 224×225 的大图块 + 三行骨架
const _heroX = 8 * labK;
const _heroY = 30 * labK;
const _heroW = 224 * labK;
const _heroH = 225 * labK;
const _heroR = 22 * labK;
const _bgRowTop = 275 * labK;

const _blockCount = 3;
const _bgRowCount = 3;

class Case47BottomSheetDetents extends StatefulWidget {
  const Case47BottomSheetDetents({super.key});

  @override
  State<Case47BottomSheetDetents> createState() => _Case47BottomSheetDetentsState();
}

class _Case47BottomSheetDetentsState extends State<Case47BottomSheetDetents>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  /// 当前停在第几档
  int _detent = 0;

  /// 跟手时的面板顶边；吸附期间冻结在 [_to] 上
  double _drag = _detents.first;

  /// 本次吸附的起点/终点，以及要不要先蓄一口
  double _from = _detents.first;
  double _to = _detents.first;
  bool _rising = false;
  bool _snapping = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      // 吸附收尾：跟手的基准回到这一档，面板重新可拖
      setState(() {
        _snapping = false;
        _drag = _to;
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _top => _snapping ? _resolve(_c.value) : _drag;

  void _snap(int detent) {
    _from = _drag;
    _to = _detents[detent];
    _detent = detent;
    _rising = _to < _from;
    _c.duration = _rising ? _windupDur + _riseDur : _fallDur;
    _snapping = true;
    _c.forward(from: 0);
    setState(() {});
  }

  double _resolve(double t) {
    if (!_rising) return _mix(_from, _to, LabEase.pop.transform(t));
    final ms = t * (_windupDur + _riseDur).inMilliseconds;
    if (ms <= _windupDur.inMilliseconds) {
      // 抬手前先往下压一口：方向永远和即将的去向相反
      return _from + _windupPx * Curves.easeIn.transform(ms / _windupDur.inMilliseconds);
    }
    final p = LabEase.smoothOut.transform(
      (ms - _windupDur.inMilliseconds) / _riseDur.inMilliseconds,
    );
    return _mix(_from + _windupPx, _to, p);
  }

  double _mix(double a, double b, double t) => a + (b - a) * t;

  void _onUpdate(Offset total, Offset at) {
    if (_snapping) return;
    setState(
      () => _drag = (_detents[_detent] + total.dy).clamp(_detents.last, _detents.first),
    );
  }

  void _onEnd(Offset total, Offset velocity) {
    if (_snapping) return;
    final d = _drag;
    var best = 0;
    for (var i = 1; i < _detents.length; i++) {
      if ((d - _detents[i]).abs() < (d - _detents[best]).abs()) best = i;
    }
    // 甩动直接往那个方向多过一档，松得太干净就只认最近的一档
    if (velocity.dy < -_flingV) best = math.min(best + 1, _detents.length - 1);
    if (velocity.dy > _flingV) best = math.max(best - 1, 0);
    _snap(best);
  }

  /// 点一下循环到下一档（指尖没有"拖到哪算哪"的余地，给它一条确定的路）
  void _cycle() => _snap((_detent + 1) % _detents.length);

  @override
  Widget build(BuildContext context) {
    final top = _top;
    final height = LabSize.stageH - top;
    // 越高的面板压得越深：低档 0、高档 _scrimMax
    final p = ((_detents.first - top) / (_detents.first - _detents.last)).clamp(0.0, 1.0);
    final scrim = p * _scrimMax;
    return LabStage(
      child: Stack(
        children: [
          LabPhoneScreen(
            children: [
              Positioned(
                left: _heroX,
                top: _heroY,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: labPillBg,
                    borderRadius: BorderRadius.circular(_heroR),
                  ),
                  child: const SizedBox(width: _heroW, height: _heroH),
                ),
              ),
              for (var i = 0; i < _bgRowCount; i++)
                Positioned(
                  left: labPad,
                  top: _bgRowTop + i * (labRowH + labRowGap),
                  child: const LabSkelRow(),
                ),
              labHomeBar,
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0xFF000000).withValues(alpha: scrim),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: top,
                child: SizedBox(
                  width: labScreenW,
                  height: height,
                  child: LabDragZone(
                    cursor: SystemMouseCursors.grab,
                    onTap: (at) => _cycle(),
                    onUpdate: _onUpdate,
                    onEnd: _onEnd,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: LabColor.card,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3)),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: (labScreenW - _handleW) / 2,
                            top: _handleTop,
                            child: LabBar(width: _handleW, height: _handleH, color: labBarBg),
                          ),
                          Positioned(
                            left: (labScreenW - _titleW) / 2,
                            top: _titleTop,
                            child: LabBar(width: _titleW, height: _titleH, color: labPillBg),
                          ),
                          Positioned(
                            left: (labScreenW - _subW) / 2,
                            top: _subTop,
                            child: LabBar(width: _subW, height: _subH, color: labPillBg),
                          ),
                          for (var i = 0; i < _blockCount; i++)
                            Positioned(
                              left: _sheetPadX,
                              top: _blockTop + i * (_blockH + _blockGap),
                              child: LabBar(width: _blockW, height: _blockH, color: labPillBg),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
