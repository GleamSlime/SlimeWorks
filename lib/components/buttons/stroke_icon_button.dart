import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../icons/draw_icon.dart';
import '../icons/stroke_geometry.dart';
import '../icons/stroke_zone.dart';

/// 可点的描边图标按钮：按下/悬停重播描边 + 按下缩放 + 悬停换色。
///
/// 取代原来加载 svg 资产的同类按钮（`SvgPicture.asset` + 两张 hover/no-hover 图）。
/// 换成几何图标后不再需要"悬停换图"：hover 只换一个颜色，两张图的一致性问题也随之消失；
/// 而 [icon] 本身变化时（比如侧栏展开/收起那对箭头）DrawIcon 会走"旧的擦回去 + 新的描出来"。
class StrokeIconButton extends StatefulWidget {
  const StrokeIconButton(
    this.icon, {
    super.key,
    required this.onTap,
    this.size = 24,
    this.color,
    this.hoverColor,
    this.scaleOnPress = false,
    this.enabled = true,
    this.semanticLabel,
  });

  final StrokeIcon icon;
  final VoidCallback? onTap;
  final double size;

  /// 缺省跟随 [IconTheme]，与 `Icon` 一致
  final Color? color;

  /// 悬停色；不给则悬停只重播描边不换色
  final Color? hoverColor;

  /// 按下时轻微放大（窗口控制灯那类需要"按住了"的手感）
  final bool scaleOnPress;

  final bool enabled;
  final String? semanticLabel;

  @override
  State<StrokeIconButton> createState() => _StrokeIconButtonState();
}

class _StrokeIconButtonState extends State<StrokeIconButton> {
  bool _hovering = false;
  bool _pressed = false;

  bool get _tappable => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final icon = DrawIcon(
      widget.icon,
      size: widget.size,
      // 不传 color 时 DrawIcon 自己按 IconTheme → 语义色兜底；这里只覆盖有值的两档
      color: _hovering
          ? widget.hoverColor ?? iconTheme.color ?? widget.color
          : widget.color,
      trigger: StrokeTrigger.hover,
      semanticLabel: widget.semanticLabel,
    );

    return MouseRegion(
      cursor: _tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _tappable ? (_) => setState(() => _pressed = true) : null,
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: widget.scaleOnPress && _pressed ? 1.1 : 1.0,
          duration: AppMotion.instant,
          curve: Curves.easeOutCubic,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.4,
            child: StrokeZone(
              // 事件源包在里侧：指针只要在按钮范围内按下就重播，
              // 不要求正好压中那 13px 的笔画。
              enabled: _tappable,
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}
