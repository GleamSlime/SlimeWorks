import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';

class AnimatedButton extends StatefulWidget {
  final String? svg;
  final String? label;
  final String? hoverSvg;
  final VoidCallback onTap;
  final bool enableScaleAnimation;
  final Duration animationDuration;

  // 样式参数
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final double? svgSize;
  final double? spacing;

  const AnimatedButton({
    super.key,
    this.svg,
    this.label,
    this.hoverSvg,
    required this.onTap,
    this.enableScaleAnimation = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.height,
    this.padding,
    this.decoration,
    this.textStyle,
    this.svgSize,
    this.spacing,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _inOpacity;
  late final Animation<double> _outOpacity;

  late final Animation<double> _inOffset;
  late final Animation<double> _outOffset;

  late final Animation<double> _inBlur;
  late final Animation<double> _outBlur;

  late final Animation<double> _scale;

  bool _hasAnimated = false;
  bool _hovering = false;

  late String _currentSvg;
  late String _currentLabel;

  String? _prevSvg;
  String? _prevLabel;

  @override
  void initState() {
    super.initState();

    _currentSvg = widget.svg ?? '';
    _currentLabel = widget.label ?? '';

    _controller = AnimationController(duration: widget.animationDuration, vsync: this);

    const customCurve = _CustomCubicCurve();

    // 新内容从顶部（按钮外）进入到中间
    _inOffset = Tween<double>(begin: -50.h, end: 0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // 旧内容向下移出按钮
    _outOffset = Tween<double>(begin: 0, end: 50.h).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInCubic));

    _inOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 1, curve: Curves.easeOut),
    );

    _outOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.75, curve: Curves.easeIn),
    );

    _inBlur = Tween<double>(begin: 2, end: 0).animate(_controller);
    _outBlur = Tween<double>(begin: 0, end: 2).animate(_controller);

    // 缩放动画：使用 cubic-bezier(0.4, 0, 0.2, 1) 曲线
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.08).chain(CurveTween(curve: customCurve)), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 1.0).chain(CurveTween(curve: customCurve)), weight: 15),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 检测 svg 或 label 是否发生变化
    if (oldWidget.svg != widget.svg || oldWidget.label != widget.label || oldWidget.hoverSvg != widget.hoverSvg) {
      _triggerAnimation();
    }
  }

  void _triggerAnimation() {
    if (!mounted) return;

    setState(() {
      _hasAnimated = true;
      _prevSvg = _currentSvg;
      _prevLabel = _currentLabel;

      _currentSvg = widget.svg ?? '';
      _currentLabel = widget.label ?? '';
    });

    _controller
      ..reset()
      ..forward();
  }

  void _handleTap() {
    widget.onTap();
  }

  void _handleHoverEnter() {
    if (widget.hoverSvg != null && widget.svg != null && !_hovering) {
      setState(() {
        _hovering = true;
        _hasAnimated = true;
        _prevSvg = _currentSvg;
        _prevLabel = _currentLabel;

        _currentSvg = widget.hoverSvg!;
        _currentLabel = widget.label ?? '';
      });

      _controller
        ..reset()
        ..forward();
    }
  }

  void _handleHoverExit() {
    if (widget.hoverSvg != null && widget.svg != null && _hovering) {
      setState(() {
        _hovering = false;
        _hasAnimated = true;
        _prevSvg = _currentSvg;
        _prevLabel = _currentLabel;

        _currentSvg = widget.svg!;
        _currentLabel = widget.label ?? '';
      });

      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? 40.h;
    final padding = widget.padding ?? EdgeInsets.symmetric(horizontal: 12.w);
    final decoration =
        widget.decoration ??
        BoxDecoration(
          borderRadius: BorderRadius.circular(32.r),
          border: Border.all(color: Colors.black45),
        );
    final textStyle = widget.textStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final svgSize = widget.svgSize ?? 20;
    final spacing = widget.spacing ?? 10;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _handleHoverEnter(),
      onExit: (_) => _handleHoverExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: widget.enableScaleAnimation ? _scale : kAlwaysCompleteAnimation,
          builder: (context, child) {
            return Transform.scale(scale: widget.enableScaleAnimation ? _scale.value : 1.0, child: child);
          },
          child: Container(
            height: height,
            padding: padding,
            decoration: decoration,
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              alignment: Alignment.centerLeft,
              children: [
                if (!_hasAnimated)
                  _Content(
                    svg: _currentSvg.isNotEmpty ? _currentSvg : null,
                    label: _currentLabel,
                    textStyle: textStyle,
                    svgSize: svgSize,
                    spacing: spacing,
                  ),

                if (_hasAnimated && _prevLabel != null)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      return Transform.translate(
                        offset: Offset(0, _outOffset.value),
                        child: Opacity(
                          opacity: 1 - _outOpacity.value,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: _outBlur.value, sigmaY: _outBlur.value),
                            child: _Content(
                              svg: _prevSvg?.isNotEmpty == true ? _prevSvg : null,
                              label: _prevLabel!,
                              textStyle: textStyle,
                              svgSize: svgSize,
                              spacing: spacing,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // 👇 新内容进入（从上）
                if (_hasAnimated)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      return Transform.translate(
                        offset: Offset(0, _inOffset.value),
                        child: Opacity(
                          opacity: _inOpacity.value,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: _inBlur.value, sigmaY: _inBlur.value),
                            child: _Content(
                              svg: _currentSvg.isNotEmpty ? _currentSvg : null,
                              label: _currentLabel,
                              textStyle: textStyle,
                              svgSize: svgSize,
                              spacing: spacing,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final String? svg;
  final String label;
  final TextStyle textStyle;
  final double svgSize;
  final double spacing;

  const _Content({required this.svg, required this.label, required this.textStyle, required this.svgSize, required this.spacing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (svg != null) SvgPicture.asset(svg!, width: svgSize, height: svgSize),
        if (label.isNotEmpty) ...[SizedBox(width: spacing), Text(label, style: textStyle)],
      ],
    );
  }
}

/// 自定义 Cubic Bezier 曲线 (0.4, 0, 0.2, 1) - 类似 CSS ease-in-out
class _CustomCubicCurve extends Curve {
  const _CustomCubicCurve();

  @override
  double transformInternal(double t) {
    // cubic-bezier(0.4, 0, 0.2, 1) 的近似实现
    final t2 = t * t;
    final t3 = t2 * t;
    return 3 * (1 - t) * (1 - t) * t * 0.4 + 3 * (1 - t) * t2 * 0.2 + t3;
  }
}
