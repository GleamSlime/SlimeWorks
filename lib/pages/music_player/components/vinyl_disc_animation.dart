import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

/// 唱片机播放动效组件（参考网易音乐黑胶唱片风格）
///
/// 特性：
/// - 旋转黑胶唱片（播放时旋转，暂停时停止）
/// - 唱片中心显示封面
/// - 唱臂动画（播放时摆到唱片上方，暂停时移开）
class VinylDiscAnimation extends StatefulWidget {
  final String? coverPath;
  final bool isPlaying;
  final double size;

  const VinylDiscAnimation({super.key, this.coverPath, required this.isPlaying, this.size = 160});

  @override
  State<VinylDiscAnimation> createState() => _VinylDiscAnimationState();
}

class _VinylDiscAnimationState extends State<VinylDiscAnimation> with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _toneArmController;

  @override
  void initState() {
    super.initState();
    // 唱片旋转动画
    _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 8));

    // 唱臂动画
    _toneArmController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    if (widget.isPlaying) {
      _spinController.repeat();
      _toneArmController.forward();
    }
  }

  @override
  void didUpdateWidget(VinylDiscAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _spinController.repeat();
        _toneArmController.forward();
      } else {
        _spinController.stop();
        _toneArmController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _toneArmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discSize = widget.size;
    final coverSize = discSize * 0.58;

    return SizedBox(
      width: discSize + 40,
      height: discSize + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 黑胶唱片（先绘制，在底层）
          AnimatedBuilder(
            animation: _spinController,
            builder: (context, child) {
              return Transform.rotate(angle: _spinController.value * 2 * pi, child: child);
            },
            child: _buildDisc(context, discSize, coverSize),
          ),
          // 唱臂（后绘制，在唱片上方）
          Positioned(top: 0, right: discSize * 0.15, child: _buildToneArm(discSize)),
        ],
      ),
    );
  }

  /// 黑胶唱片
  Widget _buildDisc(BuildContext context, double discSize, double coverSize) {
    return Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFF1a1a1a),
            Color(0xFF2a2a2a),
            Color(0xFF1a1a1a),
            Color(0xFF333333),
            Color(0xFF1a1a1a),
          ],
          stops: [0.0, 0.3, 0.5, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 唱片纹理（同心圆沟槽）
          ...List.generate(8, (i) {
            final radius = coverSize / 2 + (discSize - coverSize) / 2 * (i + 1) / 9;
            return Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.05 + (i % 2) * 0.03),
                  width: 0.5,
                ),
              ),
            );
          }),
          // 封面
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(color: Colors.black.withValues(alpha: 0.3), width: 1),
            ),
            child: ClipOval(
              child: widget.coverPath != null && File(widget.coverPath!).existsSync()
                  ? Image.file(
                      File(widget.coverPath!),
                      fit: BoxFit.cover,
                      width: coverSize,
                      height: coverSize,
                      errorBuilder: (_, _, _) => _buildDefaultCover(coverSize),
                    )
                  : _buildDefaultCover(coverSize),
            ),
          ),
          // 中心圆点
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF555555),
              border: Border.all(color: const Color(0xFF333333), width: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover(double size) {
    return Container(
      color: const Color(0xFF3a3a3a),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );
  }

  /// 唱臂
  Widget _buildToneArm(double discSize) {
    final armLength = discSize * 0.55;
    return AnimatedBuilder(
      animation: _toneArmController,
      builder: (context, child) {
        // 唱臂旋转角度：从 -30°（离开唱片）到 0°（在唱片上方）
        final angle = -30.0 + 30.0 * _toneArmController.value;
        return Transform.rotate(
          angle: angle * pi / 180,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 唱臂支点
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF888888)),
          ),
          // 唱臂杆
          Container(
            width: 3,
            height: armLength,
            decoration: BoxDecoration(
              color: const Color(0xFF888888),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          // 唱针头
          Container(
            width: 6,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFFAAAAAA),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
