import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 侧栏与内容区之间那道缝上的拖拽把手
///
/// 静止时是一根居中的竖线；悬停时竖线绕中心对折，折成一只指向"该往哪边收"
/// 的箭头（展开态收向 ‹，收起态收向 ›）。点箭头的语义按状态分：展开→收起、
/// 收起→展开、隐藏→展开；从收起再往"看不见"走一格不藏在箭头里，而是悬停时
/// 箭头下方浮出一枚闭眼图标，点它进隐藏态（旧版点箭头三连跳，收起态点一下
/// 直接消失，看着像侧栏丢了）。左右拖改宽度：展开态直接改栏宽，收起/隐藏态
/// 起拖则栏宽跟手走，松手按拖过的进度决定落到哪一档。光标跟着这几档走：
/// 竖线=左右拖、箭头=可点、按住=在拖。
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
    this.onHide,
    this.hitWidth = 22,
    this.idleColor,
    this.activeColor,
  });

  /// 侧栏是否已是收起/隐藏态；决定箭头朝向，往右拖一律是"跟手拉回来"
  final bool collapsed;

  /// 横向位移增量（逻辑像素），由调用方换算成设计宽度
  final ValueChanged<double> onDragUpdate;

  /// 点箭头：展开 ↔ 收起；隐藏态下 = 展开
  final VoidCallback onToggle;

  /// 收起态悬停时箭头下方那枚闭眼图标的点法：进隐藏态。
  /// 不传就不画这枚图标（样式总览页的演示把手就没有）。
  final VoidCallback? onHide;

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

  /// 闭眼图标只属于"收起态且指针正停在把手上"这一刻；拖拽中也收起来，
  /// 免得手指压着箭头改宽度时误触它
  bool get _showHide =>
      widget.onHide != null && widget.collapsed && _hovering && !_dragging;

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
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
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
              if (_showHide)
                // 闭眼图标贴在箭头正下方，一律不出这条 22 宽的带子：
                // 往内容区一侧扩就会把页面边缘的点击吃掉。命中的是整枚
                // 图标带一圈垫高，比裸 14px 好点中；它的 tap 在更深一层，
                // 会赢过外层"点箭头=onToggle"，互不串台。
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: scaleW(46)),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onHide,
                      child: Padding(
                        padding: EdgeInsets.all(scaleW(4)),
                        child: DrawIcon(
                          StrokeIcons.visibilityOff,
                          size: scaleW(14),
                          color: active,
                          trigger: StrokeTrigger.appear,
                          semanticLabel: '隐藏侧栏',
                        ),
                      ),
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
