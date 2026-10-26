import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 49. Long-press peek — 按住格子，它自己长成预览卡，背景糊掉压暗
///
/// 同一段手机录屏，背景是 2×3 的方格墙：格子 103×103、间距 12.5、左边距 16、
/// 首行顶 54（屏内像素，×`labK` 落到舞台上）。
///
/// 逐帧量到的一手数据（30fps，f0 = 循环切点）：
/// - f15→f20 被按的那格底色 239 → 226（170ms，**变深不是变白**）。之后按住不动，
///   什么都不发生，直到 f59。
/// - f59 起三件事**同时**起步，这才是"格子长成新元素"而不是"弹出一个新元素"的关键：
///   1. 遮罩压下来：屏底 253 → f69 的 215，330ms 走完，最深 16% 黑（拟合透过率 0.845）；
///   2. 背景糊掉：格子边缘的过渡带从 2px 宽到 f64 的 17px，高斯拟合 σ = 8.5 屏像素
///      （f65 之后不再变），约 200ms 糊到位；
///   3. 被按的那一格自己长成卡片：矩形从格子 (16,169,119,272) 直线插值到卡片
///      (28,59,221,279)——底边几乎不动（272→279），顶边 169→56→59、右边 119→225→221。
///      顶边 20 个采样点用 `Cubic(0.25,1.3,0.6,1)` 拟合 rmse 0.57px，行程 640ms，
///      多冲 3px（3%）再回落。
/// - 卡片不是"啪"一下变白的：f62 那一点量到 200（就是糊掉压暗后的格子本色），
///   f68 230、f70 251、f74 253 —— 白是 400ms 里慢慢透出来的，前半程看得见"格子在长"。
/// - 卡里的图块 f64→f68 就位；下面的上下文卡 f72→f80 **淡入**（顶边钉在 292 不动，
///   不是滑上来）。
/// - 参考稿到 f118 直接循环，没录到收回；收回按同一路线倒放，压到 300ms。
///
/// 触屏：整片格子墙是一个 [LabDragZone]，按在哪格就弹哪格（落在缝隙里取最近的一格）。
/// 按住 430ms 起预览、松手收回；点一下（没有位移）走一遍完整脚本，桌面鼠标同路。
const _pressDur = Duration(milliseconds: 170); // f15→f20 按下变深
const _holdDur = Duration(milliseconds: 430); // 长按判定
const _openDur = Duration(milliseconds: 700); // 展开全程
const _closeDur = Duration(milliseconds: 300); // 收回（参考稿没录到，倒放）

/// 演示脚本里卡片停留多久：展开在 1130ms 走完，停留 1200ms 才让收回排在 2330ms 之后
const _shownDur = Duration(milliseconds: 1200);

const _scrimMs = 330.0; // f59→f69 遮罩压到底
const _blurMs = 200.0; // f59→f65 背景糊到位
const _popMs = 640.0; // f60→f79 格子长成卡片
const _whiteMs = 400.0; // f60→f72 卡片白透出来
const _ctxAtMs = 430.0; // f72→f80 上下文卡淡入
const _ctxMs = 270.0;

/// 卡内图块：f64→f68 就位（跟着卡片长，比上下文卡早两拍）
const _imgAtMs = 133.0;
const _imgMs = 133.0;

const _openMs = 700.0;

/// 按下的格子底色：239 → 226
const _pressedFill = Color(0xFFE2E2E5);

/// 遮罩最深 16%（253 → 215）
const _scrimMax = 0.16;

/// 背景糊到多散：格边过渡带量到 σ ≈ 8.5 屏像素
const _blurSigma = 8.5 * labK;

/// 格子墙
const _tileD = 103 * labK;
const _tileR = 22 * labK;
const _tileXs = <double>[16 * labK, 131 * labK];
const _tileYs = <double>[54 * labK, 169.5 * labK, 285 * labK];
const _gridX = 16 * labK;
const _gridY = 54 * labK;
const _gridW = 218 * labK;
const _gridH = 334 * labK;

/// 预览卡：屏内 x 28..221、y 59..279，圆角比格子大一点（角上量到约 26）
const _cardRect = Rect.fromLTRB(28 * labK, 59 * labK, 221 * labK, 279 * labK);
const _cardR = 26 * labK;

/// 卡内版式，全部按卡片自己的坐标量（屏内值 ×`labK`）
const _imgRect = Rect.fromLTRB(13 * labK, 14 * labK, 180 * labK, 150 * labK);
const _line1 = Rect.fromLTRB(18 * labK, 163 * labK, 135 * labK, 171 * labK);
const _line2 = Rect.fromLTRB(18 * labK, 179 * labK, 93 * labK, 187 * labK);

/// 上下文卡：同一宽度，屏内 y 291..423，三行 44 一档，行间一条发丝线
const _ctxRect = Rect.fromLTRB(28 * labK, 291 * labK, 221 * labK, 423 * labK);
const _ctxRowH = 44 * labK;
const _ctxBarH = 8 * labK;
const _ctxBarX = 18 * labK;
const _ctxBarWs = <double>[80 * labK, 60 * labK, 72 * labK];
const _ctxBoxD = 16 * labK;
const _ctxBoxX = 162 * labK;
const _ctxDivide = Color(0xFFEDEEF1);

const _tileCount = 6;

/// 卡片只多冲 3px（顶边 56 → 59），比 `LabEase.pop` 收敛得多
const _popCurve = Cubic(0.25, 1.3, 0.6, 1);

class Case49LongPressPeek extends StatefulWidget {
  const Case49LongPressPeek({super.key});

  @override
  State<Case49LongPressPeek> createState() => _Case49LongPressPeekState();
}

class _Case49LongPressPeekState extends State<Case49LongPressPeek>
    with TickerProviderStateMixin {
  late final AnimationController _pressC = AnimationController(vsync: this);
  late final AnimationController _openC = AnimationController(vsync: this);

  /// 被按住的那一格；-1 = 没有
  int _tile = -1;

  /// 点一下走的自动脚本（此时松手不该把预览掐掉）
  bool _script = false;
  Timer? _holdTimer;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _pressC.addListener(() => setState(() {}));
    _openC.addListener(() => setState(() {}));
    _openC.addStatusListener((status) {
      if (status == AnimationStatus.completed && _script) {
        _closeTimer = Timer(_shownDur, _closeNow);
      }
      if (status == AnimationStatus.dismissed) _reset();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _closeTimer?.cancel();
    _pressC.dispose();
    _openC.dispose();
    super.dispose();
  }

  void _reset() {
    _script = false;
    _tile = -1;
  }

  Rect _tileRect(int i) => Rect.fromLTWH(_tileXs[i % 2], _tileYs[i ~/ 2], _tileD, _tileD);

  /// 落点在哪一格；落在缝隙里取中心最近的那一格
  int _tileAt(Offset at) {
    final p = Offset(at.dx + _gridX, at.dy + _gridY);
    for (var i = 0; i < _tileCount; i++) {
      if (_tileRect(i).contains(p)) return i;
    }
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < _tileCount; i++) {
      final d = (_tileRect(i).center - p).distanceSquared;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  void _onStart(Offset at) {
    if (_tile >= 0) return;
    _tile = _tileAt(at);
    _pressC.duration = _pressDur;
    _pressC.forward(from: 0);
    _holdTimer = Timer(_holdDur, _openNow);
    setState(() {});
  }

  void _onTap(Offset at) {
    // 没有位移的一下：交给脚本走完整个循环，松手不再插手
    if (!_script && _openC.value == 0) _script = true;
  }

  void _onEnd(Offset total, Offset velocity) {
    if (_script) return;
    _holdTimer?.cancel();
    if (_openC.value > 0) {
      _closeNow();
    } else if (_tile >= 0) {
      _pressC.reverse(from: _pressC.value);
      _tile = -1;
    }
  }

  void _openNow() {
    _openC.duration = _openDur;
    _openC.forward(from: 0);
  }

  void _closeNow() {
    _openC.duration = _closeDur;
    _openC.reverse(from: _openC.value);
    _pressC.reverse(from: _pressC.value);
  }

  /// 展开进度分成遮罩 / 卡片 / 上下文卡三段，各自有起跑线
  double _stage(double ms, double at, double dur) => ((ms - at) / dur).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ms = _openC.value * _openMs;
    final scrim = _stage(ms, 0, _scrimMs) * _scrimMax;
    final sigma = _blurSigma * _stage(ms, 0, _blurMs);
    final pop = _popCurve.transform(_stage(ms, 0, _popMs));
    final white = LabEase.standard.transform(_stage(ms, 0, _whiteMs));
    final ctx = _stage(ms, _ctxAtMs, _ctxMs);
    final content = _stage(ms, _imgAtMs, _imgMs);
    final press = _pressC.value;
    final card = Rect.lerp(_tileRect(_tile < 0 ? 2 : _tile), _cardRect, pop)!;
    final radius = _tileR + (_cardR - _tileR) * pop.clamp(0.0, 1.0);
    // 格子墙 + 标题条是"被糊被压暗"的那一层
    final wall = Stack(
      children: [
        labHeaderBar,
        for (var i = 0; i < _tileCount; i++)
          Positioned.fromRect(
            rect: _tileRect(i),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(labPillBg, _pressedFill, i == _tile ? press : 0.0),
                borderRadius: BorderRadius.circular(_tileR),
              ),
            ),
          ),
      ],
    );
    return LabStage(
      child: Stack(
        children: [
          LabPhoneScreen(
            children: [
              // σ 为 0 就别过 saveLayer：静止帧要和参考稿一个像素都不差
              Positioned.fill(
                child: sigma < 0.02
                    ? wall
                    : ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                        child: wall,
                      ),
              ),
              if (scrim > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: const Color(0xFF000000).withValues(alpha: scrim),
                    ),
                  ),
                ),
              if (pop > 0)
                Positioned.fromRect(
                  rect: card,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // 白是 400ms 里透出来的：前半程它还是那颗格子，后半程才是卡片
                      color: LabColor.card.withValues(alpha: white),
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF000000).withValues(alpha: 0.1 * pop),
                          blurRadius: 14 * labK,
                          offset: const Offset(0, 4) * labK,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: SizedBox(
                        width: card.width,
                        height: card.height,
                        // 内容跟着卡片一起长：先按卡片最终尺寸排，再两轴分别缩
                        child: Transform(
                          alignment: Alignment.topLeft,
                          transform: Matrix4.diagonal3Values(
                            card.width / _cardRect.width,
                            card.height / _cardRect.height,
                            1,
                          ),
                          child: Opacity(
                            opacity: content,
                            child: SizedBox(
                              width: _cardRect.width,
                              height: _cardRect.height,
                              child: Stack(
                                children: [
                                  Positioned.fromRect(
                                    rect: _imgRect,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: labPillBg,
                                        borderRadius: BorderRadius.circular(18 * labK),
                                      ),
                                    ),
                                  ),
                                  for (final r in const [_line1, _line2])
                                    Positioned.fromRect(
                                      rect: r,
                                      child: LabBar(
                                        width: r.width,
                                        height: r.height,
                                        color: labBarBg,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (ctx > 0)
                Positioned.fromRect(
                  rect: _ctxRect,
                  child: Opacity(
                    opacity: ctx,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: LabColor.card,
                        borderRadius: BorderRadius.circular(_cardR),
                      ),
                      child: Stack(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            Positioned(
                              left: _ctxBarX,
                              top: i * _ctxRowH + (_ctxRowH - _ctxBarH) / 2,
                              child: LabBar(
                                width: _ctxBarWs[i],
                                height: _ctxBarH,
                                color: labBarBg,
                              ),
                            ),
                            Positioned(
                              left: _ctxBoxX,
                              top: i * _ctxRowH + (_ctxRowH - _ctxBoxD) / 2,
                              child: LabBar(
                                width: _ctxBoxD,
                                height: _ctxBoxD,
                                color: labBarBg,
                              ),
                            ),
                            if (i > 0)
                              Positioned(
                                left: 0,
                                top: i * _ctxRowH - 0.25,
                                child: Container(
                                  width: _ctxRect.width,
                                  height: 0.5,
                                  color: _ctxDivide,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              // home 条是系统层：参考稿里它压在遮罩上面，展开时既不暗也不糊（215 → 217）
              labHomeBar,
            ],
          ),
          Positioned(
            left: labScreenX + _gridX,
            top: _gridY,
            child: SizedBox(
              width: _gridW,
              height: _gridH,
              child: LabDragZone(
                cursor: SystemMouseCursors.grab,
                onStart: _onStart,
                onTap: _onTap,
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
