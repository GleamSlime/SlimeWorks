import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Widget appBarBackButton(BuildContext context, {VoidCallback? onPressed, String? prevRoutePath}) {
  return IconButton(
    padding: EdgeInsets.zero,
    icon: const Icon(Icons.arrow_back_ios_rounded),
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
