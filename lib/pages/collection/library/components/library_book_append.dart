import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/animations/state_transition_animation.dart';
import 'package:slime_works/components/dropdown/gooey_dropdown_shader.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/draw_icon.dart';

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
            // 只摘掉下划线这一档，字号/字色仍由下面的 textStyle 与继承链决定
            style: const TextStyle(decoration: TextDecoration.none),
            child: StateTransitionAnimation(
              label: label,
              textStyle: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize13,
                color: AppSemantic.of(context).textSecondary,
                weight: FontWeight.w500,
              ),
              icon: StrokeIcons.assetLibraryImport,
              iconSize: AppTheme.metrics.fontSize15,
              loading: loading,
              height: AppTheme.metrics.kSpace40,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16),
              decoration: BoxDecoration(
                borderRadius: AppTheme.metrics.radius32,
                // 工具条底色由页面自己铺，按钮这一档保持不铺色，免得和磨砂层叠出双层底
                color: Colors.transparent,
              ),
            ),
          ),
        ),
        buttonColor: Colors.transparent,
        cardColor: Colors.transparent,
        content: _MessageContent(viewModel: widget.viewModel),
        buttonRadius: AppTheme.metrics.kSpace32,
        cardOffset: scaleW(30),
        duration: AppMotion.fast,
      );
    });
  }
}

class _MessageContent extends StatelessWidget {
  final NovelLibraryViewModel viewModel;

  const _MessageContent({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);

    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
      child: Container(
        width: scaleW(250),
        padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
        decoration: BoxDecoration(
          color: s.surfaceSunken,
          borderRadius: AppTheme.metrics.radiusControl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.metrics.kSpace4,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImportOptionItem(
              icon: StrokeIcons.insertDriveFile,
              label: '添加单个文件',
              onTap: viewModel.addSingleNovel,
            ),
            const Divider(),
            _ImportOptionItem(
              icon: StrokeIcons.folder,
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
  final StrokeIcon icon;
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
            color: _isHovered ? AppSemantic.of(context).surface : Colors.transparent,
            borderRadius: AppTheme.metrics.radiusCard,
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppSemantic.of(context).shadowKey.withAlpha(25),
                      blurRadius: scaleW(4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              DrawIcon(
                widget.icon,
                size: AppTheme.metrics.fontSize18,
                color: AppSemantic.of(context).textSecondary,
              ),
              SizedBox(width: AppTheme.metrics.kSpace10),
              Expanded(
                child: Text(
                  widget.label,
                  // 继承字族的出口只带颜色/字重，下划线仍要显式关掉
                  style: AppTextStyles.role(
                    context,
                    fontSize: AppTheme.metrics.fontSize13,
                    color: AppSemantic.of(context).textSecondary,
                  ).copyWith(decoration: TextDecoration.none),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
