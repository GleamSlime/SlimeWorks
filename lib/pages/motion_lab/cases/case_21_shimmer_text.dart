import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 21. Shimmer text — 一道渐变高光横掠正文，文字本体始终在场
///
/// 参考稿是双层：正文用 `--shimmer-base` 常显，::before 复刻同一串字、
/// 把"透明→高光→透明"的渐变裁进字形（background-clip: text），
/// 再让 4 倍宽的渐变带从背景位置 100% 滑到 0%——高光从左侧画外扫到右侧画外，
/// 2000ms 线性无限循环。Play/Pause 切换：暂停时把带子停回画外，
/// 再 Play 从 0 重扫，而不是从半路续。
class Case21ShimmerText extends StatefulWidget {
  const Case21ShimmerText({super.key});

  @override
  State<Case21ShimmerText> createState() => _Case21ShimmerTextState();
}

class _Case21ShimmerTextState extends State<Case21ShimmerText> with SingleTickerProviderStateMixin {
  static const _text = 'Planning next moves';
  static const _dur = Duration(milliseconds: 2000); // `--p15-dur`
  static const _base = Color(0xFF7C7C7C); // `--shimmer-base`（浅底版取值）
  static const _highlight = LabColor.text; // `--shimmer-highlight` #0d0d0d
  static const _band = 4.0; // `--p15-band: 400%`

  // `.p15-shimmer`：14px / 400 / 行高 18
  static const _style = TextStyle(
    fontFamily: LabFont.family,
    fontFamilyFallback: LabFont.fallback,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 18 / 14,
  );

  static const _stops = [0.0, 0.4, 0.5, 0.6, 1.0]; // 配方里的渐变停靠点
  static const _maskColors = [
    Color(0x00000000),
    Color(0x00000000),
    _highlight,
    Color(0x00000000),
    Color(0x00000000),
  ];

  late final AnimationController _c = AnimationController(vsync: this, duration: _dur);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_c.isAnimating) {
      _c.stop();
      _c.value = 0; // 带回 100% 停靠位：静止时高光藏在左侧画外
    } else {
      _c.forward(from: 0); // 中途连点也从头重扫
      _c.repeat();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playing = _c.isAnimating;
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: Stack(
              children: [
                Text(_text, style: _style.copyWith(color: _base)),
                // ::before inset:0 —— 覆层和正文同一副度量，只在动时重画
                ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) {
                    return ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (size) {
                        // background-position 100%→0%：4 倍宽带子从"右缘对齐"平移到"左缘对齐"，
                        // 暂停时停在 0（即 100% 位），高光整个在左侧画外
                        final left = (_c.value - 1) * (_band - 1) * size.width;
                        return const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: _maskColors,
                          stops: _stops,
                        ).createShader(
                          Rect.fromLTWH(left, 0, _band * size.width, size.height),
                        );
                      },
                      child: Text(_text, style: _style.copyWith(color: _highlight)),
                    );
                  },
                ),
              ],
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: playing ? 'Pause' : 'Play', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}
