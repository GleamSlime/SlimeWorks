import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart' show CircularIntervalList, dashPath;

import '../lab_kit.dart';

/// 20. Drag & drop with physics — 拖拽方块，落区"吞"下图片再回弹
///
/// 全场景由一个 2950ms 的脚本时间线驱动（松手命中时也挂到这条线的中段），
/// 每段时长/曲线照抄 token：
/// 抬起 scale 200ms 顺出（`--pv40`）、落回 500ms `--pv30`(0.34,1.56,0.64,1)，
/// 源图淡没 450ms `--pv3k`(0.34,1.35,0.64,1)+blur2（`--pv3z`），
/// 落图淡入 400ms ease-in-out（`--pv4c`/`--pv3l`）、落定弹 250ms+收尾 450ms，
/// 掏空 400ms 顺出（`--pv4d`）后 250ms 原地重生（`--pv2z`）。
///
/// 偏离说明：参考稿只在真拖拽时演这条线；golden 环境里指针事件不保证送达，
/// 所以"悬停缩略图"也会跑一遍完整投递脚本，两种触发共用同一时间线。
const _seqTotal = 2950.0;

/// 脚本各段起点/时长（ms）
const _liftEnd = 200.0;
const _travelEnd = 1000.0;
const _fadeStart = 1000.0;
const _fadeDur = 450.0; // `--pv3z`
const _fillDur = 400.0; // `--pv4c`
const _popDur = 250.0; // `--pv3y`
const _settleDur = 450.0; // `--pv4n`
const _emptyStart = 2300.0;
const _emptyDur = 400.0; // `--pv4d`
const _respawnDur = 250.0; // `--pv2z`
const _smokeDur = 1500.0; // `--pv41`

/// `--pv30`：落回用的强弹
const _bounce = Cubic(0.34, 1.56, 0.64, 1);

/// `--pv3k`：淡没用的轻弹
const _fadeEase = Cubic(0.34, 1.35, 0.64, 1);

/// 容器 `.pv57`：213×192，在舞台内居中
const _box = Offset(41.5, 34);

/// 落区 `.pv58`：104×104，圆角 12，虚线 2px（`--pv31`）
const _zoneTL = Offset(0, 88);
const _zoneSize = 104.0;
const _borderW = 2.0;

/// 源缩略图 `.pv54`：72×72，圆角 12
const _srcHomeTL = Offset(141, 0);
const _srcSize = 72.0;

/// 演示脚本里源图落点：贴住落区中心
const _demoDropTL = Offset(52 - 36, 140 - 36);

/// `--pv2y`：浮起投影（源图与落定后的落区共用）
const _floatShadow = <BoxShadow>[
  BoxShadow(color: Color(0x26000000), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, 4)),
];

/// `--pv35`：落定时弹到的倍率
const _landScale = 1.05;

/// 抬起时的 scale（lift 变量语料未公开值，与落定弹取同一档）
const _liftScale = 1.05;

class Case20DragDropWithPhysics extends StatefulWidget {
  const Case20DragDropWithPhysics({super.key});

  @override
  State<Case20DragDropWithPhysics> createState() =>
      _Case20DragDropWithPhysicsState();
}

class _Case20DragDropWithPhysicsState extends State<Case20DragDropWithPhysics>
    with TickerProviderStateMixin {
  /// 投递脚本（0→1 线性，各属性在 build 里按段取数）
  late final AnimationController _seq =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2950));

  /// 松手没进落区时的回弹（0→1）
  late final AnimationController _ret = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

  /// 拖拽中指针悬在落区上的高亮（150ms，`--pv58.is-over`）
  late final AnimationController _over = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 150));

  /// 抓起后的抬升 scale（200ms `--pv40`）
  late final AnimationController _lift = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));

  bool _seqActive = false;
  bool _returning = false;
  Offset _seqFromTL = _srcHomeTL;
  Offset _seqToTL = _demoDropTL;

  bool _dragging = false;
  Offset _dragTL = _srcHomeTL;
  double _dragTilt = 0;
  Offset _retFromTL = _srcHomeTL;
  double _retFromTilt = 0;

  @override
  void initState() {
    super.initState();
    for (final c in [_seq, _ret, _over, _lift]) {
      c.addListener(_rebuild);
    }
    _seq.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        // 收尾状态与空闲帧一致，直接归零等待下一次
        setState(() {
          _seqActive = false;
          _seq.value = 0;
        });
      }
    });
    _ret.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() {
          _returning = false;
          _ret.value = 0;
        });
      }
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _seq.dispose();
    _ret.dispose();
    _over.dispose();
    _lift.dispose();
    super.dispose();
  }

  bool get _busy => _seqActive || _dragging || _returning;

  /// 悬停缩略图 = 自动演示一次完整投递（golden 里指针事件不可靠的兜底触发）
  void _startDemo() {
    if (_busy) return;
    setState(() {
      _seqActive = true;
      _seqFromTL = _srcHomeTL;
      _seqToTL = _demoDropTL;
    });
    _seq.forward(from: 0);
  }

  void _onPanStart(DragStartDetails d) {
    if (_busy) return;
    setState(() {
      _dragging = true;
      _dragTL = _srcHomeTL;
      _dragTilt = 0;
    });
    _lift.animateTo(1, curve: LabEase.smoothOut);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() {
      _dragTL = _dragTL + d.delta;
      // 倾角跟横向速度走：语料未公开数值，按 ±3°（`--pv2e`）封顶
      _dragTilt = (_dragTilt * 0.6 + d.delta.dx * 0.9).clamp(-3.0, 3.0);
    });
    _over.animateTo(_zoneHit() ? 1 : 0);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    final hit = _zoneHit();
    setState(() => _dragging = false);
    _over.animateTo(0);
    if (hit) {
      // 命中：从脚本的"松手"一刻继续，源图就在松手位置淡没
      setState(() {
        _seqActive = true;
        _seqFromTL = _dragTL;
        _seqToTL = _dragTL;
      });
      _lift.animateTo(0, duration: const Duration(milliseconds: 500), curve: _bounce);
      _seq.value = _fadeStart / _seqTotal;
      _seq.animateTo(1, duration: const Duration(milliseconds: 1950));
    } else {
      // 落空：回弹（translate/rotate/scale 500ms `--pv36`/`--pv30`）
      setState(() {
        _returning = true;
        _retFromTL = _dragTL;
        _retFromTilt = _dragTilt;
      });
      _lift.animateTo(0, curve: _bounce);
      _ret.forward(from: 0);
    }
  }

  bool _zoneHit() {
    final c = _dragTL + const Offset(_srcSize / 2, _srcSize / 2);
    return c.dx > _zoneTL.dx &&
        c.dx < _zoneTL.dx + _zoneSize &&
        c.dy > _zoneTL.dy &&
        c.dy < _zoneTL.dy + _zoneSize;
  }

  static double _seg(double ms, double start, double dur, Curve curve) =>
      curve.transform(((ms - start) / dur).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final ms = _seqActive ? _seq.value * _seqTotal : 0.0;

    // ---- 源图：位置 / 倾斜 / 透明度 / 模糊 ----
    final Offset tl;
    double tilt;
    double opacity = 1;
    double blur = 0;
    if (_returning) {
      final p = _bounce.transform(_ret.value);
      tl = Offset.lerp(_retFromTL, _srcHomeTL, p)!;
      tilt = _retFromTilt * (1 - p);
    } else if (_dragging) {
      tl = _dragTL;
      tilt = _dragTilt;
    } else if (_seqActive) {
      final travel = _seg(ms, _liftEnd, _travelEnd - _liftEnd, LabEase.smoothOut);
      tl = Offset.lerp(_seqFromTL, _seqToTL, travel)!;
      tilt = travel > 0 && travel < 1
          ? 3 * math.sin(math.pi * travel) * (_seqToTL.dx < _seqFromTL.dx ? -1 : 1)
          : 0.0;
      if (ms >= _fadeStart) {
        final fade = _seg(ms, _fadeStart, _fadeDur, _fadeEase);
        final respawn = _seg(ms, _emptyStart + _emptyDur, _respawnDur, LabEase.smoothOut);
        opacity = (1 - fade + respawn).clamp(0.0, 1.0);
        blur = (2 * (fade - respawn)).clamp(0.0, 2.0);
      }
    } else {
      tl = _srcHomeTL;
      tilt = 0;
    }
    // 脚本段的抬升自己走时间线，只有真拖拽才用 _lift
    final liftP = _seqActive
        ? (_seg(ms, 0, _liftEnd, LabEase.smoothOut) -
                _seg(ms, _fadeStart, _fadeDur, LabEase.smoothOut))
            .clamp(0.0, 1.0)
        : _lift.value;
    final scale = 1 + (_liftScale - 1) * liftP;

    // ---- 落区：填充 / 落定弹 / 高亮 ----
    final fillIn = _seqActive ? _seg(ms, _fadeStart, _fillDur, Curves.easeInOut) : 0.0;
    final emptyOut = _seqActive
        ? _seg(ms, _emptyStart, _emptyDur, LabEase.smoothOut)
        : 0.0;
    final filled = (fillIn - emptyOut).clamp(0.0, 1.0);
    final landPop = _seqActive
        ? 1 + (_landScale - 1) *
            (_seg(ms, _fadeStart, _popDur, LabEase.smoothOut) -
                _seg(ms, _fadeStart + _popDur, _settleDur, LabEase.smoothOut))
        : 1.0;
    final overT = _over.value;

    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: _box.dx,
            top: _box.dy,
            child: SizedBox(
              width: 213,
              height: 192,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _zoneTL.dx,
                    top: _zoneTL.dy,
                    child: Transform.scale(
                      scale: landPop,
                      child: _DropZone(
                        over: overT,
                        filled: filled,
                        fillOpacity: filled,
                        fillBlur: 4 * emptyOut,
                      ),
                    ),
                  ),
                  if (_seqActive && ms >= _fadeStart && ms < _fadeStart + _smokeDur)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SmokePainter(
                              (ms - _fadeStart) / _smokeDur),
                        ),
                      ),
                    ),
                  Positioned(
                    left: tl.dx,
                    top: tl.dy,
                    child: Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.rotate(
                        angle: tilt * math.pi / 180,
                        child: Transform.scale(
                          scale: scale,
                          child: LabBlur(
                            sigma: blur,
                            child: _DraggableSource(
                              canDrag: !_busy,
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              onHoverIn: _startDemo,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 落区：虚线框 + "Drag & drop it here" + 落入后的整幅图
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.over,
    required this.filled,
    required this.fillOpacity,
    required this.fillBlur,
  });

  /// is-over 高亮进度（边框加深、底色加重）
  final double over;

  /// is-filled 进度（虚线让位给投影）
  final double filled;
  final double fillOpacity;
  final double fillBlur;

  @override
  Widget build(BuildContext context) {
    final borderAlpha = (0.10 + 0.18 * over) * (1 - filled);
    return Container(
      width: _zoneSize,
      height: _zoneSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Color.fromRGBO(234, 234, 234, 0.2 + 0.35 * over),
        boxShadow: filled > 0.01
            ? [
                for (final s in _floatShadow)
                  BoxShadow(
                    color: s.color.withValues(alpha: s.color.a * filled),
                    blurRadius: s.blurRadius,
                    offset: s.offset,
                  ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DashedBorderPainter(borderAlpha),
            ),
          ),
          // 提示文字：over 时压到 0.5，filled 后淡没
          Positioned(
            left: 0,
            right: 0,
            top: 38,
            child: Opacity(
              opacity: (1 - 0.5 * over) * (1 - filled),
              child: const SizedBox(
                width: 76,
                child: Text(
                  'Drag & drop\nit here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: LabFont.family,
                    fontFamilyFallback: LabFont.fallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 15 / 11,
                    color: LabColor.textSubtle,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: fillOpacity.clamp(0.0, 1.0),
                child: LabBlur(
                  sigma: fillBlur,
                  child: const _PhotoTile(size: _zoneSize),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2px 虚线边框（CSS dashed 的近似：4/4 段）
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter(this.alpha);

  static final CircularIntervalList<double> _dashes =
      CircularIntervalList<double>(<double>[4, 4]);

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0.001) return;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_borderW / 2, _borderW / 2,
              size.width - _borderW, size.height - _borderW),
          const Radius.circular(11),
        ),
      );
    canvas.drawPath(
      dashPath(path, dashArray: _dashes),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _borderW
        ..color = const Color(0xFF000000).withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.alpha != alpha;
}

/// 可拖的源缩略图：手势 + grab 光标 + 悬停触发自动演示
class _DraggableSource extends StatelessWidget {
  const _DraggableSource({
    required this.canDrag,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onHoverIn,
  });

  final bool canDrag;
  final void Function(DragStartDetails) onPanStart;
  final void Function(DragUpdateDetails) onPanUpdate;
  final void Function(DragEndDetails) onPanEnd;
  final VoidCallback onHoverIn;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: canDrag ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      onEnter: (_) => onHoverIn(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 触屏里竖着划会被页面滚走，手动拖拽在手机上使不上劲；
        // 给指尖留一条入口：点一下同样跑完整段投递演示
        onTap: onHoverIn,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: const _PhotoTile(size: _srcSize),
      ),
    );
  }
}

/// 图片占位：参考稿用的是真实截图，语料不带资产且位图出图会糊，
/// 用浅灰渐变 + 描边图片符号代替
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.size});

  final double size;

  static const _paths = [
    'M3.5 1.5H12.5A2 2 0 0 1 14.5 3.5V12.5A2 2 0 0 1 12.5 14.5H3.5A2 2 0 0 1 1.5 12.5V3.5A2 2 0 0 1 3.5 1.5Z',
    'M6.75 5.5A1.25 1.25 0 1 1 4.25 5.5A1.25 1.25 0 1 1 6.75 5.5Z',
    'M14.5 10.5L11 7l-7.5 7.5',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9EAEE), Color(0xFFF3F4F7)],
        ),
        boxShadow: _floatShadow,
      ),
      alignment: Alignment.center,
      child: LabIcon(
        paths: _paths,
        size: size * 0.33,
        strokeWidth: 1.4,
        color: LabColor.iconMuted,
      ),
    );
  }
}

/// "烟"爆开：落图瞬间从落区中心散出的柔光点（近似参考稿的湍流滤镜烟团）
class _SmokePainter extends CustomPainter {
  const _SmokePainter(this.q);

  /// 0→1 的消散进度
  final double q;

  @override
  void paint(Canvas canvas, Size size) {
    final center = _zoneTL + const Offset(_zoneSize / 2, _zoneSize / 2);
    for (final p in _seeds) {
      final t = q * p.life;
      final pos = center +
          Offset(
            p.vx * t + p.sway * math.sin(t * 2.4 + p.phase),
            p.vy * t - 26 * t * t,
          );
      final a = (p.alpha * (1 - q / p.life)).clamp(0.0, 1.0);
      if (a <= 0.005) continue;
      canvas.drawCircle(
        pos,
        p.r * (1 + q * 0.8),
        Paint()
          ..color = const Color(0xFF9A9AA2).withValues(alpha: a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_SmokePainter old) => old.q != q;
}

/// 固定种子预生成，帧帧一致
List<_SmokeSeed> _makeSmoke() {
  final rnd = math.Random(20);
  return List<_SmokeSeed>.generate(10, (i) {
    final ang = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 2.4;
    final sp = 34 + rnd.nextDouble() * 52;
    return _SmokeSeed(
      vx: math.cos(ang) * sp,
      vy: math.sin(ang) * sp * 0.9,
      r: 4 + rnd.nextDouble() * 5,
      alpha: 0.20 + rnd.nextDouble() * 0.18,
      sway: 4 + rnd.nextDouble() * 8,
      phase: rnd.nextDouble() * math.pi * 2,
      life: 0.6 + rnd.nextDouble() * 0.4,
    );
  });
}

final _seeds = _makeSmoke();

class _SmokeSeed {
  const _SmokeSeed({
    required this.vx,
    required this.vy,
    required this.r,
    required this.alpha,
    required this.sway,
    required this.phase,
    required this.life,
  });

  final double vx;
  final double vy;
  final double r;
  final double alpha;
  final double sway;
  final double phase;
  final double life;
}
