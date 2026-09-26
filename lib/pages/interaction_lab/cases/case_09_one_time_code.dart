import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show ImageFilter;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyEvent, KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;

import '../kit.dart';

/// 9. One-time code — 四格验证码：填满先呼吸一遍，对了融成胶囊，错了抖散
///
/// 参考稿这个块没有 `demo` 字段，全靠敲键盘，所以组件本体只有 165×44 一行
/// （`4*36 + 3*7`），没有背景、没有边框。四格和胶囊共用一个 `filter:url(#goo)`
/// 的底：**blur σ=3 → alpha 走 `24a-12` 的硬阈值**（α<0.5 全透），所以格子
/// 靠近到 6px 以内会真的"拉丝接上"，融合过程看着像两坨白互相吸过去。
///
/// 状态机 `type → check → ok|no → type`，两条弹簧都是原稿那对**离散**迭代
/// （`v += (to-x)*k*r; v *= d**r; x += v*r`，`r = 首帧 1、之后 clamp(dt/16.67, 0, 2.5)`）：
/// - 融合 `HS = {k:.075, d:1-.84*√.075 = .7699565}`，阈值 8e-4 → 60fps 下约 50 帧到位，
///   峰值 `m = 1.157`。**`k` 被截到 1，但 `m` 不截**：胶囊宽高用的是未截断的 `m-1`，
///   于是接近到位时先"窄一点、高一点"（scaleY 最高 1.066）再落回，这就是手感来源。
/// - 光标 `{k:.2, d:.62}`，阈值 .05，目标 `min(字数,3)*43 + 18` → 18/61/104/147；
///   `scaleX = 1 + min(5, |v|*.9)`，追得越快光标越宽（上限 6 倍）。
///
/// 三条时间线：填满后 **420ms** 才出结论；check 期间一道 900ms 周期的横波逐个压扁
/// 格子（`1 → .93 → 1`，每格窗口宽 2 格）；判错则 620ms 抖动（振幅 5px、τ=190ms、
/// 10Hz、每格相位 +0.55rad），960ms 后整串清空回 type。
///
/// **最容易照错的是数字掉落**：`otp-in` 带 `animation-fill-mode: both`，跑完之后
/// `opacity:1 / transform:none / filter:none` 会**永久钉住这一层**——CSS 层叠里
/// 动画声明压过作者声明，内联的 `opacity: 1-a` 根本吃不到。作者改用独立的
/// `translate` 属性才躲过这一手，所以错态的数字是**只往下掉 8px、不淡出**，
/// 到 960ms 才随整串清空一起消失。同理 `otp-ok` 用的也是 `scale:` 而不是 `transform:`。
///
/// 参考稿还有 `Length`（4/6）和 `Corner`（0–22）两个旋钮，那是演示站的设备，
/// 这一格钉默认档：4 格、静止圆角 12、融合终点恒 22。`Answer` 旋钮的 Reject 档
/// 由测试挂 [reject] 拍图，页面上走默认的 Accept。
class Case09OneTimeCode extends StatefulWidget {
  const Case09OneTimeCode({super.key, this.reject = false});

  /// true = 走参考稿 `Answer=Reject` 那档（抖动 + 掉落）
  final bool reject;

  @override
  State<Case09OneTimeCode> createState() => _Case09OneTimeCodeState();
}

enum _Phase { type, check, ok, no }

class _Case09OneTimeCodeState extends State<Case09OneTimeCode> with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------- 量出来的尺寸

  static const _cells = 4; // `RS=36` 格宽、`zS=44` 行高、`BS=7` 间距、`VS=128` 胶囊上限
  static const _cellW = 36.0;
  static const _rowH = 44.0;
  static const _gap = 7.0;
  static const _step = _cellW + _gap; // 43
  static const _rowW = _cells * _cellW + (_cells - 1) * _gap; // 165

  /// `(a - RS)/2`：四格融合之后共同的左边距
  static const _mergedX = (_rowW - _cellW) / 2; // 64.5
  static const _pillMax = 128.0;

  /// `corner` 默认 12，融合终点是 `zS/2` = 22
  static const _corner = 12.0;
  static const _cornerFull = _rowH / 2;

  /// goo 底要往外多留一圈：blur σ=3 的可见尾巴约 3σ，滤镜区原稿给的 −50%/200%
  static const _gooPad = 24.0;

  // ---------------------------------------------------------------- 时间线

  static const _checkMs = 420.0; // 填满到出结论
  static const _waveMs = 900.0; // check 期呼吸波周期
  static const _shakeMs = 620.0; // `US`
  static const _resetMs = _shakeMs + _cells * 45 + 160; // 960
  static const _entryMs = 300.0; // `otp-in`
  static const _dropLeadMs = 300.0;
  static const _dropStaggerMs = 45.0;
  static const _dropDurMs = 220.0;
  static const _dropDy = 8.0;
  static const _fadeMs = 160.0; // 光标 transition:opacity .16s
  static const _breatheMs = 1100.0; // `1.1s ... alternate`

  // ---------------------------------------------------------------- 颜色与字

  static const _slab = IlColor.pane; // `--fill-slab`
  static const _on = IlColor.ink; // `--fill-on`
  static const _err = Color(0xFFE5484D); // 错态数字色是字面量，不走变量

  static const _digitStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 19,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: -0.19, // -.01em
    color: _on,
    fontFeatures: IlFont.tabular,
  );

  static const _okStyle = TextStyle(
    fontFamily: IlFont.family,
    fontFamilyFallback: IlFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1,
    color: _on,
  );

  /// lucide `check`：viewBox 24，path `M20 6 9 17l-5-5`，size 14 / strokeWidth 2.4
  static const _checkPath = ['M20 6 9 17l-5-5'];

  /// `feGaussianBlur stdDeviation=3` + `feColorMatrix` 的 alpha 行 `0 0 0 24 -12`。
  /// 平移列在 Flutter 这边是 **0..255 未归一**，所以 −12 要写成 −12*255；
  /// 写 −12 的话阈值会掉到 α≈0.002，整层等于没滤。
  static final Float64List _gooRamp = Float64List.fromList([
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 24, -12 * 255, //
  ]);

  // ---------------------------------------------------------------- 状态

  _Phase _phase = _Phase.type;
  String _code = '';
  bool _focused = false;

  /// 组件自己的单调时钟（毫秒）：呼吸波、抖动相位、掉落、两段延迟全按它算。
  /// 用 Ticker 累计而不是 `Timer`：延迟在 test 收尾时还挂着会报 "Timer is still pending"。
  double _now = 0;
  double _checkWait = 0;
  double _noWait = 0;

  /// 每格 `otp-in` 的起跑时刻（null = 这一格没有在跑）
  final List<double?> _entryAt = [null, null, null, null];

  /// 融合弹簧与光标弹簧
  late final _Sp _merge = _Sp(k: 0.075, d: 1 - 0.84 * math.sqrt(0.075), rest: 8e-4);
  late final _Sp _caret = _Sp(k: 0.2, d: 0.62, x: _cellW / 2, rest: 0.05);

  late final _Twn _red = _Twn(0, dur: _fadeMs, curve: _cssEase);

  /// 光标：`data-on` 为真时走呼吸，关掉之后按 160ms 淡出
  bool _caretOn = false;
  double _caretSince = 0;
  double _caretA = 0;
  double _caretFadeFrom = 0;
  double _caretFadeWait = _fadeMs;

  final FocusNode _focusNode = FocusNode(debugLabel: 'interaction-lab.otp');
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocus)
      ..dispose();
    _ticker?.stop();
    super.dispose();
  }

  void _onFocus() {
    _focused = _focusNode.hasFocus;
    _kick();
  }

  // ---------------------------------------------------------------- 交互

  /// 整行的 pointerdown：已验证态是"回收重来"，其余态只是把焦点拿回来
  void _press() {
    if (_phase == _Phase.ok) {
      _code = '';
      for (var i = 0; i < _cells; i++) {
        _entryAt[i] = null;
      }
      _phase = _Phase.type;
      _merge.aim(0);
    }
    _syncCaret();
    _focusNode.requestFocus();
    _kick();
  }

  /// 参考稿是真 `<input inputMode=numeric>` 覆盖整行：只留数字、截到 4 位，
  /// 退格走浏览器原生整串回删。填满不提交，只是进 check。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_phase != _Phase.type) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      if (_code.isNotEmpty) _setCode(_code.substring(0, _code.length - 1));
      return KeyEventResult.handled;
    }
    final label = key.keyLabel;
    if (label.length != 1 || label.compareTo('0') < 0 || label.compareTo('9') > 0) {
      return KeyEventResult.ignored;
    }
    var next = _code + label;
    if (next.length > _cells) next = next.substring(0, _cells);
    if (next != _code) _setCode(next);
    return KeyEventResult.handled;
  }

  void _setCode(String next) {
    // React 的 key 是 `${i}-${digit}`：只有这一格的字符真的换了才重挂、才重播入场
    for (var i = 0; i < _cells; i++) {
      final before = i < _code.length ? _code[i] : null;
      final after = i < next.length ? next[i] : null;
      if (after != null && after != before) _entryAt[i] = _now;
    }
    _code = next;
    if (next.length == _cells) {
      _phase = _Phase.check;
      _checkWait = 0;
    }
    _syncCaret();
    _kick();
  }

  void _syncCaret() {
    _caret.aim(math.min(_code.length, _cells - 1) * _step + _cellW / 2);
  }

  /// 420ms 到点分叉
  void _verdict() {
    if (widget.reject) {
      _phase = _Phase.no;
      _noWait = 0;
      _red.aim(1);
    } else {
      _phase = _Phase.ok;
      _merge.aim(1);
      _focusNode.unfocus();
    }
  }

  void _reset() {
    _code = '';
    for (var i = 0; i < _cells; i++) {
      _entryAt[i] = null;
    }
    _phase = _Phase.type;
    _red.aim(0);
    _syncCaret();
  }

  // ---------------------------------------------------------------- 一帧只走一根钟

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
    _now += dt;
    var live = false;

    live |= _merge.step(dt);
    live |= _caret.step(dt);
    live |= _red.step(dt);
    for (var i = 0; i < _cells; i++) {
      final at = _entryAt[i];
      if (at != null) live |= (_now - at) < _entryMs;
    }

    if (_phase == _Phase.check) {
      // 呼吸波吃墙钟，必须一帧不落
      _checkWait += dt;
      live = true;
      if (_checkWait >= _checkMs) _verdict();
    } else if (_phase == _Phase.no) {
      _noWait += dt;
      live = true;
      if (_noWait >= _resetMs) _reset();
    }

    _syncCaretAlpha(dt);
    live |= _caretOn || _caretFadeWait < _fadeMs;

    setState(() {});
    if (!live) _ticker!.stop();
  }

  /// `data-on = type && 有焦点 && 没满 && 融合进度还没起步`
  void _syncCaretAlpha(double dt) {
    final on = _phase == _Phase.type &&
        _focused &&
        _code.length < _cells &&
        _merge.x.clamp(0.0, 1.0) < 0.08;
    if (on && !_caretOn) {
      _caretOn = true;
      _caretSince = _now;
    } else if (!on && _caretOn) {
      _caretOn = false;
      _caretFadeFrom = _caretA;
      _caretFadeWait = 0;
    }
    if (_caretOn) {
      _caretA = _breathe();
    } else if (_caretFadeWait < _fadeMs) {
      _caretFadeWait += dt;
      final p = (_caretFadeWait / _fadeMs).clamp(0.0, 1.0);
      _caretA = _caretFadeFrom * (1 - _cssEase.transform(p));
      if (p >= 1) _caretFadeWait = _fadeMs;
    } else {
      _caretA = 0;
    }
  }

  /// `1.1s ease-in-out infinite alternate`，1 → .25
  double _breathe() {
    final t = _now - _caretSince;
    final leg = (t / _breatheMs).floor();
    var u = (t % _breatheMs) / _breatheMs;
    if (leg.isOdd) u = 1 - u; // alternate：奇数拍反着走
    return 1 - 0.75 * _easeInOut.transform(u);
  }

  static final Curve _easeInOut = const Cubic(0.42, 0, 0.58, 1);

  // ---------------------------------------------------------------- 派生量

  /// `smoothstep(e0, e1, x)`
  static double _ss(double e0, double e1, double x) {
    final r = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return r * r * (3 - 2 * r);
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  /// 每格/每槽共同的 X：`mix(i*43, 64.5, k) + 抖动`
  double _cellX(int i, double k) {
    if (_phase != _Phase.no || _noWait >= _shakeMs) return _mix(_step * i, _mergedX, k);
    final amp = 5 * math.exp(-_noWait / 190);
    return _mix(_step * i, _mergedX, k) + amp * math.sin(_noWait / 1000 * 2 * math.pi * 10 + i * 0.55);
  }

  /// check 期的呼吸波：整行 900ms 扫一遍，每格被压到 .93
  double _cellScale(int i) {
    if (_phase != _Phase.check) return 1;
    final t = _now % _waveMs / _waveMs * (_cells + 2) - i;
    return 1 - 0.07 * (t > 0 && t < 2 ? math.sin(t / 2 * math.pi) : 0);
  }

  /// 错态掉落：右→左依次晚 45ms 起，各走 220ms
  double _drop(int i) {
    if (_phase != _Phase.no) return 0;
    return _ss(0, 1, (_noWait - _dropLeadMs - (_cells - 1 - i) * _dropStaggerMs) / _dropDurMs);
  }

  // ---------------------------------------------------------------- 树

  @override
  Widget build(BuildContext context) {
    final m = _merge.x;
    final k = m.clamp(0.0, 1.0);
    // 宽高读的是**未截断**的 m：`max(-.12, m-1)` 让胶囊到位前先窄一点、高一点
    final over = math.max(-0.12, m - 1);
    final radius = _mix(_corner, _cornerFull, _ss(0.15, 0.7, k));
    final slotA = 1 - _ss(0, 0.45, k);
    final pillW = _pillMax * _ss(0.3, 1, k) * (1 + over * 0.9);
    final pillY = 1 - over * 0.55;
    final okA = _ss(0.72, 1, k);

    return IlStage(
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: _rowW,
          height: _rowH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _goo(pillW > 0.5 ? pillW : null, pillY, radius, k),
              for (var i = 0; i < _cells; i++) _slot(i, k, slotA),
              _caretBox(),
              _okBox(okA),
              // `.otp-field` 排在最后：整个 165×44 都是它的命中区
              Positioned.fill(
                child: MouseRegion(
                  key: const ValueKey('hit'),
                  cursor: _phase == _Phase.ok ? SystemMouseCursors.click : SystemMouseCursors.text,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _press(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `.otp-goo`：四格 + 胶囊一起过 blur 和 alpha 硬阈值
  Widget _goo(double? pillW, double pillY, double radius, double k) {
    final cells = [
      for (var i = 0; i < _cells; i++)
        Positioned(
          left: _gooPad,
          top: _gooPad,
          width: _cellW,
          height: _rowH,
          child: Transform(
            key: ValueKey('cell-xf-$i'),
            alignment: Alignment.center,
            transform: _xf(_cellX(i, k), _cellScale(i)),
            child: DecoratedBox(
              key: ValueKey('cell-$i'),
              decoration: BoxDecoration(color: _slab, borderRadius: BorderRadius.circular(radius)),
            ),
          ),
        ),
      if (pillW != null)
        Positioned(
          left: _gooPad,
          top: _gooPad,
          width: pillW,
          height: _rowH,
          child: Transform(
            key: const ValueKey('pill-xf'),
            alignment: Alignment.center,
            // `translateX((a-re)/2) scaleY(ie)`
            transform: Matrix4.identity()
              ..setEntry(0, 3, (_rowW - pillW) / 2)
              ..setEntry(1, 1, pillY),
            child: const DecoratedBox(
              key: ValueKey('pill'),
              decoration: BoxDecoration(color: _slab, borderRadius: BorderRadius.all(Radius.circular(22))),
            ),
          ),
        ),
    ];
    return Positioned(
      key: const ValueKey('goo'),
      left: -_gooPad,
      top: -_gooPad,
      width: _rowW + _gooPad * 2,
      height: _rowH + _gooPad * 2,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_gooRamp),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3, tileMode: TileMode.decal),
          child: Stack(clipBehavior: Clip.none, children: cells),
        ),
      ),
    );
  }

  /// `translateX(N) scale(P)`，transform-origin 是格子自己的中心
  static Matrix4 _xf(double tx, double s) => Matrix4.identity()
    ..setEntry(0, 0, s)
    ..setEntry(1, 1, s)
    ..setEntry(0, 3, tx);

  /// `.otp-slot`：数字层，跟着格子一起位移，融合时整层淡掉
  Widget _slot(int i, double k, double slotA) {
    final digit = i < _code.length ? _code[i] : null;
    return Positioned(
      left: 0,
      top: 0,
      width: _cellW,
      height: _rowH,
      child: Transform.translate(
        key: ValueKey('slot-xf-$i'),
        offset: Offset(_cellX(i, k), 0),
        child: Opacity(
          key: ValueKey('slot-$i'),
          opacity: slotA,
          child: digit == null ? null : _digit(i, digit),
        ),
      ),
    );
  }

  Widget _digit(int i, String d) {
    final at = _entryAt[i];
    final p = at == null ? 1.0 : ((_now - at) / _entryMs).clamp(0.0, 1.0);
    final t = IlEase.smoothOut.transform(p); // `cubic-bezier(.22,1,.36,1)`
    final dropA = _drop(i);
    Widget body = Text(
      d,
      key: ValueKey('digit-$i'),
      style: _digitStyle.copyWith(color: Color.lerp(_on, _err, _red.v.clamp(0.0, 1.0))!),
    );
    // `otp-in`： translateY(45%) scale(.86) + blur(3px) + 透明 → 全钉在 1
    if (p < 1) {
      final sigma = (1 - t) * 3;
      body = Opacity(
        key: ValueKey('in-$i'),
        opacity: t,
        child: Transform(
          key: ValueKey('in-xf-$i'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(1, 3, (1 - t) * 0.45 * 19) // 45% 是数字盒自高（line-height 1 → 19）
            ..setEntry(0, 0, _mix(0.86, 1, t))
            ..setEntry(1, 1, _mix(0.86, 1, t)),
          child: sigma > 0.05
              ? ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                  child: body,
                )
              : body,
        ),
      );
    }
    // 错态掉落：只有位移——内联 opacity 会被 otp-in 的 fill:both 盖掉，这里不补
    return Center(
      child: Transform.translate(
        key: ValueKey('drop-xf-$i'),
        offset: Offset(0, dropA * _dropDy),
        child: body,
      ),
    );
  }

  /// 2×18 的竖条：`translateX(x-1) scaleX(1+min(5,|v|*.9))`
  Widget _caretBox() {
    final double stretch = 1 + math.min(5.0, _caret.v.abs() * 0.9);
    return Positioned(
      left: 0,
      top: (_rowH - 18) / 2, // `top:50%; margin-top:-9px`
      width: 2,
      height: 18,
      child: Opacity(
        key: const ValueKey('caret'),
        opacity: _caretA.clamp(0.0, 1.0),
        child: Transform(
          key: const ValueKey('caret-xf'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(0, 3, _caret.x - 1)
            ..setEntry(0, 0, stretch),
          child: const ColoredBox(color: _on),
        ),
      ),
    );
  }

  /// 图标 + `Verified`，跟着融合进度露出来
  Widget _okBox(double a) {
    return Positioned.fill(
      child: Opacity(
        key: const ValueKey('ok'),
        opacity: a,
        child: Transform(
          key: const ValueKey('ok-xf'),
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(0, 0, _mix(0.92, 1, a))
            ..setEntry(1, 1, _mix(0.92, 1, a)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const IlIcon(paths: _checkPath, size: 14, viewBox: 24, strokeWidth: 2.4, color: _on),
              const SizedBox(width: 6),
              const Text('Verified', style: _okStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// 参考稿那两条离散弹簧，逐字照抄：
/// `r = 首帧 1，否则 clamp(dt/16.67, 0, 2.5)`；`v += (to-x)*k*r; v *= d**r; x += v*r`；
/// `|to-x| < rest 且 |v| < rest` 才吸附并停钟（两条弹簧的 rest 不同，融合 8e-4、光标 .05）。
class _Sp {
  _Sp({required this.k, required this.d, this.x = 0, required this.rest});

  final double k;
  final double d;
  final double rest;

  double x;
  double v = 0;
  double to = 0;
  bool _first = true;

  bool get live => to != x || v != 0;

  /// 只有"停过钟再重新起跑"才算首帧（r=1）；钟一直在跑时换目标不重置
  void aim(double target) {
    if (!live) _first = true;
    to = target;
  }

  bool step(double ms) {
    if (!live) {
      x = to;
      v = 0;
      return false;
    }
    final r = _first ? 1.0 : (ms / 16.67).clamp(0.0, 2.5);
    _first = false;
    v += (to - x) * k * r;
    v *= math.pow(d, r);
    x += v * r;
    if ((to - x).abs() < rest && v.abs() < rest) {
      x = to;
      v = 0;
      _first = true;
    }
    return live;
  }
}

/// 值到值的定时补间（对应 CSS 那条 `transition`）
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

  /// 目标没变就别重起：反复 aim 同一个值会把 `_e` 清零，钟停不下来
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
    return true;
  }
}

/// CSS 不写缓动名时的那条
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);
