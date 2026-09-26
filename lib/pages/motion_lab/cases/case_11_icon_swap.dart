import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 11. Icon swap — 两个图标叠在同一格，一个淡掉一个亮起来
///
/// 参考稿把 menu / close 两张 svg 绝对定位在同一个 32 方格里，
/// 换的那一下三条属性一起走（250ms 渐入渐出）：
/// opacity 0/1、scale 1↔0.25、blur 0↔4px。
/// 退场的那枚必须同时缩到 0.25 再糊掉，只淡出的话两枚图标会重影叠在一起。
class Case11IconSwap extends StatefulWidget {
  const Case11IconSwap({super.key});

  @override
  State<Case11IconSwap> createState() => _Case11IconSwapState();
}

class _Case11IconSwapState extends State<Case11IconSwap> {
  /// `--p5-dur: var(--duration-fast)`
  static const _dur = Duration(milliseconds: 250);

  /// `--p5-ease: var(--ease-in-out)`
  static const _ease = LabEase.inOut;

  /// `--p5-blur` / `--p5-start-scale`
  static const _blur = 4.0;
  static const _startScale = 0.25;

  /// `.p5-icon-wrap` 32×32，里面的 svg 是 24
  static const _wrap = 32.0;
  static const _icon = 24.0;

  bool _on = false;

  void _toggle() => setState(() => _on = !_on);

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            // t = 0 是 menu，t = 1 是 close：一条进度喂两枚，天然反向
            child: LabTween(
              target: _on ? 1 : 0,
              duration: _dur,
              curve: _ease,
              builder: (context, t) => SizedBox(
                width: _wrap,
                height: _wrap,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _layer(
                      opacity: 1 - t,
                      scale: _lerpScale(1 - t),
                      blur: _blur * t,
                      paths: _menuPaths,
                    ),
                    _layer(
                      opacity: t,
                      scale: _lerpScale(t),
                      blur: _blur * (1 - t),
                      paths: _closePaths,
                    ),
                  ],
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }

  double _lerpScale(double k) => _startScale + (1 - _startScale) * k;

  /// svg 是 24 viewBox / 1.75 描边，尺寸与描边一起按原稿走
  Widget _layer({
    required double opacity,
    required double scale,
    required double blur,
    required List<String> paths,
  }) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: LabBlur(
          sigma: blur,
          child: LabIcon(
            paths: paths,
            size: _icon,
            viewBox: 24,
            strokeWidth: 1.75,
            color: LabColor.text,
          ),
        ),
      ),
    );
  }

  static const _menuPaths = ['M4 7H20', 'M4 12H20', 'M4 17H20'];
  static const _closePaths = ['M6 6L18 18', 'M18 6L6 18'];
}
