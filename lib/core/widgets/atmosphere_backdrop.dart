import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_atmosphere.dart';

/// 柔彩氛围底：对角基色 + 四团径向色斑，叠成一层不可命中的背景
///
/// **全站只画一次**，画在内容区底（`_ContentSurface`）。页面再铺一层自己的渐变，
/// 就是两张氛围皮叠着，滚动时色差会漂——试验页在试验期有这个特权，上收后取消。
///
/// [layered] 是给移动端和窄窗的降级档：只留单层对角渐变。留的是**颜色语言**
/// （柔彩底不是效果，是底色），裁掉的是四团色团——小窗上四团挤成一团脏色。
///
/// [opacity] 用来配合 `WindowGlass.contentAlpha` 那类"内容区要透出桌面"的半透明档：
/// 整层一起降，而不是只把基色换成带 alpha 的实色，否则色团会盖过基色、层次倒挂。
class AtmosphereBackdrop extends StatelessWidget {
  const AtmosphereBackdrop({
    super.key,
    this.child,
    this.layered = true,
    this.opacity = 1.0,
  });

  final Widget? child;

  /// false = 只铺对角基色，不叠四团色团
  final bool layered;

  /// 整层不透明度；1.0 时直接画，不套 `Opacity`（少一层保存图层）
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final a = AppAtmosphere.of(context);
    final layers = layered ? a.backgroundLayers : <BoxDecoration>[BoxDecoration(gradient: a.canvas)];

    final backdrop = Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            children: [
              for (final d in layers)
                Positioned.fill(child: DecoratedBox(decoration: d)),
            ],
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (opacity >= 1.0)
          backdrop
        else
          Positioned.fill(
            child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: backdrop.child),
          ),
        ?child,
      ],
    );
  }
}
