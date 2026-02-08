import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:slime_works/core/index.dart';

class StateTransitionAnimation extends StatefulWidget {
  final String? svg;
  final String? label;
  final String? hoverSvg;
  final bool enableScaleAnimation;
  final Duration animationDuration;

  // 样式参数
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final double? svgSize;
  final Color? svgColor;
  final double? spacing;
  final bool? loading;

  const StateTransitionAnimation({
    super.key,
    this.svg,
    this.label,
    this.hoverSvg,
    this.enableScaleAnimation = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.height,
    this.padding,
    this.decoration,
    this.textStyle,
    this.svgSize,
    this.spacing,
    this.svgColor,
    this.loading = false,
  });

  @override
  State<StateTransitionAnimation> createState() => _StateTransitionAnimationState();
}

class _StateTransitionAnimationState extends State<StateTransitionAnimation> with SingleTickerProviderStateMixin {
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
  void didUpdateWidget(StateTransitionAnimation oldWidget) {
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
    // 如果调用方没有显式传入 textStyle，则从环境中继承 DefaultTextStyle，
    // 并与默认大小/粗细合并。这允许外层的 DefaultTextStyle（例如 overlay 中强制设置的样式）生效。
    final textStyle = widget.textStyle != null
        ? widget.textStyle!
        : DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 14, fontWeight: FontWeight.w500));
    final svgSize = widget.svgSize ?? 20;
    final spacing = widget.spacing ?? 10;
    final svgColor = widget.svgColor ?? Theme.of(context).textTheme.bodyMedium?.color;

    return MouseRegion(
      // cursor: widget.loading == true ? SystemMouseCursors.noDrop : SystemMouseCursors.click,
      onEnter: (_) => _handleHoverEnter(),
      onExit: (_) => _handleHoverExit(),
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
            children: [
              // 基线（不可见）内容：用于根据当前标签确定按钮的尺寸
              Opacity(
                opacity: 0,
                alwaysIncludeSemantics: false,
                child: _Content(
                  svg: _currentSvg.isNotEmpty ? _currentSvg : null,
                  label: _currentLabel,
                  textStyle: textStyle,
                  svgSize: svgSize,
                  svgColor: svgColor,
                  spacing: spacing,
                  loading: widget.loading,
                ),
              ),

              // 已退出（之前）的内容：定位为不影响布局尺寸
              if (_hasAnimated && _prevLabel != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, _) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.translate(
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
                                svgColor: svgColor,
                                spacing: spacing,
                                loading: widget.loading,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 进入（当前）的内容：同样定位以不影响布局尺寸
              if (_hasAnimated)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (_, _) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.translate(
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
                                svgColor: svgColor,
                                spacing: spacing,
                                loading: widget.loading,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 初始非动画状态：显示当前内容
              if (!_hasAnimated)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _Content(
                      svg: _currentSvg.isNotEmpty ? _currentSvg : null,
                      label: _currentLabel,
                      textStyle: textStyle,
                      svgSize: svgSize,
                      svgColor: svgColor,
                      spacing: spacing,
                      loading: widget.loading,
                    ),
                  ),
                ),
            ],
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
  final Color? svgColor;
  final bool? loading;

  const _Content({
    required this.svg,
    required this.label,
    required this.textStyle,
    required this.svgSize,
    required this.svgColor,
    required this.spacing,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle textStyle = this.textStyle;

    if (loading == true) {
      textStyle = textStyle.copyWith(color: (textStyle.color ?? Theme.of(context).textTheme.bodyMedium?.color)?.withAlpha(100));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (svg != null && loading != true)
          SvgPicture.asset(
            svg!,
            width: svgSize,
            height: svgSize,
            colorFilter: svgColor != null ? ColorFilter.mode(svgColor!, BlendMode.srcIn) : null,
          ),
        if (loading == true)
          SizedBox(
            width: svgSize,
            height: svgSize,
            child: CircularProgressIndicator(
              strokeWidth: scaleW(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(svgColor ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black),
            ),
          ),
        if (label.isNotEmpty) ...[
          if (svg != null) SizedBox(width: spacing),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              style: textStyle.copyWith(decoration: TextDecoration.none),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// 自定义 Cubic Bezier 曲线 (0.4, 0, 0.2, 1) - 类似 CSS 的 ease-in-out
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
