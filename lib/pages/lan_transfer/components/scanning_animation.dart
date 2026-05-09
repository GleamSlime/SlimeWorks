import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';

/// 雷达扫描动画组件
class ScanningAnimation extends StatefulWidget {
  const ScanningAnimation({super.key});

  @override
  State<ScanningAnimation> createState() => _ScanningAnimationState();
}

class _ScanningAnimationState extends State<ScanningAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, double.infinity),
          painter: _RadarPainter(
            progress: _controller.value,
            primaryColor: primaryColor,
            isDark: isDark,
          ),
          child: child,
        );
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: scaleW(56),
              height: scaleW(56),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isDark ? DarkColors.primary : LightColors.primary).withValues(alpha: 0.15),
              ),
              child: Icon(
                Icons.wifi_tethering,
                size: scaleW(28),
                color: isDark ? DarkColors.primary : LightColors.primary,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            Text(
              '正在搜索设备...',
              style: TextStyle(fontSize: 13.0, height: 1.5, color: isDark ? DarkColors.white80 : LightColors.black80),
            ),
          ],
        ),
      ),
    );
  }
}

/// 雷达扫描画笔
class _RadarPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final bool isDark;

  _RadarPainter({required this.progress, required this.primaryColor, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;

    // 绘制同心圆
    for (int i = 1; i <= 3; i++) {
      final radius = maxRadius * i / 3;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = primaryColor.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // 绘制扫描扇形（渐变 alpha）
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + math.pi * 2,
        colors: [
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.0),
          primaryColor.withValues(alpha: 0.25),
          primaryColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.6, 1.0, 1.0],
        transform: GradientRotation(progress * math.pi * 2 - math.pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius * 0.85, sweepPaint);

    // 绘制扫描线
    final angle = progress * math.pi * 2 - math.pi / 2;
    final lineEnd = Offset(
      center.dx + math.cos(angle) * maxRadius * 0.85,
      center.dy + math.sin(angle) * maxRadius * 0.85,
    );
    canvas.drawLine(
      center,
      lineEnd,
      Paint()
        ..color = primaryColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => oldDelegate.progress != progress;
}
