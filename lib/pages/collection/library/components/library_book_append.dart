import 'package:flutter/material.dart';
import 'package:slime_works/components/buttons/animated_button.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/gen/assets.gen.dart';

class LibraryBookAppendButton extends StatefulWidget {
  final void Function()? onTap;

  const LibraryBookAppendButton({super.key, this.onTap});

  @override
  State<LibraryBookAppendButton> createState() => _LibraryBookAppendButtonState();
}

class _LibraryBookAppendButtonState extends State<LibraryBookAppendButton> {
  String label = "导入";

  bool loading = false;

  void handleTap() async {
    setState(() {
      label = '导入中...';
      loading = true;
    });
    await Future.delayed(const Duration(seconds: 10));
    setState(() {
      label = "导入完毕";
      loading = false;
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      label = "导入";
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedButton(
      onTap: widget.onTap ?? handleTap,
      label: label,
      svg: Assets.image.svg.libraryImport,
      svgSize: AppTheme.metrics.fontSize12,
      loading: loading,
      decoration: BoxDecoration(
        borderRadius: AppTheme.metrics.radius8,
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(50)),
      ),
    );
  }
}
