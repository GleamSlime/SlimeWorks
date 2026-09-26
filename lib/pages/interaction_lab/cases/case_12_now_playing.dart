import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/material.dart';

import '../kit.dart';

/// 12 号 Now playing —— 一条 78 高的播放条，展开成 189 的完整播放器
///
/// 整块只有一个状态数：`v`（0→1，460ms quart-out）。盒高、圆角、封面、文字、进度条、
/// 操作组的圆心、每个按钮的边长、图标尺寸——全部读成 `mix(折叠值, 展开值, v)`。
/// 样式表里没有任何一条针对形状的 transition，所以这里也不许给哪一块单独起钟：
/// 少一个读数就说明有一处走了别的时间线。
///
/// 三条附属时间线，各自独立：
/// - 晚到内容 `k = clamp((v-.6)/.4,0,1)`：时间和喜欢只走最后 40%（quart-out 起手极快，
///   换算成墙钟大约 72ms 之后才开始出现）。进度条本身不淡入，靠盒子的 `overflow:hidden` 裁。
/// - 播放/暂停是**画**出来的形变，不是切换：300ms in-out cubic，两条四边形从双竖条插值到
///   三角，同时 `sin(πt)` 包络驱动 `rotate ∓9°`、`scale(.87x, 1.11y)`、两半各自靠拢 1.6。
///   包络两端严格为 0 → 连点两次落回原样。
/// - 落位回弹只给折叠方向：同一段时长的**线性**读数 `y`，`scale = 1 - .035·sin(π·y^1.5)`
///   → 最低 0.965，`y^1.5` 把峰值推到 63% 那一拍（越位越晚，落地时才收得住）。展开时恒 1。
///
/// 三处刻意没照抄：
/// - 封面原稿是一张 464×464 的照片，仓库不引外部位图，这里自己画一张同色重的封套
///   （长春花底 + 柠檬绿光晕 + 一枚橙红主体）。`background-size:cover` 落在正方形上
///   等价于按 0..1 归一画，所以封套跟着尺寸一起长。
/// - `backdrop-filter: blur(2px) saturate(150%)` 在 flat 档底下是纯色，糊了等于没糊。
/// - `:focus-visible` 那圈双环和点击音效（expand/off/click）不属于视觉复刻。
class Case12NowPlaying extends StatefulWidget {
  const Case12NowPlaying({super.key});

  @override
  State<Case12NowPlaying> createState() => _Case12NowPlayingState();
}

class _Case12NowPlayingState extends State<Case12NowPlaying> with SingleTickerProviderStateMixin {
  // ---- 几何：全部字面值，这一格不读全局主题
  static const _w = 260.0;
  static const _hCollapsed = 78.0;
  static const _hExpanded = 189.0;
  static const _inset = 10.0;

  static const _art0 = 40.0;
  static const _art1 = 64.0;
  static const _artR0 = 10.0; // 封面圆角 = .625·corner → corner
  static const _artR1 = 16.0;
  static const _boxR0 = 20.0; // 盒圆角 = 封面圆角 + 同心偏移 10
  static const _boxR1 = 26.0;

  static const _sayL0 = 60.0;
  static const _sayL1 = 84.0;
  static const _sayW0 = 94.0;
  static const _sayW1 = 126.0;
  static const _titleFs0 = 13.0;
  static const _titleFs1 = 15.5;
  static const _byFs0 = 11.0;
  static const _byFs1 = 12.0;

  static const _barTop0 = 65.0;
  static const _barTop1 = 96.0;
  static const _barW = 240.0;
  static const _railH = 3.0;
  static const _barGap = 8.0;
  static const _clockFs = 10.5;

  static const _tapW0 = 260.0;
  static const _tapW1 = 240.0;
  static const _tapH1 = 64.0;

  static const _likeL = 220.0;
  static const _likeS = 30.0;

  static const _opsX0 = 206.0;
  static const _opsX1 = 130.0;
  static const _opsY0 = 30.0;
  static const _opsY1 = 156.0;
  static const _op0 = 24.0;
  static const _op1 = 34.0;
  static const _lead0 = 30.0;
  static const _lead1 = 46.0;
  static const _gap0 = 5.0;
  static const _gap1 = 14.0;
  static const _icon0 = 13.0;
  static const _icon1 = 16.0;
  static const _ppIcon0 = 14.0;
  static const _ppIcon1 = 18.0;

  // ---- 时间线
  static const _dur = 460.0;
  static const _ppDur = 300.0;
  static const _beatDur = 340.0;
  static const popCurve = Cubic(0.3, 0.9, 0.4, 1); // 缩放 .13s
  static const cssEase = Cubic(0.25, 0.1, 0.25, 1); // 颜色/底色 .16s（CSS 默认 ease）
  static const _beatCurve = Cubic(0.3, 1.4, 0.5, 1);

  static const _pressTo = 0.96; // 按住开合热区时封面缩这一档
  static const _opPressTo = 0.9;
  static const _bounceTo = 0.035;

  // ---- 配色（`--rail`/`--hover` 两档水洗只有这一格用，就地给字面值）
  static const _railWash = 0.12;
  static const _hoverWash = 0.07;

  static const _total = 214;
  static const _title = 'Cabra Field';
  static const _by = 'Side B';

  /// lucide `skip-back` / `skip-forward` / `heart`，viewBox 24 / stroke 2
  static const _backPath = [
    'M17.971 4.285A2 2 0 0 1 21 6v12a2 2 0 0 1-3.029 1.715l-9.997-5.998a2 2 0 0 1-.003-3.432z', //
    'M3 20V4',
  ];
  static const _fwdPath = [
    'M21 4v16', //
    'M6.029 4.285A2 2 0 0 0 3 6v12a2 2 0 0 0 3.029 1.715l9.997-5.998a2 2 0 0 0 .003-3.432z',
  ];
  static const _heartPath = [
    'M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5' //
    'c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5',
  ];

  // ---- 状态：折叠、暂停、没喜欢，进度停在 0:52
  bool _open = false;
  bool _playing = false;
  bool _liked = false;
  int _sec = 52;
  Timer? _second;
  Ticker? _ticker;
  Duration _last = Duration.zero;

  final _Morph _m = _Morph(0, _dur);
  late final _Twn _pp = _Twn(1, dur: _ppDur, curve: const _InAndOut());
  late final _Twn _artPress = _Twn(0, dur: 130, curve: popCurve);
  final _Pulse _beat = _Pulse(dur: _beatDur, curve: _beatCurve);

  /// 喜欢的变色是 `[data-on]` 那条 `color .16s`，和 hover 那条共用一个终值
  /// 但不共用一根钟：两条各走各的，取大的那一头
  final _Twn _likeCol = _Twn(0, dur: 160, curve: cssEase);
  final _OpFx _prev = _OpFx();
  final _OpFx _lead = _OpFx();
  final _OpFx _next = _OpFx();
  final _OpFx _likeFx = _OpFx();

  @override
  void dispose() {
    _second?.cancel();
    _ticker?.stop();
    super.dispose();
  }

  // ---- 交互

  void _toggleOpen() {
    setState(() => _open = !_open);
    _m.aim(_open ? 1 : 0);
    _kick();
  }

  /// 点盒子外面才收起：盒子内部（进度条那片）落下去什么都不做
  void _outside() {
    if (_open) _toggleOpen();
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    _pp.aim(_playing ? 0 : 1);
    _kick();
    _syncSecond();
  }

  /// 进度是 1Hz **阶跃**，不是补间：一秒一跳，跳到 214 归零
  void _syncSecond() {
    _second?.cancel();
    _second = null;
    if (!_playing) return;
    _second = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _sec = _sec >= _total ? 0 : _sec + 1);
    });
  }

  void _toStart() => setState(() => _sec = 0);

  void _toggleLike() {
    setState(() => _liked = !_liked);
    _likeCol.aim(_liked ? 1 : 0);
    // 动画挂在 `[data-on]` 上：只有"变成喜欢"那一回才重播，取消喜欢不重播
    if (_liked) _beat.fire();
    _kick();
  }

  // ---- 一帧只走一根钟

  void _kick() {
    _ticker ??= createTicker(_tick);
    if (!_ticker!.isActive) {
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _tick(Duration e) {
    final dt = (e - _last).inMilliseconds.toDouble();
    _last = e;
    var live = false;
    live |= _m.step(dt);
    live |= _pp.step(dt);
    live |= _artPress.step(dt);
    live |= _beat.step(dt);
    live |= _likeCol.step(dt);
    for (final fx in [_prev, _lead, _next, _likeFx]) {
      live |= fx.step(dt);
    }
    setState(() {});
    if (!live) _ticker!.stop();
  }

  // ---- 树

  @override
  Widget build(BuildContext context) {
    final v = _m.v;
    final boxH = _mix(_hCollapsed, _hExpanded, v);
    final boxR = _mix(_boxR0, _boxR1, v);
    final art = _mix(_art0, _art1, v);
    final tapSide = _mix(0, _inset, v);
    final k = ((v - 0.6) / 0.4).clamp(0.0, 1.0);

    // 回弹只吃线性读数，而且只在折叠那一头：展开时盒子从 78 长到 189 本身就是事件
    final y = _m.y.clamp(0.0, 1.0);
    final bounce = _env(math.pow(y, 1.5).toDouble());
    final scale = _open ? 1.0 : 1 - _bounceTo * bounce;

    return IlStage(
      center: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('outside'),
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _outside(),
            ),
          ),
          Align(
            child: SizedBox(
              width: _w,
              height: _hExpanded,
              child: Align(
                child: Transform(
                  key: const ValueKey('box-xf'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(0, 0, scale)
                    ..setEntry(1, 1, scale),
                  child: DecoratedBox(
                    key: const ValueKey('box'),
                    decoration: BoxDecoration(
                      color: IlColor.pane,
                      borderRadius: BorderRadius.circular(boxR),
                      // `[data-stroke=on] .snd-box{ box-shadow:0 0 0 1px var(--pane-edge) }`
                      boxShadow: const [
                        BoxShadow(color: IlColor.paneEdge, blurRadius: 0, spreadRadius: 1),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(boxR),
                      child: SizedBox(
                        key: const ValueKey('box-h'),
                        width: _w,
                        height: boxH,
                        child: Stack(
                          children: [
                            _hitBody(),
                            _art(art, _mix(_artR0, _artR1, v)),
                            _say(art, v),
                            _bar(_mix(_barTop0, _barTop1, v), k),
                            _tap(tapSide),
                            _like(_likeS, k),
                            _ops(v),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 盒子内部的落点吸收层：原稿的"点外面收起"判据是 `!box.contains(target)`，
  /// 点在盒子下半截（进度条那片）不该被当成点外面
  Widget _hitBody() {
    return Positioned.fill(
      child: GestureDetector(
        key: const ValueKey('box-hit'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {},
      ),
    );
  }

  Widget _art(double size, double radius) {
    return Positioned(
      key: const ValueKey('art'),
      left: _inset,
      top: _inset,
      width: size,
      height: size,
      child: Transform(
        key: const ValueKey('art-xf'),
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(0, 0, _mix(1, _pressTo, _artPress.v))
          ..setEntry(1, 1, _mix(1, _pressTo, _artPress.v)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            size: Size.square(size),
            painter: _Sleeve(size: size),
          ),
        ),
      ),
    );
  }

  Widget _say(double artH, double v) {
    final titleFs = _mix(_titleFs0, _titleFs1, v);
    final byFs = _mix(_byFs0, _byFs1, v);
    return Positioned(
      key: const ValueKey('say'),
      left: _mix(_sayL0, _sayL1, v),
      top: _inset,
      width: _mix(_sayW0, _sayW1, v),
      height: artH,
      child: IgnorePointer(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _title,
                key: const ValueKey('title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: IlFont.family,
                  fontFamilyFallback: IlFont.fallback,
                  fontSize: titleFs,
                  height: 1.25,
                  letterSpacing: -0.01 * titleFs,
                  fontWeight: FontWeight.w500,
                  color: IlColor.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _by,
                key: const ValueKey('by'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: IlFont.family,
                  fontFamilyFallback: IlFont.fallback,
                  fontSize: byFs,
                  height: 1.25,
                  color: IlColor.ink4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double top, double k) {
    return Positioned(
      key: const ValueKey('bar'),
      left: _inset,
      top: top,
      width: _barW,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _barW,
              height: _railH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ilWash(_railWash),
                  borderRadius: BorderRadius.circular(_railH / 2),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    key: const ValueKey('run'),
                    width: _barW * _sec / _total,
                    height: _railH,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: IlColor.ink,
                        borderRadius: BorderRadius.all(Radius.circular(_railH / 2)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _barGap),
            Opacity(
              key: const ValueKey('clock'),
              opacity: k,
              child: SizedBox(
                width: _barW,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_clock(_sec), style: _clockStyle()),
                    // 原稿前缀是 U+2212 减号，不是 ASCII 连字符
                    Text('\u2212${_clock(_total - _sec)}', style: _clockStyle()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _clockStyle() => TextStyle(
        fontFamily: IlFont.family,
        fontFamilyFallback: IlFont.fallback,
        fontSize: _clockFs,
        height: 1,
        letterSpacing: 0.04 * _clockFs,
        color: IlColor.ink4,
        fontFeatures: IlFont.tabular,
      );

  static String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  /// `.snd-tap`：折叠时盖住整条，展开时只剩封面那一片
  Widget _tap(double side) {
    return Positioned(
      key: const ValueKey('tap'),
      left: side,
      top: side,
      width: _mix(_tapW0, _tapW1, _m.v),
      height: _mix(_hCollapsed, _tapH1, _m.v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            _artPress.aim(1);
            _kick();
          },
          onTapUp: (_) => _artPress.aim(0),
          onTapCancel: () => _artPress.aim(0),
          onTap: _toggleOpen,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _like(double size, double k) {
    final color = Color.lerp(IlColor.ink3, IlColor.ink, math.max(_likeFx.hov.v, _likeCol.v))!;
    final press = _mix(1, _opPressTo, _likeFx.prs.v);
    return Positioned(
      key: const ValueKey('like'),
      left: _likeL,
      top: _inset,
      width: size,
      height: size,
      child: Opacity(
        key: const ValueKey('like-a'),
        opacity: k,
        child: IgnorePointer(
          key: const ValueKey('like-hit'),
          ignoring: k <= 0.9,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              _likeFx.hov.aim(1);
              _kick();
            },
            onExit: (_) {
              _likeFx.hov.aim(0);
              _kick();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                _likeFx.prs.aim(1);
                _kick();
              },
              onTapUp: (_) => _likeFx.prs.aim(0),
              onTapCancel: () => _likeFx.prs.aim(0),
              onTap: _toggleLike,
              child: Transform(
                key: const ValueKey('like-xf'),
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(0, 0, press)
                  ..setEntry(1, 1, press),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ilWash(_hoverWash * _likeFx.hov.v),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Center(
                      child: Transform(
                        key: const ValueKey('beat'),
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(0, 0, _beat.value)
                          ..setEntry(1, 1, _beat.value),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          // 原稿是同一个 path 先 fill 再 stroke：填色层只在做客时垫在下面
                          child: Stack(
                            children: [
                              if (_liked)
                                const Positioned.fill(
                                  child: IlIcon(
                                    paths: _heartPath,
                                    size: 16,
                                    viewBox: 24,
                                    strokeWidth: 2,
                                    filled: true,
                                  ),
                                ),
                              Positioned.fill(
                                child: IlIcon(
                                  paths: _heartPath,
                                  size: 16,
                                  viewBox: 24,
                                  strokeWidth: 2,
                                  color: color,
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
          ),
        ),
      ),
    );
  }

  Widget _ops(double v) {
    final op = _mix(_op0, _op1, v);
    final lead = _mix(_lead0, _lead1, v);
    final gap = _mix(_gap0, _gap1, v);
    final icon = _mix(_icon0, _icon1, v);
    final tw = op * 2 + lead + gap * 2;
    return Positioned(
      key: const ValueKey('ops'),
      // 原稿是 `left/top` 定圆心 + `translate:-50% -50%`，这里直接把左上角算出来
      left: _mix(_opsX0, _opsX1, v) - tw / 2,
      top: _mix(_opsY0, _opsY1, v) - lead / 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _op('op-prev', op, _prev, onTap: _toStart, child: IlIcon(
                paths: _backPath, size: icon, viewBox: 24, strokeWidth: 2, color: _inkOf(_prev),
              )),
          SizedBox(width: gap),
          _op('op-lead', lead, _lead, lead: true, onTap: _togglePlay, child: PlayPauseGlyph(
                key: const ValueKey('pp'),
                r: _pp.v,
                rotDeg: (_playing ? -9 : 9) * _env(_pp.v),
                size: _mix(_ppIcon0, _ppIcon1, v),
                color: IlColor.pane,
              )),
          SizedBox(width: gap),
          _op('op-next', op, _next, onTap: _toStart, child: IlIcon(
                paths: _fwdPath, size: icon, viewBox: 24, strokeWidth: 2, color: _inkOf(_next),
              )),
        ],
      ),
    );
  }

  Color _inkOf(_OpFx fx) => Color.lerp(IlColor.ink3, IlColor.ink, fx.hov.v)!;

  Widget _op(
    String key,
    double size,
    _OpFx fx, {
    required VoidCallback onTap,
    required Widget child,
    bool lead = false,
  }) {
    final press = _mix(1, _opPressTo, fx.prs.v);
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        key: ValueKey('$key-a'),
        // 主按钮的 hover 是整颗 `opacity:.88`，底色和图标一起淡
        opacity: lead ? 1 - 0.12 * fx.hov.v : 1,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            fx.hov.aim(1);
            _kick();
          },
          onExit: (_) {
            fx.hov.aim(0);
            _kick();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) {
              fx.prs.aim(1);
              _kick();
            },
            onTapUp: (_) => fx.prs.aim(0),
            onTapCancel: () => fx.prs.aim(0),
            onTap: onTap,
            child: Transform(
              key: ValueKey('$key-xf'),
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(0, 0, press)
                ..setEntry(1, 1, press),
              child: DecoratedBox(
                key: ValueKey(key),
                decoration: BoxDecoration(
                  color: lead ? IlColor.ink : ilWash(_hoverWash * fx.hov.v),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: size, height: size, child: Center(child: child)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _mix(double a, double b, double t) => a + (b - a) * t;

/// 共用包络 `sin(πr)`，但两端钉死为 0
///
/// Dart 的 `sin(π)` 是 1.2e-16 而不是 0，直接拿它当"形变一定落回原样"的那个数，
/// 读数里就会留一条永远归不了零的尾巴（旋转角、靠拢量都跟着抖那一丁点）。
double _env(double r) => (r <= 0 || r >= 1) ? 0 : math.sin(math.pi * r);

/// 封套：仓库不引外部位图，所以按参考照片的色重自己画一张
///
/// 画在 0..1 的归一坐标里，`background-size:cover` 落在正方形上就是"跟着边长一起长"，
/// 40 和 64 两档看到的是同一张图。
class _Sleeve extends CustomPainter {
  _Sleeve({required this.size});

  final double size;

  static const _field = Color(0xFFB0B5CE);
  static const _fieldDeep = Color(0xFF9BA0BC);
  static const _lime = Color(0xFFC3D94F);
  static const _body = Color(0xFFF0703F);
  static const _bodyDeep = Color(0xFFE2552B); // 尾段压深一档，参考图的分节感

  @override
  void paint(Canvas canvas, Size s) {
    final box = Offset.zero & s;
    final k = s.width;
    canvas.drawRect(
      box,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.53, -0.85),
          end: Alignment(0.53, 0.85),
          colors: [_field, _fieldDeep],
        ).createShader(box),
    );

    // 整张参考图都是气笔颗粒，没有一条硬轮廓，所以每一块都带模糊
    const tilt = -0.62; // 身体从左上斜到右下

    // 光晕：柠檬绿一大团，压在中心偏上
    _halo(canvas, Offset(k * 0.5, k * 0.46), k * 0.44, _lime, 0.85, k * 0.12);

    // 两片翅：右上、左下各一片，长轴和身体平行
    _smudge(canvas, Offset(k * 0.63, k * 0.29), k * 0.42, k * 0.17, tilt, _lime, 0.95, k * 0.07);
    _smudge(canvas, Offset(k * 0.36, k * 0.64), k * 0.36, k * 0.15, tilt, _lime, 0.9, k * 0.07);
    // 翅根到身体之间那一段发白的亮绿：喷枪叠出来的高光
    _halo(canvas, Offset(k * 0.47, k * 0.42), k * 0.17, const Color(0xFFE4F08A), 0.9, k * 0.06);

    // 身体：头、胸、腹三段沿同一条斜线叠出来。翅的长轴是"左下↔右上"，
    // 身体是"左上↔右下"，所以两者旋转方向相反
    const tiltBody = 0.62;
    _smudge(canvas, Offset(k * 0.38, k * 0.34), k * 0.16, k * 0.14, tiltBody, _body, 1, k * 0.03);
    _smudge(canvas, Offset(k * 0.48, k * 0.45), k * 0.19, k * 0.16, tiltBody, _body, 1, k * 0.03);
    _smudge(canvas, Offset(k * 0.585, k * 0.565), k * 0.2, k * 0.13, tiltBody, _bodyDeep, 0.95, k * 0.03);
  }

  /// 一团带软边的径向渐变：光晕和高光用它
  void _halo(Canvas c, Offset at, double r, Color color, double alpha, double blur) {
    final rect = Rect.fromCircle(center: at, radius: r);
    c.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  /// 一枚斜放的实心软边椭圆：翅和身体都是它
  void _smudge(
    Canvas c,
    Offset at,
    double w,
    double h,
    double rot,
    Color color,
    double alpha,
    double blur,
  ) {
    c
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(rot)
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_Sleeve old) => old.size != size;
}

/// 播放/暂停两端四边形的四个顶点（viewBox 24×24）
const _pauseL = <double>[6, 4, 10, 4, 10, 20, 6, 20];
const _playL = <double>[6.5, 4, 13.25, 8, 13.25, 16, 6.5, 20];
const _pauseR = <double>[14, 4, 18, 4, 18, 20, 14, 20];

/// 右半在播放端**退化成一条线**：第 2、3 个顶点重合，这就是"三角的右半边"
const _playR = <double>[13.25, 8, 20, 12, 20, 12, 13.25, 16];

/// 播放/暂停：两条四边形从双竖条插值到三角，外面再套一层包络
class PlayPauseGlyph extends StatelessWidget {
  const PlayPauseGlyph({
    super.key,
    required this.r,
    required this.rotDeg,
    required this.size,
    required this.color,
  });

  /// 0 = 暂停（双竖条），1 = 播放（三角）
  final double r;
  final double rotDeg;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PlayPausePainter(r: r, rotDeg: rotDeg, color: color),
    );
  }
}

class _PlayPausePainter extends CustomPainter {
  _PlayPausePainter({required this.r, required this.rotDeg, required this.color});

  final double r;
  final double rotDeg;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    // goo 包络：两端严格为 0 → 连点两次一定落回原样
    final goo = _env(r);
    final shift = 1.6 * goo;
    canvas
      ..translate(s.width / 2, s.height / 2)
      ..rotate(rotDeg * math.pi / 180)
      ..scale(1 - 0.13 * goo, 1 + 0.11 * goo)
      ..translate(-s.width / 2, -s.height / 2)
      ..scale(s.width / 24);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // CSS 那边 fill 和 stroke 是同一个 currentColor，描出来等于把形状外扩 1px
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final p in [
      _quad(_pauseL, _playL, shift),
      _quad(_pauseR, _playR, -shift),
    ]) {
      canvas
        ..drawPath(p, fill)
        ..drawPath(p, line);
    }
  }

  Path _quad(List<double> a, List<double> b, double dx) {
    final path = Path()..moveTo(_mix(a[0], b[0], r) + dx, _mix(a[1], b[1], r));
    for (var i = 2; i < 8; i += 2) {
      path.lineTo(_mix(a[i], b[i], r) + dx, _mix(a[i + 1], b[i + 1], r));
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_PlayPausePainter old) =>
      old.r != r || old.rotDeg != rotDeg || old.color != color;
}

/// `zx`：in-out cubic（`e < .5 ? 4e³ : 1 - (-2e+2)³/2`）
///
/// 不用 `Cubic(.65,0,.35,1)` 那条贝塞尔近似——原稿给的就是这条闭式函数。
class _InAndOut extends Curve {
  const _InAndOut();

  @override
  double transformInternal(double t) {
    final u = -2 * t + 2;
    return t < 0.5 ? 4 * t * t * t : 1 - u * u * u / 2;
  }
}

/// 主进度：一根补间同时给出两条读数
///
/// 原稿是两个 tween 实例（quart-out 和线性）跑同一段时长。合在一个对象里算是为了
/// 同表同停——分头 aim 会让回弹的峰值和形状的落位错开一帧。
class _Morph {
  _Morph(double to, this.dur)
      : _from = to,
        _to = to,
        v = to,
        y = to;

  final double dur;
  double _from;
  double _to;
  double _e = 0;
  bool _run = false;

  /// quart-out：`1 - (1-t)⁴`，起手极快、全程不过冲
  double v;

  /// 线性读数，只给落位回弹用
  double y;

  /// 每次都从当前值重起一段完整时长（原稿那条补间就是这个语义），目标没变也照跑
  void aim(double target) {
    _from = v;
    _to = target;
    _e = 0;
    _run = _from != _to;
  }

  bool step(double dt) {
    if (!_run) return false;
    _e += dt;
    final p = (_e / dur).clamp(0.0, 1.0);
    v = _from + (_to - _from) * (1 - math.pow(1 - p, 4));
    y = _from + (_to - _from) * p;
    if (p >= 1.0) {
      v = _to;
      y = _to;
      _run = false;
    }
    return _run;
  }
}

/// 值到值的定时补间（原稿每条都是一个 `transition`）
class _Twn {
  _Twn(double from, {required double dur, required Curve curve})
      : _v = from,
        _from = from,
        _to = from,
        _dur = dur,
        _curve = curve;

  double _v;
  double _from;
  double _to;
  double _e = 0;
  final double _dur;
  final Curve _curve;
  bool _running = false;

  double get v => _v;

  /// 目标没变就别重起：悬停这类每帧重发同值会把钟永远清零
  void aim(double target) {
    if (_to == target) return;
    _from = _v;
    _to = target;
    _e = 0;
    _running = true;
  }

  bool step(double dt) {
    if (!_running) return false;
    _e += dt;
    final p = (_e / _dur).clamp(0.0, 1.0);
    _v = _from + (_to - _from) * _curve.transform(p);
    if (p >= 1.0) {
      _v = _to;
      _running = false;
    }
    return _running;
  }
}

/// 一次性脉冲：`@keyframes` 三段（1 → 1.34 @38% → 1）
///
/// CSS 的 `animation-timing-function` 是**逐段**生效的，不是整条动画一次，
/// 所以这里也得按 38% 切成两段各吃一次曲线。
class _Pulse {
  _Pulse({required double dur, required Curve curve})
      : _dur = dur,
        _curve = curve;

  final double _dur;
  final Curve _curve;
  double _e = 0;
  bool _on = false;

  double value = 1;

  void fire() {
    _e = 0;
    _on = true;
  }

  bool step(double dt) {
    if (!_on) return false;
    _e += dt;
    final p = (_e / _dur).clamp(0.0, 1.0);
    if (p >= 1.0) {
      value = 1;
      _on = false;
    } else {
      value = p <= 0.38
          ? 1 + 0.34 * _curve.transform(p / 0.38)
          : 1.34 - 0.34 * _curve.transform((p - 0.38) / 0.62);
    }
    return _on;
  }
}

/// 一颗操作钮的两条 CSS transition：颜色/底色 .16s，缩放 .13s
class _OpFx {
  _OpFx()
      : hov = _Twn(0, dur: 160, curve: _Case12NowPlayingState.cssEase),
        prs = _Twn(0, dur: 130, curve: _Case12NowPlayingState.popCurve);

  final _Twn hov;
  final _Twn prs;

  /// 两条都得走：`||` 会在 hover 还活着的那几十毫秒里整个跳过 press，
  /// 于是"悬停着按住"这一档缩放根本不动
  bool step(double dt) => hov.step(dt) | prs.step(dt);
}

