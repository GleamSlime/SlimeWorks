import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 12. Success check — 绿盘从下方浮起、边转边糊，勾再沿路径描出来
///
/// 入场是**四条并行 + 一条延迟**：淡入、从 80 度转回正、10px 糊到 0、
/// 向上 40px 落回原位都走 500ms，但各自有曲线（落位用带过冲的那条，
/// 其余用顺出）；描线晚 80ms 起步、同样 500ms，所以整段实际是 580ms。
/// 退场只淡出 + 糊到 4px，不反向播放入场——倒着转回去会变成"撤销"而不是"完成"。
class Case12SuccessCheck extends StatefulWidget {
  const Case12SuccessCheck({super.key});

  @override
  State<Case12SuccessCheck> createState() => _Case12SuccessCheckState();
}

enum _Phase { hidden, appearing, shown, exiting }

class _Case12SuccessCheckState extends State<Case12SuccessCheck> with TickerProviderStateMixin {
  /// `--p10-opacity/rotate/blur/bob/path-dur: var(--duration-very-slow)`
  static const _propMs = 500.0;

  /// `--p10-path-delay: var(--duration-micro)`
  static const _delayMs = 80.0;

  static const _propDur = Duration(milliseconds: 500);

  /// 描线延迟在窗口之外，所以总时长是 580ms 而不是 500ms
  static const _totalDur = Duration(milliseconds: 580);

  /// `--p10-rotate-from: 80deg` / `--p10-y-amount: 40px`
  static const _rotateFrom = 80.0 * math.pi / 180;
  static const _yAmount = 40.0;

  /// `--p10-blur-from: 10px` / `--p10-blur-out-from: 4px`
  static const _blurIn = 10.0;
  static const _blurOut = 4.0;

  /// `--p10-ease-opacity/rotate/out/path: var(--ease-smooth-out)`
  static const _smooth = LabEase.smoothOut;

  /// `--p10-ease-bob: cubic-bezier(0.34, 1.35, 0.64, 1)`（比通用弹值低一档，单独存）
  static const _easeBob = Cubic(0.34, 1.35, 0.64, 1);

  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: _totalDur,
  );
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: _propDur,
  );

  _Phase _phase = _Phase.hidden;

  @override
  void initState() {
    super.initState();
    // build 里直接读两条钟的 value，所以必须挂重绘监听：不挂就只在 setState
    // 那一次取到起点值，整段入场退场全部瞬移（看着像没有动效）
    _in.addListener(_repaint);
    _out.addListener(_repaint);
    // 用状态回调接力而不是 await forward()：中途被 dispose 时 future 会抛取消错
    _in.addStatusListener((status) {
      if (status == AnimationStatus.completed && _phase == _Phase.appearing) {
        setState(() => _phase = _Phase.shown);
      }
    });
    _out.addStatusListener((status) {
      if (status == AnimationStatus.completed && _phase == _Phase.exiting) {
        _in.value = 0;
        setState(() => _phase = _Phase.hidden);
      }
    });
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_phase == _Phase.appearing || _phase == _Phase.shown) {
      // 已经在台上 → 只走退场（淡到 0 + 糊到 4px），不反向播放入场
      _in.stop();
      setState(() => _phase = _Phase.exiting);
      _out.forward(from: 0);
    } else {
      // 冷启动和"刚退完"都从 0 重播入场，keyframes 是从头起的
      _out.stop();
      _out.value = 0;
      setState(() => _phase = _Phase.appearing);
      _in.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 各属性自己算，避免把四种曲线合成一条
    double opacity;
    double rotate;
    double blur;
    double dy;
    double draw;
    switch (_phase) {
      case _Phase.appearing:
        final elapsed = _in.value * (_propMs + _delayMs);
        // 四条并行属性只占前 500ms，描线从 80ms 起再走 500ms
        final a = (elapsed / _propMs).clamp(0.0, 1.0);
        final s = _smooth.transform(a);
        opacity = s;
        rotate = (1 - s) * _rotateFrom;
        blur = _blurIn * (1 - s);
        dy = _yAmount * (1 - _easeBob.transform(a));
        draw = _smooth.transform(((elapsed - _delayMs) / _propMs).clamp(0.0, 1.0));
      case _Phase.shown:
        opacity = 1;
        rotate = 0;
        blur = 0;
        dy = 0;
        draw = 1;
      case _Phase.exiting:
        final e = _smooth.transform(_out.value);
        opacity = 1 - e;
        rotate = 0;
        blur = _blurOut * e;
        dy = 0;
        draw = 1;
      case _Phase.hidden:
        opacity = 0;
        rotate = 0;
        blur = 0;
        dy = 0;
        draw = 0;
    }
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: Transform.translate(
              // CSS 里 translate 排在 rotate 之前，所以位移在外、旋转在内
              offset: Offset(0, dy),
              child: Transform.rotate(
                angle: rotate,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: LabBlur(sigma: blur, child: _SuccessDisc(draw: draw)),
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

/// 48 绿盘 + 白色勾：盘自己不动，动的是外面那层 wrapper
class _SuccessDisc extends StatelessWidget {
  const _SuccessDisc({required this.draw});

  /// 描线进度 0→1
  final double draw;

  static const _disc = Color(0xFF35BA00);

  /// 内圈那层 1px 用描边代替（Flutter 的 boxShadow 没有 inset）
  static const _ring = Color(0x0D000000); // rgba(0,0,0,.05)
  static const _shadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), blurRadius: 1, offset: Offset(0, 1)), // rgba(0,0,0,.10)
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)), // rgba(0,0,0,.08)
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: _disc,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: _ring)),
        boxShadow: _shadow,
      ),
      alignment: Alignment.center,
      // svg 是 48 viewBox 画在 48px 上，1:1
      child: CustomPaint(size: const Size(48, 48), painter: _CheckPainter(progress: draw)),
    );
  }
}

/// stroke-dasharray/dashoffset 的等价写法：按进度截出前段路径再整条描
class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress});

  final double progress;

  static final Path _path = Path()
    ..moveTo(17.2803, 24.9602)
    ..lineTo(21.7603, 29.7602)
    ..lineTo(30.7203, 20.1602);

  static final double _length =
      _path.computeMetrics().fold<double>(0.0, (sum, m) => sum + m.length);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final metric = _path.computeMetrics().first;
    final segment = metric.extractPath(0.0, _length * progress);
    canvas.drawPath(
      segment,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
