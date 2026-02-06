import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:slime_works/components/animations/state_transition_animation.dart';

/// Gooey粘连下拉组件（基于GPU Shader实现）
///
/// 使用示例：
/// ```dart
/// GooeyDropdownShader(
///   button: Icon(Icons.menu, color: Colors.white),
///   content: YourContentWidget(),
///   buttonSize: Size(56, 56),
///   cardSize: Size(300, 200),
///   buttonColor: Colors.black,
///   cardColor: Colors.black,
///   onOpen: () => print('Opened'),
///   onClose: () => print('Closed'),
/// )
/// ```
class GooeyDropdownShader extends StatefulWidget {
  /// 按钮内容Widget
  final Widget button;

  /// 卡片内容Widget
  final Widget content;

  /// 按钮尺寸，默认 56x56
  final Size? buttonSize;

  /// 卡片尺寸，默认 320x220
  final Size? cardSize;

  /// 按钮颜色，默认黑色
  final Color? buttonColor;

  /// 卡片颜色，默认黑色（shader会使用此颜色）
  final Color? cardColor;

  /// 按钮圆角半径，默认为按钮高度的一半（圆形）
  final double? buttonRadius;

  /// 卡片圆角半径，默认 18
  final double? cardRadius;

  /// 卡片阴影
  final List<BoxShadow>? cardBoxShadow;

  /// 卡片边框
  final Border? cardBorder;

  /// 动画时长，默认 700ms
  final Duration? duration;

  /// 卡片相对按钮的间隙，默认 0（从按钮底部开始）
  final double? gap;

  /// 卡片相对按钮的偏移量，默认向下80
  final double? cardOffset;

  /// 显示方向，默认自动检测
  final DropdownDirection? direction;

  /// 动画曲线，默认 easeOut 和 easeInOut 组合
  final Curve? curve;

  /// 可选的按钮构造器，用于在覆盖层中创建独立的按钮实例（避免复用同一 widget 导致状态丢失）
  final WidgetBuilder? buttonBuilder;

  /// 打开时回调
  final VoidCallback? onOpen;

  /// 关闭时回调
  final VoidCallback? onClose;

  const GooeyDropdownShader({
    super.key,
    required this.button,
    this.buttonBuilder,
    required this.content,
    this.buttonSize,
    this.cardSize,
    this.buttonColor,
    this.cardColor,
    this.buttonRadius,
    this.cardRadius,
    this.cardBoxShadow,
    this.cardBorder,
    this.duration,
    this.gap,
    this.cardOffset,
    this.direction,
    this.curve,
    this.onOpen,
    this.onClose,
  });

  @override
  State<GooeyDropdownShader> createState() => _GooeyDropdownShaderState();
}

/// 卡片显示方向
enum DropdownDirection {
  /// 自动检测
  auto,

  /// 向下
  bottom,

  /// 向上
  up,

  /// 向左
  left,

  /// 向右
  right,

  /// 右上
  topRight,

  /// 左上
  topLeft,

  /// 左下
  bottomLeft,

  /// 右下
  bottomRight,
}

class _GooeyDropdownShaderState extends State<GooeyDropdownShader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.FragmentShader? _shader;
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  Size? _measuredButtonSize;

  // 默认值
  Size get buttonSize => widget.buttonSize ?? _measuredButtonSize ?? const Size(56, 56);
  Size get cardSize => widget.cardSize ?? const Size(320, 220);
  Color get buttonColor => widget.buttonColor ?? Colors.black;
  Color get cardColor => widget.cardColor ?? Colors.black;
  double get buttonRadius => widget.buttonRadius ?? (buttonSize.height / 2);
  Border? get cardBorder => widget.cardBorder;
  Duration get duration => widget.duration ?? const Duration(milliseconds: 700);
  double get gap => widget.gap ?? 0.0;
  double get cardOffset => widget.cardOffset ?? 80.0;
  DropdownDirection get direction => widget.direction ?? DropdownDirection.auto;
  Curve get curve => widget.curve ?? Curves.easeInOutCubic;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: duration, vsync: this);
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/gooey.frag');
    if (mounted) {
      setState(() {
        _shader = program.fragmentShader();
      });
    }
  }

  void open() {
    if (_overlayEntry != null) return;

    final RenderBox? renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || _shader == null) return;

    final buttonSize = renderBox.size;
    // 确保获取相对于屏幕的全局坐标
    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 计算最佳显示方向
    final actualDirection = _calculateDirection(buttonPosition, buttonSize, screenSize);

    final originDefaultTextStyle = _buttonKey.currentContext != null
        ? DefaultTextStyle.of(_buttonKey.currentContext!).style
        : DefaultTextStyle.of(context).style;

    _overlayEntry = OverlayEntry(
      builder: (context) => _DropdownOverlay(
        shader: _shader!,
        controller: _controller,
        buttonPosition: buttonPosition,
        buttonSize: buttonSize,
        cardSize: cardSize,
        buttonColor: buttonColor,
        cardColor: cardColor,
        buttonRadius: widget.buttonRadius ?? (buttonSize.height / 2),
        cardRadius: widget.cardRadius ?? 18.0,
        gap: gap,
        cardOffset: cardOffset,
        cardBoxShadow: widget.cardBoxShadow,
        cardBorder: cardBorder,
        direction: actualDirection,
        curve: curve,
        content: widget.content,
        buttonWidget: widget.button,
        buttonBuilder: widget.buttonBuilder,
        originContext: context,
        originDefaultTextStyle: originDefaultTextStyle,
        onClose: close,
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    _controller.forward();
    widget.onOpen?.call();
  }

  void close() {
    _controller.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
    widget.onClose?.call();
  }

  DropdownDirection _calculateDirection(Offset buttonPos, Size buttonSize, Size screenSize) {
    if (direction != DropdownDirection.auto) return direction;

    // 计算8个方向的可用空间
    final padding = 20.0;
    final spaceTop = buttonPos.dy;
    final spaceBottom = screenSize.height - (buttonPos.dy + buttonSize.height);
    final spaceLeft = buttonPos.dx;
    final spaceRight = screenSize.width - (buttonPos.dx + buttonSize.width);

    // 优先级：下 > 上 > 右 > 左 > 对角线方向
    if (spaceBottom >= cardSize.height + cardOffset + padding) {
      return DropdownDirection.bottom;
    } else if (spaceTop >= cardSize.height + cardOffset + padding) {
      return DropdownDirection.up;
    } else if (spaceRight >= cardSize.width + cardOffset + padding) {
      return DropdownDirection.right;
    } else if (spaceLeft >= cardSize.width + cardOffset + padding) {
      return DropdownDirection.left;
    } else if (spaceBottom >= cardSize.height / 2 && spaceRight >= cardSize.width / 2) {
      return DropdownDirection.bottomRight;
    } else if (spaceBottom >= cardSize.height / 2 && spaceLeft >= cardSize.width / 2) {
      return DropdownDirection.bottomLeft;
    } else if (spaceTop >= cardSize.height / 2 && spaceRight >= cardSize.width / 2) {
      return DropdownDirection.topRight;
    } else if (spaceTop >= cardSize.height / 2 && spaceLeft >= cardSize.width / 2) {
      return DropdownDirection.topLeft;
    } else {
      return DropdownDirection.bottom; // 默认向下
    }
  }

  bool get isOpen => _overlayEntry != null;

  @override
  void dispose() {
    _overlayEntry?.remove();
    _controller.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final size = renderBox.size;
        if (_measuredButtonSize == null || _measuredButtonSize != size) {
          setState(() => _measuredButtonSize = size);
        }
      }
    });

    final hasFixedButtonSize = widget.buttonSize != null;
    return GestureDetector(
      key: _buttonKey,
      onTap: isOpen ? null : open,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 动画时隐藏背景容器，但保留按钮内容
          return Stack(
            children: [
              // 背景容器（动画时隐藏）
              if (hasFixedButtonSize)
                Opacity(
                  opacity: _controller.value > 0 ? 0 : 1,
                  child: Container(
                    width: buttonSize.width,
                    height: buttonSize.height,
                    decoration: BoxDecoration(color: buttonColor, borderRadius: BorderRadius.circular(buttonRadius)),
                  ),
                ),
              // 按钮内容（始终保持可见）
              SizedBox(
                width: hasFixedButtonSize ? buttonSize.width : null,
                height: hasFixedButtonSize ? buttonSize.height : null,
                child: widget.button,
              ),

              // (removed erroneous background tap-catcher here)
            ],
          );
        },
      ),
    );
  }
}

/// Dropdown覆盖层
class _DropdownOverlay extends StatefulWidget {
  final ui.FragmentShader shader;
  final AnimationController controller;
  final Offset buttonPosition;
  final Size buttonSize;
  final Size cardSize;
  final Color buttonColor;
  final Color cardColor;
  final double buttonRadius;
  final double cardRadius;
  final List<BoxShadow>? cardBoxShadow;
  final Border? cardBorder;
  final double gap;
  final double cardOffset;
  final DropdownDirection direction;
  final Curve curve;
  final Widget content;
  final Widget buttonWidget;
  final WidgetBuilder? buttonBuilder;
  final BuildContext originContext;
  final TextStyle? originDefaultTextStyle;
  final VoidCallback onClose;

  const _DropdownOverlay({
    required this.shader,
    required this.controller,
    required this.buttonPosition,
    required this.buttonSize,
    required this.cardSize,
    required this.buttonColor,
    required this.cardColor,
    required this.buttonRadius,
    required this.cardRadius,
    this.cardBoxShadow,
    this.cardBorder,
    required this.gap,
    required this.cardOffset,
    required this.direction,
    required this.curve,
    required this.content,
    required this.buttonWidget,
    this.buttonBuilder,
    required this.originContext,
    required this.originDefaultTextStyle,
    required this.onClose,
  });
  @override
  State<_DropdownOverlay> createState() => _DropdownOverlayState();
}

class _DropdownOverlayState extends State<_DropdownOverlay> {
  double? _measuredContentHeight;
  double? _measuredContentWidth;
  final GlobalKey _measureKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final enforcedTextStyle = (widget.originDefaultTextStyle ?? DefaultTextStyle.of(widget.originContext).style).copyWith(
      decoration: TextDecoration.none,
    );

    // 在帧后测量隐藏的 content 大小并记录高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _measureKey.currentContext;
      if (ctx != null) {
        final render = ctx.findRenderObject();
        if (render is RenderBox) {
          final s = render.size;
          final heightChanged = s.height > 0 && (_measuredContentHeight == null || (_measuredContentHeight! - s.height).abs() > 0.5);
          final widthChanged = s.width > 0 && (_measuredContentWidth == null || (_measuredContentWidth! - s.width).abs() > 0.5);
          if (heightChanged || widthChanged) {
            setState(() {
              if (heightChanged) _measuredContentHeight = s.height;
              if (widthChanged) _measuredContentWidth = s.width;
            });
          }
        }
      }
    });

    return Theme(
      data: Theme.of(widget.originContext),
      child: DefaultTextStyle(
        style: enforcedTextStyle,
        child: Stack(
          children: [
            // 全局背景遮罩（点击关闭）- 放在最底层，保证上层卡片能接收鼠标/点击事件
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onClose,
                child: Container(color: Colors.transparent),
              ),
            ),

            // 动画内容
            AnimatedBuilder(
              animation: widget.controller,
              builder: (context, child) {
                if (widget.controller.value == 0) {
                  return const SizedBox.shrink();
                }

                final t = widget.controller.value;

                // 使用传入的曲线，实现丝滑的缓动效果
                final sizeProgress = widget.curve.transform(t);

                final clampedProgress = sizeProgress.clamp(0.0, 1.0);

                // 目标卡片宽度优先使用测量到的内容宽度（如果可用），否则回退到传入的 cardSize.width
                final maxAllowedWidth = MediaQuery.of(context).size.width - 16.0; // 留白
                final measuredW = _measuredContentWidth ?? widget.cardSize.width;
                final targetWidth = measuredW.clamp(widget.buttonSize.width, maxAllowedWidth);

                // 目标卡片高度优先使用测量到的内容高度（如果可用），否则回退到传入的 cardSize.height
                final measuredH = _measuredContentHeight ?? widget.cardSize.height;
                final targetHeight = measuredH;

                final width = ui.lerpDouble(widget.buttonSize.width, targetWidth, clampedProgress)!;
                final height = ui.lerpDouble(widget.buttonSize.height, targetHeight, clampedProgress)!;
                final radius = ui.lerpDouble(widget.buttonRadius, widget.cardRadius, clampedProgress)!;
                final offset = ui.lerpDouble(0, widget.cardOffset, clampedProgress)!;

                // 粘连效果计算：根据cardOffset动态调整粘连范围
                // offset越小，粘连消失越快；offset越大，粘连持续更久
                // 使用更激进的归一化，确保小offset时粘连迅速消失
                final normalizedOffset = (widget.cardOffset / 100.0).clamp(0.15, 1.0); // 归一化到0.15-1.0

                // 粘连持续时间：offset小时快速结束，offset大时持续更久
                // cardOffset=10时约0.35，cardOffset=30时约0.45，cardOffset=80时约0.65
                final gooeyThreshold = 0.3 + (normalizedOffset * 0.35);

                // 消退速度：offset越小消退越快
                // cardOffset=10时约0.08，cardOffset=30时约0.10，cardOffset=80时约0.20
                final gooeyFadeRange = 0.06 + (normalizedOffset * 0.14);

                final gooeyStrength = (t < gooeyThreshold ? t / gooeyThreshold : 1 - ((t - gooeyThreshold) / gooeyFadeRange)).clamp(0.0, 1.0);

                // 根据offset调整blur强度，确保小offset使用很小的blur值
                // cardOffset=10: minBlur≈20, maxBlur≈50
                // cardOffset=30: minBlur≈25, maxBlur≈70
                // cardOffset=80: minBlur≈35, maxBlur≈120
                final minBlur = 15.0 + (normalizedOffset * 20.0);
                final maxBlur = 40.0 + (normalizedOffset * 80.0);
                final blurAmount = ui.lerpDouble(minBlur, maxBlur, gooeyStrength)!;

                // 按钮中心位置（全局坐标）
                final buttonCenterX = widget.buttonPosition.dx + widget.buttonSize.width / 2;
                final buttonCenterY = widget.buttonPosition.dy + widget.buttonSize.height / 2;

                // 计算卡片位置（根据方向），卡片从按钮位置开始
                late double cardCenterX;
                late double cardCenterY;

                switch (widget.direction) {
                  case DropdownDirection.bottom:
                    cardCenterX = buttonCenterX;
                    cardCenterY = buttonCenterY + widget.gap + offset + height / 2;
                    break;
                  case DropdownDirection.up:
                    cardCenterX = buttonCenterX;
                    cardCenterY = buttonCenterY - widget.gap - offset - height / 2;
                    break;
                  case DropdownDirection.left:
                    cardCenterX = buttonCenterX - widget.gap - offset - width / 2;
                    cardCenterY = buttonCenterY;
                    break;
                  case DropdownDirection.right:
                    cardCenterX = buttonCenterX + widget.gap + offset + width / 2;
                    cardCenterY = buttonCenterY;
                    break;
                  case DropdownDirection.topRight:
                    final diagOffset = offset * 0.707; // 对角线距离
                    cardCenterX = buttonCenterX + widget.gap + diagOffset + width / 2;
                    cardCenterY = buttonCenterY - widget.gap - diagOffset - height / 2;
                    break;
                  case DropdownDirection.topLeft:
                    final diagOffset = offset * 0.707;
                    cardCenterX = buttonCenterX - widget.gap - diagOffset - width / 2;
                    cardCenterY = buttonCenterY - widget.gap - diagOffset - height / 2;
                    break;
                  case DropdownDirection.bottomLeft:
                    final diagOffset = offset * 0.707;
                    cardCenterX = buttonCenterX - widget.gap - diagOffset - width / 2;
                    cardCenterY = buttonCenterY + widget.gap + diagOffset + height / 2;
                    break;
                  case DropdownDirection.bottomRight:
                    final diagOffset = offset * 0.707;
                    cardCenterX = buttonCenterX + widget.gap + diagOffset + width / 2;
                    cardCenterY = buttonCenterY + widget.gap + diagOffset + height / 2;
                    break;
                  case DropdownDirection.auto:
                    cardCenterX = buttonCenterX;
                    cardCenterY = buttonCenterY + widget.gap + offset + height / 2;
                    break;
                }

                // 屏幕边缘自适应：防止卡片在水平方向越界
                final screenSize = MediaQuery.of(context).size;
                final edgePadding = 8.0;
                final left = cardCenterX - width / 2;
                final right = cardCenterX + width / 2;
                if (left < edgePadding) {
                  cardCenterX += (edgePadding - left);
                }
                if (right > screenSize.width - edgePadding) {
                  cardCenterX -= (right - (screenSize.width - edgePadding));
                }

                return Stack(
                  children: [
                    // Shader绘制的Gooey效果（全屏）
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: CustomPaint(
                          painter: _GooeyShaderPainter(
                            shader: widget.shader,
                            progress: gooeyStrength,
                            buttonPos: Offset(buttonCenterX, buttonCenterY),
                            cardPos: Offset(cardCenterX, cardCenterY),
                            buttonRadius: widget.buttonSize.height / 2,
                            cardWidth: width,
                            cardHeight: height,
                            cardRadius: radius,
                            blurAmount: blurAmount,
                            buttonColor: widget.buttonColor,
                            cardColor: widget.cardColor,
                          ),
                        ),
                      ),
                    ),

                    // 卡片内容（带边框和阴影）
                    Positioned(
                      top: cardCenterY - height / 2,
                      left: cardCenterX - width / 2,
                      child: IgnorePointer(
                        ignoring: false,
                        child: Container(
                          width: width,
                          // 不再使用固定的 cardSize.height，让高度随内容动画过渡
                          height: height,
                          decoration: BoxDecoration(
                            color: widget.cardColor,
                            borderRadius: BorderRadius.circular(radius),
                            border: widget.cardBorder,
                            boxShadow: widget.cardBoxShadow,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(radius),
                            child: _ContentWrapper(
                              progress: t,
                              width: width,
                              height: height,
                              child: GooeyDropdownScope(close: widget.onClose, child: widget.content),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 按钮内容（在shader上层渲染，确保icon/text可见）
                    Positioned(
                      top: buttonCenterY - widget.buttonSize.height / 2,
                      left: buttonCenterX - widget.buttonSize.width / 2,
                      child: IgnorePointer(
                        child: SizedBox(
                          width: widget.buttonSize.width,
                          height: widget.buttonSize.height,
                          child: Builder(
                            builder: (ctx) {
                              final built = widget.buttonBuilder?.call(widget.originContext) ?? widget.buttonWidget;

                              Widget normalized = built;
                              // 如果 StateTransitionAnimation 被包裹在 Container/ Padding 等常见容器内，
                              // 我们需要递归替换深层的 StateTransitionAnimation 实例，确保 overlay 中使用修正后的 textStyle。
                              final origDefault = widget.originDefaultTextStyle ?? DefaultTextStyle.of(widget.originContext).style;

                              Widget replaceDeep(Widget w) {
                                if (w is StateTransitionAnimation) {
                                  final original = w;
                                  final base = original.textStyle ?? origDefault;
                                  final fixed = base.copyWith(
                                    fontFamily: origDefault.fontFamily ?? base.fontFamily,
                                    fontFamilyFallback: origDefault.fontFamilyFallback ?? base.fontFamilyFallback,
                                    color: base.color ?? origDefault.color,
                                    decoration: TextDecoration.none,
                                  );

                                  return StateTransitionAnimation(
                                    svg: original.svg,
                                    label: original.label,
                                    hoverSvg: original.hoverSvg,
                                    enableScaleAnimation: original.enableScaleAnimation,
                                    animationDuration: original.animationDuration,
                                    height: original.height,
                                    padding: original.padding,
                                    decoration: original.decoration,
                                    textStyle: fixed,
                                    svgSize: original.svgSize,
                                    spacing: original.spacing,
                                    svgColor: original.svgColor,
                                    loading: original.loading,
                                  );
                                }

                                // 常见的单子组件容器：Container, Padding, Center, SizedBox
                                if (w is Container) {
                                  return Container(
                                    key: w.key,
                                    alignment: w.alignment,
                                    padding: w.padding,
                                    color: w.color,
                                    decoration: w.decoration,
                                    foregroundDecoration: w.foregroundDecoration,
                                    constraints: w.constraints,
                                    margin: w.margin,
                                    clipBehavior: w.clipBehavior,
                                    child: w.child != null ? replaceDeep(w.child!) : null,
                                  );
                                }

                                if (w is Padding) {
                                  return Padding(padding: w.padding, child: replaceDeep(w.child!));
                                }

                                if (w is Center) {
                                  return Center(
                                    key: w.key,
                                    widthFactor: w.widthFactor,
                                    heightFactor: w.heightFactor,
                                    child: w.child != null ? replaceDeep(w.child!) : null,
                                  );
                                }

                                if (w is SizedBox) {
                                  return SizedBox(
                                    key: w.key,
                                    width: w.width,
                                    height: w.height,
                                    child: w.child != null ? replaceDeep(w.child!) : null,
                                  );
                                }

                                // 未识别的 widget，返回原始（无法替换）
                                return w;
                              }

                              normalized = replaceDeep(built);

                              // 强制使用原始 Theme 和 完全覆盖的 DefaultTextStyle，确保字体/下划线一致
                              // 额外包裹一层 DefaultTextStyle 确保 decoration.none 生效
                              return DefaultTextStyle(
                                style: const TextStyle(decoration: TextDecoration.none),
                                child: InheritedTheme.captureAll(widget.originContext, normalized),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // 隐藏但排版的内容测量器：用来测量 content 在自然宽度下的尺寸
            // 我们把内容放到屏幕外并通过 GlobalKey 在帧后读取尺寸
            Positioned(
              left: -10000,
              top: -10000,
              child: Builder(
                builder: (ctx) {
                  final screenW = MediaQuery.of(ctx).size.width;
                  // 限制测量宽度为屏幕宽度的可用空间，避免无限扩展
                  // 限制测量宽度为屏幕宽度的可用空间，避免无限扩展
                  final probeMaxWidth = screenW - 16.0;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: probeMaxWidth),
                    child: Theme(
                      data: Theme.of(widget.originContext),
                      // 不再强制给 SizedBox 一个固定宽度，让 child 在 maxWidth 限制下按自然宽度测量
                      child: SizedBox(key: _measureKey, child: widget.content),
                    ),
                  );
                },
              ),
            ),

            // NOTE: background tap handler moved to the bottom of the stack
          ],
        ),
      ),
    );
  }
}

/// Shader绘制器
class _GooeyShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double progress;
  final Offset buttonPos;
  final Offset cardPos;
  final double buttonRadius;
  final double cardWidth;
  final double cardHeight;
  final double cardRadius;
  final double blurAmount;
  final Color buttonColor;
  final Color cardColor;

  _GooeyShaderPainter({
    required this.shader,
    required this.progress,
    required this.buttonPos,
    required this.cardPos,
    required this.buttonRadius,
    required this.cardWidth,
    required this.cardHeight,
    required this.cardRadius,
    required this.blurAmount,
    required this.buttonColor,
    required this.cardColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, progress);
    shader.setFloat(1, buttonPos.dx);
    shader.setFloat(2, buttonPos.dy);
    shader.setFloat(3, cardPos.dx);
    shader.setFloat(4, cardPos.dy);
    shader.setFloat(5, buttonRadius);
    shader.setFloat(6, cardWidth);
    shader.setFloat(7, cardHeight);
    shader.setFloat(8, cardRadius);
    shader.setFloat(9, blurAmount);
    // 传递按钮颜色 (RGBA)
    shader.setFloat(10, buttonColor.red / 255.0);
    shader.setFloat(11, buttonColor.green / 255.0);
    shader.setFloat(12, buttonColor.blue / 255.0);
    shader.setFloat(13, buttonColor.opacity);
    // 传递卡片颜色 (RGBA)
    shader.setFloat(14, cardColor.red / 255.0);
    shader.setFloat(15, cardColor.green / 255.0);
    shader.setFloat(16, cardColor.blue / 255.0);
    shader.setFloat(17, cardColor.opacity);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GooeyShaderPainter oldDelegate) => true;
}

/// 提供 overlay 关闭控制的 InheritedWidget
class GooeyDropdownScope extends InheritedWidget {
  final VoidCallback close;

  const GooeyDropdownScope({required this.close, required Widget child, Key? key}) : super(key: key, child: child);

  static GooeyDropdownScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GooeyDropdownScope>();
  }

  @override
  bool updateShouldNotify(covariant GooeyDropdownScope oldWidget) => oldWidget.close != close;
}

/// 内容包装器（处理淡入动画和溢出）
class _ContentWrapper extends StatelessWidget {
  final double progress;
  final double width;
  final double height;
  final Widget child;

  const _ContentWrapper({required this.progress, required this.width, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    // 内容在卡片出现期间淡入：透明度从0到1
    final contentProgress = progress.clamp(0.0, 1.0);
    final opacity = Curves.easeInOut.transform(contentProgress);

    // 当进度非常小时，隐藏内容以避免布局和渲染开销
    // 进度太小时卡片尺寸不足，会导致内部 Row/Text 布局溢出，使用较高阈值避免此问题
    if (progress < 0.25) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: opacity,
      child: ClipRect(
        child: OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: width,
          maxHeight: height,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: child),
          ),
        ),
      ),
    );
  }
}
