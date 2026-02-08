import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GooeyDropdownDemo extends StatefulWidget {
  const GooeyDropdownDemo({super.key});

  @override
  State<GooeyDropdownDemo> createState() => _GooeyDropdownDemoState();
}

class _GooeyDropdownDemoState extends State<GooeyDropdownDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  ui.FragmentShader? _shader;

  static const double buttonSize = 56;
  static const double cardWidth = 320;
  static const double cardHeight = 220;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await ui.FragmentProgram.fromAsset('shaders/gooey.frag');
    setState(() {
      _shader = program.fragmentShader();
    });
  }

  void open() => _controller.forward();
  void close() => _controller.reverse();

  bool get isOpen => _controller.value > 0;

  @override
  void dispose() {
    _controller.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff2f2f2),
      body: GestureDetector(
        // 在整个body上监听点击，用于关闭卡片
        onTap: () {
          if (isOpen) {
            print('背景被点击，关闭卡片');
            close();
          }
        },
        child: Center(
          child: SizedBox(
            width: 400,
            height: 500,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                /// Gooey 效果层（shader绘制按钮和卡片的粘连效果）
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, _) {
                    if (_controller.value == 0 || _shader == null) {
                      return const SizedBox.shrink();
                    }

                    final t = _controller.value;

                    /// 卡片尺寸插值（从按钮大小 → 最终大小）
                    /// 前60%慢速（粘连阶段），后40%快速
                    final sizeProgress = t < 0.6 ? Curves.easeOut.transform(t / 0.6) * 0.7 : 0.7 + Curves.easeInOut.transform((t - 0.6) / 0.4) * 0.3;
                    final width = ui.lerpDouble(buttonSize, cardWidth, sizeProgress)!;
                    final height = ui.lerpDouble(buttonSize, cardHeight, sizeProgress)!;
                    final radius = ui.lerpDouble(buttonSize / 2, 18, sizeProgress)!;

                    /// 卡片向下移动距离（从按钮中心开始向下）
                    final cardOffset = ui.lerpDouble(0, 80, sizeProgress)!;

                    // 不再使用弹跳效果
                    /// Gooey强度（0.5之后减弱）
                    final gooeyStrength = (t < 0.5 ? t / 0.5 : 1 - ((t - 0.5) / 0.1).clamp(0, 1)).toDouble();

                    /// Blur强度（控制粘连效果的强度）- 增大范围以获得更明显的粘连效果
                    final blurAmount = ui.lerpDouble(20, 80, gooeyStrength)!;

                    /// 按钮中心位置
                    const buttonCenterX = 172.0 + buttonSize / 2;
                    const buttonCenterY = 50.0 + buttonSize / 2;

                    /// 卡片中心位置（在按钮下方）
                    final cardCenterY = buttonCenterY + buttonSize / 2 + cardOffset + height / 2;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        /// Shader绘制的Gooey效果（包含按钮和卡片）
                        Positioned.fill(
                          child: CustomPaint(
                            painter: GooeyShaderPainter(
                              shader: _shader!,
                              progress: gooeyStrength,
                              buttonPos: const Offset(buttonCenterX, buttonCenterY),
                              cardPos: Offset(buttonCenterX, cardCenterY),
                              buttonRadius: buttonSize / 2,
                              cardWidth: width,
                              cardHeight: height,
                              cardRadius: radius,
                              blurAmount: blurAmount,
                            ),
                          ),
                        ),

                        /// 卡片内容（只显示文字，背景透明以显示shader效果）
                        Positioned(
                          top: cardCenterY - height / 2,
                          left: buttonCenterX - width / 2,
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              child: Container(
                                width: width,
                                height: height,
                                alignment: Alignment.center,
                                child: Content(progress: t),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                /// 按钮（固定在中心，显示在最上层）
                Positioned(
                  top: 50,
                  left: 172,
                  child: GestureDetector(
                    onTap: () {
                      print('按钮被点击');
                      open();
                    },
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                      child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// GLSL Shader Painter（真正的GPU Gooey效果）
/// =======================
class GooeyShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double progress;
  final Offset buttonPos;
  final Offset cardPos;
  final double buttonRadius;
  final double cardWidth;
  final double cardHeight;
  final double cardRadius;
  final double blurAmount;

  GooeyShaderPainter({
    required this.shader,
    required this.progress,
    required this.buttonPos,
    required this.cardPos,
    required this.buttonRadius,
    required this.cardWidth,
    required this.cardHeight,
    required this.cardRadius,
    required this.blurAmount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 设置shader uniforms（按shader中定义的顺序）
    shader.setFloat(0, progress); // uProgress
    shader.setFloat(1, buttonPos.dx); // uButtonPos.x
    shader.setFloat(2, buttonPos.dy); // uButtonPos.y
    shader.setFloat(3, cardPos.dx); // uCardPos.x
    shader.setFloat(4, cardPos.dy); // uCardPos.y
    shader.setFloat(5, buttonRadius); // uButtonRadius
    shader.setFloat(6, cardWidth); // uCardWidth
    shader.setFloat(7, cardHeight); // uCardHeight
    shader.setFloat(8, cardRadius); // uCardRadius
    shader.setFloat(9, blurAmount); // uBlur

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant GooeyShaderPainter oldDelegate) => true;
}

/// =======================
/// 卡片内容（后出现）
/// =======================
class Content extends StatelessWidget {
  final double progress;

  const Content({super.key, required this.progress});
  @override
  Widget build(BuildContext context) {
    // 内容在卡片出现（缩放期间）就开始淡入：0.0 -> 0.5 期间完成
    final contentProgress = (progress / 0.5).clamp(0.0, 1.0);
    final show = Curves.easeOut.transform(contentProgress);

    return Opacity(
      opacity: show,
      child: Transform.translate(
        offset: Offset(0, (1 - show) * 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Messages', style: TextStyle(color: Colors.white, fontSize: 16)),
              SizedBox(height: 12),
              _Row(),
              _Row(),
              _Row(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: const [
          CircleAvatar(radius: 14),
          SizedBox(width: 10),
          Expanded(
            child: Text('Message preview text', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
