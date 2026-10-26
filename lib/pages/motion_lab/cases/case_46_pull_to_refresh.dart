import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 46. Pull to refresh — 下拉整页（带阻尼），顶部那枚圆弧随距离长出来
///
/// 同一段手机录屏，逐帧量出来的一条时间线（30fps，误差 ±33ms）：
/// 指尖在屏正中落下 f24，往下带 f29→f82（≈1770ms，指尖走 187 而内容只走 87 ——
/// **阻尼 0.48**，"下拉有弹性"就是这一条），松手后内容从峰 87 **弹回**挂住位 68
/// f82→f101（630ms，`Curves.easeOut` 拟合 rmse 0.07；smoothOut 太急、标准曲线太钝），
/// 挂在 68 那一档转圈 f101→f119+（参考稿一直到循环切点都没停，这里给 1400ms，
/// 好让终态帧正好落在"挂在半空转圈"那一档），最后 430ms 落回原位让 demo 能重复
/// 触发。脚本总长 2460 = 630+1400+430。
///
/// 关键的一点：**转圈的那枚不跟着内容走**。它的圆心钉在屏顶 y≈48.5（屏宽正中），
/// 内容偏到 87 它仍然只占 y 36..61 那一小块。顶部那条标题条倒是跟内容一起走的。
///
/// 圆弧也不是独立播放的动画：**张角 = 当前偏移 / 挂住位**，最多铺到 290°（留 70° 缺口）。
/// 偏到 13 它刚冒头（f38 只有 10 个蓝像素），偏到 69 就铺满（f70 起 225 个蓝像素不再长），
/// 所以下拉时它长出来、弹回时它自己缩回去，只有挂在半空那一段才**顺时针转**——
/// 量到缺口中心 43 帧转了 320° ≈ 223°/s。
///
/// 触屏：整块屏就是一个 [LabDragZone]，按住期间锁掉页面滚动；指尖点一下等于
/// 一次完整的"下拉→刷新→落回"，桌面鼠标拖/点同一条路。
const _toHoldDur = Duration(milliseconds: 630); // f82→f101 峰 87 弹回挂住位 68
const _spinDur = Duration(milliseconds: 1400); // 挂在半空转圈
const _backDur = Duration(milliseconds: 430); // 落回原位（参考稿是硬切）

/// 脚本总长
final _seqTotal = _toHoldDur + _spinDur + _backDur;

// 各段在脚本时间线上的位置（ms）
const _toHoldEnd = 630.0;
const _spinEnd = 2030.0;
const _seqMs = 2460.0;
const _backMs = 430.0;

/// 挂住位：参考稿 68（屏 548 高的一成二），等比缩进来
const _holdOffset = 68 * labK;

/// 能拉到的最远处：参考稿松手那一帧是 87
const _maxOffset = 87 * labK;

/// 阻尼：指尖走 1，内容走 0.48（参考稿 187→87 量出来的）
const _damp = 0.48;

/// 拉到挂住位的一半就算"要刷新"
const _commitAt = 0.5;

/// 甩动也算 commit（px/s）
const _flingV = 180;

/// 圆弧：满张角 290°（留 70° 缺口）、描边 4，外轮廓 26 屏内像素，全是参考稿原值
const _sweepFull = 290 * math.pi / 180;
const _spinnerStroke = 4 * labK;
const _spinnerR = 11 * labK;
const _spinnerCY = 48.5 * labK;
const _spinnerBox = _spinnerR * 2 + _spinnerStroke;

/// 缺口中心 43 帧转 320° → 每秒 0.619 圈
const _spinRate = 223 / 360;

/// 参考稿那支蓝（取最饱和的几枚像素，落在 #3ABEEE～#45C4F5 之间）
const _spinnerColor = Color(0xFF3EC3F3);

/// 被下拉的是 5 行骨架
const _rowCount = 5;

enum _Phase { none, refresh, settle }

class Case46PullToRefresh extends StatefulWidget {
  const Case46PullToRefresh({super.key});

  @override
  State<Case46PullToRefresh> createState() => _Case46PullToRefreshState();
}

class _Case46PullToRefreshState extends State<Case46PullToRefresh>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _seqTotal)
        // 脚本跑完要把状态交回给手指，否则第二次就拉不动了
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed && _phase != _Phase.none) {
            _from = 0;
            setState(() => _phase = _Phase.none);
          }
        });

  _Phase _phase = _Phase.none;

  /// 跟手阶段的偏移（≥0）；松手后交给脚本，起点记在 [_from]
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

  /// 跟手：位移过一道阻尼，指尖走满也只有 `_damp` 成落到内容上
  double _clamped(double dy) => (dy * _damp).clamp(0.0, _maxOffset);

  void _onUpdate(Offset total, Offset at) {
    if (_phase != _Phase.none) return;
    setState(() => _drag = _clamped(total.dy));
  }

  void _onEnd(Offset total, Offset velocity) {
    if (_phase != _Phase.none) return;
    final d = _clamped(total.dy);
    if (d >= _holdOffset * _commitAt || velocity.dy >= _flingV) {
      _run(_Phase.refresh, _seqTotal, d);
    } else if (d > 0) {
      _run(_Phase.settle, _backDur, d);
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

  /// 当前偏移 + 圆弧已经转过的角度（弧度）
  (double offset, double spin) _resolve() {
    switch (_phase) {
      case _Phase.none:
        return (_drag, 0);
      case _Phase.settle:
        final t = _seg(_c.value * _backMs, 0, _backMs, Curves.easeOutCubic);
        return (_from * (1 - t), 0);
      case _Phase.refresh:
        final ms = _c.value * _seqMs;
        final toHold = _seg(ms, 0, _toHoldEnd, Curves.easeOut);
        final back = _seg(ms, _spinEnd, _seqMs, Curves.easeOutCubic);
        final offset = back > 0
            ? _holdOffset * (1 - back)
            : _from + (_holdOffset - _from) * toHold;
        // 只有挂在半空的那一段在转，落回时角度冻住、缺口随偏移一起缩
        final spinning = (ms - _toHoldEnd).clamp(0.0, _spinDur.inMilliseconds.toDouble());
        return (offset, spinning / 1000 * _spinRate * 2 * math.pi);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final (offset, spin) = _resolve();
          final fill = (offset / _holdOffset).clamp(0.0, 1.0);
          return Stack(
            children: [
              LabPhoneScreen(
                children: [
                  // 标题条 + 5 行是一起被拉下去的那一组；整层往下挪，
                  // 里面的坐标仍然按面板原点算，所以行距不用重算
                  Positioned(
                    left: 0,
                    top: offset,
                    child: SizedBox(
                      width: labScreenW,
                      height: LabSize.stageH,
                      child: Stack(
                        children: [
                          labHeaderBar,
                          for (var i = 0; i < _rowCount; i++)
                            Positioned(
                              left: labPad,
                              top: labRowY(i),
                              child: const LabSkelRow(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  labHomeBar,
                  // 圆弧钉在屏顶，不跟着内容走
                  Positioned(
                    left: (labScreenW - _spinnerBox) / 2,
                    top: _spinnerCY - _spinnerBox / 2,
                    child: CustomPaint(
                      size: Size.square(_spinnerBox),
                      painter: _ArcPainter(
                        sweep: fill * _sweepFull,
                        spin: spin,
                      ),
                    ),
                  ),
                ],
              ),
              // 整块屏都是下拉区
              Positioned(
                left: labScreenX,
                top: 0,
                child: SizedBox(
                  width: labScreenW,
                  height: LabSize.stageH,
                  child: LabDragZone(
                    cursor: SystemMouseCursors.grab,
                    onTap: (at) => _run(_Phase.refresh, _seqTotal, _holdOffset),
                    onUpdate: _onUpdate,
                    onEnd: _onEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 一段圆弧：从 12 点起顺时针铺 [sweep]，整体再转 [spin]
class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.sweep, required this.spin});

  final double sweep;
  final double spin;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0.001) return;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: _spinnerR,
      ),
      -math.pi / 2 + spin,
      math.min(sweep, _sweepFull),
      false,
      Paint()
        ..color = _spinnerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _spinnerStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.sweep != sweep || old.spin != spin;
}
