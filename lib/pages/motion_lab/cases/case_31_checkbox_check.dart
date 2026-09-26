import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 31. Checkbox check — 框先填色，勾再顺着路径画出来
///
/// 参考稿这一格没有 Animate 按钮：整行（框 + 文案）自己就是开关。
/// 两段时长不对称：勾上时描线 350ms，取消时只给 150ms 收回去，
/// 而且走的是**同一个 progress**——所以中途反悔会从当前笔画位置倒着收回，
/// 不是整条消失再重画。底色和描边环那一路固定 150ms，跟描线互不牵连。
const _boxDur = Duration(milliseconds: 150); // --p25-box-dur / --p25-uncheck-dur

/// --p25-draw-dur（--p25-draw-delay 是 0，不用等）
const _drawDur = Duration(milliseconds: 350);
const _ease = LabEase.smoothOut; // --p25-ease

/// `.p25-box` 18×18 / 圆角 6，里面的 svg 是 10px（viewBox 10.1668、描边 2）
const _box = 18.0;
const _radius = 6.0;
const _glyph = 10.0;
const _viewBox = 10.1668;
const _strokeWidth = 2.0;

/// --p25-ring: rgba(0,0,0,.11)，未选中那圈内描边
const _ring = Color(0x1C000000);

class Case31CheckboxCheck extends StatefulWidget {
  const Case31CheckboxCheck({super.key});

  @override
  State<Case31CheckboxCheck> createState() => _Case31CheckboxCheckState();
}

class _Case31CheckboxCheckState extends State<Case31CheckboxCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: _drawDur,
    value: 0,
  );

  bool _checked = false;

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_checked;
    setState(() => _checked = next);
    // 勾上给足 350ms，取消压到 150ms：收得快才不像"又画了一遍"
    _draw.animateTo(next ? 1 : 0, duration: next ? _drawDur : _boxDur, curve: _ease);
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // `.p25-field`：框和文案一起点，之间隔 9
            onTap: _toggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: _boxDur,
                  curve: _ease,
                  width: _box,
                  height: _box,
                  decoration: BoxDecoration(
                    // 选中：实心 + 环同色；未选中：白底 + 淡环
                    color: _checked ? LabColor.text : LabColor.card,
                    borderRadius: const BorderRadius.all(Radius.circular(_radius)),
                    border: Border.fromBorderSide(
                      BorderSide(color: _checked ? LabColor.text : _ring),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size.square(_glyph),
                    painter: _CheckPainter(progress: _draw.value),
                  ),
                ),
                const SizedBox(width: 9),
                const Text('Notify me', style: LabText.title),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 勾的描线：按进度截出前段路径再整条描，端点圆头（对应 svg 的 round cap）
class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress});

  final double progress;

  static final Path _path = Path()
    ..moveTo(1.00004, 5.52096)
    ..lineTo(3.9167, 9.16679)
    ..lineTo(9.1667, 1.00012);

  static final double _length =
      _path.computeMetrics().fold<double>(0.0, (sum, m) => sum + m.length);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    // 10.1668 的坐标系缩到 10px，描边宽度跟着一起缩
    canvas.scale(size.width / _viewBox);
    final segment = _path.computeMetrics().first.extractPath(0.0, _length * progress);
    canvas.drawPath(
      segment,
      Paint()
        ..color = LabColor.card // stroke: var(--surface-bg)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
