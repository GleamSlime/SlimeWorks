import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/pages/tools/components/extract_params_dialog.dart';
import 'package:slime_works/pages/tools/components/extract_progress_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class ExtractCard extends StatefulWidget {
  const ExtractCard({super.key});

  @override
  State<ExtractCard> createState() => _ExtractCardState();
}

class _ExtractCardState extends State<ExtractCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => _onTap(context),
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          transform: Matrix4.translationValues(0, _isHovered ? -2.0 : 0, 0),
          width: scaleW(220),
          padding: EdgeInsets.all(m.kSpace20),
          decoration: AppCard.glassDecoration(
            context,
            borderRadius: m.radiusCard,
            borderColor: _isHovered ? s.borderStrong : null,
            lifted: _isHovered,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: scaleW(48),
                height: scaleW(48),
                decoration: BoxDecoration(
                  color: s.accent.withValues(alpha: s.isDark ? 0.18 : 0.12),
                  borderRadius: m.radiusControl,
                ),
                child: Center(
                  child: DrawIcon(
                    StrokeIcons.folderZip,
                    color: s.accent,
                    size: scaleW(24),
                  ),
                ),
              ),
              SizedBox(height: m.kSpace14),
              Text('解压工具', style: AppTextStyles.cardTitle(context)),
              SizedBox(height: m.kSpace4),
              Text('批量多线程解压归档包', style: AppTextStyles.caption(context)),
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) async {
    final service = getIt.get<ExtractService>();

    if (service.isExtracting.value) {
      _showProgressDialog(context);
      return;
    }

    final result = await showDialog<ExtractParams>(
      context: context,
      builder: (_) => const ExtractParamsDialog(),
    );

    if (result == null || !context.mounted) return;

    _showProgressDialog(context);

    service.startExtract(
      sourceDir: result.sourceDir,
      outputDir: result.outputDir,
      outputMode: result.outputMode,
      password: result.password,
      parallelCount: result.parallelCount,
      deleteAfterExtract: result.deleteAfterExtract,
    );
  }

  void _showProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExtractProgressDialog(),
    );
  }
}

class ExtractParams {
  final String sourceDir;
  final String outputDir;
  final ExtractOutputMode outputMode;
  final String? password;
  final int parallelCount;
  final bool deleteAfterExtract;

  const ExtractParams({
    required this.sourceDir,
    required this.outputDir,
    required this.outputMode,
    this.password,
    this.parallelCount = 1,
    this.deleteAfterExtract = false,
  });
}