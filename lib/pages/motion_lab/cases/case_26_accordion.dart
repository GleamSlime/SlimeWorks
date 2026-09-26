import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 26. Accordion — 面板从 0 长到满，V 形箭头顶翻成 ^
///
/// 参考稿用 `grid-template-rows: 0fr → 1fr` 拿到"不用量高度"的展开，等价写法是
/// 外层给补间出来的高度、内层始终按完整高度排版再裁掉——内容才不会被压扁。
/// 展开/收起/箭头同为 250ms 顺出，所以共用一条时钟。
/// 箭头是 `scaleY(1 → -1)` 绕中心翻，中点正好压成一条平线；`vector-effect:
/// non-scaling-stroke` 要求描边恒定宽，直接 Transform.scale 会把线一起压细，
/// 故单独画顶点（见 _ChevronPainter）。
const _dur = Duration(
  milliseconds: 250,
); // --p21-expand-dur / --p21-collapse-dur / --p21-chevron-dur
const _ease = LabEase.smoothOut; // --p21-ease

const _itemW = 261.0; // .p21-accordion 宽
const _itemH = 166.0; // .p21-accordion 固定高：展开时标题不上跳
const _headH = 56.0; // .p21-head
const _radius = 12.0; // .p21-item
const _padX = 24.0; // .p21-rows 左右内衬（标题行是 24 / 22）
const _panelH = _itemH - _headH; // 110 = 4 + 14×3 + 20×2 + 24

/// 舞台里横向居中、底部同幅内衬：(296 - 261) / 2
const _inset = (296.0 - _itemW) / 2;

const _blurSmall = 2.0; // --blur-small
const _strokeWidth = 1.5; // svg stroke-width

/// .p21-row：14 高 / 圆角 4 的成对骨架条，行内左右分开、行间 20
const _barH = 14.0;
const _rows = [
  [77.0, 42.0],
  [93.0, 42.0],
  [57.0, 32.0],
];

class Case26Accordion extends StatefulWidget {
  const Case26Accordion({super.key});

  @override
  State<Case26Accordion> createState() => _Case26AccordionState();
}

class _Case26AccordionState extends State<Case26Accordion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: _dur,
    value: 0,
  );

  bool _open = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _toggle() {
    final next = !_open;
    setState(() => _open = next);
    _t.animateTo(next ? 1 : 0, curve: _ease);
  }

  @override
  Widget build(BuildContext context) {
    final p = _t.value;
    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: _inset,
            bottom: _inset,
            width: _itemW,
            height: _itemH,
            child: Align(
              alignment: Alignment.topLeft,
              // 投影不能被裁掉，所以描在外层、裁在内层
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: LabColor.card,
                  borderRadius: BorderRadius.circular(_radius),
                  boxShadow: LabShadow.material,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_radius),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _head(),
                      SizedBox(
                        height: _panelH * p,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: _panelH,
                              child: Opacity(
                                opacity: p.clamp(0.0, 1.0),
                                child: LabBlur(
                                  sigma: _blurSmall * (1 - p),
                                  child: const _Rows(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 标题行：整行可点，右侧箭头跟着同一条时钟顶翻
  Widget _head() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: SizedBox(
          height: _headH,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_padX, 0, 22, 0),
            child: Row(
              children: [
                const Expanded(child: Text('Appearance', style: LabText.title)),
                CustomPaint(
                  size: const Size.square(16),
                  painter: _ChevronPainter(scaleY: 1 - 2 * _t.value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// svg `M4 6.5L8 10.5L12 6.5`（16 viewBox / 描边 1.5 / round）的等价绘制：
/// 三个顶点绕 y=8 对称缩放，描边宽度不参与缩放
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.scaleY});

  final double scaleY;

  /// 翻转轴：16×16 的中心
  static const _axis = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final p0 = _flip(const Offset(4, 6.5));
    final p1 = _flip(const Offset(8, 10.5));
    final p2 = _flip(const Offset(12, 6.5));
    canvas.drawPath(
      Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy),
      Paint()
        ..color = LabColor
            .slate // stroke: var(--muted)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Offset _flip(Offset p) => Offset(p.dx, _axis + (p.dy - _axis) * scaleY);

  @override
  bool shouldRepaint(_ChevronPainter old) => old.scaleY != scaleY;
}

/// 三行骨架条
class _Rows extends StatelessWidget {
  const _Rows();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padX, 4, _padX, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _rows.length - 1 ? 0 : 20),
              child: SizedBox(
                height: _barH,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final w in _rows[i])
                      SizedBox(
                        width: w,
                        height: _barH,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            color: LabColor.skeleton,
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
