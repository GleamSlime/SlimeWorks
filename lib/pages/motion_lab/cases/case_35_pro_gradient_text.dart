import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 35. Pro gradient text — 七团彩色水绕着字跑，色相自己也在转
///
/// 参考稿这行字没有"颜色"：`background-clip: text` + `color: transparent`，
/// 看到的完全是那 8 层背景（一层灰色纵向渐变打底 + 7 层彩色径向），
/// 每层占元素的 180%，靠 `background-position` 从 0% 推到 100% 让色团横扫过字面。
/// 四档关键帧把 7 层的落点排成环（同一层在 0%/25%/50%/75% 各换一个角落），
/// 每段 1250ms、各自 ease-in-out，整圈 5000ms；另一条 4000ms 的 linear
/// 把整层色相转掉 360° 并提饱和 1.3。两条周期互质，20000ms 才重样一次。
/// 色团半轴由 `gradientTransform` 的两个列向量长度折算（先换成占背景盒的比例，
/// 再乘 1.8 回到元素坐标系），圆心就是那一层背景盒的正中。
const _text = 'Pro';

/// `.pv17`：44/500、行高 1、字距 -0.01em（44px 下就是 -0.44）
const _style = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 44,
  fontWeight: FontWeight.w500,
  height: 1,
  letterSpacing: -0.44,
);

/// 背景最底下那层灰：`linear-gradient(#6c6c6c 0%, #d8d8d8 100%)`，尺寸 100%、不跟着跑
const _baseColors = [Color(0xFF6C6C6C), Color(0xFFD8D8D8)];

const _segMs = 1250.0; // 5000ms / 4 段（`--pvx`）
const _hueDur = Duration(milliseconds: 4000); // `--pv18`
const _loopMs = 20000.0; // 两条周期的公倍数，一个完整回合

/// 一层彩色水：半轴按元素宽/高计，颜色里已带这层自己的 opacity
class _Wash {
  const _Wash(this.fx, this.fy, this.colors, this.stops);

  final double fx;
  final double fy;
  final List<Color> colors;
  final List<double> stops;
}

/// CSS `background-image` 的列表顺序（第一项压在最上面）
const _washes = [
  // 0.88 蓝：半径只有元素的 9% × 38%，是一颗贴着字心的小亮点
  _Wash(0.093, 0.384, [Color(0xE1006EF5), Color(0x00006EF5)], [0, 1]),
  // 0.5 蓝：横向 36%、纵向铺开，负责把上半段染蓝
  _Wash(0.356, 1.296, [Color(0x80006EF5), Color(0x00006EF5)], [0, 1]),
  // 0.4 紫红：0.717 处就收干净
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

/// 关键帧给的四档 `background-position`（百分比，成对给 X/Y），顺序对齐 `_washes`
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

class Case35ProGradientText extends StatefulWidget {
  const Case35ProGradientText({super.key});

  @override
  State<Case35ProGradientText> createState() => _Case35ProGradientTextState();
}

class _Case35ProGradientTextState extends State<Case35ProGradientText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(microseconds: (_loopMs * 1000).round()),
  )..repeat();

  /// 字只在挂载时量一次：度量和画笔用的是同一副 style
  late final TextPainter _tp = TextPainter(
    text: TextSpan(text: _text, style: _style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Center(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => CustomPaint(
            size: Size(_tp.width, _tp.height),
            painter: _WashPainter(tp: _tp, elapsed: _c.value * _loopMs),
          ),
        ),
      ),
    );
  }
}

/// 八层背景铺满字身的外框，再拿字形当遮罩把外面裁掉
class _WashPainter extends CustomPainter {
  const _WashPainter({required this.tp, required this.elapsed});

  final TextPainter tp;

  /// 毫秒，两条周期各自取模
  final double elapsed;

  /// `filter: hue-rotate(-360deg·t) saturate(1.3)`
  double get _hue => -360 * ((elapsed % _hueDur.inMilliseconds) / _hueDur.inMilliseconds);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();

    canvas.saveLayer(rect, Paint());
    paint.shader = labLinearGradient(180, _shift(_baseColors)).createShader(rect);
    canvas.drawRect(rect, paint);
    paint.shader = null;
    // 列表从下往上画，第一层才盖在最上面
    for (var i = _washes.length - 1; i >= 0; i--) {
      _wash(canvas, paint, rect, i);
    }

    // 文字单独成层再以 dstIn 合成：留下的就是"背景 ∩ 字形"
    canvas.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    canvas.restore();
  }

  /// 一层水：圆心由该层当前的 background-position 推出来
  void _wash(Canvas canvas, Paint paint, Rect rect, int i) {
    final w = _washes[i];
    final pos = _position(i);
    // 背景盒宽 180%，位置 0% 时左边缘在 -0.8W ⇒ 圆心在 0.9W；100% 时退到 0.1W
    final center = Offset(
      rect.width * (0.9 - 0.8 * pos.dx / 100),
      rect.height * (0.9 - 0.8 * pos.dy / 100),
    );
    final rx = w.fx * rect.width;
    final ry = w.fy * rect.height;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(rx, ry);
    // 径向渐变在缩放的单位圆上画，铺满整个外框（半径之外是最后一个 stop 的透明）
    final l = -center.dx / rx;
    final t = -center.dy / ry;
    final r = (rect.width - center.dx) / rx;
    final b = (rect.height - center.dy) / ry;
    paint.shader = ui.Gradient.radial(Offset.zero, 1.0, _shift(w.colors), w.stops);
    canvas.drawRect(Rect.fromLTRB(l, t, r, b), paint);
    canvas.restore();
    paint.shader = null;
  }

  /// 四档关键帧之间插值，每段各自 ease-in-out
  Offset _position(int i) {
    final u = elapsed / _segMs;
    final n = _frames.length;
    final s = (u.floor() % n + n) % n;
    final a = _frames[s][i];
    final b = _frames[(s + 1) % n][i];
    final k = LabEase.inOut.transform(u - u.floor());
    return Offset(
      a.dx + (b.dx - a.dx) * k,
      a.dy + (b.dy - a.dy) * k,
    );
  }

  /// 灰色那层没有色相可转，饱和也提不起来，所以只动彩色层
  List<Color> _shift(List<Color> colors) {
    return [
      for (final c in colors)
        () {
          final hsv = HSVColor.fromColor(c);
          if (hsv.saturation <= 0) return c;
          final s = math.min(hsv.saturation * 1.3, 1.0);
          // 负角度取模在 Dart 里会落到负区间，withHue 只收 0..360
          final h = ((hsv.hue + _hue) % 360 + 360) % 360;
          return hsv.withHue(h).withSaturation(s).toColor().withAlpha(
                (c.a * 255).round(),
              );
        }()
    ];
  }

  @override
  bool shouldRepaint(_WashPainter old) => old.elapsed != elapsed;
}
