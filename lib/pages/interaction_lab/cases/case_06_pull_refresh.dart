import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerCancelEvent, PointerDownEvent, PointerEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import 'package:flutter/material.dart';

import '../kit.dart';

/// 6. Pull to refresh — 真按住卡片往下拽，越过阈值松手才刷新
///
/// 这一格和前面几格不一样：**能动的部件只有一个，但它同时驱动四个读数**。
/// 手指位移 → 橡皮筋（`D = 510c/(510+c)`）→ 弹簧（只在回弹时走）→ 同一帧里
/// 同时改：卡片白底的高度（`--grow`）、内容下沉的像素（`--at`）、液滴环的
/// 透明度/半径/转角（`--p`）。所以弹簧的值必须一次算完、一次重建，
/// 分四个补间各走各的就会散架。
///
/// 三件参考稿写死的事：
/// - **拖的时候不走弹簧**。`zf(target, 58, immediate)` 的第三参在 `hold` 里恒为真
///   → 表观位移就是橡皮筋读数，直接贴手；松手那一刻才换成弹簧回 0。
///   弹簧自己会冲到负值（−18），但 `--at` 取 `max(0, O)` 钳住，于是负值只露在
///   `--grow` 上：卡片白底薄掉 8px 又鼓回来。
/// - **阈值 58 是"表观"像素**。橡皮筋吃掉一截，手指真要走 65.07px 才够。
///   判定在拖动过程中就做（`j>=1` 即 armed），松手只是执行它。
/// - **刷新不换图动画**。1150ms 到点整条 series 一次性替换，路径没有 morph；
///   期间唯一在动的是液滴环以 2400ms/圈匀速转。
///
/// 图表是量出来的：`viewBox="0 0 100 40"` + `preserveAspectRatio:none` 画在
/// 296×92 上（x 一档 2.96px、y 一档 2.3px），描边 2.1px 走
/// `vector-effect:non-scaling-stroke` → 非等比缩放**不作用于线宽**。
/// 折点按该窗口自身 min/max 归一，y 落在 4..36；平滑用标准 Catmull-Rom
/// 转三次贝塞尔（控制点权重 1/6，端点用重复点兜底），坐标一律两位小数。
/// 没有坐标轴、没有网格、没有面积填充——读数全在文字上。
///
/// 舞台比别格高（372）：卡片是往下长的，参考稿自己的舞台也给下方留了 101px。
class Case06PullRefresh extends StatefulWidget {
  const Case06PullRefresh({super.key});

  @override
  State<Case06PullRefresh> createState() => _Case06PullRefreshState();
}

enum _Phase { idle, hold, work }

/// 时间窗：标签 / 取几个尾部点 / 未扫读时的区间文案
@immutable
class _Window {
  const _Window(this.label, this.take, this.span);
  final String label;
  final int take;
  final String span;
}

/// 卡片内容一帧的读数
@immutable
class _Readout {
  const _Readout(this.chart, this.value, this.delta, this.percent, this.when, this.up, this.point);

  /// 当前窗口的曲线（图和大读数共用一份）
  final _Chart chart;

  /// `$` 那一大行的数值
  final double value;

  /// 相对窗口首点的涨跌额与百分比
  final double delta;
  final double percent;

  /// 右侧的时间/区间文案
  final String when;
  final bool up;

  /// 提示点在 viewBox 里的坐标（x 0..100、y 4..36）
  final Offset point;
}

class _Case06PullRefreshState extends State<Case06PullRefresh> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 量出来的尺寸

  static const _cardW = 320.0;

  /// 22+33+9+19.5+22+104+16+32+4，和 DOM 里 `.bal-scroll` 的 261.5 对上
  static const _sheetH = 261.5;
  static const _padT = 22.0;
  static const _padX = 12.0;
  static const _sumH = 33.0;
  static const _moveH = 19.5;
  static const _svgH = 92.0;
  static const _plotPadY = 6.0;
  static const _winH = 32.0;

  static const _corner = 26.0;

  /// `--bal-tab-r = min(16, corner*0.62)`
  static const _tabCorner = 16.0;

  static const _plotW = _cardW - _padX * 2; // 296
  static const _plotH = _svgH + _plotPadY * 2; // 104
  static const _tabW = (_plotW - 4 * 2) / 3; // 96

  /// 液滴环：60×60 的盒子钉在 `top:30 / left:50%` 再各退 30 → 圆心 (160, 30)
  static const _gooBox = 60.0;
  static const _ringY = 30.0;
  static const _dotSize = 4.0;

  static const _stageH = 372.0;
  static const _cardTop = 14.0;

  // ---------------------------------------------------------------- 交互的量

  /// `E = 700 - resistance/100*380`，resistance 默认 50
  static const _resist = 510.0;
  static const _threshold = 58.0;
  static const _growBase = 8.0;
  static const _growSat = 110.0;

  /// `zf(target, 58)` → `k = .08+58/100*.16`、`d = .62+58/100*.2`
  static const _springK = 0.1728;
  static const _springD = 0.736;

  static const _dots = 6;
  static const _ringR = 12.0; // `12 + (dots-6)*1.3`
  static const _rpm = 2400.0; // `3000 - spin/100*1200`
  static const _workMs = 1150;

  /// 死区：往下 4px 才成立，往上 4px 立刻交还给滚动
  static const _dead = 4.0;

  static const _pillEase = Cubic(0.34, 1.16, 0.5, 1); // 药丸 .38s
  static const _tipEase = Cubic(0.28, 1.4, 0.36, 1); // 提示点 .16s
  static const _btnEase = Cubic(0.28, 1.2, 0.36, 1); // 按钮按下 .2s
  static const _cssEase = Cubic(0.25, 0.1, 0.25, 1); // transition 缺省

  static const _lineUp = Color(0xFF12B055);
  static const _lineDown = Color(0xFFE8552A);
  static const _textUp = Color(0xFF15803D);
  static const _textDown = Color(0xFFB8431C);

  // ---------------------------------------------------------------- 状态

  final IlSpring _s = IlSpring(k: _springK, d: _springD);
  final FocusNode _node = FocusNode();

  /// 刷新次数：决定取哪一条 series（`Vv[p%3]`）
  int _ticks = 0;
  int _win = 2; // 默认 1D

  /// 图上扫读的位置（null = 没在扫，读数停在末点）
  double? _scrub;

  _Phase _phase = _Phase.idle;

  /// work 期间环的累计转角；进 work 归零，等价于 CSS 动画在加类那一刻起
  double _spinMs = 0;

  Timer? _work;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  int? _pointer;
  Offset? _downAt;
  bool _engaged = false;

  @override
  void initState() {
    super.initState();
    _s.jumpTo(0);
  }

  @override
  void dispose() {
    _dropRoute();
    _work?.cancel();
    _ticker?.stop();
    _ticker = null;
    _node.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 数据

  /// 三条 series，每条 34 点；后一条的首点就是前一条的末点
  static const _series = <List<double>>[
    [
      57630.15, 57672.02, 57697.31, 57740.67, 57829.15, 57881.9, 57875.25, 57871.44, //
      57841.43, 57824.68, 57957.03, 58078.61, 58095.22, 58136.25, 58156.95, 58113.65, //
      58180.3, 58394.72, 58518.55, 58536.23, 58450.89, 58354.12, 58489.6, 58573.06, //
      58508.69, 58536.64, 58594.77, 58647.64, 58668.57, 58682.61, 58720.06, 58743.78, //
      58784.11, 58834.75, //
    ],
    [
      58834.75, 58842.84, 58858.72, 58877.48, 58874.75, 58872.61, 58896.56, 58906.48, //
      58893.08, 58922.63, 58981.41, 58963.18, 58940.77, 59001.24, 59035.63, 59026.34, //
      59052.16, 59073.47, 59033.25, 59010.92, 58996.54, 58935.27, 58911.5, 58975.07, //
      59037.9, 59022.02, 59004.8, 59038.44, 59055.78, 59056.52, 59072.15, 59078.52, //
      59088.28, 59102.4, //
    ],
    [
      59102.4, 59086.9, 59077.06, 59068.52, 59055.95, 59019.04, 58999.47, 58975.1, //
      58903.86, 58916.98, 58989.57, 58926.11, 58763.26, 58683.68, 58727.54, 58778, //
      58758.83, 58718.66, 58682.76, 58709.66, 58792.35, 58782.87, 58692.33, 58598.58, //
      58598.77, 58672.38, 58655.19, 58615.97, 58621.85, 58624.03, 58595.53, 58549.14, //
      58523.68, 58516.05, //
    ],
  ];

  static const _windows = <_Window>[
    _Window('1H', 5, 'past hour'),
    _Window('4H', 17, 'past 4 hours'),
    _Window('1D', 34, 'today'),
  ];

  List<double> get _all => _series[_ticks % _series.length];

  /// 只看尾部 `take` 个点；`off` 是这段时间文案要的**首点在整条 series 上的下标**
  ///
  /// 时间轴是按整条 34 点铺的（09:00→17:30），换窗口只是换了读数窗口，
  /// 刻度不许跟着切片重新铺——否则 1H 的五点会被拉回 09:00 起。
  ({List<double> w, int off}) get _slice {
    final c = _all;
    final from = math.max(0, c.length - _windows[_win].take);
    return (w: c.sublist(from), off: from);
  }

  // ---------------------------------------------------------------- 指针

  void _onDown(PointerDownEvent e) {
    // 原稿：正在刷新、或者已经滚出顶部，都不接这个手势
    if (_phase == _Phase.work || _downAt != null) return;
    _downAt = e.position;
    _engaged = false;
  }

  void _onMove(PointerMoveEvent e) {
    final start = _downAt;
    if (start == null) return;
    final n = e.position.dy - start.dy;
    final r = e.position.dx - start.dx;
    if (!_engaged) {
      if (n < -_dead) {
        _downAt = null;
        return;
      }
      if (r.abs() > _dead && r.abs() > n.abs()) {
        _downAt = null;
        return;
      }
      if (n < _dead) return;
      _engaged = true;
      _pointer = e.pointer;
      GestureBinding.instance.pointerRouter.addRoute(e.pointer, _route);
      _scrub = null;
    }
    // 拖的时候贴手：`zf(..., immediate = hold)` 这一段不走弹簧
    setState(() {
      _phase = _Phase.hold;
      _s.jumpTo(_rubber(math.max(0, n)));
    });
  }

  void _onUp() {
    if (_downAt == null) return;
    _downAt = null;
    final wasEngaged = _engaged;
    _engaged = false;
    _dropRoute();
    if (!wasEngaged) return;
    if (_armed) {
      _startWork();
    } else {
      setState(() => _phase = _Phase.idle);
      _s.aim(0);
      _refresh();
    }
  }

  void _route(PointerEvent e) {
    if (e is PointerMoveEvent) {
      _onMove(e);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _onUp();
    }
  }

  void _dropRoute() {
    final p = _pointer;
    if (p == null) return;
    GestureBinding.instance.pointerRouter.removeRoute(p, _route);
    _pointer = null;
  }

  /// 橡皮筋：真实位移 `c` → 表观位移（要走 65.07px 才够 58 的阈值）
  double _rubber(double c) => _resist * c / (_resist + c);

  bool get _armed => math.max(0, _s.value) >= _threshold;

  void _startWork() {
    _work?.cancel();
    setState(() {
      _phase = _Phase.work;
      _spinMs = 0;
      _scrub = null;
    });
    // 原稿释放时先 `l(0)` 再进 work，两次 setState 同批落地，于是弹簧看见的目标
    // 直接是 threshold——不存在"先回 0 再去 58"
    _s.aim(_threshold);
    _refresh();
    _work = Timer(const Duration(milliseconds: _workMs), () {
      if (!mounted) return;
      setState(() {
        _ticks += 1;
        _phase = _Phase.idle;
      });
      _s.aim(0);
      _refresh();
    });
  }

  // ---------------------------------------------------------------- 发帧

  void _refresh() {
    final busy = !_s.atRest || _phase == _Phase.work;
    if (!busy) {
      _ticker?.stop();
      return;
    }
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      // 停过再起的 Ticker，elapsed 从零重算，对表值得跟着归零
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds.toDouble();
    _last = elapsed;
    if (_phase == _Phase.work) _spinMs += dt;
    _s.step(dt);
    if (mounted) setState(() {});
    _refresh();
  }

  // ---------------------------------------------------------------- 派生读数

  /// `--at`：弹簧冲出的负值被钳掉，下沉只看正
  double get _at => math.max(0, _s.value);

  /// `--grow`：负值在这儿露出来，卡片白底最薄 0px
  double get _grow {
    final o = _s.value;
    final a = o >= 0 ? _growSat * _tanh(o / _growSat) : math.max(-_growBase, o);
    return _growBase + a;
  }

  static double _tanh(double x) => (math.exp(2 * x) - 1) / (math.exp(2 * x) + 1);

  /// `--p`
  double get _progress => (_at / _threshold).clamp(0.0, 1.0);

  /// 环的半径与起始角：越拉越拢（15→12），同时整圈转 220°
  ({double radius, double angle}) get _ring {
    if (_phase == _Phase.work) return (radius: _ringR, angle: 0);
    final j = _progress;
    return (radius: _ringR + 3 - 3 * j, angle: j * 220);
  }

  _Readout get _readout {
    final w = _slice.w;
    final te = w.length - 1;
    final m = _scrub ?? te.toDouble();
    final lo = m.floor().clamp(0, te);
    final hi = math.min(te, m.ceil());
    final value = w[lo] + (w[hi] - w[lo]) * (m - lo);
    final delta = value - w.first;
    final chart = _Chart(w, 100, 40, 4);
    final off = _slice.off;
    return _Readout(
      chart,
      value,
      delta,
      (delta / w.first * 100).abs(),
      _scrub == null ? _windows[_win].span : _clock(off + m, _all.length),
      delta >= 0,
      chart.at(m),
    );
  }

  /// 轴映射：540 分钟起、跨 510 分钟（09:00 → 17:30）
  static String _clock(double m, int len) {
    final n = (540 + 510 * m / (len - 1)).round();
    return '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------- 绘制

  @override
  Widget build(BuildContext context) {
    return IlStage(
      height: _stageH,
      center: false,
      child: SizedBox(
        width: IlSize.stageW,
        height: _stageH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (IlSize.stageW - _cardW) / 2,
              top: _cardTop,
              child: _card(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    return SizedBox(
      width: _cardW,
      height: _sheetH + _grow,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_corner),
        child: ColoredBox(
          color: IlColor.pane,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: (_cardW - _gooBox) / 2, top: _ringY - _gooBox / 2, child: _gooLayer()),
              Positioned(left: 0, top: _at, width: _cardW, child: _scroll()),
            ],
          ),
        ),
      ),
    );
  }

  /// 液滴环压在内容层**底下**：不往下拽就根本看不见它
  Widget _gooLayer() {
    final ring = _ring;
    final working = _phase == _Phase.work;
    final p = working ? 1.0 : _progress;
    final spin = working ? _spinMs / _rpm * 360 : 0.0;
    return Opacity(
      opacity: p,
      child: Transform.rotate(
        angle: spin * math.pi / 180,
        child: Transform.scale(
          // work 那一档 CSS 把 scale 钉回 1
          scale: working ? 1 : 0.82 + p * 0.18,
          child: SizedBox(
            width: _gooBox,
            height: _gooBox,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < _dots; i++) _drop(i, ring.radius, ring.angle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _drop(int i, double radius, double angle) {
    final a = (i / _dots * 360 + angle) * math.pi / 180;
    return Positioned(
      left: _gooBox / 2 + math.sin(a) * radius - _dotSize / 2,
      top: _gooBox / 2 - math.cos(a) * radius - _dotSize / 2,
      width: _dotSize,
      height: _dotSize,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0x5717181A), // rgba(23,24,26,.34)
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _scroll() {
    final ro = _readout;
    return Focus(
      focusNode: _node,
      onKeyEvent: (node, event) {
        // 原稿 `role=group` + "Press Enter to refresh"
        if (event is KeyDownEvent &&
            _phase != _Phase.work &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          _startWork();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onUp(),
        onPointerCancel: (_) => _onUp(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: IlColor.pane,
            borderRadius: BorderRadius.circular(_corner),
            // `:focus-visible` 才有这圈；Listener 不抢焦点，所以鼠标点不亮它
            border: _node.hasFocus ? Border.all(color: IlColor.ink.withValues(alpha: 0.45), width: 2) : null,
          ),
          child: Semantics(
            container: true,
            label: 'Portfolio. Press Enter to refresh.',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_padX, _padT, _padX, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: _sumH, child: _sum(ro)),
                  const SizedBox(height: 9),
                  SizedBox(height: _moveH, child: _move(ro)),
                  const SizedBox(height: 22),
                  _plot(ro),
                  const SizedBox(height: 16),
                  _tabs(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _ts(double size, {Color? color, double? ls, double height = 1, double alpha = 1}) => TextStyle(
        fontFamily: IlFont.family,
        fontFamilyFallback: IlFont.fallback,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: ls,
        height: height,
        color: (color ?? IlColor.ink).withValues(alpha: alpha),
        fontFeatures: IlFont.tabular,
      );

  /// `$58,834.75`——整数 33px、小数 24px 且只有 34% 不透明度，同一条基线
  Widget _sum(_Readout ro) {
    final (intPart, decPart) = _split(ro.value);
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: _ts(_sumH, ls: -0.03 * _sumH),
          children: [
            // `.bal-cur{margin-right:2px}`：本档字距是 −.99，补 2px 就是 +1.01
            TextSpan(text: r'$', style: _ts(_sumH, ls: 2 - 0.03 * _sumH)),
            TextSpan(text: intPart),
            TextSpan(text: decPart, style: _ts(24, ls: -0.03 * 24, alpha: 0.34)),
          ],
        ),
      ),
    );
  }

  Widget _move(_Readout ro) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            // 负号是 U+2212，不是连字符
            '${ro.delta < 0 ? '−' : '+'}${_hv(ro.delta.abs())} · ${ro.percent.toStringAsFixed(1)}%',
            style: _ts(12.5, color: ro.up ? _textUp : _textDown, height: _moveH / 12.5),
          ),
          const SizedBox(width: 7),
          Text(ro.when, style: _ts(12.5, height: _moveH / 12.5, alpha: 0.42)),
        ],
      ),
    );
  }

  Widget _plot(_Readout ro) {
    final line = ro.up ? _lineUp : _lineDown;
    final scrubbing = _scrub != null;
    final x = ro.point.dx / 100 * _plotW;
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onExit: (_) {
        if (_downAt == null && !_engaged && _phase != _Phase.work && _scrub != null) {
          setState(() => _scrub = null);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // 原稿挂的是 `pointermove`——鼠标没按键也在图上扫，这里得连 hover 一起接
        onPointerDown: _scrubTo,
        onPointerMove: _scrubTo,
        onPointerHover: _scrubTo,
        child: SizedBox(
          width: _plotW,
          height: _plotH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: _plotPadY,
                width: _plotW,
                height: _svgH,
                child: CustomPaint(painter: _CurvePainter(ro.chart.path, line)),
              ),
              Positioned(
                // `.bal-guide`：上下各缩 6px，宽 1px 再退半格
                left: x,
                top: _plotPadY,
                child: IlTween(
                  target: scrubbing ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  curve: _cssEase,
                  builder: (context, v) => Transform.translate(
                    offset: const Offset(-0.5, 0),
                    child: Opacity(
                      opacity: 0.28 * v,
                      child: Container(width: 1, height: _svgH, color: line),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: x,
                // `top: calc(6px + (100% - 12px) * --tip)`，--tip = y/40
                top: _plotPadY + _svgH * (ro.point.dy / 40),
                child: IlTween(
                  target: scrubbing ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  curve: _tipEase,
                  builder: (context, v) => Transform.translate(
                    // 原稿是 9×9 的元素配 `box-shadow:0 0 0 2px`（圈在盒子**外面**），
                    // `margin:-4.5` 把 9 的盒心对到坐标上。Flutter 的 `Border.all`
                    // 画在盒内，所以这里退的是外沿一半（6.5），不是 4.5
                    offset: const Offset(-6.5, -6.5),
                    child: Transform.scale(
                      // 静止 1、扫读 1.18，绕自身中心
                      scale: 1 + 0.18 * v,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: IlColor.pane,
                          shape: BoxShape.circle,
                          // `box-shadow:0 0 0 2px` 不给颜色 = currentColor
                          border: Border.all(color: line, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrubTo(PointerEvent e) {
    // 按住下拉期间、以及刷新中，图上的扫读一律不响应
    if (_engaged || _phase == _Phase.work) return;
    final te = (_slice.w.length - 1).toDouble();
    final n = (e.localPosition.dx / _plotW).clamp(0.0, 1.0) * te;
    if (n == _scrub) return;
    setState(() => _scrub = n);
  }

  Widget _tabs() {
    return SizedBox(
      width: _plotW,
      height: _winH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: _tabW,
            height: _winH,
            child: IlTween(
              target: _win.toDouble(),
              duration: const Duration(milliseconds: 380),
              curve: _pillEase,
              builder: (context, v) => Transform.translate(
                // `translateX(calc(var(--win) * (100% + 4px)))`
                offset: Offset(v * (_tabW + 4), 0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x1217181A), // rgba(23,24,26,.07)
                    borderRadius: BorderRadius.all(Radius.circular(_tabCorner)),
                  ),
                  child: SizedBox(width: _tabW, height: _winH),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < _windows.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _TabButton(
                  label: _windows[i].label,
                  on: i == _win,
                  onTap: () {
                    if (i == _win) return;
                    _scrub = null;
                    setState(() => _win = i);
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间窗按钮：颜色 .2s 走缺省曲线，按下 .94 缩放走带 1.2 过冲的那条
class _TabButton extends StatefulWidget {
  const _TabButton({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: _Case06PullRefreshState._tabW,
          height: _Case06PullRefreshState._winH,
          child: IlTween(
            target: _down ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            curve: _Case06PullRefreshState._btnEase,
            builder: (context, v) => Transform.scale(
              scale: 1 - 0.06 * v,
              child: IlTween(
                target: widget.on || _hover ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: _Case06PullRefreshState._cssEase,
                builder: (context, c) => Center(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: IlFont.family,
                      fontFamilyFallback: IlFont.fallback,
                      fontSize: 12.5,
                      height: 19.5 / 12.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.01 * 12.5,
                      // 未选 .45 → 选中/悬停 1
                      color: IlColor.ink.withValues(alpha: 0.45 + 0.55 * c),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Yv(values, 100, 40, 4)`：x 按 index 线性铺，y 用**本窗口自己的** min/max 归一
///
/// 原稿把 path 每一位都 `toFixed(2)`，这里照做——于是画出来的曲线和参考稿
/// DOM 里那条 `d` 是同一串数字（测试按字符串比对）。
class _Chart {
  _Chart(List<double> v, double w, double h, double r)
      : _pts = _points(v, w, h, r) {
    final p = _pts;
    for (var i = 0; i < p.length - 1; i++) {
      final a = p[i], b = p[i + 1];
      final prev = i > 0 ? p[i - 1] : a;
      final next2 = i + 2 < p.length ? p[i + 2] : b;
      _segs.add(_Seg(
        a,
        Offset(a.dx + (b.dx - prev.dx) / 6, a.dy + (b.dy - prev.dy) / 6),
        Offset(b.dx - (next2.dx - a.dx) / 6, b.dy - (next2.dy - a.dy) / 6),
        b,
      ));
    }
    _d = StringBuffer('M${f(p.first.dx)} ${f(p.first.dy)}');
    for (final s in _segs) {
      _d.write(' C${f(s.c1.dx)} ${f(s.c1.dy)} ${f(s.c2.dx)} ${f(s.c2.dy)} ${f(s.end.dx)} ${f(s.end.dy)}');
    }
  }

  final List<Offset> _pts;
  final List<_Seg> _segs = [];
  late final StringBuffer _d;

  static List<Offset> _points(List<double> v, double w, double h, double r) {
    var lo = v.first, hi = v.first;
    for (final e in v) {
      if (e < lo) lo = e;
      if (e > hi) hi = e;
    }
    final span = hi == lo ? 1.0 : hi - lo;
    return [
      for (var i = 0; i < v.length; i++) //
        Offset(i / (v.length - 1) * w, h - r - (v[i] - lo) / span * (h - r * 2)),
    ];
  }

  static String f(double x) => x.toStringAsFixed(2);

  /// DOM 里那条 `d`
  String get d => _d.toString();

  /// 读数点：在**未取整**的控制点上做三次插值；位置跟着手指即时移动（原稿这儿没有过渡）
  Offset at(double m) {
    final i = m.floor().clamp(0, _segs.length - 1);
    return _segs[i].at((m - i).clamp(0.0, 1.0));
  }

  /// viewBox → CSS 像素（x 一档 2.96、y 一档 2.3）。先变换再描边，
  /// 正是 `non-scaling-stroke` 的口径：线宽不吃非等比缩放
  Path get path {
    const sx = 296 / 100, sy = 92 / 40;
    final p = Path()..moveTo(_pts.first.dx * sx, _pts.first.dy * sy);
    for (final s in _segs) {
      p.cubicTo(s.c1.dx * sx, s.c1.dy * sy, s.c2.dx * sx, s.c2.dy * sy, s.end.dx * sx, s.end.dy * sy);
    }
    return p;
  }
}

@immutable
class _Seg {
  const _Seg(this.start, this.c1, this.c2, this.end);
  final Offset start, c1, c2, end;

  Offset at(double t) {
    final u = 1 - t;
    return Offset(
      u * u * u * start.dx + 3 * u * u * t * c1.dx + 3 * u * t * t * c2.dx + t * t * t * end.dx,
      u * u * u * start.dy + 3 * u * u * t * c1.dy + 3 * u * t * t * c2.dy + t * t * t * end.dy,
    );
  }
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.path, this.color);

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        // `stroke-width:2.1px` + `vector-effect:non-scaling-stroke`
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.path != path || old.color != color;
}

/// `toLocaleString('en-GB',{min/maxFractionDigits:2})`——千分位逗号 + 两位小数
String _hv(double v) {
  final (i, d) = _split(v);
  return '$i$d';
}

/// `Uv`：整数串（带千分位）与含小数点的尾串——两者字号不同，必须分开
(String, String) _split(double v) {
  final s = v.toStringAsFixed(2);
  final dot = s.lastIndexOf('.');
  return (_group(s.substring(0, dot)), s.substring(dot));
}

String _group(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}
