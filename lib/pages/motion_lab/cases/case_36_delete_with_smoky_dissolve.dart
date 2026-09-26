import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 36. Delete with smoky dissolve — 图片碎成瓦片往下掉，越掉越糊成一团烟
///
/// CSS 这边只留了两件事：整块 120×120 的圆角卡（`--pv2d`）和"复活"那 250ms
/// （`pv1a`：opacity 0→1、scale .96→1、顺出曲线）。碎掉本身全在 canvas 里画，
/// 所以时长/曲线只能按可见结果推：按行错开起步（下面那排先走，读起来才像被拽下去）、
/// 每片自己的落程 560ms、位移走平方（越落越快）、同时缩小 + 淡掉，
/// 整层再补一遍随时间加深的糊（原稿那句 "downscale/upscale pass for the blur"）。
/// 消解层 z-index 3 压在卡上面，所以卡本体在这段是藏起来的——
/// 看到的碎块其实就是那张图，只是切了 64 份、每份还在源空间里被圆角裁过。
const _tile = 120.0; // `--pv2d`
const _radius = 16.0;
const _tileBg = Color(0xFFEEEEEF); // `var(--stage-bg, #eeeeef)` 的兜底值

/// `--pro-surface-shadow`
const _tileShadow = <BoxShadow>[
  BoxShadow(color: LabColor.border, blurRadius: 0, spreadRadius: 1),
  BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x0F000000), blurRadius: 42, offset: Offset(0, 4)),
];

/// `.pv1m`：24 圆、白底 92%、图标 #17181c、一层短投影、换底色 120ms
const _btn = 24.0;
const _btnOffset = 8.0; // top/right 8px
const _btnBg = Color(0xEBFFFFFF);
const _btnBgHover = Color(0xFFFFFFFF);
const _btnIcon = Color(0xFF17181C);
const _btnShadow = BoxShadow(
  color: Color(0x40000000), // rgba(0,0,0,.25)
  blurRadius: 3,
  offset: Offset(0, 1),
);
const _xIconPath = 'M1.5 1.5L8.5 8.5M8.5 1.5L1.5 8.5';

/// 复活：`.pv2c.is-respawning`
const _respawnDur = Duration(milliseconds: 250);
const _respawnFrom = 0.96;

/// 消解段（原稿由脚本驱动，这里按观感定档）
const _dissolveMs = 900.0;
const _staggerMs = 240.0; // 最上排比最下排晚起步这么多
const _shardLifeMs = 560.0;
const _rows = 8;
const _cols = 8;
const _maxFall = 46.0;
const _maxBlur = 3.6;

enum _Phase { shown, dissolving, respawning }

class Case36DeleteWithSmokyDissolve extends StatefulWidget {
  const Case36DeleteWithSmokyDissolve({super.key});

  @override
  State<Case36DeleteWithSmokyDissolve> createState() => _Case36DeleteWithSmokyDissolveState();
}

class _Case36DeleteWithSmokyDissolveState extends State<Case36DeleteWithSmokyDissolve>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _respawnDur);

  _Phase _phase = _Phase.shown;
  bool _hovered = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _delete() {
    if (_phase != _Phase.shown) return;
    setState(() => _phase = _Phase.dissolving);
    _c.duration = Duration(microseconds: (_dissolveMs * 1000).round());
    _c.forward(from: 0).then((_) {
      if (!mounted || _phase != _Phase.dissolving) return;
      // 碎完直接接"复活"，中间不留空帧
      setState(() => _phase = _Phase.respawning);
      _c.duration = _respawnDur;
      _c.forward(from: 0).then((_) {
        if (!mounted || _phase != _Phase.respawning) return;
        setState(() => _phase = _Phase.shown);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            // 消解段本体让位给碎块（那张图就是被切碎的对象）
            opacity: _phase == _Phase.dissolving ? 0 : 1,
            child: _tileWidget(),
          ),
          if (_phase == _Phase.dissolving)
            Positioned.fill(
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => CustomPaint(
                    painter: _ShardPainter(elapsed: _c.value * _dissolveMs),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tileWidget() {
    final respawn = _phase == _Phase.respawning;
    final k = LabEase.smoothOut.transform(_c.value);
    return Transform.scale(
      scale: respawn ? _respawnFrom + (1 - _respawnFrom) * k : 1.0,
      child: Opacity(
        opacity: respawn ? k : 1.0,
        child: SizedBox(
          width: _tile,
          height: _tile,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _tileBg, boxShadow: _tileShadow),
              child: Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _PhotoPainter())),
                  Positioned(top: _btnOffset, right: _btnOffset, child: _deleteButton()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _delete,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120), // transition: background-color 120ms ease
          curve: Curves.ease,
          width: _btn,
          height: _btn,
          decoration: BoxDecoration(
            color: _hovered ? _btnBgHover : _btnBg,
            shape: BoxShape.circle,
            boxShadow: const [_btnShadow],
          ),
          alignment: Alignment.center,
          child: LabIcon(
            paths: const [_xIconPath],
            size: 10,
            viewBox: 10,
            strokeWidth: 1.5,
            color: _btnIcon,
          ),
        ),
      ),
    );
  }
}

/// 一片碎块：格子位置 + 起步时刻 + 自己的落程/横飘/转速
class _Shard {
  const _Shard({
    required this.rect,
    required this.delay,
    required this.fall,
    required this.drift,
    required this.spin,
    required this.puff,
  });

  final Rect rect;
  final double delay;
  final double fall;
  final double drift;
  final double spin;

  /// 落到位后呼出的那团烟的半径
  final double puff;

  /// 进度 0→1；还没起步的返回 0（留在原位，画面才不至于先空一拍），落定的返回 null
  double? progress(double elapsed) {
    final q = (elapsed - delay) / _shardLifeMs;
    if (q <= 0) return 0;
    if (q >= 1) return null;
    return q;
  }
}

/// 落点/时序全用固定种子生成，出图每一版都同一副样子
final List<_Shard> _shards = () {
  final r = math.Random(20260936);
  final cw = _tile / _cols;
  final ch = _tile / _rows;
  final out = <_Shard>[];
  for (var row = 0; row < _rows; row++) {
    for (var col = 0; col < _cols; col++) {
      final fromBottom = _rows - 1 - row;
      out.add(
        _Shard(
          rect: Rect.fromLTWH(col * cw, row * ch, cw, ch),
          delay: fromBottom * (_staggerMs / (_rows - 1)) + r.nextDouble() * 40,
          fall: _maxFall * (0.55 + r.nextDouble() * 0.45),
          drift: (r.nextDouble() - 0.5) * 18,
          spin: (r.nextDouble() - 0.5) * 0.7,
          puff: 5 + r.nextDouble() * 7,
        ),
      );
    }
  }
  return out;
}();

/// 64 块一起落，整层糊度随时间加深
class _ShardPainter extends CustomPainter {
  const _ShardPainter({required this.elapsed});

  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final tileRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: _tile,
      height: _tile,
    );
    final g = (elapsed / _dissolveMs).clamp(0.0, 1.0);
    final sigma = _maxBlur * g * g;
    canvas.saveLayer(
      tileRect.inflate(_maxFall + _maxBlur * 4),
      Paint()
        ..imageFilter = sigma <= 0.05
            ? null
            : ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
    );

    final photo = Rect.fromLTWH(0, 0, _tile, _tile);
    final rrect = RRect.fromRectAndRadius(photo, const Radius.circular(_radius));
    final paint = Paint();
    for (final s in _shards) {
      final q = s.progress(elapsed);
      if (q == null) continue;
      final alpha = 1 - math.pow(q, 1.4).toDouble();
      final center = tileRect.topLeft + s.rect.center;
      canvas.save();
      canvas.translate(center.dx + s.drift * q, center.dy + s.fall * q * q);
      canvas.rotate(s.spin * q);
      canvas.scale(1 - 0.5 * q);
      // 先按格子取这一片，再回到源坐标系把整张图画进去：
      // 圆角是在源空间裁的，所以角上那几块本身就是带圆弧的碎片
      canvas.clipRect(Offset.zero & s.rect.size);
      canvas.translate(-s.rect.center.dx, -s.rect.center.dy);
      canvas.clipRRect(rrect);
      paintPhoto(canvas, photo, alpha);
      canvas.restore();
    }
    _puffs(canvas, tileRect, paint);
    canvas.restore();
  }

  /// 碎块落到一半时呼出的灰烟：起— peak—散，各自跟着自己那片走
  void _puffs(Canvas canvas, Rect tileRect, Paint paint) {
    for (final s in _shards) {
      final q = s.progress(elapsed);
      if (q == null || q < 0.35) continue;
      final k = (q - 0.35) / 0.65;
      final alpha = 0.16 * math.sin(k * math.pi);
      final c = Offset(
        tileRect.left + s.rect.center.dx + s.drift * q * 1.4,
        tileRect.top + s.rect.center.dy + s.fall * q * q - 6 * k,
      );
      final rad = s.puff * (0.6 + 1.5 * k);
      paint.shader = RadialGradient(
        colors: [Color.fromRGBO(122, 128, 138, alpha), const Color(0x007A808A)],
      ).createShader(Rect.fromCircle(center: c, radius: rad));
      canvas.drawCircle(c, rad, paint);
      paint.shader = null;
    }
  }

  @override
  bool shouldRepaint(_ShardPainter old) => old.elapsed != elapsed;
}

/// 占位照片：参考稿用的是位图资产，这里一律本地画——
/// 天空渐变 + 一轮低阳 + 两道山形 + 前景水面，比例全部归一化，任何尺寸同一副样子
const _sky = [Color(0xFF9FB8D8), Color(0xFFE9D9C4)];
const _sunColor = Color(0xFFFFF1DA);
const _ridgeFar = Color(0xFF7D8A99);
const _ridgeNear = Color(0xFF5C6773);
const _waterColor = Color(0xFF46505B);

void paintPhoto(Canvas canvas, Rect r, [double alpha = 1.0]) {
  final paint = Paint()..shader = labLinearGradient(180, _sky).createShader(r);
  canvas.drawRect(r, paint);
  paint.shader = null;

  paint.color = _dim(_sunColor, alpha);
  canvas.drawCircle(Offset(r.left + r.width * 0.72, r.top + r.height * 0.3), r.width * 0.07, paint);

  paint.color = _dim(_ridgeFar, alpha);
  canvas.drawPath(_ridge(r, 0.28, 0.44), paint);
  paint.color = _dim(_ridgeNear, alpha);
  canvas.drawPath(_ridge(r, 0.7, 0.56), paint);

  paint.color = _dim(_waterColor, alpha);
  canvas.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.8, r.width, r.height * 0.2), paint);
}

Color _dim(Color c, double a) => c.withAlpha((c.a * 255 * a).round().clamp(0, 255));

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

/// 整张图（未切碎时）那一层
class _PhotoPainter extends CustomPainter {
  const _PhotoPainter();

  @override
  void paint(Canvas canvas, Size size) => paintPhoto(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_PhotoPainter old) => false;
}
