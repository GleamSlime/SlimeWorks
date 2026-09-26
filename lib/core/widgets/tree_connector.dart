import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 树形连接线：把一组子项和它们的父项在视觉上串成一族
///
/// 只靠缩进读不出"这三行属于上面那一行"，尤其侧栏里还夹着别的顶层项。
/// 这一层画在子项**背后**（一整块 Column 一次画完），而不是每行各画一段：
/// 行高由外层给定，几何就能精确对齐，不用每行去猜自己在第几格。
///
/// 竖干从**父项那一行的下沿**（本层 y=0）起、到最后一枝的转弯处**为止**。
/// 从第一枝的中心起，父项和这一族之间就断了一截（只有一个子项时最明显：
/// 只剩一个悬空的小钩）；穿过末项继续往下，又读成"下面还有"，而它没有。
class TreeConnector extends StatelessWidget {
  const TreeConnector({
    super.key,
    required this.childCount,
    required this.rowHeight,
    required this.child,
    this.spacing = 0,
    this.stemX,
    this.branchLength,
  });

  final int childCount;

  /// 单行高度（不含 [spacing]）：调用方必须给确定值，否则中心线会飘
  final double rowHeight;

  /// 行间距，要和子项 Column 的 spacing 一致
  final double spacing;

  /// 竖干的横向位置
  final double? stemX;

  /// 横枝长度
  final double? branchLength;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final x = stemX ?? scaleW(12);
    final branch = branchLength ?? scaleW(10);
    final radius = scaleW(6);

    return CustomPaint(
      painter: _TreeLinePainter(
        childCount: childCount,
        rowHeight: rowHeight,
        spacing: spacing,
        stemX: x,
        branchLength: branch,
        radius: radius,
        color: s.border,
      ),
      // 线在内容底下，所以文字那一侧要让出竖干 + 横枝的横向空间
      child: Padding(padding: EdgeInsets.only(left: x + branch), child: child),
    );
  }
}

class _TreeLinePainter extends CustomPainter {
  _TreeLinePainter({
    required this.childCount,
    required this.rowHeight,
    required this.spacing,
    required this.stemX,
    required this.branchLength,
    required this.radius,
    required this.color,
  });

  final int childCount;
  final double rowHeight;
  final double spacing;
  final double stemX;
  final double branchLength;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (childCount <= 0) return;

    // 线宽固定 1：吃缩放的话，缩放后不足 1 物理像素会被抗锯齿冲淡成一条灰边
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    double center(int i) => i * (rowHeight + spacing) + rowHeight / 2;
    // 弯的大小固定，不跟行高走，否则高行会翻出一个大钩子
    final elbow = math.min(radius, rowHeight / 4);
    final lastY = center(childCount - 1);

    // 竖干：贴着本层顶端起，也就是父项那一行的下沿，一直画到末枝的转弯处
    canvas.drawLine(Offset(stemX, 0), Offset(stemX, lastY - elbow), paint);

    for (var i = 0; i < childCount; i++) {
      final y = center(i);
      final endX = stemX + branchLength;
      // 每一枝都是"竖着下来 → 圆角转弯 → 横着出去"，和参考图里 ╰╴ 那种枝一致。
      // 反过来先横后竖会读成表格线，而且竖干还没到就已经拐走了。
      final path = Path()
        ..moveTo(stemX, y - elbow)
        ..arcToPoint(
          Offset(stemX + elbow, y),
          radius: Radius.circular(elbow),
          clockwise: true,
        )
        ..lineTo(endX, y);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TreeLinePainter old) =>
      old.childCount != childCount ||
      old.rowHeight != rowHeight ||
      old.spacing != spacing ||
      old.stemX != stemX ||
      old.branchLength != branchLength ||
      old.color != color;
}
