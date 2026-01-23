import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class HoverSvgButton extends StatefulWidget {
  final String svg;
  final String? hoverSvg;
  final VoidCallback onTap;
  final double size;

  const HoverSvgButton({super.key, required this.svg, this.hoverSvg, required this.onTap, this.size = 24});

  @override
  State<HoverSvgButton> createState() => _HoverSvgButtonState();
}

class _HoverSvgButtonState extends State<HoverSvgButton> {
  bool _hovering = false;

  @override
  void didUpdateWidget(HoverSvgButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检测 svg 或 label 是否发生变化
    if (oldWidget.svg != widget.svg) {
      _triggerAnimation();
    }
  }

  void _triggerAnimation() {
    if (!mounted) return;

    setState(() => _hovering = true);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: SvgPicture.asset(
            _hovering && widget.hoverSvg != null ? widget.hoverSvg! : widget.svg,
            key: ValueKey(_hovering),
            width: widget.size,
            height: widget.size,
          ),
        ),
      ),
    );
  }
}

class AnimatedSvgIconButton extends StatefulWidget {
  final String svg;
  final String hoverSvg;
  final VoidCallback onTap;
  final double size;

  const AnimatedSvgIconButton({super.key, required this.svg, required this.hoverSvg, required this.onTap, this.size = 24});

  @override
  State<AnimatedSvgIconButton> createState() => _AnimatedSvgIconButtonState();
}

class _AnimatedSvgIconButtonState extends State<AnimatedSvgIconButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed
        ? 0.92
        : _hovering
        ? 1.08
        : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: SvgPicture.asset(_hovering ? widget.hoverSvg : widget.svg, key: ValueKey(_hovering), width: widget.size, height: widget.size),
          ),
        ),
      ),
    );
  }
}
