import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';

/// 侧栏与内容区之间那道缝上的拖拽把手
///
/// 静止时是一根居中的竖线；悬停时竖线绕中心对折，折成一只指向"该往哪边收"
/// 的箭头（展开态收向 ‹，收起态收向 ›），点一下切展开/收起。左右拖改宽度，
/// 拖到最窄自动收起。光标跟着这三档走：竖线=左右拖、箭头=可点、按住=在拖。
///
/// 必须挂在内容区一侧：Row 里后画的盖先画的，把手贴在侧栏右缘上会被内容区
/// 吃掉一半，缩在侧栏里又会被那条滚动条压住。
class SidebarResizeHandle extends StatefulWidget {
  const SidebarResizeHandle({
    super.key,
    required this.collapsed,
    required this.onDragUpdate,
    required this.onToggle,
    this.onDragStart,
    this.onDragEnd,
    this.hitWidth = 22,
    this.idleColor,
    this.activeColor,
  });

  /// 侧栏是否已是收起态（图标条）；决定箭头朝向，也决定往右拖算不算拉回来
  final bool collapsed;

  /// 横向位移增量（逻辑像素），由调用方换算成设计宽度
  final ValueChanged<double> onDragUpdate;

  /// 点按：展开 / 收起
  final VoidCallback onToggle;

  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// 命中区有多宽：把手画在正中，两侧各让出一半，太窄就点不中、也太难拖
  final double hitWidth;

  /// 配色；不传则取语义色层。样式总览页自带一套调色板，靠这几个参数复用同一份实现。
  final Color? idleColor;

  /// 折成箭头后的线色
  final Color? activeColor;

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle>
    with SingleTickerProviderStateMixin {
  /// 对折进度：0 是竖线，1 是箭头
  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );

  bool _hovering = false;
  bool _dragging = false;

  /// 半根线的长度，对折前后共用同一个端点，所以折的是"臂长"
  static const double _armLength = 13;
  static const double _stroke = 3;

  @override
  void initState() {
    super.initState();
    // 进度是每帧从 controller 里读出来的，没人重建就只会看到起终点两帧，
    // 所以动画必须挂一个监听跟着重画
    _fold.addListener(_repaint);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fold.removeListener(_repaint);
    _fold.dispose();
    super.dispose();
  }

  // 光标分三档说清三件事：竖线能左右拖、箭头能点、按住就是在拖
  MouseCursor get _cursor {
    if (_dragging) return SystemMouseCursors.grabbing;
    return _fold.value >= 0.6
        ? SystemMouseCursors.click
        : SystemMouseCursors.resizeLeftRight;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final idle = widget.idleColor ?? s.textTertiary;
    final active = widget.activeColor ?? s.textSecondary;

    // 折这一下要一路看得见：easeOutBack 三成进度就折满了，等于没动画
    final t = Curves.easeOutCubic.transform(_fold.value);
    // 拖拽只摊回竖线，不加粗不变色：那根线本来就是被拖着走的东西，
    // 再给它换个身份只会看成一件事变成了两件
    final lineColor = Color.lerp(idle, active, _fold.value)!;

    return MouseRegion(
      cursor: _cursor,
      onEnter: (_) {
        setState(() => _hovering = true);
        _fold.forward();
      },
      onExit: (_) {
        setState(() => _hovering = false);
        _fold.reverse();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onHorizontalDragStart: (_) {
          // 按下去箭头要摊回成一根线：这时候手上的事是拖，不是点
          _fold.reverse();
          setState(() => _dragging = true);
          widget.onDragStart?.call();
        },
        onHorizontalDragUpdate: (d) => widget.onDragUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          if (_hovering) _fold.forward();
          widget.onDragEnd?.call();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          if (_hovering) _fold.forward();
          widget.onDragEnd?.call();
        },
        child: SizedBox(
          width: widget.hitWidth,
          // 画布比线本身留出一截，圆头端点才不会被裁掉
          child: Center(
            child: CustomPaint(
              size: Size(widget.hitWidth, _armLength * 2 + _stroke * 2),
              painter: _FoldPainter(
                progress: t,
                arm: _armLength,
                stroke: _stroke,
                color: lineColor,
                // 展开态往左折成 ‹，收起态往右折成 ›
                pointLeft: !widget.collapsed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 折到底的角度：45° 时两臂正好拼成一只箭头
const double _foldAngle = math.pi / 4;

/// 一根线绕中心对折成箭头
class _FoldPainter extends CustomPainter {
  _FoldPainter({
    required this.progress,
    required this.arm,
    required this.stroke,
    required this.color,
    required this.pointLeft,
  });

  /// 0 = 竖直，1 = 折满 45°
  final double progress;
  final double arm;
  final double stroke;
  final Color color;
  final bool pointLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final angle = progress * _foldAngle;
    // 竖着量是臂长，折过去以后两臂各自摊开一点：cos 给箭头的纵深，sin 给张口
    final reach = arm * math.cos(angle);
    final spread = arm * math.sin(angle);
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 折痕就是两臂共用的那个端点，也就是箭头的尖；尖和两臂末端一前一后，
    // 整个图形按中心左右对称，折的时候才不会看着往一边偏
    // pointLeft（展开态）时尖在左、两臂朝右张开，就是 ‹
    final dir = pointLeft ? 1 : -1;
    final apex = Offset(centerX - dir * spread / 2, centerY);
    final tipX = centerX + dir * spread / 2;
    canvas.drawLine(apex, Offset(tipX, centerY - reach), paint);
    canvas.drawLine(apex, Offset(tipX, centerY + reach), paint);
  }

  @override
  bool shouldRepaint(_FoldPainter old) =>
      old.progress != progress ||
      old.arm != arm ||
      old.stroke != stroke ||
      old.color != color ||
      old.pointLeft != pointLeft;
}
