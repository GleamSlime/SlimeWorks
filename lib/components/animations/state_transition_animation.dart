import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/index.dart';

class StateTransitionAnimation extends StatefulWidget {
  final StrokeIcon? icon;
  final String? label;
  final StrokeIcon? hoverIcon;
  final bool enableScaleAnimation;
  final Duration animationDuration;

  // 样式参数
  final double? height;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final double? iconSize;
  final Color? iconColor;
  final double? spacing;
  final bool? loading;

  const StateTransitionAnimation({
    super.key,
    this.icon,
    this.label,
    this.hoverIcon,
    this.enableScaleAnimation = true,
    // 默认档取 emphasis：一次「图标+文字」整体换态属于强调级，读秒要沉稳些
    this.animationDuration = AppMotion.emphasis,
    this.height,
    this.padding,
    this.decoration,
    this.textStyle,
    this.iconSize,
    this.spacing,
    this.iconColor,
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

  late StrokeIcon? _currentIcon;
  late String _currentLabel;

  StrokeIcon? _prevIcon;
  String? _prevLabel;

  @override
  void initState() {
    super.initState();

    _currentIcon = widget.icon;
    _currentLabel = widget.label ?? '';

    _controller = AnimationController(duration: widget.animationDuration, vsync: this);

    const customCurve = _CustomCubicCurve();

    // 位移要吃掉整格高度：胶囊默认高 40，只挪 travelLarge(30) 的话旧内容会
    // 半截留在框里和新内容叠在一起，这一档 travel* 没覆盖到，保持宽度族等值。
    final travel = scaleW(50);

    // 新内容从顶部（按钮外）进入到中间
    _inOffset = Tween<double>(begin: -travel, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.decelerate),
    );

    // 旧内容向下移出按钮
    _outOffset = Tween<double>(begin: 0, end: travel).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.accelerate),
    );

    _inOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 1, curve: AppMotion.decelerate),
    );

    _outOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.75, curve: AppMotion.accelerate),
    );

    _inBlur = Tween<double>(begin: AppMotion.blurContent, end: 0).animate(_controller);
    _outBlur = Tween<double>(begin: 0, end: AppMotion.blurContent).animate(_controller);

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

    // 检测图标或 label 是否发生变化
    if (oldWidget.icon != widget.icon || oldWidget.label != widget.label || oldWidget.hoverIcon != widget.hoverIcon) {
      _triggerAnimation();
    }
  }

  void _triggerAnimation() {
    if (!mounted) return;

    setState(() {
      _hasAnimated = true;
      _prevIcon = _currentIcon;
      _prevLabel = _currentLabel;

      _currentIcon = widget.icon;
      _currentLabel = widget.label ?? '';
    });

    _controller
      ..reset()
      ..forward();
  }

  void _handleHoverEnter() {
    if (widget.hoverIcon != null && widget.icon != null && !_hovering) {
      setState(() {
        _hovering = true;
        _hasAnimated = true;
        _prevIcon = _currentIcon;
        _prevLabel = _currentLabel;

        _currentIcon = widget.hoverIcon!;
        _currentLabel = widget.label ?? '';
      });

      _controller
        ..reset()
        ..forward();
    }
  }

  void _handleHoverExit() {
    if (widget.hoverIcon != null && widget.icon != null && _hovering) {
      setState(() {
        _hovering = false;
        _hasAnimated = true;
        _prevIcon = _currentIcon;
        _prevLabel = _currentLabel;

        _currentIcon = widget.icon!;
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    // 胶囊整体（高/内距/图标/图标与文字的间隔）都走宽度族：它的外框高度是定值，
    // 一旦图标改用随字号缩放的那一族，用户把字号拉到 2.0 就会把这一排顶破。
    final height = widget.height ?? scaleW(40);
    final padding = widget.padding ?? EdgeInsets.symmetric(horizontal: m.kSpace12);
    final decoration =
        widget.decoration ??
        BoxDecoration(
          borderRadius: m.radiusPill,
          border: Border.all(color: s.border),
        );
    // 如果调用方没有显式传入 textStyle，则从环境中继承 DefaultTextStyle，
    // 并与默认大小/粗细合并。这允许外层的 DefaultTextStyle（例如 overlay 中强制设置的样式）生效。
    final textStyle = widget.textStyle != null
        ? widget.textStyle!
        : DefaultTextStyle.of(context).style.merge(
            // 只借角色档的字号/字重/字体族，颜色留给外层那条样式决定
            AppTextStyles.rowTitle(context).copyWith(color: DefaultTextStyle.of(context).style.color),
          );
    final iconSize = widget.iconSize ?? scaleW(20);
    final spacing = widget.spacing ?? m.kSpace10;
    final iconColor = widget.iconColor ?? s.textSecondary;

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
                  icon: _currentIcon,
                  label: _currentLabel,
                  textStyle: textStyle,
                  iconSize: iconSize,
                  iconColor: iconColor,
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
                                icon: _prevIcon,
                                label: _prevLabel!,
                                textStyle: textStyle,
                                iconSize: iconSize,
                                iconColor: iconColor,
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
                                icon: _currentIcon,
                                label: _currentLabel,
                                textStyle: textStyle,
                                iconSize: iconSize,
                                iconColor: iconColor,
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
                      icon: _currentIcon,
                      label: _currentLabel,
                      textStyle: textStyle,
                      iconSize: iconSize,
                      iconColor: iconColor,
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
  final StrokeIcon? icon;
  final String label;
  final TextStyle textStyle;
  final double iconSize;
  final double spacing;
  final Color? iconColor;
  final bool? loading;

  const _Content({
    required this.icon,
    required this.label,
    required this.textStyle,
    required this.iconSize,
    required this.iconColor,
    required this.spacing,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle textStyle = this.textStyle;

    if (loading == true) {
      // 载入中就是"暂时点不动"，直接用禁用文字角色，不再手压一层 alpha
      textStyle = textStyle.copyWith(color: AppSemantic.of(context).textDisabled);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null && loading != true)
          // 这里不叠描边动画：切换本身已经有位移 + 模糊 + 淡入三层，
          // 再让图标自己描一遍会糊成一团，动效只能留一个主角。
          DrawIcon(
            icon!,
            size: iconSize,
            color: iconColor,
            trigger: StrokeTrigger.none,
          ),
        if (loading == true)
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: scaleW(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(iconColor ?? AppSemantic.of(context).textSecondary),
            ),
          ),
        if (label.isNotEmpty) ...[
          if (icon != null) SizedBox(width: spacing),
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
