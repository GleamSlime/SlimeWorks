import 'package:flutter/material.dart';

import '../lab_kit.dart';
import 'lab_phone.dart';

/// 50. Edge swipe back — 从左边横向划走详情页，列表页跟在后面滑进来
///
/// 两页版式都按屏内像素量（×`labK` 落到舞台）：详情页是标题条 + 大块的
/// hero（y66..241）+ 一条标题 + 四行正文（y292/309/326/343，行距 17）+ 一颗
/// 57 高的按钮；列表页是居中的标题条 + 五行 `LabSkelRow`。
///
/// 逐帧量到的一手数据（`detailLeft` = 详情页左边的 x）：
/// - 跟手段 f28→f82：detailLeft 0 → 180，每帧 3.5px 匀速，就是 1:1 跟手。
/// - 列表页的视差：d = -A(1-p)。f60 预测 -57、f70 -43、f78 -32，实测头像右边
///   界落在 8 / 26 / 33（静止时是 65）——三条都对得上，A 取 96。
/// - 列表页上压了一层遮罩，随行程线性退掉：f60 底色 229、f70 233、f78 238、
///   详情页离场后 f90 已经 251。按 253×(1-α) 反推 α≈0.16。
/// - 详情页左沿带一道投影：宽约 24 屏内像素，贴着边最深（229 → 219）。
/// - 松手后两页**不同步**：详情页 f82→f88 匀速飞出（180→202→228→出屏），
///   列表页却慢半拍，f84 -23 → f98 归位，14 帧 467ms，逐段 7/6/4/3/1/1/1，
///   正好是 `easeOutQuad`。所以飞出只占整段行程的前 200/470。
/// - 详情页**不停在屏右界**：f88 左沿已经到 254（屏宽 248），f95 更走到 300 开外。
///   正是这一程把它那道左沿投影一起带出屏——停在 248 的话，投影还剩 36px 压在列表页上。
///
/// 触屏：整块屏幕是一个 [LabDragZone]，横向跟手；划过半程或往右甩就走完，
/// 否则弹回。已经回到列表页时，点一下（或往左拖）再把详情页推回来。
const _settleDur = Duration(milliseconds: 470); // f84→f98 列表页归位
const _backDur = Duration(milliseconds: 300); // 没划到位弹回（参考稿没录到）
const _returnDur = Duration(milliseconds: 350); // 点列表行换回详情（同上）

/// 飞出占整段行程的比例：过了这一段详情页已经离场，列表页还在收尾
const _flyPart = 200 / 470;

/// 走满之后详情页再多飞的一程（屏宽的比例）：停在屏右界的话，它左沿那道
/// 投影会留 36px 压在列表页上，所以进度得越过 1 把投影一起带出屏
const _exitExtra = 0.3;

/// 停在列表页那一端的进度
const _parked = 1.0 + _exitExtra;

/// 列表页的视差行程
const _parallax = 96 * labK;

/// 压在列表页上的遮罩最深 16%
const _scrimMax = 0.16;

/// 过半或者甩够快才算划到底
const _doneAt = 0.45;
const _flingV = 240;

/// 投影：宽 24 屏内像素、贴边最深约 4%
const _shadowBlur = 36 * labK;
const _shadowAlpha = 0.09;

const _rowCount = 5;

/// 标题条两页都是居中那根（屏内 x70..179、y36..47）
const _headW = 110 * labK;
const _headH = 12 * labK;
const _headX = (labScreenW - _headW) / 2;
const _headY = 36 * labK;

/// 详情页
const _heroRect = Rect.fromLTRB(16 * labK, 66 * labK, 234 * labK, 241 * labK);
const _titleRect = Rect.fromLTRB(16 * labK, 263 * labK, 158 * labK, 275 * labK);
const _lineYs = <double>[292 * labK, 309 * labK, 326 * labK, 343 * labK];
const _lineH = 7 * labK;
const _lineWs = <double>[218 * labK, 218 * labK, 218 * labK, 153 * labK];
const _btnRect = Rect.fromLTRB(16 * labK, 383 * labK, 234 * labK, 440 * labK);

/// 返回箭头：屏内 x19..30、y32..52、笔锋 3.5。`LabIcon` 的 16 viewBox 里
/// 这个 `d` 占 7×12，所以画布要放到 28 才凑出 12×21，左上角再倒回字身留的空
const _chevPath = 'M11 2L4 8L11 14';
const _chevSize = 28 * labK;
const _chevLeft = 12 * labK;
const _chevTop = 28.5 * labK;

enum _Mode { rest, drag, fly, back }

class Case50EdgeSwipeBack extends StatefulWidget {
  const Case50EdgeSwipeBack({super.key});

  @override
  State<Case50EdgeSwipeBack> createState() => _Case50EdgeSwipeBackState();
}

class _Case50EdgeSwipeBackState extends State<Case50EdgeSwipeBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  _Mode _mode = _Mode.rest;

  /// 静止时的揭示进度：0 = 详情页压在上面，[_parked] = 列表页露全
  double _p = 0;
  double _dragP = 0;
  double _dragFrom = 0;
  double _from = 0;
  double _to = 0;
  double _toDet = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _p = _toDet;
      _mode = _Mode.rest;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 往哪个进度走、走多久
  void _go(double to, Duration dur) {
    _from = _mode == _Mode.drag ? _dragP : _p;
    _to = to;
    _toDet = to >= 1.0 ? _parked : to;
    _mode = to > _from ? _Mode.fly : _Mode.back;
    _c.duration = dur;
    _c.forward(from: 0);
  }

  void _onStart(Offset at) {
    if (_mode != _Mode.rest) return;
    _dragFrom = _p;
    _dragP = _p;
    _mode = _Mode.drag;
  }

  void _onUpdate(Offset total, Offset at) {
    if (_mode != _Mode.drag) return;
    setState(() => _dragP = (_dragFrom + total.dx / labScreenW).clamp(0.0, _parked));
  }

  void _onEnd(Offset total, Offset velocity) {
    if (_mode != _Mode.drag) return;
    var to = _dragP >= _doneAt ? 1.0 : 0.0;
    if (velocity.dx > _flingV) to = 1;
    if (velocity.dx < -_flingV) to = 0;
    _go(to, to > _dragP ? _settleDur : _backDur);
  }

  void _onTap(Offset at) {
    // `LabDragZone` 先送 onTap 再送 onEnd，所以这一下还挂在 drag 上；
    // 没有位移就是列表页露全时点了一下 = 换回详情
    if ((_mode == _Mode.drag || _mode == _Mode.rest) && _p >= 1) {
      _go(0, _returnDur);
    }
  }

  /// 详情页：飞出那段是匀速（180→202→228 每两帧 22、26），走满还继续往屏外冲
  double get _detP => switch (_mode) {
        _Mode.drag => _dragP,
        _Mode.fly => _mix(_from, _toDet, (_c.value / _flyPart).clamp(0.0, 1.0)),
        _Mode.back => _mix(_from, _toDet, LabEase.smoothOut.transform(_c.value)),
        _Mode.rest => _p,
      };

  /// 列表页：整段 470ms 走 `easeOutQuad`，比详情页慢半拍；只认 0..1 那一段
  double get _listP => switch (_mode) {
        _Mode.fly => _mix(_from, _to, Curves.easeOutQuad.transform(_c.value)),
        _ => _detP.clamp(0.0, 1.0),
      };

  double _mix(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final det = _detP;
    final list = _listP;
    return LabStage(
      child: Stack(
        children: [
          LabPhoneScreen(
            children: [
              Positioned(
                left: -_parallax * (1 - list),
                top: 0,
                child: _listPage,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: const Color(0xFF000000)
                        .withValues(alpha: _scrimMax * (1 - list)),
                  ),
                ),
              ),
              Positioned(
                left: labScreenW * det,
                top: 0,
                child: _detailPage,
              ),
              Positioned.fill(
                child: LabDragZone(
                  cursor: SystemMouseCursors.grab,
                  onStart: _onStart,
                  onUpdate: _onUpdate,
                  onEnd: _onEnd,
                  onTap: _onTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget get _listPage => _page([
        Positioned(
          left: _headX,
          top: _headY,
          child: LabBar(width: _headW, height: _headH, color: labPillBg),
        ),
        for (var i = 0; i < _rowCount; i++)
          Positioned(
            left: labPad,
            top: labRowY(i),
            child: const LabSkelRow(),
          ),
        labHomeBar,
      ]);

  Widget get _detailPage => _page(
        [
          Positioned(
            left: _headX,
            top: _headY,
            child: LabBar(width: _headW, height: _headH, color: labPillBg),
          ),
          Positioned(
            left: _chevLeft,
            top: _chevTop,
            child: LabIcon(
              paths: const [_chevPath],
              size: _chevSize,
              strokeWidth: 2,
              color: labBarBg,
            ),
          ),
          Positioned.fromRect(
            rect: _heroRect,
            child: _block(labPillBg, 18 * labK),
          ),
          Positioned.fromRect(
            rect: _titleRect,
            child: LabBar(
              width: _titleRect.width,
              height: _titleRect.height,
              color: labBarBg,
            ),
          ),
          for (var i = 0; i < _lineYs.length; i++)
            Positioned(
              left: labPad,
              top: _lineYs[i],
              child: LabBar(width: _lineWs[i], height: _lineH, color: labBarBg),
            ),
          Positioned.fromRect(
            rect: _btnRect,
            child: _block(labPillBg, 18 * labK),
          ),
          labHomeBar,
        ],
        lift: true,
      );

  /// [lift] = 这一页浮在另一页上面，左沿带一道投影
  ///
  /// 底色那层必须自己带尺寸：Stack 给非定位子项的是松约束，空 `DecoratedBox`
  /// 会直接塌成 0×0，底色画不出来，下面的遮罩就透到正文上去了。
  Widget _page(List<Widget> children, {bool lift = false}) => SizedBox(
        width: labScreenW,
        height: LabSize.stageH,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: labScreenBg,
                boxShadow: [
                  if (lift)
                    BoxShadow(
                      color: const Color(0xFF000000)
                          .withValues(alpha: _shadowAlpha),
                      blurRadius: _shadowBlur,
                    ),
                ],
              ),
              child: const SizedBox(
                width: labScreenW,
                height: LabSize.stageH,
              ),
            ),
            ...children,
          ],
        ),
      );

  Widget _block(Color color, double radius) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
