import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 29. Image open tilt — 缩略图放大展开，中途甩一次 3D 倾转 + 画面弯曲
///
/// 参考稿把"开"和"收"分成两套时长/曲线：开 450ms 顺出，收 350ms 带过冲
/// （`--pv13/--pvw` vs `--pvv/--pvl`），而 scale、圆角、倾转关键帧三者共用同一套，
/// 所以只用一条控制器，方向和时长换一下就行。
/// 倾转的关键帧是三段式（0% → 45% → 100%）：`translateZ` 从 -70px 起、
/// 45% 处到 -28px、末尾回 0；旋转角在 45% 处取指针留下的 `--pv1j/--pv1k`，
/// 而**收的时候同一组角度取 -0.45 倍**（方向反过来），所以去程和回程不是镜像。
/// 静止态既没有倾角也没有位移（基态 transform 写死 0deg），指针只决定"待会儿怎么甩"，
/// 这就是悬停时画面纹丝不动、点下去才扭一下的原因。
/// 弯曲是切片位移：横向抛物线（中间最大、两边为 0）逐片上下挪，
/// 圆角在每片内部按源坐标系裁，所以轮廓自己也跟着鼓起来。
const _tileW = 220.0; // `--pv1i`
const _tileH = 160.0; // `--pv1h`

/// 合上的视觉尺寸 = 220×160 再乘 `--pvb`（0.3），圆角跟着缩，所以小图仍是圆的
const _closedScale = 0.3; // `--pvb`
const _radiusClosed = 32.0;
const _radiusOpen = 16.0;

const _perspective = 900.0; // `--pvf`
const _maxZ = 70.0; // `--pv29`

const _openDur = Duration(milliseconds: 450); // `--pv13`
const _closeDur = Duration(milliseconds: 350); // `--pvv`
const _easeOpen = LabEase.smoothOut; // `--pvw`
const _easeClose = Cubic(0.34, 1.25, 0.64, 1); // `--pvl`

/// 关键帧上那两个角度在 CSS 里默认 0deg、由指针写入，所以最大幅度没有现成值：
/// 按 900px 透视 + 70px 位移的量级取 12°，超过就开始看得出"贴纸感"
const _maxTilt = 12.0;

/// 弯曲峰值（px）：原稿是软件位移量，这里按画面尺寸给一个不撕裂缝的档位
const _bendMax = 4.0;

/// `.pv28`：底色写的是 `var(--stage-bg, #eeeeef)`，取那条兜底值
const _tileBg = Color(0xFFEEEEEF);

/// `--pro-surface-shadow`（Flutter 的 boxShadow 没有 inset，1px 那圈改用 spreadRadius）
const _tileShadow = <BoxShadow>[
  BoxShadow(color: LabColor.border, blurRadius: 0, spreadRadius: 1),
  BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
];

class Case29ImageOpenTilt extends StatefulWidget {
  const Case29ImageOpenTilt({super.key});

  @override
  State<Case29ImageOpenTilt> createState() => _Case29ImageOpenTiltState();
}

enum _Phase { closed, opening, open, closing }

class _Case29ImageOpenTiltState extends State<Case29ImageOpenTilt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _openDur);

  _Phase _phase = _Phase.closed;

  /// 指针在画面上留下的倾角（度），只在播放关键帧时被读到
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    final opening = _phase == _Phase.closed;
    if (!opening && _phase != _Phase.open) return;
    setState(() => _phase = opening ? _Phase.opening : _Phase.closing);
    _c.duration = opening ? _openDur : _closeDur;
    _c.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _phase = opening ? _Phase.open : _Phase.closed);
    });
  }

  /// 指针落点 → 倾角：上半往怀里倒、右半往右边转
  void _track(Offset local) {
    setState(() {
      _tiltX = (0.5 - (local.dy / _tileH).clamp(0.0, 1.0)) * _maxTilt * 2;
      _tiltY = ((local.dx / _tileW).clamp(0.0, 1.0) - 0.5) * _maxTilt * 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 悬停/点击的是那块没变形的 220×160 外框：参考稿的按钮盒子本来就没跟着缩
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (e) => _track(e.localPosition),
            onHover: (e) => _track(e.localPosition),
            onExit: (_) => setState(() {
              _tiltX = 0;
              _tiltY = 0;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: SizedBox(
                width: _tileW,
                height: _tileH,
                child: ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => _tile(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile() {
    final v = _c.value;
    // 关键帧在两个方向上都是从 0 播到 1，所以先算"这一趟走到哪了"
    final u = switch (_phase) {
      _Phase.opening => _easeOpen.transform(v),
      _Phase.closing => _easeClose.transform(v),
      _Phase.open => 1.0,
      _Phase.closed => 0.0,
    };
    // 展开度：收的时候过冲会越过 0，正合那条带弹的 transition
    final openness = switch (_phase) {
      _Phase.opening => u,
      _Phase.closing => 1 - u,
      _Phase.open => 1.0,
      _Phase.closed => 0.0,
    };

    // 位移：去程 -70 → -28(45%) → 0，回程 0 → -28(45%) → 0
    final z = switch (_phase) {
      _Phase.opening => _piece(u, -_maxZ, -_maxZ * 0.4, 0),
      _Phase.closing => _piece(u, 0, -_maxZ * 0.4, 0),
      _ => 0.0,
    };
    // 角度系数：去程在 45% 处取满，回程同一处取 -0.45
    final tiltK = switch (_phase) {
      _Phase.opening => _bell(u),
      _Phase.closing => _bell(u) * -0.45,
      _ => 0.0,
    };
    final bend = _bell(u) * _bendMax;
    final radius = _radiusClosed + (_radiusOpen - _radiusClosed) * openness;
    final openScale = _closedScale + (1 - _closedScale) * openness;

    final m = Matrix4.identity()
      ..setEntry(3, 2, -1 / _perspective)
      ..rotateX(_tiltX * tiltK * math.pi / 180)
      ..rotateY(_tiltY * tiltK * math.pi / 180)
      // CSS 的 transform 串：perspective → rotateX → rotateY → translateZ
      ..multiply(Matrix4.translationValues(0, 0, z))
      // 独立属性 scale 排在这串之后，所以在最内层缩放
      ..multiply(Matrix4.diagonal3Values(openScale, openScale, openScale));

    return Transform(
      alignment: Alignment.center,
      transform: m,
      child: Container(
        decoration: BoxDecoration(
          color: _tileBg,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: _tileShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            size: const Size(_tileW, _tileH),
            painter: _WarpPainter(bend: bend, radius: radius),
          ),
        ),
      ),
    );
  }
}

/// 三段折线：0% → 45% → 100%
double _piece(double u, double a, double b, double c) {
  if (u <= 0.45) return a + (b - a) * (u / 0.45);
  return b + (c - b) * ((u - 0.45) / 0.55);
}

/// 同一个骨架的包络：两端 0、45% 处到 1
double _bell(double u) => _piece(u, 0, 1, 0);

/// 竖向切片 + 横向抛物线位移（中间最大、两边为 0）
class _WarpPainter extends CustomPainter {
  const _WarpPainter({required this.bend, required this.radius});

  final double bend;
  final double radius;

  static const _slices = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(math.max(radius, 0)));
    if (bend <= 0.02) {
      canvas.clipRRect(rrect);
      paintPhoto(canvas, rect);
      return;
    }
    final sw = size.width / _slices;
    for (var i = 0; i < _slices; i++) {
      final u = (i + 0.5) / _slices;
      final dy = bend * (1 - math.pow(2 * u - 1, 2).toDouble());
      canvas.save();
      // 切片先按设备坐标取（左右各让出半像素，免得露出发丝缝）
      canvas.clipRect(Rect.fromLTWH(i * sw - 0.5, -_bendMax, sw + 1, size.height + _bendMax * 2));
      canvas.translate(0, dy);
      // 圆角在位移后的源空间里裁，轮廓才会跟着一起鼓
      canvas.clipRRect(rrect);
      paintPhoto(canvas, rect);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WarpPainter old) => old.bend != bend || old.radius != radius;
}

/// 占位照片：参考稿用的是位图资产，这里一律本地画——
/// 天空渐变 + 一轮低阳 + 两道山形 + 前景水面，比例全部归一化，任何尺寸下同一副样子
const _sky = [Color(0xFF9FB8D8), Color(0xFFE9D9C4)];
const _sunColor = Color(0xFFFFF1DA);
const _ridgeFar = Color(0xFF7D8A99);
const _ridgeNear = Color(0xFF5C6773);
const _waterColor = Color(0xFF46505B);

void paintPhoto(Canvas canvas, Rect r) {
  final paint = Paint()
    ..shader = labLinearGradient(180, _sky).createShader(r);
  canvas.drawRect(r, paint);
  paint.shader = null;

  paint.color = _sunColor;
  canvas.drawCircle(Offset(r.left + r.width * 0.72, r.top + r.height * 0.3), r.width * 0.07, paint);

  paint.color = _ridgeFar;
  canvas.drawPath(_ridge(r, 0.28, 0.44), paint);
  paint.color = _ridgeNear;
  canvas.drawPath(_ridge(r, 0.7, 0.56), paint);

  paint.color = _waterColor;
  canvas.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.8, r.width, r.height * 0.2), paint);
}

/// 一个山头：顶点在 (cx, peak)，两侧斜到画面底
Path _ridge(Rect r, double cx, double peak) {
  final w = r.width;
  final h = r.height;
  return Path()
    ..moveTo(r.left + w * (cx - 0.44), r.top + h)
    ..lineTo(r.left + w * cx, r.top + h * peak)
    ..lineTo(r.left + w * (cx + 0.44), r.top + h)
    ..close();
}
