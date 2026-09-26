import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 43. Get Pro button — 同一套彩色水，只从药丸的边上透出来
///
/// 和标题那格共用同一份背景配方（7 层径向、180% 尺寸、5000ms 走位 + 4000ms 转色相），
/// 区别全在 `::before` 外面那圈遮罩：
/// `radial-gradient(ellipse 46% 46%, transparent 50%, black 200%)`
/// ——椭圆半径的 50% 以内完全透明，到 200% 才全不透明，所以字心始终是白的、
/// 只有四周一圈把颜色接住，读起来像"从边缘亮起来"。
/// 因为最后一档落在 200%，那颗椭圆的最外沿也只能到 `1.087/2` 的覆盖率：
/// 药丸角落实际只有约 69% 的遮罩强度，本来就不该亮成实心。
/// 上面还挂了 `blur(6px)`（`--pv6q`）把水纹糊开，整层 `opacity: 0.7`（`--pv6d`）。
const _label = 'Get Pro';

const _pillH = 40.0; // `.pv6u` height
const _pillPadX = 18.0; // padding: 0 18px
const _pillRadius = 50.0;

const _labelStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.4,
  color: LabColor.text,
);

/// `background: var(--surface-bg)` + 那圈投影（Flutter 没有 inset，改用 border 顶）
const _pillBg = Color(0xFFFFFFFF);
const _hairline = Color(0x0F000000); // rgba(0,0,0,.06)
const _bottomLine = Color(0x1A000000); // 0 -1px 0 rgba(0,0,0,.10) inset
const _drop = BoxShadow(
  color: Color(0x0A000000), // rgba(0,0,0,.04)
  blurRadius: 3,
  offset: Offset(0, 1),
);

const _rimOpacity = 0.7; // `--pv6d`
const _rimBlur = 6.0; // `--pv6q`
const _ellipseF = 0.46; // `ellipse 46% 46%`
const _maskFrom = 0.5; // `transparent var(--pv6r)`
const _maskTo = 2.0; // `black calc(--pv6r + --pv6b)` = 50% + 150%

const _hueDur = Duration(milliseconds: 4000); // `--pv6f`
const _segMs = 1250.0; // `--pv6c` 5000ms / 4 段
const _loopMs = 20000.0; // 两条周期的公倍数

/// 一层彩色水：半轴按药丸宽/高计，颜色里已带该层自己的 opacity
class _Wash {
  const _Wash(this.fx, this.fy, this.colors, this.stops);

  final double fx;
  final double fy;
  final List<Color> colors;
  final List<double> stops;
}

/// `.pv6u::before` 的 `background-image` 列表（第一项在最上面），没有灰底那层
const _washes = [
  _Wash(0.093, 0.384, [Color(0xE1006EF5), Color(0x00006EF5)], [0, 1]),
  _Wash(0.356, 1.296, [Color(0x80006EF5), Color(0x00006EF5)], [0, 1]),
  _Wash(
    0.355,
    1.564,
    [Color(0x66CC00A7), Color(0x00AA00CC), Color(0x00AA00CC)],
    [0, 0.71709, 1],
  ),
  _Wash(0.137, 0.489, [Color(0xFFCC00A7), Color(0x00AA00CC)], [0, 1]),
  _Wash(0.235, 0.870, [Color(0xFFFFAD55), Color(0x00FFAD55)], [0, 1]),
  _Wash(
    0.348,
    1.552,
    [Color(0xFF00CC44), Color(0xBF00C466), Color(0x8000BB88), Color(0x0000AACC)],
    [0, 0.25, 0.5, 1],
  ),
  _Wash(0.306, 1.964, [Color(0xFF00AACC), Color(0x0000AACC)], [0, 1]),
];

/// `--pv6l` 的四档 `background-position`
const _frames = <List<Offset>>[
  [
    Offset(100, 0), Offset(0, 50), Offset(100, 50), //
    Offset(0, 100), Offset(0, 0), Offset(50, 0), Offset(50, 100),
  ],
  [
    Offset(100, 100), Offset(50, 0), Offset(50, 100), //
    Offset(0, 0), Offset(100, 0), Offset(100, 50), Offset(0, 50),
  ],
  [
    Offset(0, 100), Offset(100, 50), Offset(0, 50), //
    Offset(100, 0), Offset(100, 100), Offset(50, 100), Offset(50, 0),
  ],
  [
    Offset(0, 0), Offset(50, 100), Offset(50, 0), //
    Offset(100, 100), Offset(0, 100), Offset(0, 50), Offset(100, 50),
  ],
];

class Case43GetProButton extends StatefulWidget {
  const Case43GetProButton({super.key});

  @override
  State<Case43GetProButton> createState() => _Case43GetProButtonState();
}

class _Case43GetProButtonState extends State<Case43GetProButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(microseconds: (_loopMs * 1000).round()),
  )..repeat();

  /// 药丸宽度 = 字宽 + 左右 18，量的和画的同一套数
  late final double _pillW = _measure() + _pillPadX * 2;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _measure() {
    final p = TextPainter(
      text: const TextSpan(text: _label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = p.width;
    p.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Center(
        child: SizedBox(
          width: _pillW,
          height: _pillH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _pillBg,
              borderRadius: BorderRadius.circular(_pillRadius),
              boxShadow: const [_drop],
              border: Border.all(color: _hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_pillRadius - 1),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 内描边那道压暗（CSS 是 -1px 的 inset 影）画在水层底下
                  const Positioned(
                    left: 1,
                    right: 1,
                    bottom: 0,
                    height: 1,
                    child: ColoredBox(color: _bottomLine),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ListenableBuilder(
                        listenable: _c,
                        builder: (context, _) => CustomPaint(
                          painter: _RimPainter(elapsed: _c.value * _loopMs),
                        ),
                      ),
                    ),
                  ),
                  const Text(_label, style: _labelStyle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 水层 + 边缘遮罩 + 6px 糊 + 0.7 总透明度
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.elapsed});

  final double elapsed;

  double get _hue => -360 * ((elapsed % _hueDur.inMilliseconds) / _hueDur.inMilliseconds);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();

    // 组透明度：整层一起压到 0.7，别让每层各自乘一遍
    canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, _rimOpacity));
    // 糊在水纹上、遮罩之前（CSS 的 filter 排在 mask 之前生效）
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: _rimBlur,
          sigmaY: _rimBlur,
          tileMode: TileMode.decal,
        ),
    );
    for (var i = _washes.length - 1; i >= 0; i--) {
      _wash(canvas, paint, rect, i);
    }
    canvas.restore();

    _rimMask(canvas, rect);
    canvas.restore();
  }

  void _wash(Canvas canvas, Paint paint, Rect rect, int i) {
    final w = _washes[i];
    final pos = _position(i);
    // 背景盒宽 180%，位置 0% 时左边缘在 -0.8W ⇒ 圆心在 0.9W
    final center = Offset(
      rect.width * (0.9 - 0.8 * pos.dx / 100),
      rect.height * (0.9 - 0.8 * pos.dy / 100),
    );
    final rx = w.fx * rect.width;
    final ry = w.fy * rect.height;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    paint.shader = ui.Gradient.radial(Offset.zero, 1.0, _shift(w.colors), w.stops);
    canvas.drawRect(
      Rect.fromLTRB(
        -center.dx / rx,
        -center.dy / ry,
        (rect.width - center.dx) / rx,
        (rect.height - center.dy) / ry,
      ),
      paint,
    );
    canvas.restore();
    paint.shader = null;
  }

  /// 中间挖空、越靠边越实：把画布压回单位圆再画那颗径向渐变
  void _rimMask(Canvas canvas, Rect rect) {
    final center = rect.center;
    final rx = rect.width * _ellipseF;
    final ry = rect.height * _ellipseF;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    // stop 换算：0% → 半径 2.0 的 1/4 处（即椭圆的 50%）还是全透，2.0 处才全实
    final far = _maskTo * math.max(
      math.max((rect.width - center.dx) / rx, center.dx / rx),
      math.max((rect.height - center.dy) / ry, center.dy / ry),
    );
    canvas.drawRect(
      Rect.fromLTRB(-far, -far, far, far),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          Offset.zero,
          _maskTo,
          const [Color(0x00000000), Color(0x00000000), Color(0xFF000000)],
          [0, _maskFrom / _maskTo, 1],
        ),
    );
    canvas.restore();
  }

  Offset _position(int i) {
    final u = elapsed / _segMs;
    final n = _frames.length;
    final s = (u.floor() % n + n) % n;
    final a = _frames[s][i];
    final b = _frames[(s + 1) % n][i];
    final k = LabEase.inOut.transform(u - u.floor());
    return Offset(a.dx + (b.dx - a.dx) * k, a.dy + (b.dy - a.dy) * k);
  }

  List<Color> _shift(List<Color> colors) {
    return [
      for (final c in colors)
        () {
          final hsv = HSVColor.fromColor(c);
          if (hsv.saturation <= 0) return c;
          final s = math.min(hsv.saturation * 1.3, 1.0);
          final h = ((hsv.hue + _hue) % 360 + 360) % 360;
          return hsv.withHue(h).withSaturation(s).toColor().withAlpha((c.a * 255).round());
        }()
    ];
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.elapsed != elapsed;
}
