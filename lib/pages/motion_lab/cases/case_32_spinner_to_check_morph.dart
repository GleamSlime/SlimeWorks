import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 32. Spinner to check morph — 转圈 loader 弹成绿盘，勾再从盘里描出来
///
/// 参考稿这里七八条时间线各有各的时长，逐条单独补间才拢得住：
/// 绿盘（`.pv5b`，比 loader 外扩 1px）350ms 淡入、轨道环 245ms 淡出、
/// 转圈那头 175ms 淡出并就地冻住（`animation-play-state: paused`），
/// 整个标记先抬 3px（250ms）再落回（300ms，晚 250ms 起步），
/// 同时整体放大到 1.09（350ms、过冲很凶的那条），勾的描线晚 230ms 起步、走 600ms。
/// 一个坑：勾的 `stroke-dasharray` 写的是 20，而实测这段折线只有 12.3 长，
/// 所以"画满"发生在 600ms 的 61.5% 处，后面那截是空转——这是原稿的数，照抄。
/// 退回去时全部按基态那条 250ms 的 transition 走，抬升则撤掉 animation 直接归零。
const _marker = 22.0; // `.pv4t` 22×22
const _discInset = 1.0; // `.pv5b` inset:-1px
const _border = 2.5; // `--pv4p`
const _rowGap = 16.0; // `.pv5j` gap
const _linesGap = 3.0; // `.pv4w` gap

const _track = Color(0x1A000000); // rgba(0,0,0,.1)
const _spinnerTop = Color(0xFF7A7A7A); // border-top-color
const _discColor = Color(0xFF35BA00); // `--pv4v`

const _stroke = 2.0; // `--pv4h`（viewBox 24 上的用户单位）
const _dash = 20.0; // `stroke-dasharray: var(--pv3q,20)`

const _spinDur = Duration(milliseconds: 900); // `--pv48`，linear

/// 完成态各条时间线（毫秒）
const _liftUpMs = 250.0; // `--pv4q`
const _liftDownMs = 300.0; // `--pv43`
const _lift = 3.0; // `--pv5i`
const _scaleMs = 350.0; // `--pv4i`
const _scaleTo = 1.09; // `--pv3u`
const _discMs = 350.0; // `--pv45`
const _ringMs = 245.0; // `calc(--pv45 * 0.7)`
const _spinOutMs = 175.0; // `calc(--pv45 * 0.5)`
const _drawMs = 600.0; // `--pv44`
const _drawDelayMs = 230.0; // `calc(--pv45 + --pv3d - 200ms)`
const _crossMs = 157.5; // `calc(--pv45 * 0.45)`——糊进去那一下
const _blurSigma = 0.5; // `--pv59`

/// 回到转圈态：所有属性都走基态那条 250ms（`--pv3e`）
const _backMs = 250.0;

/// 参考稿用了三条不同的"弹"：通用弹（盘淡入/抬起）、强过冲（放大）、
/// 几乎直挺的回弹（落回），合成一条就不像了
const _easePop = Cubic(0.34, 1.35, 0.64, 1); // `--pv3t` / `--pv4j`
const _easeOvershoot = Cubic(0.34, 1.96, 0.94, 1); // `--pv47`
const _easeSettle = Cubic(0.14, 2.56, 0.94, 1); // `--pv3r`
const _cssEase = Cubic(0.25, 0.1, 0.25, 1); // transition 里裸写的 `ease`

const _titleStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1,
  color: LabColor.text,
);

/// `.pv5k`：同字号同字重，靠 opacity .5 压下去
const _subStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1,
  color: Color(0x800D0D0D),
);

class Case32SpinnerToCheckMorph extends StatefulWidget {
  const Case32SpinnerToCheckMorph({super.key});

  @override
  State<Case32SpinnerToCheckMorph> createState() => _Case32SpinnerToCheckMorphState();
}

enum _Phase { spinning, morphing, done, reverting }

class _Case32SpinnerToCheckMorphState extends State<Case32SpinnerToCheckMorph>
    with TickerProviderStateMixin {
  /// 总长 = 描线延迟 + 描线时长（其余几条都在它之前就跑完了）
  static const _totalMs = _drawDelayMs + _drawMs;

  late final AnimationController _spin = AnimationController(vsync: this, duration: _spinDur)
    ..repeat();
  late final AnimationController _c = AnimationController(vsync: this, duration: _ms(_totalMs));

  _Phase _phase = _Phase.spinning;

  @override
  void dispose() {
    _spin.dispose();
    _c.dispose();
    super.dispose();
  }

  static Duration _ms(double v) => Duration(microseconds: (v * 1000).round());

  void _toggle() {
    final toDone = _phase == _Phase.spinning || _phase == _Phase.morphing;
    // 中途连点：停掉当前这趟再改方向重播，别留两条在跑
    _c.stop();
    setState(() => _phase = toDone ? _Phase.morphing : _Phase.reverting);
    _c.duration = _ms(toDone ? _totalMs : _backMs);
    if (toDone) {
      // 原稿是 paused 而不是 cancel：转圈那头冻在当下这个角度
      _spin.stop();
      _c.forward(from: 0).then((_) {
        if (!mounted || _phase != _Phase.morphing) return;
        setState(() => _phase = _Phase.done);
      });
    } else {
      _c.forward(from: 0).then((_) {
        if (!mounted || _phase != _Phase.reverting) return;
        setState(() => _phase = _Phase.spinning);
        _spin.repeat();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(child: _row()),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }

  Widget _row() {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final m = _values();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `.pv3p`：那 0.5px 糊只落在标记上，文字不参与
            LabBlur(
              sigma: m.blur,
              child: Transform.translate(
                offset: Offset(0, -m.lift),
                child: Transform.scale(scale: m.scale, child: _markerStack(m)),
              ),
            ),
            const SizedBox(width: _rowGap),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Build demo page', style: _titleStyle),
                SizedBox(height: _linesGap),
                Text('8 subtasks', style: _subStyle),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 22 见方的标记：绿盘 / 轨道环 / 转圈那头 / 勾，四层叠着各自淡
  Widget _markerStack(_Values m) {
    return SizedBox(
      width: _marker,
      height: _marker,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_discInset,
            top: -_discInset,
            child: Opacity(
              opacity: m.disc,
              child: Container(
                width: _marker + _discInset * 2,
                height: _marker + _discInset * 2,
                decoration: const BoxDecoration(
                  color: _discColor,
                  shape: BoxShape.circle,
                  // 0.504px 那圈内描边用 border 顶，两道落影照抄
                  border: Border.fromBorderSide(BorderSide(color: Color(0x0D000000), width: 0.504)),
                  boxShadow: [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 0.504, offset: Offset(0, 0.504)),
                    BoxShadow(color: Color(0x14000000), blurRadius: 2.016, offset: Offset(0, 0.504)),
                  ],
                ),
              ),
            ),
          ),
          Opacity(opacity: m.ring, child: _ring(_track)),
          Opacity(
            opacity: m.spinner,
            child: RotationTransition(
              turns: _spin,
              child: CustomPaint(
                size: const Size(_marker, _marker),
                painter: const _TopArcPainter(color: _spinnerTop),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(_marker, _marker),
            painter: _DrawPainter(progress: m.draw),
          ),
        ],
      ),
    );
  }

  Widget _ring(Color color) {
    return Container(
      width: _marker,
      height: _marker,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: color, width: _border)),
      ),
    );
  }

  /// 正播按各自的起跳时刻排，倒放全部并回那一条 250ms
  _Values _values() {
    final v = _c.value;
    switch (_phase) {
      case _Phase.spinning:
        return const _Values(ring: 1, spinner: 1, disc: 0, scale: 1, lift: 0, draw: 0, blur: 0);
      case _Phase.done:
        return const _Values(ring: 0, spinner: 0, disc: 1, scale: 1, lift: 0, draw: 1, blur: 0);
      case _Phase.morphing:
        final e = v * _totalMs;
        return _Values(
          ring: 1 - _cssEase.transform((e / _ringMs).clamp(0.0, 1.0)),
          spinner: 1 - _cssEase.transform((e / _spinOutMs).clamp(0.0, 1.0)),
          disc: _easePop.transform((e / _discMs).clamp(0.0, 1.0)),
          scale: 1 + (_scaleTo - 1) * _easeOvershoot.transform((e / _scaleMs).clamp(0.0, 1.0)),
          lift: _liftEnvelope(e),
          draw: _drawn(LabEase.smoothOut.transform(((e - _drawDelayMs) / _drawMs).clamp(0.0, 1.0))),
          blur: _blurEnvelope(e),
        );
      case _Phase.reverting:
        final s = LabEase.smoothOut.transform(v);
        final e = _cssEase.transform(v);
        // 抬升挂的是 animation：data-state 一撤就归位，所以这里给 0 而不是补间
        return _Values(
          ring: e,
          spinner: e,
          disc: 1 - s,
          scale: _scaleTo + (1 - _scaleTo) * s,
          lift: 0,
          draw: _drawn(1 - s),
          blur: 0,
        );
    }
  }

  /// 250ms 抬起 3px，再花 300ms 落回（落回那条自带一点回弹）
  double _liftEnvelope(double e) {
    if (e <= _liftUpMs) return _lift * _easePop.transform(e / _liftUpMs);
    if (e <= _liftUpMs + _liftDownMs) {
      return _lift * (1 - _easeSettle.transform((e - _liftUpMs) / _liftDownMs));
    }
    return 0;
  }

  /// 交叉点那一下糊 0.5px：进 .is-crossing 用 157.5ms，出作用基态 250ms
  double _blurEnvelope(double e) {
    // 糊在 _crossMs 内到位，之后一直保持到绿盘落定；不夹住就会把 >1 的
    // 行程喂给 Cubic.transform，断言直接炸
    if (e <= _discMs) {
      return _blurSigma * _easePop.transform((e / _crossMs).clamp(0.0, 1.0));
    }
    final k = ((e - _discMs) / _backMs).clamp(0.0, 1.0);
    return _blurSigma * (1 - LabEase.smoothOut.transform(k));
  }

  /// dasharray(20) 比线长大，所以描满只用到行程的 61.5%
  double _drawn(double p) => (p * _dash / _DrawPainter.length).clamp(0.0, 1.0);
}

class _Values {
  const _Values({
    required this.ring,
    required this.spinner,
    required this.disc,
    required this.scale,
    required this.lift,
    required this.draw,
    required this.blur,
  });

  final double ring;
  final double spinner;
  final double disc;
  final double scale;
  final double lift;

  /// 0→1 的描线进度（已按 dasharray 的富余量折算）
  final double draw;
  final double blur;
}

/// 只有上边那一划有色：对应 `border-top-color`，线心半径与 CSS 边框中线一致
class _TopArcPainter extends CustomPainter {
  const _TopArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a <= 0.001) return;
    final rect = Rect.fromLTWH(
      _border / 2,
      _border / 2,
      size.width - _border,
      size.height - _border,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _border,
    );
  }

  @override
  bool shouldRepaint(_TopArcPainter old) => old.color != color;
}

/// stroke-dashoffset 的等价写法：按进度截出前段路径再整条描
class _DrawPainter extends CustomPainter {
  const _DrawPainter({required this.progress});

  final double progress;

  /// `.pv4u`：viewBox 24 上的这段折线
  static final Path _path = Path()
    ..moveTo(8, 12.5)
    ..lineTo(10.8, 15.5)
    ..lineTo(16.4, 9.5);

  static final double length =
      _path.computeMetrics().fold<double>(0.0, (sum, m) => sum + m.length);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    // svg 是 24 的 viewBox 画在 22 的盒子上，描边宽度也一起等比缩
    canvas.scale(size.width / 24);
    final segment = _path.computeMetrics().first.extractPath(0.0, length * progress);
    canvas.drawPath(
      segment,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DrawPainter old) => old.progress != progress;
}
