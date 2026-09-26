import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerCancelEvent, PointerDownEvent, PointerEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/scheduler.dart' show Ticker;

import 'package:flutter/material.dart';

import '../kit.dart';

/// 4. Reorder list — 按住整行拖，别的行让开，松手吸附
///
/// 结构和动效实验室那些格子不一样：**色块和文字分两层**。下层（blobs）只有四颗药丸，
/// 整层过一遍 `blur(2.6) + alpha×28−14`，于是两颗靠近到 6px 以内会"熔"在一起；
/// 上层（ink）是不进滤镜的头像和姓名，靠同一个 y 值和下面对齐。文字绝不能进滤镜。
///
/// 三条轴各管各的，这是参考稿写死的分工：
/// - **位置**：拿起那行每次位移直写 `原槽×50 + 累计位移`，不插值、不钳边界——它必须钉在指上；
///   其余行走弹簧 `{220, 14, 0.5}` 让位。
/// - **形变**：只作用在拿起那行的药丸上，由"每 16ms 像素位移"归一化的速度驱动
///   （钳 ±3、dt 下限 8ms）：`scaleY = 1 + give/100·|S|·.12`、`scaleX = 1/scaleY`、
///   `skewY = lean/100·S·2.6°`。give=50 / lean=18 → 最大 1.18 / 0.847 / ±1.404°。
/// - **颜色/尺寸**：药丸 196↔208、头像 1↔1.08 走同一条弹簧；底色 220ms、文字色 200ms 走补间。
///
/// 换序判据是**行中心落在哪个 50px 槽**（阈值 = 半步 25px）；越界的只有这个读数被钳 0..3。
class Case04ReorderList extends StatefulWidget {
  const Case04ReorderList({super.key});

  @override
  State<Case04ReorderList> createState() => _Case04ReorderListState();
}

@immutable
class _Person {
  const _Person(this.name, this.initials, this.tint, this.here);

  final String name;
  final String initials;
  final Color tint;
  final bool here;
}

const _people = <_Person>[
  _Person('Mara Quinn', 'MQ', Color(0xFF7C3AED), true),
  _Person('Tomás Oliveira', 'TO', Color(0xFF0E7490), false),
  _Person('Lars Andersen', 'LA', Color(0xFFB8431C), true),
  _Person('Sofia Ricci', 'SR', Color(0xFF15803D), false),
];

class _Case04ReorderListState extends State<Case04ReorderList> with SingleTickerProviderStateMixin {
  /// 量出来的那几个数：药丸 196×44、行距 50（间隙 6）、列表 262×200
  static const _step = 50.0;
  static const _pill = 196.0;
  static const _rowH = 44.0;
  static const _corner = 22.0;
  static const _listW = 262.0;
  static const _listH = 200.0;

  /// 画布比列表上下各多 16，正好和舞台同高：融合滤镜按图层边界切，
  /// 图层只有 200 高的话，行一拖出列表就在那条线上被齐齐断掉
  static const _paintH = IlSize.stageH;
  static const _top = (_paintH - _listH) / 2;

  static const _liftW = 12.0; // 208 - 196，左右各 6
  static const _av = 32.0;
  static const _insetL = 6.0;
  static const _padR = 16.0;
  static const _gap = 11.0;
  static const _dot = 9.0;
  static const _ring = 2.0;

  /// `--lift` = 16% 墨混白；`--warm` = 1.3% 墨混白
  static const _liftBg = Color(0xFFDADADA);
  static const _warmBg = Color(0xFFFCFCFC);
  static const _online = Color(0xFF15803D);

  /// 旋钮默认档：Give 50 / Lean 18
  static const _give = 50.0;
  static const _lean = 18.0;

  static IlSpring _spring() => IlSpring.phys(stiffness: 220, damping: 14, mass: 0.5);

  /// `_order[槽] = 行号`
  List<int> _order = const [0, 1, 2, 3];
  final List<IlSpring> _y = List<IlSpring>.generate(_people.length, (_) => _spring());
  final List<IlSpring> _lift = List<IlSpring>.generate(_people.length, (_) => _spring());

  int? _held;
  int? _hover;
  int? _pointer;
  int _startSlot = 0;
  double _dy = 0;
  double _lastY = 0;
  Duration _lastAt = Duration.zero;

  /// 归一化速度：每 16ms 的像素位移，钳在 ±3
  double _s = 0;

  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _y.length; i++) {
      _y[i].jumpTo(i * _step);
    }
  }

  @override
  void dispose() {
    // 手指还按着就把销毁掉的 State 摘掉，否则 router 还往这儿投事件
    _dropRoute();
    _ticker?.stop();
    _ticker = null;
    super.dispose();
  }

  // ---------------------------------------------------------------- 指针

  /// 按下即"抓起"。跟手靠 `pointerRouter` 收这个指针的全部事件，
  /// 等价于原稿的 `setPointerCapture`——手指划出这一行也还在跟
  void _grab(int id, PointerDownEvent e) {
    // 原稿 `if(!drag.current)return`：按住期间不响应第二根手指
    if (_held != null) return;
    setState(() {
      _held = id;
      _pointer = e.pointer;
      _startSlot = _order.indexOf(id);
      _dy = 0;
      _s = 0;
      _lastY = e.position.dy;
      _lastAt = e.timeStamp;
      _y[id].jumpTo(_startSlot * _step);
      _lift[id].aim(1);
    });
    GestureBinding.instance.pointerRouter.addRoute(e.pointer, _route);
    _refresh();
  }

  void _route(PointerEvent e) {
    if (e is PointerMoveEvent) {
      _move(e);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _release();
    }
  }

  void _move(PointerMoveEvent e) {
    final id = _held;
    if (id == null) return;
    final dy = e.position.dy - _lastY;
    final dt = (e.timeStamp - _lastAt).inMilliseconds.toDouble();
    _lastY = e.position.dy;
    _lastAt = e.timeStamp;
    setState(() {
      // dt 下限 8ms：一帧里夹两次位移会把速度算爆
      final l = dt < 8 ? 8.0 : dt;
      _s = (dy / l * 16).clamp(-3.0, 3.0);
      _dy += dy;
      final at = _startSlot * _step + _dy;
      _y[id].jumpTo(at);
      // 只有这个读数钳过，位置本身放开拖
      final target = (at / _step).round().clamp(0, _people.length - 1);
      if (target != _order.indexOf(id)) _reorder(target);
    });
    _refresh();
  }

  void _reorder(int target) {
    final id = _held!;
    final next = <int>[for (final e in _order) if (e != id) e]..insert(target, id);
    _order = next;
    for (var slot = 0; slot < next.length; slot++) {
      final e = next[slot];
      if (e != id) _y[e].aim(slot * _step);
    }
  }

  void _release() {
    final id = _held;
    if (id == null) return;
    _dropRoute();
    setState(() {
      _held = null;
      // 松手把速度清零 → 形变直接回 1，原稿这儿没有额外的回弹缓动
      _s = 0;
      _lift[id].aim(0);
      // 吸附到新槽：弹簧走完，没有抛掷惯性
      _y[id].aim(_order.indexOf(id) * _step);
    });
    _refresh();
  }

  void _dropRoute() {
    final p = _pointer;
    if (p == null) return;
    GestureBinding.instance.pointerRouter.removeRoute(p, _route);
    _pointer = null;
  }

  // ---------------------------------------------------------------- 发帧

  void _refresh() {
    final busy = _y.any((s) => !s.atRest) || _lift.any((s) => !s.atRest);
    if (!busy) {
      _ticker?.stop();
      return;
    }
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      // 停过再起，喂给回调的 elapsed 是从零重算的，对表值必须跟着归零
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds.toDouble();
    _last = elapsed;
    for (final s in _y) {
      s.step(dt);
    }
    for (final s in _lift) {
      s.step(dt);
    }
    if (mounted) setState(() {});
    _refresh();
  }

  // ---------------------------------------------------------------- 派生量

  /// `give` 越大越能被甩长；`scaleX` 取倒数，于是拉长必然压扁，面积守恒
  double _scaleY(int id) => id == _held ? 1 + _give / 100 * _s.abs() * 0.12 : 1;

  double _scaleX(int id) {
    if (id != _held) return 1;
    return 1 / _scaleY(id);
  }

  double _skew(int id) => id == _held ? _lean / 100 * _s * 2.6 * math.pi / 180 : 0;

  double _width(int id) => _pill + _lift[id].value * _liftW;

  Color _bg(int id) => id == _held ? _liftBg : _restBg(id);

  /// 没拿起时的两档底色：静止纯白 / 悬停暖白
  Color _restBg(int id) => id == _hover ? _warmBg : IlColor.pane;

  /// 拿起的行压在其余行之上（原稿 `z-index:2`）：把它挪到绘制序列末尾
  List<int> get _paintOrder {
    final ids = <int>[for (var i = 0; i < _order.length; i++) i];
    final held = _held;
    if (held != null) {
      ids.remove(held);
      ids.add(held);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final ids = _paintOrder;
    return IlStage(
      child: SizedBox(
        width: _listW,
        height: _paintH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: _listW,
              height: _paintH,
              // 色块层不接命中：按住的地方只有墨层那 196×44
              child: IgnorePointer(
                child: IlGoo(
                  sigma: 2.6,
                  contrast: 28,
                  keepSource: false,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [for (final i in ids) _blob(i)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: _listW,
              height: _paintH,
              child: Stack(clipBehavior: Clip.none, children: [for (final i in ids) _row(i)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(int id) {
    final w = _width(id);
    return Positioned(
      // 拿起的行会被挪到绘制序列末尾（压在其他行之上），没有 key 的话
      // Stack 按下标复用 Element，颜色补间会串到别的行上
      key: ValueKey('blob$id'),
      left: (_listW - w) / 2,
      top: _top + _y[id].value,
      // 位置和形变不共用一个 transform：位置钉在指上不许插值，形变要在停手那一刻立刻收回
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.skewY(_skew(id))..scaleByDouble(_scaleX(id), _scaleY(id), 1, 1),
        // 宽不能用 `AnimatedContainer`：它已经在吃弹簧的值了，每帧都变一次就会
        // 每帧重启一遍自己的补间，于是永远追不上。只有底色是 220ms 补间
        child: IlTween(
          target: id == _held ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          builder: (context, v) => Container(
            width: w,
            height: _rowH,
            decoration: BoxDecoration(
              color: Color.lerp(_restBg(id), _liftBg, v),
              borderRadius: BorderRadius.circular(_corner),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(int id) {
    final p = _people[id];
    final w = _width(id);
    final held = id == _held;
    return Positioned(
      key: ValueKey('row$id'),
      left: (_listW - w) / 2,
      top: _top + _y[id].value,
      width: w,
      height: _rowH,
      child: MouseRegion(
        cursor: held ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        onEnter: (_) => setState(() => _hover = id),
        onExit: (_) {
          if (_hover == id) setState(() => _hover = null);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _grab(id, e),
          child: Padding(
            padding: const EdgeInsets.only(left: _insetL, right: _padR),
            child: Row(
              children: [
                SizedBox(
                  width: _av,
                  height: _av,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // 头像恒定正圆，Corner 旋钮不碰它；拿起时只放大 8%
                      Transform.scale(
                        scale: 1 + _lift[id].value * 0.08,
                        child: Container(
                          width: _av,
                          height: _av,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: p.tint, shape: BoxShape.circle),
                          child: Text(
                            p.initials,
                            style: const TextStyle(
                              fontFamily: IlFont.family,
                              fontFamilyFallback: IlFont.fallback,
                              fontSize: 12,
                              height: 1,
                              letterSpacing: 0.12,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: _online,
                            shape: BoxShape.circle,
                            // CSS 的 `0 0 0 2px` 是外圈，环色跟着药丸底色走
                            boxShadow: [
                              BoxShadow(
                                color: _bg(id),
                                spreadRadius: _ring,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: _gap),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      fontFamily: IlFont.family,
                      fontFamilyFallback: IlFont.fallback,
                      fontSize: 12.5,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      color: held ? IlColor.ink : IlColor.ink2,
                    ),
                    child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
