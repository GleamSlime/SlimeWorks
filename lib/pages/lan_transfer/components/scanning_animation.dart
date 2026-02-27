import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';

/// 扫描动画组件
class ScanningAnimation extends StatefulWidget {
  const ScanningAnimation({super.key});

  @override
  State<ScanningAnimation> createState() => _ScanningAnimationState();
}

class _ScanningAnimationState extends State<ScanningAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat();

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Container(
      height: scaleW(200),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 脉冲圆圈动画
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // 外圈
                  Container(
                    width: scaleW(100) * (1 + _animation.value * 0.5),
                    height: scaleW(100) * (1 + _animation.value * 0.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isDark ? DarkColors.primary : LightColors.primary).withOpacity(
                          1 - _animation.value,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                  // 中圈
                  Container(
                    width: scaleW(80),
                    height: scaleW(80),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isDark ? DarkColors.primary : LightColors.primary).withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  // 内圈
                  Container(
                    width: scaleW(60),
                    height: scaleW(60),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isDark ? DarkColors.primary : LightColors.primary).withOpacity(0.3),
                    ),
                    child: Icon(
                      Icons.radar,
                      size: scaleW(32),
                      color: isDark ? DarkColors.white100 : LightColors.black100,
                    ),
                  ),
                ],
              );
            },
          ),

          SizedBox(height: AppTheme.metrics.kSpace24),

          Text(
            '正在搜索设备...',
            style: AppTextStyles.body1(color: isDark ? DarkColors.white80 : LightColors.black80),
          ),

          SizedBox(height: AppTheme.metrics.kSpace8),

          Text(
            '请确保设备在同一局域网内',
            style: AppTextStyles.caption(color: isDark ? DarkColors.white80 : LightColors.black80),
          ),
        ],
      ),
    );
  }
}
