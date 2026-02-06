import 'package:flutter/material.dart';

import 'package:slime_works/components/animations/state_transition_animation.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown_shader.dart';
import 'package:slime_works/core/index.dart';
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
    return GooeyDropdownShader(
        width: scaleW(200),
      button: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: DefaultTextStyle.merge(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Container(
            padding: EdgeInsets.all(AppTheme.metrics.kSpace4),
            child: StateTransitionAnimation(
              label: label,
              textStyle: TextStyle(fontSize: AppTheme.metrics.fontSize14, color: Theme.of(context).textTheme.bodyMedium?.color),
              svg: Assets.image.svg.libraryImport,
              svgSize: AppTheme.metrics.fontSize16,
              loading: loading,
              height: AppTheme.metrics.fontSize34,
              decoration: BoxDecoration(
                borderRadius: AppTheme.metrics.radius8,
                color: Theme.of(context).appBarTheme.backgroundColor,
                border: Border.all(color: Theme.of(context).dividerColor.withAlpha(128)),
              ),
            ),
          ),
        ),
      ),
      content: const _MessageContent(),
      buttonColor: Colors.white,
      cardColor: Colors.white,
      cardSize: Size(100, 120),
      cardOffset: scaleW(30),
      duration: const Duration(milliseconds: 150),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent();

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
      child: Container(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
        decoration: BoxDecoration(color: theme.inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace4,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImportOptionItem(
              icon: Icons.insert_drive_file_outlined,
              label: '从文件导入',
              onTap: () {
                print('从文件导入');
              },
            ),
            _ImportOptionItem(
              icon: Icons.folder_outlined,
              label: '从文件夹导入',
              onTap: () {
                print('从文件夹导入');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportOptionItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImportOptionItem({required this.icon, required this.label, required this.onTap});

  @override
  State<_ImportOptionItem> createState() => _ImportOptionItemState();
}

class _ImportOptionItemState extends State<_ImportOptionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          GooeyDropdownScope.of(context)?.close();
          widget.onTap();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12, vertical: AppTheme.metrics.kSpace10),
          decoration: BoxDecoration(
            color: _isHovered ? Theme.of(context).cardColor : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace10),
            boxShadow: _isHovered ? [BoxShadow(color: Theme.of(context).shadowColor.withAlpha(25), blurRadius: scaleW(4))] : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: AppTheme.metrics.fontSize18, color: Theme.of(context).textTheme.bodyMedium?.color),
              SizedBox(width: AppTheme.metrics.kSpace10),
              Expanded(
                child: Text(
                  widget.label + (_isHovered ? ' (点击)' : '--'),
                  style: TextStyle(
                    fontSize: AppTheme.metrics.fontSize14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    decoration: TextDecoration.none,
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
