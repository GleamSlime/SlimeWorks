import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 28. Like button — 点亮：变色、回弹、八向炸点，四条独立时间线
///
/// 原稿这四条各走各的时长，合成一条就会露馅：
/// 变色/填充 150ms 先把心染红（`--p23-fill-dur`），
/// 图标同时弹一下 350ms（`--p23-pop-dur`，曲线过冲到 1.96，所以是"压一下再顶回来"），
/// 粒子再飞 600ms（`--p23-particle-dur`，ease-out，末段淡出）。
/// 弹和炸只在"点亮"这一次播——原稿把它们绑在 `data-liked="true"` 上，
/// 取消只是颜色退回去，所以这里不反着播，每次从头起。
/// 粒子方向是**写死的八向**（0.57 ≈ 45° 的分量），原稿舞台上就是这个量，
/// 不用随机数：随机会让每次截图对不上，也就没法验收。
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

/// `--p23-particle-dist`
const _dist = 20.0;

/// 八向单位向量 × `--p23-particle-dist`（0.57 = cos45° 的取值）
const _vectors = <Offset>[
  Offset(1, 0),
  Offset(0.57, 0.57),
  Offset(0, 1),
  Offset(-0.57, 0.57),
  Offset(-1, 0),
  Offset(-0.57, -0.57),
  Offset(0, -1),
  Offset(0.57, -0.57),
];

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

  /// 粒子飞散那条 600ms
  late final AnimationController _burst = AnimationController(vsync: this, duration: _particleDur);

  bool _liked = false;

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
                                    painter: _BurstPainter(progress: _burst.value),
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

/// 八向粒子：位置/透明度/缩放三段插值，画在图标中心往外
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress});

  /// 0..1，对应 600ms。0 = 未开始，1 = 落定（原稿末帧就是透明，所以两端都不画）
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint();
    for (final v in _vectors) {
      final dir = v * _dist;
      final double opacity;
      final double scale;
      final Offset pos;
      if (progress <= 0.2) {
        // 0% → 20%：从中心 0.4 倍涨到 1 倍，同时淡入
        final s = _burstEase.transform(progress / 0.2);
        opacity = s;
        scale = _mix(0.4, 1, s);
        pos = dir * (0.25 * s);
      } else {
        // 20% → 100%：飞到位、缩到 0.6、淡出
        final s = _burstEase.transform((progress - 0.2) / 0.8);
        opacity = 1 - s;
        scale = _mix(1, 0.6, s);
        pos = dir * _mix(0.25, 1, s);
      }
      paint.color = _likeColor.withAlpha((255 * opacity.clamp(0.0, 1.0)).round());
      canvas.drawCircle(center + pos, _dotSize * 0.5 * scale, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}
