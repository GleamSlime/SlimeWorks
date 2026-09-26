import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 22. Organic shimmer — 灰板下有彩斑，一道斜向"雨刷"周期性扫过，边缘带彩光
///
/// 结构照抄参考稿三层：
/// 底层 `.pv5q` 是六个固定位的大彩斑 + 一层 5% 灰水；
/// 中间 `.pv5p` 是一张近不透明的骨架色（#eee）蒙皮，
/// 沿 135° 留了一条约 187px 宽的软边透明带（两侧停点比例按 `--pv5z` 原样换算），
/// 透明带从板外左上扫到板外右下就是那道 shimmer；
/// 顶层 `.pv5x/.pv5w/.pv5t` 是同一套边缘彩斑的 1px 环 / 2px 糊 / 20px 大糊三档。
///
/// 循环 3000ms（`--pv5s`）、每轮 ease-out（`--pv5u`）。Play 之前是
/// `animation-play-state: paused`——空闲帧固定停在扫描带完全在板外的一刻，
/// 整块板就是纯 #eee，golden 可复现。
const _tileSize = 142.0;
const _tileRadius = 12.0;

/// 舞台版式：`.stage-inner` 底部给按钮让出 56
const _tileLeft = (296 - _tileSize) / 2;
const _tileTop = (260 - 56 - _tileSize) / 2;

/// 彩斑层从板缘外扩 20px（`.pv62/.pv65` inset:-20）
const _pad = 20.0;
const _layerSize = _tileSize + _pad * 2;

/// 扫描带宽 ≈ 0.22048（`--pv5z` = 26%×0.848）× 330% 层的渐变线长 849
const _bandW = 187.0;

/// 142×142 板沿 135° 方向的渐变线长（142 × 1.414）
const _diag = 200.8;

/// 参考稿透明带两侧停点：相对带心的偏移（单位 = 带宽）与对应不透明度
const _stopOffsets = [-2.527, -1.9, -1.4, -0.583, 0.0, 0.243, 0.4725];
const _stopAlphas = [1.0, 0.94, 0.82, 0.55, 0.0, 0.5, 1.0];

const _cRed = Color(0xFFFF3264);
const _cBlue = Color(0xFF288CFF);
const _cGreen = Color(0xFF32C850);
const _cTeal = Color(0xFF1EB9AA);
const _cIndigo = Color(0xFF6446FF);
const _cOrange = Color(0xFFFF7828);
const _cPink = Color(0xFFF032B4);
const _cPurple = Color(0xFFB428F0);
const _cGray = Color(0xFF5A5A64);
const _skeleton = Color(0xFFEEEEEE);

Color _a(Color c, double alpha) => c.withValues(alpha: alpha);

/// 椭圆彩斑：半径 ×2 + 中心百分比 + 色
class _Blob {
  const _Blob(this.rx, this.ry, this.cxPct, this.cyPct, this.color);

  final double rx;
  final double ry;
  final double cxPct;
  final double cyPct;
  final Color color;
}

/// `.pv5q`：底色大彩斑（坐标相对 182 的外扩盒）
const _blobLayer = [
  _Blob(90, 70, 20, 15, _cBlue),
  _Blob(80, 60, 65, 25, _cRed),
  _Blob(70, 80, 30, 55, _cGreen),
  _Blob(90, 70, 75, 65, _cPurple),
  _Blob(70, 60, 45, 85, _cOrange),
  _Blob(60, 60, 10, 85, _cTeal),
];
const _blobAlphas = [0.14, 0.13, 0.12, 0.13, 0.12, 0.11];

/// `.pv5x`：1px 亮环档（坐标相对 142 的板）
const _ringBlobs = [
  _Blob(42, 24, 33, -7.4, _cRed),
  _Blob(36, 21, 12, -5, _cBlue),
  _Blob(24, 42, 2.1, 68.3, _cGreen),
  _Blob(12, 21, 2.1, 68.3, _cTeal),
  _Blob(108, 19, 74.4, 100, _cIndigo),
  _Blob(51, 16, 55, 100, _cBlue),
  _Blob(44, 19, 93.9, 0, _cOrange),
  _Blob(16, 25, 100, 27.1, _cPink),
  _Blob(31, 29, 100, 27.1, _cPurple),
];
const _ringAlphas = [0.62, 0.48, 0.55, 0.44, 0.58, 0.51, 0.65, 0.5, 0.56];

/// `.pv5w`：2px 糊档（同位再收一圈 + 四角灰点）
const _glowBlobs = [
  _Blob(39, 21, 33, -7.4, _cRed),
  _Blob(33, 18, 12, -5, _cBlue),
  _Blob(21, 39, 2.1, 68.3, _cGreen),
  _Blob(9, 18, 2.1, 68.3, _cTeal),
  _Blob(104, 17, 74.4, 100, _cIndigo),
  _Blob(48, 13, 55, 100, _cBlue),
  _Blob(41, 17, 93.9, 0, _cOrange),
  _Blob(13, 23, 100, 27.1, _cPink),
  _Blob(28, 26, 100, 27.1, _cPurple),
  _Blob(36, 36, 0, 0, _cGray),
  _Blob(36, 36, 100, 0, _cGray),
  _Blob(36, 36, 0, 100, _cGray),
  _Blob(36, 36, 100, 100, _cGray),
];
const _glowAlphas = [
  0.34, 0.28, 0.30, 0.25, 0.32, 0.28, 0.35, 0.28, 0.30, //
  0.14, 0.14, 0.14, 0.14,
];

/// `.pv5t`：20px 大糊档
const _hazeBlobs = [
  _Blob(55, 31, 33, -7.4, _cRed),
  _Blob(47, 27, 12, -5, _cBlue),
  _Blob(31, 55, 2.1, 68.3, _cGreen),
  _Blob(140, 25, 74.4, 100, _cIndigo),
  _Blob(66, 20, 55, 100, _cBlue),
  _Blob(58, 25, 93.9, 0, _cOrange),
  _Blob(40, 38, 100, 27.1, _cPurple),
];
const _hazeAlphas = [0.40, 0.34, 0.38, 0.40, 0.35, 0.44, 0.38];

class Case22OrganicShimmer extends StatefulWidget {
  const Case22OrganicShimmer({super.key});

  @override
  State<Case22OrganicShimmer> createState() => _Case22OrganicShimmerState();
}

class _Case22OrganicShimmerState extends State<Case22OrganicShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000), // `--pv5s`
  );
  late final CurvedAnimation _sweep =
      CurvedAnimation(parent: _c, curve: Curves.easeOut); // `--pv5u`

  bool _playing = false;

  @override
  void initState() {
    super.initState();
    // 带心的位置是从 build 里读 _sweep.value 算出来的，
    // 循环钟不挂监听就永远停在挂载那一帧
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sweep.dispose();
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _c.repeat();
    } else {
      // play-state: paused —— 停在当前帧，不倒回
      _c.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 带心沿对角线从板外左上（-0.6 带宽）扫到板外右下（对角长 + 0.6 带宽）
    final c = -0.6 * _bandW +
        _sweep.value * (_diag + 1.2 * _bandW);
    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: _tileLeft,
            top: _tileTop,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_tileRadius),
              child: SizedBox(
                width: _tileSize,
                height: _tileSize,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: _skeleton),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _BlobsPainter()),
                    ),
                    Positioned.fill(
                      child: CustomPaint(painter: _SweepPainter(c)),
                    ),
                    // 三档边缘光：大糊 → 2px 糊 → 1px 环，依次压顶
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: CustomPaint(
                          painter: _RingPainter(_hazeBlobs, _hazeAlphas, 6),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.7, // `--pv5n`
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                          child: CustomPaint(
                            painter: _RingPainter(_glowBlobs, _glowAlphas, 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RingPainter(_ringBlobs, _ringAlphas, 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Play', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

void _drawBlob(Canvas canvas, _Blob b, double alpha, {Offset shift = Offset.zero}) {
  canvas.save();
  canvas.translate(
    shift.dx + b.cxPct / 100 * _layerSize,
    shift.dy + b.cyPct / 100 * _layerSize,
  );
  canvas.scale(b.rx, b.ry);
  canvas.drawCircle(
    Offset.zero,
    1,
    Paint()
      ..shader = RadialGradient(
        colors: [_a(b.color, alpha), _a(b.color, 0)],
      ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
  );
  canvas.restore();
}

/// 底色彩斑层：整块画在板上（外扩盒相对板偏移 -20）
class _BlobsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _a(_cGray, 0.05),
    );
    for (var i = 0; i < _blobLayer.length; i++) {
      _drawBlob(canvas, _blobLayer[i], _blobAlphas[i],
          shift: const Offset(-_pad, -_pad));
    }
  }

  @override
  bool shouldRepaint(_BlobsPainter old) => false;
}

/// 雨刷层：骨架色蒙皮 + 中央透明带，带心位于对角坐标 c
class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.c);

  final double c;

  @override
  void paint(Canvas canvas, Size size) {
    // 渐变两端各多留一档，保证带外是纯粹的不透明蒙皮
    final start = c - 2.7 * _bandW;
    final end = c + 0.65 * _bandW;
    final span = end - start;
    final colors = [
      for (var i = 0; i < _stopOffsets.length; i++)
        _a(_skeleton, _stopAlphas[i]),
    ];
    final stops = [
      for (final o in _stopOffsets)
        ((c + o * _bandW - start) / span).clamp(0.0, 1.0),
    ];
    // 等色线垂直于对角线：渐变两端取对角线上两点，
    // 用超出 ±1 的 Alignment 把这两点钉进 rect（createShader 允许）
    final half = size.width / 2;
    Alignment ax(double v) {
      final p = v * 0.7071067811865476 / half - 1;
      return Alignment(p, p);
    }

    final paint = Paint()
      ..shader = LinearGradient(
        begin: ax(start),
        end: ax(end),
        colors: colors,
        stops: stops,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.c != c;
}

/// 边缘光：把彩斑裁进一圈 `band` 宽的环带里（mask-composite: exclude 的等效）
class _RingPainter extends CustomPainter {
  const _RingPainter(this.blobs, this.alphas, this.band);

  final List<_Blob> blobs;
  final List<double> alphas;

  /// 环带宽：1px 亮环档 = 1
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_tileRadius),
      ));
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(band, band, size.width - band * 2, size.height - band * 2),
        Radius.circular(_tileRadius - band),
      ));
    canvas.clipPath(Path.combine(PathOperation.difference, outer, inner));
    if (band == 1) {
      // `.pv5x` 最底层那遍 22% 灰水
      canvas.drawRect(Offset.zero & size, Paint()..color = _a(_cGray, 0.22));
    }
    // 边缘彩斑的百分比相对 142 的板本体
    for (var i = 0; i < blobs.length; i++) {
      _drawBlobPct(canvas, blobs[i], alphas[i], size);
    }
  }

  void _drawBlobPct(Canvas canvas, _Blob b, double alpha, Size size) {
    canvas.save();
    canvas.translate(b.cxPct / 100 * size.width, b.cyPct / 100 * size.height);
    canvas.scale(b.rx, b.ry);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = RadialGradient(
          colors: [_a(b.color, alpha), _a(b.color, 0)],
        ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.band != band || old.blobs != blobs || old.alphas != alphas;
}
