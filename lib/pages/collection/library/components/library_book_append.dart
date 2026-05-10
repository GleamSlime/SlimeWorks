import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/animations/state_transition_animation.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown_shader.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryBookAppendButton extends StatefulWidget {
  final void Function()? onTap;
  final NovelLibraryViewModel viewModel;

  const LibraryBookAppendButton({super.key, this.onTap, required this.viewModel});

  @override
  State<LibraryBookAppendButton> createState() => _LibraryBookAppendButtonState();
}

class _LibraryBookAppendButtonState extends State<LibraryBookAppendButton> {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final loading = widget.viewModel.isScanning.value;
      final status = widget.viewModel.scanStatusText.value;
      final progress = widget.viewModel.scanProgressText.value;
      final label = loading
          ? (progress.isEmpty ? (status.isEmpty ? '扫描中...' : status) : '${status.isEmpty ? '扫描中' : status} $progress')
          : '导入';

      return GooeyDropdownShader(
        button: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: DefaultTextStyle.merge(
            style: const TextStyle(decoration: TextDecoration.none),
            child: StateTransitionAnimation(
              label: label,
              textStyle: TextStyle(
                fontSize: AppTheme.metrics.fontSize13,
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: FontWeight.w500,
              ),
              svg: Assets.image.svg.libraryImport,
              svgSize: AppTheme.metrics.fontSize15,
              loading: loading,
              height: AppTheme.metrics.kSpace40,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16),
              decoration: BoxDecoration(
                borderRadius: AppTheme.metrics.radius32,
                color: Theme.of(context).appBarTheme.backgroundColor,
              ),
            ),
          ),
        ),
        buttonColor: Theme.of(context).appBarTheme.backgroundColor!,
        cardColor: Theme.of(context).appBarTheme.backgroundColor!,
        content: _MessageContent(viewModel: widget.viewModel),
        buttonRadius: AppTheme.metrics.kSpace32,
        cardOffset: scaleW(30),
        duration: const Duration(milliseconds: 150),
      );
    });
  }
}

class _MessageContent extends StatelessWidget {
  final NovelLibraryViewModel viewModel;

  const _MessageContent({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
      child: Container(
        width: scaleW(250),
        padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
        decoration: BoxDecoration(
          color: theme.inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace4,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImportOptionItem(
              icon: Icons.insert_drive_file_outlined,
              label: '添加单个文件',
              onTap: viewModel.addSingleNovel,
            ),
            const Divider(),
            _ImportOptionItem(
              icon: Icons.folder_outlined,
              label: '扫描文件夹',
              onTap: viewModel.scanFolder,
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
  final Future<void> Function() onTap;

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
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) async {
          GooeyDropdownScope.of(context)?.close();
          await widget.onTap();
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace12,
            vertical: AppTheme.metrics.kSpace10,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? Theme.of(context).colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace10),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Theme.of(context).shadowColor.withAlpha(25),
                      blurRadius: scaleW(4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: AppTheme.metrics.fontSize18,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              SizedBox(width: AppTheme.metrics.kSpace10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: AppTheme.metrics.fontSize13,
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
