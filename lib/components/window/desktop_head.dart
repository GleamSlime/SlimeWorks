import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class DesktopHead extends StatelessWidget {
  final Widget child;

  const DesktopHead({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

class DesktopHeadToolsButton extends StatelessWidget {
  final Widget? child;

  final double size;

  final Widget? icon;

  final void Function()? onTap;

  const DesktopHeadToolsButton({super.key, this.child, this.icon, this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size / 4),
          color: theme.appBarTheme.backgroundColor,
          border: Border.all(color: theme.dividerColor.withAlpha(50)),
          // boxShadow: [BoxShadow(color: theme.shadowColor.withAlpha(25), blurRadius: scaleW(5))],
        ),
        child: child ?? icon,
      ),
    );
  }
}
