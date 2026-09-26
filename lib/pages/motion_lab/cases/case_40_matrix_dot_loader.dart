import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 40. Matrix dot loader — 四个 16 点阵各自按不同延迟脉冲
///
/// 四个点阵长得完全一样（4×4 的 2px 点、2px 间距），差的只是一张延迟表：
/// scan 按列推 120ms、twinkle 按打乱表推 75ms、orbit 沿外环推 150ms 且中心四点
/// 不动、pulse 先亮内圈、外圈再晚 192ms。圆角版把四角的点挖掉不画。
/// 共用的是同一个 1200ms 色循环：0→15% 由底色亮到亮色，15%→45% 暗回去，
/// 45% 之后一路保持底色（这段保持才是"点阵"而不是一闪一闪的关键）。
/// 于是只开一条循环 + 每点一个相位差，四个点阵 56 个可见点一次 CustomPaint 画完，
/// 既不逐点开 controller 也不逐点建 widget。
class Case40MatrixDotLoader extends StatefulWidget {
  const Case40MatrixDotLoader({super.key});

  @override
  State<Case40MatrixDotLoader> createState() => _Case40MatrixDotLoaderState();
}

/// `--matrix-*`：一轮 1200ms，ease-in-out，底色/亮色两档
const _cycleMs = 1200;
const _base = Color(0xFFD9D9D9);
const _active = Color(0xFF85858F);

const _dotSize = 2.0;
const _dotGap = 2.0;
const _loaders = 4;
const _loaderW = _dotSize * 4 + _dotGap * 3; // 14
const _rowGap = 28.0;
const _rowW = _loaderW * _loaders + _rowGap * 3;

/// 一个点：坐标以整行为坐标系，delay 以"一个循环"为单位，steady = 不参与脉冲
class _Dot {
  const _Dot(this.x, this.y, this.delay, this.steady);

  final double x;
  final double y;

  /// 相位差（循环的几分之几）
  final double delay;
  final bool steady;

  static const _corners = [0, 3, 12, 15];
  static const _inner = [5, 6, 9, 10];
  static const _ring = [1, 2, 7, 11, 14, 13, 8, 4];
  static const _twinkleOrder = [7, 2, 11, 5, 14, 9, 0, 12, 3, 15, 6, 10, 13, 1, 8, 4];

  /// 四种花样就是四张延迟表，按参考稿给的顺序从左到右排
  static List<_Dot> build() {
    final out = <_Dot>[];
    for (var v = 0; v < _loaders; v++) {
      final ox = v * (_loaderW + _rowGap);
      for (var i = 0; i < 16; i++) {
        final col = i % 4;
        final row = i ~/ 4;
        final rounded = v >= 2; // orbit / pulse 是圆角版
        if (rounded && _corners.contains(i)) continue;
        final ring = _ring.indexOf(i);
        final inner = _inner.contains(i);
        final (delay, steady) = switch (v) {
          0 => (col / 10, false), // scan：整列一起走
          1 => (_twinkleOrder[i] / 16, false), // twinkle：按打乱表散布
          2 => (ring < 0 ? 0.0 : ring / 8, ring < 0), // orbit：沿外环一圈，中心四点稳住
          // pulse：内圈先亮，其余晚 0.16 轮
          _ => (inner ? 0.0 : 0.16, false),
        };
        out.add(_Dot(ox + col * (_dotSize + _dotGap), row * (_dotSize + _dotGap), delay, steady));
      }
    }
    return out;
  }
}

final _dots = _Dot.build();

class _Case40MatrixDotLoaderState extends State<Case40MatrixDotLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _cycleMs),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 参考稿这一格没有按钮（stage-inner--no-btn），点阵自己一直转
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) => CustomPaint(
                  size: const Size(_rowW, _loaderW),
                  painter: _MatrixPainter(_c.value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixPainter extends CustomPainter {
  const _MatrixPainter(this.phase);

  /// 0→1，一个色循环
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final d in _dots) {
      paint.color = d.steady ? _base : _pulse(d.delay);
      canvas.drawRect(Rect.fromLTWH(d.x, d.y, _dotSize, _dotSize), paint);
    }
  }

  /// 关键帧：0/45/100% 底色，15% 亮色，段内走 ease-in-out
  Color _pulse(double delay) {
    var p = phase - delay;
    p -= p.floor();
    if (p < .15) return Color.lerp(_base, _active, LabEase.inOut.transform(p / .15))!;
    if (p < .45) return Color.lerp(_active, _base, LabEase.inOut.transform((p - .15) / .3))!;
    return _base;
  }

  @override
  bool shouldRepaint(_MatrixPainter old) => old.phase != phase;
}
