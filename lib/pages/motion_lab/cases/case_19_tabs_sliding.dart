import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 19. Tabs sliding — 药丸指示条跟着选中的 tab 走
///
/// 参考稿的指示条是绝对定位的一根条，`translateX` 和 `width` 一起补间，
/// 时长/曲线和文字换色共用一个（250ms 顺出）。所以没借现成 TabBar 的指示器：
/// 它的宽度由布局给，切换时是"跳"过去而不是拉长过去。
/// 每档宽度按 `文字宽 + 12×2` 自己量，量的和画的同一套数才对得上。
const _labels = ['Plan', 'Debug', 'Ask'];

/// 参考稿 `--p16-*`：条 3 内衬、档间 3、高 30、左右各 12
const _dur = Duration(milliseconds: 250);
const _barPad = 3.0;
const _gap = 3.0;
const _tabH = 30.0;
const _tabPadX = 12.0;

const _barBg = Color(0xFF202020);
const _pillBg = Color(0xFF454545);
const _active = Color(0xFFFFFFFF);

/// rgba(193, 193, 193, .8)
const _muted = Color(0xCCC1C1C1);

const _tabStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.4,
);

class Case19TabsSliding extends StatefulWidget {
  const Case19TabsSliding({super.key});

  @override
  State<Case19TabsSliding> createState() => _Case19TabsSlidingState();
}

class _Case19TabsSlidingState extends State<Case19TabsSliding> {
  int _selected = 0;
  int _hovered = -1;

  @override
  Widget build(BuildContext context) {
    final widths = [for (final l in _labels) _tabWidth(context, l)];
    final lefts = <double>[];
    var x = _barPad;
    for (final w in widths) {
      lefts.add(x);
      x += w + _gap;
    }
    final barW = lefts.last + widths.last + _barPad;

    return LabStage(
      child: Center(
        child: SizedBox(
          width: barW,
          height: _tabH + _barPad * 2,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _barBg,
                    borderRadius: BorderRadius.all(Radius.circular(48)),
                  ),
                ),
              ),
              // 指示条压在文字下面（z-index 0），所以先画
              AnimatedPositioned(
                duration: _dur,
                curve: LabEase.smoothOut,
                left: lefts[_selected],
                top: _barPad,
                height: _tabH,
                width: widths[_selected],
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _pillBg,
                    borderRadius: BorderRadius.all(Radius.circular(48)),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _barPad),
                  child: Row(
                    children: [
                      for (var i = 0; i < _labels.length; i++) ...[
                        if (i > 0) const SizedBox(width: _gap),
                        _Tab(
                          label: _labels[i],
                          width: widths[i],
                          // 选中档不看悬停：它已经是亮字，再亮也没处亮
                          color: i == _selected || i == _hovered ? _active : _muted,
                          onTap: () => setState(() => _selected = i),
                          onHover: (v) => setState(() => _hovered = v ? i : -1),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _tabWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _tabStyle),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w + _tabPadX * 2;
  }
}

/// 一档 tab：只有文字颜色补间，未选中的悬停时提亮
class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.width,
    required this.color,
    required this.onTap,
    required this.onHover,
  });

  final String label;
  final double width;
  final Color color;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedDefaultTextStyle(
          duration: _dur,
          curve: LabEase.smoothOut,
          style: _tabStyle.copyWith(color: color),
          child: SizedBox(
            width: width,
            height: _tabH,
            child: Center(child: Text(label)),
          ),
        ),
      ),
    );
  }
}
