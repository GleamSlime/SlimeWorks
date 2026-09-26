import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

Widget appBarBackButton(BuildContext context, {VoidCallback? onPressed, String? prevRoutePath}) {
  return IconButton(
    padding: EdgeInsets.zero,
    icon: DrawIcon(StrokeIcons.arrowBackIos),
    onPressed: () {
      if (onPressed != null) {
        return onPressed();
      }

      if (context.canPop()) {
        context.pop();
      } else {
        context.go(prevRoutePath ?? '/');
      }
    },
  );
}
