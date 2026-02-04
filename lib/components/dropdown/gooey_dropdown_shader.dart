import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  /// 动画时长，默认 1200ms
  final Duration? duration;

  /// 卡片相对按钮的间隙，默认 10
  final double? gap;

  /// 卡片相对按钮的偏移量，默认向下80
  final double? cardOffset;

  /// 显示方向，默认自动检测
  final DropdownDirection? direction;

  /// 动画曲线，默认 easeOut 和 easeInOut 组合
  final Curve? curve;

  /// 打开时回调
  final VoidCallback? onOpen;

  /// 关闭时回调
  final VoidCallback? onClose;

  const GooeyDropdownShader({
    super.key,
    required this.button,
    required this.content,
    this.buttonSize,
    this.cardSize,
    this.buttonColor,
    this.cardColor,
    this.buttonRadius,
    this.cardRadius,
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
  down,

  /// 向上
  up,

  /// 向左
  left,

  /// 向右
  right,
}

class _GooeyDropdownShaderState extends State<GooeyDropdownShader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.FragmentShader? _shader;
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  // 默认值
  Size get buttonSize => widget.buttonSize ?? const Size(56, 56);
  Size get cardSize => widget.cardSize ?? const Size(320, 220);
  Color get buttonColor => widget.buttonColor ?? Colors.black;
  Color get cardColor => widget.cardColor ?? Colors.black;
  double get buttonRadius => widget.buttonRadius ?? (buttonSize.height / 2);
  double get cardRadius => widget.cardRadius ?? 18.0;
  Duration get duration => widget.duration ?? const Duration(milliseconds: 1200);
  double get gap => widget.gap ?? 10.0;
  double get cardOffset => widget.cardOffset ?? 80.0;
  DropdownDirection get direction => widget.direction ?? DropdownDirection.auto;
  Curve get curve => widget.curve ?? Curves.easeOut;

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

    // 调试信息
    print('按钮位置: $buttonPosition, 大小: $buttonSize, 屏幕: $screenSize');

    // 计算最佳显示方向
    final actualDirection = _calculateDirection(buttonPosition, buttonSize, screenSize);

    _overlayEntry = OverlayEntry(
      builder: (context) => _DropdownOverlay(
        shader: _shader!,
        controller: _controller,
        buttonPosition: buttonPosition,
        buttonSize: buttonSize,
        cardSize: cardSize,
        buttonColor: buttonColor,
        cardColor: cardColor,
        buttonRadius: buttonRadius,
        cardRadius: cardRadius,
        gap: gap,
        cardOffset: cardOffset,
        direction: actualDirection,
        curve: curve,
        content: widget.content,
        buttonWidget: widget.button,
        onClose: close,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
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

    // 自动检测：优先向下，如果空间不够则向上
    final spaceBelow = screenSize.height - (buttonPos.dy + buttonSize.height);
    final spaceAbove = buttonPos.dy;

    if (spaceBelow >= cardSize.height + gap + 20) {
      return DropdownDirection.down;
    } else if (spaceAbove >= cardSize.height + gap + 20) {
      return DropdownDirection.up;
    } else {
      return DropdownDirection.down; // 默认向下
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
                width: buttonSize.width,
                height: buttonSize.height,
                child: widget.button,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dropdown覆盖层
class _DropdownOverlay extends StatelessWidget {
  final ui.FragmentShader shader;
  final AnimationController controller;
  final Offset buttonPosition;
  final Size buttonSize;
  final Size cardSize;
  final Color buttonColor;
  final Color cardColor;
  final double buttonRadius;
  final double cardRadius;
  final double gap;
  final double cardOffset;
  final DropdownDirection direction;
  final Curve curve;
  final Widget content;
  final Widget buttonWidget;
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
    required this.gap,
    required this.cardOffset,
    required this.direction,
    required this.curve,
    required this.content,
    required this.buttonWidget,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 动画内容
        AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            if (controller.value == 0) {
              return const SizedBox.shrink();
            }

            final t = controller.value;

            // 动画曲线：慢慢快 - 前60%慢速（粘连阶段），后40%快速断开
            // 使用简单的二次曲线避免回弹
            final sizeProgress = t < 0.6 
                ? (t / 0.6) * (t / 0.6) * 0.5  // 前60%二次加速到50%
                : 0.5 + ((t - 0.6) / 0.4) * 0.5;  // 后40%线性到100%

            final clampedProgress = sizeProgress.clamp(0.0, 1.0);
            
            final width = ui.lerpDouble(buttonSize.width, cardSize.width, clampedProgress)!;
            final height = ui.lerpDouble(buttonSize.height, cardSize.height, clampedProgress)!;
            final radius = ui.lerpDouble(buttonRadius, cardRadius, clampedProgress)!;
            final offset = ui.lerpDouble(0, cardOffset, clampedProgress)!;

            // Gooey强度（前60%强粘连，后面快速减弱）
            final gooeyStrength = (t < 0.6 ? t / 0.6 : 1 - ((t - 0.6) / 0.2)).clamp(0.0, 1.0);
            final blurAmount = ui.lerpDouble(50, 150, gooeyStrength)!;  // 提高blur值增强粘连

            // 按钮中心位置（全局坐标）
            final buttonCenterX = buttonPosition.dx + buttonSize.width / 2;
            final buttonCenterY = buttonPosition.dy + buttonSize.height / 2;

            // 计算卡片位置（根据方向）
            late final double cardCenterX;
            late final double cardCenterY;

            switch (direction) {
              case DropdownDirection.down:
                cardCenterX = buttonCenterX;
                cardCenterY = buttonCenterY + buttonSize.height / 2 + gap + offset + height / 2;
                break;
              case DropdownDirection.up:
                cardCenterX = buttonCenterX;
                cardCenterY = buttonCenterY - buttonSize.height / 2 - gap - offset - height / 2;
                break;
              case DropdownDirection.left:
                cardCenterX = buttonCenterX - buttonSize.width / 2 - gap - offset - width / 2;
                cardCenterY = buttonCenterY;
                break;
              case DropdownDirection.right:
                cardCenterX = buttonCenterX + buttonSize.width / 2 + gap + offset + width / 2;
                cardCenterY = buttonCenterY;
                break;
              case DropdownDirection.auto:
                cardCenterX = buttonCenterX;
                cardCenterY = buttonCenterY + buttonSize.height / 2 + gap + offset + height / 2;
                break;
            }

            return Stack(
              children: [
                // Shader绘制的Gooey效果（全屏）
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GooeyShaderPainter(
                      shader: shader,
                      progress: gooeyStrength,
                      buttonPos: Offset(buttonCenterX, buttonCenterY),
                      cardPos: Offset(cardCenterX, cardCenterY),
                      buttonRadius: buttonSize.height / 2,
                      cardWidth: width,
                      cardHeight: height,
                      cardRadius: radius,
                      blurAmount: blurAmount,
                      buttonColor: buttonColor,
                      cardColor: cardColor,
                    ),
                  ),
                ),

                // 卡片内容
                Positioned(
                  top: cardCenterY - height / 2,
                  left: cardCenterX - width / 2,
                  child: IgnorePointer(
                    ignoring: false,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Container(
                        width: width,
                        height: height,
                        child: _ContentWrapper(progress: t, width: width, height: height, child: content),
                      ),
                    ),
                  ),
                ),

                // 按钮内容（在shader上层渲染，确保icon/text可见）
                Positioned(
                  top: buttonCenterY - buttonSize.height / 2,
                  left: buttonCenterX - buttonSize.width / 2,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: buttonSize.width,
                      height: buttonSize.height,
                      child: buttonWidget,
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // 全局背景遮罩（点击关闭）- 放在最上层确保能接收到点击
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
      ],
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

/// 内容包装器（处理淡入动画和溢出）
class _ContentWrapper extends StatelessWidget {
  final double progress;
  final double width;
  final double height;
  final Widget child;

  const _ContentWrapper({required this.progress, required this.width, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    // 内容在卡片出现期间就开始淡入
    final contentProgress = (progress / 0.5).clamp(0.0, 1.0);
    final show = Curves.easeOut.transform(contentProgress);

    // 当卡片太小时（进度<0.3），完全隐藏内容以避免布局溢出警告
    if (progress < 0.3) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: show,
      child: ClipRect(
        child: SizedBox(
          width: width,
          height: height,
          // 使用SingleChildScrollView解决溢出问题
          child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: child),
        ),
      ),
    );
  }
}
