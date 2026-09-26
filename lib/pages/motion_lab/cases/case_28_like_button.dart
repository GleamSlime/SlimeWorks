import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 28. Like button — 点亮：变色、回弹、随机炸点，四条独立时间线
///
/// 原稿这四条各走各的时长，合成一条就会露馅：
/// 变色/填充 150ms 先把心染红（`--p23-fill-dur`），
/// 图标同时弹一下 350ms（`--p23-pop-dur`，曲线过冲到 1.96，所以是"压一下再顶回来"），
/// 粒子再飞 600ms（`--p23-particle-dur`，ease-out，末段淡出）。
/// 弹和炸只在"点亮"这一次播——原稿把它们绑在 `data-liked="true"` 上，
/// 取消只是颜色退回去，所以这里不反着播，每次从头起。
///
/// 粒子每次点亮的**数量、方向、距离、大小、延迟、时长都是随机的**（原稿那组
/// `--psize/--pdelay/--pdur` 就是留给运行时的）。随机数按"第几次点亮"播种：
/// 第 n 次点击永远是同一副散点，观感随机、出图可复现，两件事不冲突。
const _likeColor = Color(0xFFF40051); // `--p23-color`
const _fillDur = Duration(milliseconds: 150); // `--p23-fill-dur`
const _popDur = Duration(milliseconds: 350); // `--p23-pop-dur`
const _particleDur = Duration(milliseconds: 600); // `--p23-particle-dur`

/// `--p23-pop-ease: cubic-bezier(0.34, 1.96, 0.64, 1)`
const _popEase = Cubic(0.34, 1.96, 0.64, 1);

/// CSS 的 `ease-out`（粒子的分段缓动，不是整套动效的）
const _burstEase = Cubic(0, 0, 0.58, 1);

/// `.p23-like`：36 高药丸，左右内衬 12，图标与文字之间 8
const _btnH = 36.0;
const _btnPadX = 12.0;
const _iconGap = 8.0;
const _iconSize = 16.0;

/// `--p23-particle-size`：直径 2.5
const _dotSize = 2.5;

/// `--p23-particle-dist`：随机距离在这个量的 ±25% 里取
const _dist = 20.0;

/// `--pdelay` 的上限；`--pdur` 在 600ms 的 ±25% 里取
const _maxDelayMs = 80;

/// 一条钟要罩住最晚那颗：600 × 1.25 + 80
const _burstWindowMs = 830;

/// 一次点亮的粒子数：6–12 颗
const _minSparks = 6;
const _maxSparks = 12;

/// 一颗粒子的散点参数（`--px/--py/--psize/--pdelay/--pdur`）
class _Spark {
  const _Spark({
    required this.dir,
    required this.size,
    required this.delayMs,
    required this.durMs,
  });

  /// 终点相对图标中心的位移
  final Offset dir;
  final double size;
  final int delayMs;
  final int durMs;
}

/// 按第 n 次点亮播种，所以同一序号永远生成同一副散点
List<_Spark> _makeSparks(int burstIndex) {
  final rng = math.Random(burstIndex);
  final count = _minSparks + rng.nextInt(_maxSparks - _minSparks + 1);
  return List.generate(count, (_) {
    final angle = rng.nextDouble() * math.pi * 2;
    final dist = _dist * (0.75 + rng.nextDouble() * 0.5);
    return _Spark(
      dir: Offset(math.cos(angle), math.sin(angle)) * dist,
      size: 0.6 + rng.nextDouble() * 0.9,
      delayMs: (rng.nextDouble() * _maxDelayMs).round(),
      durMs: (_particleDur.inMilliseconds * (0.75 + rng.nextDouble() * 0.5)).round(),
    );
  });
}

/// 心形描边的 `d`
const _heartPath =
    'M7.99511 3.42388C6.66221 1.8656 4.4395 1.44643 2.76947 2.87334'
    'C1.09944 4.30026 0.86432 6.68598 2.17581 8.3736C3.26622 9.77674 6.56619'
    ' 12.7361 7.64774 13.6939C7.76874 13.801 7.82925 13.8546 7.89982'
    ' 13.8757C7.96141 13.8941 8.02881 13.8941 8.0904 13.8757C8.16097 13.8546'
    ' 8.22147 13.801 8.34248 13.6939C9.42403 12.7361 12.724 9.77674 13.8144'
    ' 8.3736C15.1259 6.68598 14.9195 4.28525 13.2207 2.87334C11.522 1.46144'
    ' 9.32801 1.8656 7.99511 3.42388Z';

const _labelStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.4,
  color: LabColor.text,
);

class Case28LikeButton extends StatefulWidget {
  const Case28LikeButton({super.key});

  @override
  State<Case28LikeButton> createState() => _Case28LikeButtonState();
}

class _Case28LikeButtonState extends State<Case28LikeButton>
    with TickerProviderStateMixin {
  /// 图标回弹那条 350ms
  late final AnimationController _pop = AnimationController(vsync: this, duration: _popDur);

  /// 粒子飞散那条：窗口要把每颗自己的延迟和最长时间算进去
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _burstWindowMs),
  );

  bool _liked = false;

  /// 本次点亮的散点，以及第几次点亮（散点按它播种）
  List<_Spark> _sparks = const [];
  int _burstIndex = 0;

  @override
  void initState() {
    super.initState();
    _pop.addListener(_rebuild);
    _burst.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pop.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _liked = !_liked);
    if (_liked) {
      // 两个都是"只在点亮时播一次"的动画，所以每次都从头起
      _sparks = _makeSparks(++_burstIndex);
      _pop.forward(from: 0);
      _burst.forward(from: 0);
    } else {
      // 取消只是颜色退回去：动画直接撤掉，不反着播
      _pop.stop();
      _pop.reset();
      _burst.stop();
      _burst.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: Container(
                  height: _btnH,
                  padding: const EdgeInsets.symmetric(horizontal: _btnPadX),
                  decoration: BoxDecoration(
                    color: LabColor.card,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: LabShadow.material,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _iconSize,
                        height: _iconSize,
                        child: LabTween(
                          // 染色和填充共用这一条 150ms：分两条会看出先后
                          target: _liked ? 1 : 0,
                          duration: _fillDur,
                          curve: LabEase.smoothOut,
                          builder: (context, t) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Transform.scale(
                                scale: _popScale,
                                child: _Heart(t: t),
                              ),
                              Positioned.fill(
                                // 粒子从图标中心飞出去，画在描边之上
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _BurstPainter(
                                      sparks: _sparks,
                                      elapsedMs:
                                          _burst.value * _burstWindowMs,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: _iconGap),
                      const Text('Like', style: _labelStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `p23-pop`：0% 1 → 30% .82 → 100% 1，每段各带一次过冲曲线
  double get _popScale {
    final t = _pop.value;
    if (t <= 0.3) {
      return _mix(1, 0.82, _popEase.transform(t / 0.3));
    }
    return _mix(0.82, 1, _popEase.transform((t - 0.3) / 0.7));
  }
}

double _mix(double a, double b, double t) => a + (b - a) * t;

/// 心形：描边常驻，填充是同一颗心的实心版按 150ms 淡进来
class _Heart extends StatelessWidget {
  const _Heart({required this.t});

  /// 0 = 未点亮，1 = 点亮
  final double t;

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(LabColor.text, _likeColor, t)!;
    return Stack(
      children: [
        LabIcon(paths: const [_heartPath], size: _iconSize, strokeWidth: 1.5, color: tint),
        // fill: transparent → currentColor，同一时长同一个进度
        Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: LabIcon(
            paths: const [_heartPath],
            size: _iconSize,
            strokeWidth: 1.5,
            color: _likeColor,
            filled: true,
          ),
        ),
      ],
    );
  }
}

/// 散点粒子：每颗按自己的延迟和时长走同一条三段插值，画在图标中心往外
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.sparks, required this.elapsedMs});

  /// 本次点亮的全部粒子
  final List<_Spark> sparks;

  /// 从点亮那刻算起的毫秒数。0 = 未开始，超出窗口 = 落定（末帧本就透明，两端都不画）
  final double elapsedMs;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();
    for (final s in sparks) {
      final progress = ((elapsedMs - s.delayMs) / s.durMs).clamp(0.0, 1.0);
      if (progress <= 0 || progress >= 1) continue;
      final double opacity;
      final double scale;
      final Offset pos;
      if (progress <= 0.2) {
        // 0% → 20%：从中心 0.4 倍涨到 1 倍，同时淡入
        final t = _burstEase.transform(progress / 0.2);
        opacity = t;
        scale = _mix(0.4, 1, t);
        pos = s.dir * (0.25 * t);
      } else {
        // 20% → 100%：飞到位、缩到 0.6、淡出
        final t = _burstEase.transform((progress - 0.2) / 0.8);
        opacity = 1 - t;
        scale = _mix(1, 0.6, t);
        pos = s.dir * _mix(0.25, 1, t);
      }
      paint.color = _likeColor.withAlpha((255 * opacity.clamp(0.0, 1.0)).round());
      canvas.drawCircle(center + pos, _dotSize * 0.5 * s.size * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.elapsedMs != elapsedMs || !identical(old.sparks, sparks);
}
