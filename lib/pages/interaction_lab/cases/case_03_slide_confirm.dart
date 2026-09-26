import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

import '../kit.dart';

/// 3. Slide to confirm — 真拖：右边缘钉住，把手在它身后摊开
///
/// 拖的时候 1:1 跟手、没有任何补间；`speed` 旋钮只管松手之后。参考稿这里
/// 最要紧的一条是**偏移在第一次移动时才取**（`grab = n - p`），不是在按下
/// 时——不然在轨道右端按一下就把手"传送"过去了。
///
/// 拖到底（位移 = 全行程 224px，没有提前提交也没有速度判定）松手才提交，
/// 提交是**形变不是换手**：把手的位移和宽度同增同减同样的量，所以
/// `x + width` 恒等于 272，右边缘纹丝不动，看着像把手在身后摊平填满轨道。
/// 1500ms 后自动收回。
///
/// 向左过拉会挤压：`scaleX = 1 - min(.08, 过拉px/110)`，`scaleY = 1/scaleX`
/// （面积守恒）；只有左向有形变，右向顶到 224px 是硬边界。
class Case03SlideConfirm extends StatefulWidget {
  const Case03SlideConfirm({super.key});

  @override
  State<Case03SlideConfirm> createState() => _Case03SlideConfirmState();
}

// 三个钟（图标淡出 / 轨道脉冲 / Confirmed 淡入）+ 弹簧发帧各一只 Ticker，
// 所以是 TickerProviderStateMixin 不是 Single 那一档
class _Case03SlideConfirmState extends State<Case03SlideConfirm>
    with TickerProviderStateMixin {
  /// `b_=56` 轨道高、`x_=4` 内衬、`S_=48` 把手、`T_=28` 圆角上限
  static const _trackW = 280.0;
  static const _trackH = 56.0;
  static const _pad = 4.0;
  static const _grip = 48.0;
  static const _radius = 28.0;
  static const _gripRadius = 24.0; // max(0, 28 - 4)

  /// `TRAVEL = W - 8 - 48`；提交阈值 = 全行程，无提前、无速度判定
  static const _travel = _trackW - _pad * 2 - _grip; // 224

  /// `S = 260 + speed/100*640`，speed=50 → 580；`damping = 2√(S·.9)` = 45.69
  static const _k = 580.0;
  static const _dSubmit = 45.69;

  /// 未提交回弹那条：阻尼再乘 .62，也就是更弹
  static const _dBounce = _dSubmit * 0.62; // 28.33

  /// hover 给 scaleX/scaleY 各乘 1.03（`D_`），且没有缓动——一帧跳变
  static const _hoverScale = 1.03;

  /// 确认文案/轨道脉冲共用的那条 `cubic-bezier(.33,.55,.2,1)`
  static const _doneCurve = Cubic(0.33, 0.55, 0.2, 1);

  /// 把手位移 / 右边缘参考点
  final IlSpring _p = IlSpring.phys(stiffness: _k, damping: _dSubmit, mass: 0.9);
  final IlSpring _m = IlSpring.phys(stiffness: _k, damping: _dSubmit, mass: 0.9);

  Ticker? _ticker;
  Duration _last = Duration.zero;

  bool _held = false;
  bool _hover = false;
  bool _done = false;

  /// 第一次移动才定，按下时是 null
  double? _grab;

  Timer? _undoTimer;
  Timer? _gTimer;

  /// 把手内图标的淡出（提交 120ms / 复位 200ms 且延 120ms）
  double _gFrom = 1;
  double _gTo = 1;
  late final AnimationController _gC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );

  /// 整条轨道的 `[1, .974, 1]` 脉冲：延 100ms + 460ms，一起算成 560ms
  static const _pulseTotal = 560;
  late final AnimationController _pulseC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _pulseTotal),
  );

  /// "Confirmed" 那一段：180ms，opacity 0↔1、scale .7↔1
  late final AnimationController _doneC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _p.jumpTo(0);
    _m.jumpTo(0);
    _p.addListener(_onSpring);
    _m.addListener(_onSpring);
    for (final c in [_gC, _pulseC, _doneC]) {
      c.addListener(() => setState(() {}));
    }
    _gC.value = 1;
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _gTimer?.cancel();
    _p.removeListener(_onSpring);
    _m.removeListener(_onSpring);
    _p.dispose();
    _m.dispose();
    _gC.dispose();
    _pulseC.dispose();
    _doneC.dispose();
    _ticker?.stop();
    _ticker?.dispose();
    super.dispose();
  }

  void _onSpring() {
    if (!mounted) return;
    setState(() {});
    if (_p.atRest && _m.atRest) {
      _ticker?.stop();
    } else {
      _ticker ??= Ticker(_tick);
      if (!_ticker!.isActive) {
        // Ticker 停过再起，喂给回调的 elapsed 是从零重算的，对表值必须跟着归零，
        // 不然复位那一段第一帧拿到的是"距上次起跑"的整个时长
        _last = Duration.zero;
        _ticker!.start();
      }
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds.toDouble();
    _last = elapsed;
    if (dt <= 0) return;
    _p.step(dt);
    _m.step(dt);
  }

  // ---------------------------------------------------------------- 拖拽

  void _dragStart(double atX) {
    if (_done) return;
    setState(() {
      _held = true;
      // 不在按下时取偏移：按下点可能离把手很远，一取就把把手瞬移过去
      _grab = null;
    });
  }

  void _dragUpdate(double atX) {
    if (_done) return;
    final g = _grab;
    if (g == null) {
      _grab = atX - _p.value;
      return;
    }
    _p.jumpTo((atX - g).clamp(0.0, _travel));
  }

  void _dragEnd() {
    if (_done) return;
    setState(() => _held = false);
    if (_p.value >= _travel - 0.02) {
      _submit();
    } else {
      _p.retune(stiffness: _k, damping: _dBounce, mass: 0.9);
      _p.aim(0);
    }
  }

  // ---------------------------------------------------------------- 提交

  void _submit() {
    // 冻结右边缘参考点：此后 width = 48 + clamp(m - p, 0, travel)
    _m.jumpTo(_p.value);
    _p.retune(stiffness: _k, damping: _dSubmit, mass: 0.9);
    _p.aim(0);
    _fadeG(0, const Duration(milliseconds: 120));
    _pulseC.forward(from: 0);
    setState(() => _done = true);
    _doneC.forward(from: 0);
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(milliseconds: 1500), _undo);
  }

  void _undo() {
    if (!mounted) return;
    setState(() => _done = false);
    _doneC.reverse();
    _fadeG(1, const Duration(milliseconds: 200), const Duration(milliseconds: 120));
    // m 从冻结点收回 0：宽度 48+m 跟着缩回把手
    _m.retune(stiffness: 380, damping: 34, mass: 0.9);
    _m.aim(0);
  }

  void _fadeG(double to, Duration dur, [Duration delay = Duration.zero]) {
    _gFrom = _g;
    _gTo = to;
    _gC.duration = dur;
    _gTimer?.cancel();
    if (delay == Duration.zero) {
      _gC.forward(from: 0);
    } else {
      _gTimer = Timer(delay, () {
        if (mounted) _gC.forward(from: 0);
      });
    }
  }

  // ---------------------------------------------------------------- 派生量

  double get _g => _gFrom + (_gTo - _gFrom) * Curves.easeInOut.transform(_gC.value);

  /// 轨道脉冲：延 100ms 之后 460ms 走完 `1 → .974 → 1`
  double get _trackScale {
    const span = _pulseTotal - 100;
    final t = _pulseC.value * _pulseTotal - 100;
    if (t <= 0 || t >= span) return 1;
    final q = t / span;
    return q < 0.62
        ? 1 + (0.974 - 1) * _doneCurve.transform(q / 0.62)
        : 0.974 + (1 - 0.974) * _doneCurve.transform((q - 0.62) / 0.38);
  }

  /// 向左过拉才挤压：`A = 1 - min(.08, max(0,-p)/110)`
  double get _squash {
    final over = _p.value < 0 ? -_p.value : 0.0;
    return 1 - (over / 110).clamp(0.0, 0.08);
  }

  /// `x = clamp(p,0,v)`，`width = 48 + clamp(m - p, 0, v)`
  ///
  /// 提交的 1500ms 里 m 钉在 224，于是 x+width 恒为 272——右边缘不动。
  /// 复位时换成 m 往 0 收，宽度缩回 48。
  ({double x, double w}) get _gripBox {
    final x = _p.value.clamp(0.0, _travel);
    return (x: x, w: _grip + (_m.value - _p.value).clamp(0.0, _travel));
  }

  /// 位移从 .55v 起淡出；确认那一瞬也要压住它，不然回弹时提示语会
  /// 跟着弹簧倒放、和"Confirmed"叠在同一帧上
  double get _sayOpacity =>
      _sayBase * (1 - _doneCurve.transform(_doneC.value));

  double get _sayBase => (1 - _p.value / (_travel * 0.55)).clamp(0.0, 1.0);

  /// 箭头：从 .55v 起淡出、到 .95v 为 0，再乘 g
  double get _arrowOpacity =>
      _g * (1 - (_p.value - _travel * 0.55) / (_travel * 0.4)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final box = _gripBox;
    final sq = _squash;
    final hoverK = (_hover && !_held && !_done) ? _hoverScale : 1.0;
    final t = _doneCurve.transform(_doneC.value);

    return IlStage(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _dragStart(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _dragUpdate(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _dragEnd(),
        onHorizontalDragCancel: () => setState(() => _held = false),
        child: MouseRegion(
          cursor: _held ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Transform.scale(
            scale: _trackScale,
            child: Container(
              width: _trackW,
              height: _trackH,
              decoration: BoxDecoration(
                color: IlColor.pane,
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Stack(
                children: [
                  // 进度填充：宽度恒等于"轨道左缘到把手右缘"。只写把手宽度
                  // 的话，拖到中段会在它身后露出白底
                  Positioned(
                    left: _pad,
                    top: _pad,
                    bottom: _pad,
                    width: box.x + box.w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: IlColor.ink,
                        // 高 48 / 圆角 24 = 内缩一档的胶囊，左端正好贴合轨道
                        // 半径 28 的内弧
                        borderRadius: BorderRadius.circular(_gripRadius),
                      ),
                    ),
                  ),
                  // `.sld-say`：铺满整轨居中
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: _sayOpacity,
                        child: const Text('Slide to confirm', style: _sayStyle),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _pad + box.x,
                    top: _pad,
                    child: _Grip(
                      width: box.w,
                      scaleX: sq * hoverK,
                      scaleY: (1 / sq) * hoverK,
                      arrowOpacity: _arrowOpacity,
                      doneOpacity: t,
                      doneScale: 0.7 + 0.3 * t,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip({
    required this.width,
    required this.scaleX,
    required this.scaleY,
    required this.arrowOpacity,
    required this.doneOpacity,
    required this.doneScale,
  });

  final double width;
  final double scaleX;
  final double scaleY;
  final double arrowOpacity;
  final double doneOpacity;
  final double doneScale;

  @override
  Widget build(BuildContext context) {
    // `transform-origin:0%` —— 以左边缘为原点，挤压时左端不动
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(0, 0, scaleX)
        ..setEntry(1, 1, scaleY),
      child: Container(
        width: width,
        height: 48,
        decoration: const BoxDecoration(
          color: IlColor.ink,
          borderRadius: BorderRadius.all(Radius.circular(_gripR)),
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: arrowOpacity.clamp(0.0, 1.0),
              child: const IlIcon(
                paths: ['M5 12h14', 'M12 5l7 7-7 7'],
                size: 20,
                viewBox: 24,
                strokeWidth: 2.4,
                color: IlColor.pane,
              ),
            ),
            Opacity(
              opacity: doneOpacity.clamp(0.0, 1.0),
              // 提交那一瞬把手只有 48 宽，"Confirmed" 却已经 100 上下：用
              // OverflowBox 让它探出去画（字是白的，探到白轨道上等于看不见）。
              // 用 UnconstrainedBox 的话它自己就是那条溢出报错的来源
              child: OverflowBox(
                alignment: Alignment.center,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform.scale(
                  scale: doneScale,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IlIcon(
                        paths: ['M20 6L9 17l-5-5'],
                        size: 19,
                        viewBox: 24,
                        strokeWidth: 2.8,
                        color: IlColor.pane,
                      ),
                      SizedBox(width: 8),
                      Text('Confirmed', style: _labelStyle),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _gripR = 24.0;

/// 14px / 500 / 字距 -.006em
const _sayStyle = TextStyle(
  fontFamily: IlFont.family,
  fontFamilyFallback: IlFont.fallback,
  fontSize: 14,
  fontWeight: FontWeight.w500,
  letterSpacing: -0.084,
  height: 1.5,
  color: Color(0x7317181A), // rgba(23,24,26,.45)
);

const _labelStyle = TextStyle(
  fontFamily: IlFont.family,
  fontFamilyFallback: IlFont.fallback,
  fontSize: 14,
  fontWeight: FontWeight.w500,
  letterSpacing: -0.084,
  height: 1.5,
  color: IlColor.pane,
);
