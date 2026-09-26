import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';


import '../lab_kit.dart';

/// 24. 3D tilt — 卡片跟着指针连续倾斜，高光跟着指针跑
///
/// 这一格不是"悬停开/关"的补间：指针在卡面上每动一点，`rotateX/rotateY`
/// 和高光圆心都要跟着改（原稿就是每次移动把四个自定义属性写回去）。
/// 所以倾角由 `onHover` 的局部坐标归一化后直接算，两端各 ±max/2，
/// 只有两档时长——移动中 400ms（跟手但不抖），离开 1000ms 慢慢躺平。
/// 归位比跟随慢是这套观感的关键，别统一成一个值。
/// 高光只补间 opacity（300ms 淡到 `--p19-glare-opacity`），圆心用**未经补间的
/// 原始指针位置**：原稿里位置那几个变量本来就没有 transition，
/// 跟着缓动值走的话光斑会拖在指针后面。
/// `perspective(1000px)` 落成 m34 = -1/1000，顺序 perspective → rotateX → rotateY。
const _cardW = 192.0;
const _cardH = 106.0;
const _radius = 12.0;

/// `max = 32`（度）：指针走到边缘时的倾角
const _maxTilt = 32.0;

/// `--tilt-perspective: 1000px`
const _perspective = 1000.0;

const _followDur = Duration(milliseconds: 400); // `--p19-follow-dur`
const _returnDur = Duration(milliseconds: 1000); // `--p19-return-dur`
const _glareFade = Duration(milliseconds: 300); // `--p19-glare-fade`
const _glareOpacity = 0.32; // `--p19-glare-opacity`

/// `.p19-card`：浅色盘下是一块中性灰卡面 + 两层投影
const _cardBg = Color(0xFF6A6A6A);
const _cardShadow = <BoxShadow>[
  BoxShadow(color: Color(0x30000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
];

/// `.p19-card::before`：固定方向的斜向高光，和跟随高光各管各的。
/// 135deg 换算到 Alignment 就是左上→右下这条对角线
const _sheen = LinearGradient(
  begin: Alignment(-0.7071, -0.7071),
  end: Alignment(0.7071, 0.7071),
  colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
  stops: [0, 0.42],
);

/// 卡面文字：9.17/13.755 白字
const _faceStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 9.17,
  height: 13.755 / 9.17,
  color: Color(0xFFFFFFFF),
);

/// 姓名/卡号那两行走等宽数字（`.p19-name/.p19-num` 用的是 mono 字体档）
const _monoStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 9.17,
  height: 13.755 / 9.17,
  color: Color(0xFFFFFFFF),
  fontFeatures: LabFont.tabular,
);

const _visaStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.5,
  height: 1,
  color: Color(0xFFFFFFFF),
);

/// 内缩 13.76 是原稿量出来的数，别圆成 14
const _inset = 13.76;

class Case24Tilt3D extends StatefulWidget {
  const Case24Tilt3D({super.key});

  @override
  State<Case24Tilt3D> createState() => _Case24Tilt3DState();
}

class _Case24Tilt3DState extends State<Case24Tilt3D> {
  bool _hovering = false;

  /// 指针在卡面上的归一化位置；0.5 正好是"躺平"那一档，也是复位目标
  double _px = 0.5;
  double _py = 0.5;

  /// 把指针落点归一化到 0..1；卡面外的落点钳在边上，别让倾角越过 max
  void _track(Offset local) {
    final nx = (local.dx / _cardW).clamp(0.0, 1.0).toDouble();
    final ny = (local.dy / _cardH).clamp(0.0, 1.0).toDouble();
    if (_hovering && nx == _px && ny == _py) return;
    setState(() {
      _hovering = true;
      _px = nx;
      _py = ny;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            // 悬停区域是这块没变形的 192×106 外框：
            // 让倾斜后的卡面自己去接指针，卡角一抬指针就"掉出去"了
            child: LabHoverRegion(
              // 触屏按点按落点定倾角，再点一下回正
              group: 'c24',
              onHoverAt: _track,
              // 离开时只收倾角，不抹指针位置：光斑留在最后待过的地方淡出去
              onExit: () => setState(() => _hovering = false),
              child: SizedBox(
                width: _cardW,
                height: _cardH,
                child: LabTween(
                  target: _hovering ? _px : 0.5,
                  duration: _hovering ? _followDur : _returnDur,
                  curve: LabEase.smoothOut,
                  builder: (context, tx) => LabTween(
                    target: _hovering ? _py : 0.5,
                    duration: _hovering ? _followDur : _returnDur,
                    curve: LabEase.smoothOut,
                    builder: (context, ty) => LabTween(
                      target: _hovering ? 1 : 0,
                      duration: _glareFade,
                      curve: LabEase.smoothOut,
                      builder: (context, glow) => _Card(
                        tiltX: (0.5 - ty) * _maxTilt,
                        tiltY: (tx - 0.5) * _maxTilt,
                        glare: glow * _glareOpacity,
                        glareAt: Offset(_px * _cardW, _py * _cardH),
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
}

/// 卡面：倾斜的是整块（含文字和高光），所以高光也在圆角 clip 里面
class _Card extends StatelessWidget {
  const _Card({
    required this.tiltX,
    required this.tiltY,
    required this.glare,
    required this.glareAt,
  });

  /// 单位：度
  final double tiltX;
  final double tiltY;
  final double glare;
  final Offset glareAt;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, -1 / _perspective)
        ..rotateX(tiltX * math.pi / 180)
        ..rotateY(tiltY * math.pi / 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: _cardBg, boxShadow: _cardShadow),
          child: SizedBox(
            width: _cardW,
            height: _cardH,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(decoration: BoxDecoration(gradient: _sheen)),
                ),
                const Positioned(
                  left: _inset,
                  top: 14.05,
                  child: Opacity(opacity: 0.9, child: Text('Credit', style: _faceStyle)),
                ),
                const Positioned(right: _inset, top: 11, child: Text('VISA', style: _visaStyle)),
                const Positioned(left: _inset, top: 64.76, child: Text('John Smith', style: _monoStyle)),
                const Positioned(
                  left: _inset,
                  top: 78.52,
                  child: Text('4111 - 1111 - 1111 - 1111', style: _monoStyle),
                ),
                // 整层不接指针：它盖在卡面上，接了就抢走 onHover。
                // 淡入淡出直接乘进画笔颜色的 alpha，不走 Opacity——
                // 外面套一层 Opacity 会先开一个透明缓存，screen 就没东西可叠了
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GlarePainter(at: glareAt, alpha: glare)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 跟随指针的四层柔光：screen 叠亮，亮度由 alpha 参数管淡入淡出
class _GlarePainter extends CustomPainter {
  const _GlarePainter({required this.at, required this.alpha});

  final Offset at;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.001) return;
    // saveLayer 是为了让 screen 拿到卡面当背景，否则只是叠在透明层上
    canvas.saveLayer(Offset.zero & size, Paint());
    final paint = Paint()..blendMode = BlendMode.screen;
    for (final layer in _GlareLayer.all) {
      paint.shader = ui.Gradient.radial(
        layer.shift == null ? at : at + layer.shift!,
        layer.radius,
        [for (final c in layer.colors) _fade(c)],
        layer.stops,
      );
      canvas.drawRect(Offset.zero & size, paint);
    }
    canvas.restore();
  }

  /// 按淡入进度整体压暗一层：只动 alpha，颜色本身保持纯白
  Color _fade(Color c) => c.withAlpha(((c.a * 255) * alpha.clamp(0.0, 1.0)).round());

  @override
  bool shouldRepaint(_GlarePainter old) => old.at != at || old.alpha != alpha;
}

class _GlareLayer {
  const _GlareLayer(this.radius, this.shift, this.colors, this.stops);

  /// CSS 的 `circle Npx at ...`
  final double radius;

  /// 第四层那种偏一点的小亮斑，其余圆心就在指针上
  final Offset? shift;
  final List<Color> colors;
  final List<double> stops;

  /// 半径末端之前完全收干净（对应 CSS 渐变的最后一个 stop）
  static const _out = Color(0x00FFFFFF);

  static const all = <_GlareLayer>[
    _GlareLayer(95, null, [Color(0x7AFFFFFF), Color(0x0FFFFFFF), _out], [0, 0.52, 0.84]),
    _GlareLayer(200, null, [Color(0x38FFFFFF), Color(0x0AFFFFFF), _out], [0, 0.58, 0.78]),
    _GlareLayer(360, null, [Color(0x1AFFFFFF), _out], [0, 0.88]),
    _GlareLayer(55, Offset(14, -17), [Color(0x52FFFFFF), _out], [0, 0.74]),
  ];
}
