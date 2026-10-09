import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 唱片与唱臂的材质色（恒定材质调色板）
///
/// 黑胶在任何主题下都是黑的，唱臂也永远是那几档金属灰：判据同 `AppReaderPaper`
/// / `AppTerminalPalette`——这一层是"用户看到的一件实物材质"，不是界面表面，
/// 跟主题反相的话，暗色下盘面会糊进背景、亮色下唱臂会变白。
/// 集中成一组常量（而不是散在各 build 方法里）是为了看得出
/// 「盘面五档沟槽 + 轴心 + 唱臂金属」是成套的，单独调其中一档就破坏关系。
abstract final class _DiscMaterial {
  /// 无封面时的盘面占位底（也是默认封面那一格的底）
  static const Color placeholder = Color(0xFF3a3a3a);

  /// 盘面径向渐变的五档：中心→外缘反复明暗，模拟沟槽反光
  static const List<Color> discGradient = [
    Color(0xFF1a1a1a),
    Color(0xFF2a2a2a),
    Color(0xFF1a1a1a),
    Color(0xFF333333),
    Color(0xFF1a1a1a),
  ];

  /// 轴心圆点与其外圈
  static const Color spindle = Color(0xFF555555);
  static const Color spindleRing = Color(0xFF333333);

  /// 唱臂支点与臂杆（同一种金属灰）
  static const Color toneArmMetal = Color(0xFF888888);

  /// 唱针头（比臂杆亮一档）
  static const Color toneArmStylus = Color(0xFFAAAAAA);
}

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
    // 唱片旋转动画：一整圈自转走 AppMotion.spin（转得出来但不至于晕）
    _spinController = AnimationController(vsync: this, duration: AppMotion.spin);

    // 唱臂动画：落下/抬起是一次性的重头动作，时长并到 AppMotion.emphasis
    _toneArmController = AnimationController(
      vsync: this,
      duration: AppMotion.emphasis,
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
            child: _buildDisc(discSize, coverSize),
          ),
          // 唱臂（后绘制，在唱片上方）
          Positioned(top: 0, right: discSize * 0.15, child: _buildToneArm(discSize)),
        ],
      ),
    );
  }

  /// 黑胶唱片
  Widget _buildDisc(double discSize, double coverSize) {
    // 盘面上的投影与沟槽高光都是"压在 art 上的墨"，走媒体令牌（恒白/恒黑，不随明暗）
    final s = AppSemantic.of(context);
    return Container(
      width: discSize,
      height: discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: _DiscMaterial.discGradient,
          stops: [0.0, 0.3, 0.5, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: s.mediaStage.withValues(alpha: 0.5),
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
                  color: s.onMedia.withValues(alpha: 0.05 + (i % 2) * 0.03),
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
              // 无封面时的占位色必须跟着唱片本身的暗色质感走：这里原先用主题的
              // surfaceContainerHighest，亮色模式下会在黑胶上挖出一个白圆盘，
              // 和下面 _buildDefaultCover 的深灰占位也对不上。
              color: _DiscMaterial.placeholder,
              border: Border.all(color: s.mediaStage.withValues(alpha: 0.3), width: AppTheme.metrics.strokeHairline),
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
              color: _DiscMaterial.spindle,
              border: Border.all(color: _DiscMaterial.spindleRing, width: AppTheme.metrics.strokeRegular),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover(double size) {
    // 无封面时的占位是深色盘面，音符图标是盘面之上的墨字（恒白）
    final s = AppSemantic.of(context);
    return Container(
      color: _DiscMaterial.placeholder,
      child: DrawIcon(StrokeIcons.musicNote,
        size: size * 0.4,
        color: s.onMedia.withValues(alpha: 0.5),
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
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _DiscMaterial.toneArmMetal),
          ),
          // 唱臂杆
          Container(
            width: 3,
            height: armLength,
            decoration: BoxDecoration(
              color: _DiscMaterial.toneArmMetal,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          // 唱针头
          Container(
            width: 6,
            height: 12,
            decoration: BoxDecoration(
              color: _DiscMaterial.toneArmStylus,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
