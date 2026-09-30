import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/view_models/media_library_viewmodel.dart';

/// 桌面端框选层：拖出矩形后按网格几何反推命中卡片。
///
/// 独立成层的意义：拖框过程中的 setState 只重建本组件自己的 State，
/// [child]（浏览网格）是同一个 widget 实例，整帧零重建——
/// 旧实现里框选拖动会让网格 State 全量 setState，每帧重建所有可见卡片。
/// 框选矩形自身走 RepaintBoundary + CustomPaint，重绘不波及子树。
class SelectionMarquee extends StatefulWidget {
  const SelectionMarquee({
    super.key,
    required this.viewModel,
    required this.scrollController,
    required this.child,
  });

  /// 被框选覆盖的网格本体（同一实例复用，拖框期间不重建）
  final Widget child;

  final MediaLibraryViewModel viewModel;

  /// 网格的滚动控制器：拖框坐标是视口系，命中反推要加回滚动偏移才是内容系
  final ScrollController scrollController;

  @override
  State<SelectionMarquee> createState() => _SelectionMarqueeState();
}

class _SelectionMarqueeState extends State<SelectionMarquee> {
  /// 框选起点（本组件本地坐标）
  Offset? _start;

  /// 框选终点（本组件本地坐标）
  Offset? _end;

  MediaLibraryViewModel get vm => widget.viewModel;

  /// 网格本体的 RenderBox key，用于把本组件坐标换算到网格坐标
  final GlobalKey _gridKey = GlobalKey();

  void _updateSelectionByBox() {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return;
    final selectionRect = Rect.fromPoints(start, end);
    final gridRenderBox =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (gridRenderBox == null) return;

    final items = vm.visibleItems;
    final newSelection = <String>{};
    // 列数与格宽走同一条公式（见 MediaCutoutGeometry.gridColumnsFor）：
    // 这里是拿来判命中的矩形，和 delegate 差一列就会选中隔壁那张卡。
    final (crossAxisCount, itemWidth) = MediaCutoutGeometry.gridColumnsFor(
      gridRenderBox.size.width,
    );
    if (crossAxisCount <= 0) return;

    // 拖框矩形是视口系坐标，卡片行高是内容系坐标：
    // 已经滚动过一段再拖框时，必须减去滚动偏移换算到同一坐标系，
    // 否则命中的是「视口顶部那几行」而不是用户框住的行。
    final controller = widget.scrollController;
    final scrollOffset = controller.hasClients ? controller.offset : 0.0;

    final spacing = appMetrics.kSpace12;
    final padding = appMetrics.kSpace12;
    final itemHeight = itemWidth / MediaCutoutGeometry.aspectFor(itemWidth);

    for (int index = 0; index < items.length; index++) {
      final row = index ~/ crossAxisCount;
      final column = index % crossAxisCount;
      final left = padding + column * (itemWidth + spacing);
      final top = padding + row * (itemHeight + spacing) - scrollOffset;
      final itemRect = Rect.fromLTWH(left, top, itemWidth, itemHeight);
      if (selectionRect.overlaps(itemRect)) {
        newSelection.add(items[index].id);
      }
    }
    vm.applyBoxSelection(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = _end;
    final dragging = start != null && end != null;
    return GestureDetector(
      // 拖框期间不响应点击穿透，避免拖框误触卡片
      behavior: dragging ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onPanStart: (details) {
        setState(() {
          _start = details.localPosition;
          _end = details.localPosition;
        });
      },
      onPanUpdate: (details) {
        setState(() => _end = details.localPosition);
        _updateSelectionByBox();
      },
      onPanEnd: (_) {
        setState(() {
          _start = null;
          _end = null;
        });
      },
      child: Stack(
        children: [
          KeyedSubtree(key: _gridKey, child: widget.child),
          if (dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _MarqueePainter(
                      start: start,
                      end: end,
                      color: Theme.of(context).colorScheme.primary.withAlpha(48),
                      borderColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 框选矩形绘制器。
class _MarqueePainter extends CustomPainter {
  const _MarqueePainter({
    required this.start,
    required this.end,
    required this.color,
    required this.borderColor,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scaleW(1.5);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor;
  }
}
