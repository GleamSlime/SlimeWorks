import 'package:flutter/material.dart';

/// 波形进度条组件
///
/// 显示音频波形图，已播放部分高亮，点击可跳转播放位置
class WaveformSeekBar extends StatelessWidget {
  /// 波形数据（0.0~1.0 振幅数组）
  final List<double> waveform;

  /// 当前播放位置（毫秒）
  final int positionMs;

  /// 总时长（毫秒）
  final int durationMs;

  /// 点击跳转回调
  final ValueChanged<int> onSeek;

  /// 已播放部分颜色
  final Color activeColor;

  /// 未播放部分颜色
  final Color inactiveColor;

  /// 是否正在加载
  final bool isLoading;

  /// 波形条之间的间距
  final double barGap;

  /// 波形条圆角
  final double barRadius;

  const WaveformSeekBar({
    super.key,
    required this.waveform,
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x66FFFFFF),
    this.isLoading = false,
    this.barGap = 2.0,
    this.barRadius = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (waveform.isEmpty) {
      return const SizedBox.shrink();
    }

    // 计算播放进度比例
    final progress = durationMs > 0 ? positionMs / durationMs : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final totalBars = waveform.length;
        // 根据采样点数量自适应间距：采样点多时间距缩小
        final adaptiveGap = totalBars > 500 ? 0.5 : (totalBars > 200 ? 1.0 : barGap);
        final barWidth = (width - (totalBars - 1) * adaptiveGap) / totalBars;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
          onHorizontalDragUpdate: (details) {
            _handleSeek(details.localPosition.dx, width);
          },
          onTapDown: (details) {
            _handleSeek(details.localPosition.dx, width);
          },
          child: CustomPaint(
            size: Size(width, 48),
            painter: _WaveformPainter(
              waveform: waveform,
              progress: progress,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              barWidth: barWidth.clamp(0.5, 8.0),
              barGap: adaptiveGap,
              barRadius: barRadius.clamp(0.0, barWidth / 2),
            ),
          ),
        ),
        );
      },
    );
  }

  void _handleSeek(double dx, double width) {
    final ratio = (dx / width).clamp(0.0, 1.0);
    final seekMs = (ratio * durationMs).round();
    onSeek(seekMs);
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double barGap;
  final double barRadius;

  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.barWidth,
    required this.barGap,
    required this.barRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalBars = waveform.length;
    if (totalBars == 0) return;

    final height = size.height;
    final activeBarCount = (progress * totalBars).round();

    for (int i = 0; i < totalBars; i++) {
      final amplitude = waveform[i].clamp(0.05, 1.0); // 最低 5% 高度
      final barHeight = height * amplitude;
      final x = i * (barWidth + barGap);
      final y = (height - barHeight) / 2;

      final isActive = i < activeBarCount;
      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barRadius),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveform != waveform;
  }
}
