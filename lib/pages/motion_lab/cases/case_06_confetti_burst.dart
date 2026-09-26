import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 6. Confetti burst — 彩带从按钮上方喷出，重力下坠，1.5s 内淡没
///
/// 参考稿舞台是一张铺满的画布（`.pv1c`，z-index 2 压在按钮下面一层）+ Animate 按钮。
/// 粒子参数在脚本里生成、语料没有公开，所以按可见结果复刻语义：
/// 从按钮正上方（bottom 20 + 高 36 → 顶边 y=204）成扇面向上喷出，
/// 带重力自由落体，整段寿命 1500ms（`--pv41`）内收尾淡出。
/// 所有"随机"都来自固定种子预生成的常量表：t=0 的帧恒为空，出图可复现。
const _life = Duration(milliseconds: 1500); // `--pv41`
const _gravity = 520.0; // px/s²，落体在 1.5s 内刚好穿过舞台底部

/// 喷口：按钮顶边（y=204）上方 2px，水平居中
const _origin = Offset(148, 202);

/// 彩带色盘（语料未公开，按常见庆祝彩带的红/黄/绿/蓝/紫/橙取）
const _palette = [
  Color(0xFFFF6B6B),
  Color(0xFFFFD93D),
  Color(0xFF6BCB77),
  Color(0xFF4D96FF),
  Color(0xFFB983FF),
  Color(0xFFFF9F45),
];

class Case06ConfettiBurst extends StatefulWidget {
  const Case06ConfettiBurst({super.key});

  @override
  State<Case06ConfettiBurst> createState() => _Case06ConfettiBurstState();
}

class _Case06ConfettiBurstState extends State<Case06ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: _life);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _fire() => _c.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            // 画布不吃手势（pointer-events:none），只有按钮能点
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_c.value)),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _fire)],
          ),
        ],
      ),
    );
  }
}

/// 一颗彩带的预生成参数：出射角/速度/尺寸/翻面频率/延后起跳
class _Piece {
  const _Piece({
    required this.speed,
    required this.angle,
    required this.w,
    required this.h,
    required this.color,
    required this.spin,
    required this.flip,
    required this.delay,
    required this.round,
  });

  final double speed;
  final double angle;
  final double w;
  final double h;
  final Color color;

  /// 自旋 rad/s
  final double spin;

  /// 翻面（纸片绕长边抖）频率 rad/s
  final double flip;
  final double delay;
  final bool round;
}

/// 固定种子 → 同一套粒子，每次重放完全一致
List<_Piece> _makePieces() {
  final rnd = math.Random(6);
  return List<_Piece>.generate(30, (i) {
    // -90° ± 38°：锥形朝上，不然会当场喷到舞台外
    final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * 1.33;
    return _Piece(
      speed: 190 + rnd.nextDouble() * 140,
      angle: angle,
      w: 4 + rnd.nextDouble() * 3,
      h: 6 + rnd.nextDouble() * 4,
      color: _palette[i % _palette.length],
      spin: (rnd.nextDouble() - 0.5) * 14,
      flip: 6 + rnd.nextDouble() * 8,
      delay: rnd.nextDouble() * 0.12,
      round: rnd.nextDouble() < 0.25,
    );
  });
}

final _pieces = _makePieces();

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.t);

  /// 0→1 的整段寿命进度
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final paint = Paint();
    for (final p in _pieces) {
      final life = 1.5 - p.delay;
      final e = t * 1.5 - p.delay; // 存活时长（秒）
      if (e <= 0 || e >= life) continue;
      // 抛物线：出射速度 + 重力
      final x = _origin.dx + math.cos(p.angle) * p.speed * e;
      final y =
          _origin.dy + math.sin(p.angle) * p.speed * e + 0.5 * _gravity * e * e;
      // 后 35% 淡出，对应"约 1.5s 内消失"
      final q = e / life;
      final alpha = q < 0.65 ? 1.0 : (1 - (q - 0.65) / 0.35).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * e);
      // cos<0 是纸片翻到背面，压扁成一条再翻回来
      final f = math.cos(p.flip * e);
      canvas.scale(f.abs() < 0.15 ? 0.15 : f.abs(), 1);
      paint.color = p.color.withValues(alpha: alpha);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.w / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
