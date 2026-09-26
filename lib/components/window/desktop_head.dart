import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';

class DesktopHead extends StatelessWidget {
  final Widget child;

  const DesktopHead({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

/// 工具栏圆形图标按钮
///
/// 底色原本取 appBarTheme.backgroundColor，而两套主题里那都是 transparent，
/// 等于这颗按钮从来没有底、悬停也从来没有反馈。
/// 不加投影：工具栏贴在内容区上，一圈阴影只会把行高压出毛边，反馈靠水洗就够。
class DesktopHeadToolsButton extends StatefulWidget {
  final Widget? child;

  final double size;

  final Widget? icon;

  final void Function()? onTap;

  const DesktopHeadToolsButton({super.key, this.child, this.icon, this.onTap, required this.size});

  @override
  State<DesktopHeadToolsButton> createState() => _DesktopHeadToolsButtonState();
}

class _DesktopHeadToolsButtonState extends State<DesktopHeadToolsButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final bg = _pressed
        ? s.surfaceActive
        : _hovering
              ? s.surfaceHover
              : Colors.transparent;

    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size),
            color: bg,
          ),
          child: widget.child ?? widget.icon,
        ),
      ),
    );
  }
}
