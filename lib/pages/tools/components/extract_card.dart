import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/pages/tools/components/extract_params_dialog.dart';
import 'package:slime_works/pages/tools/components/extract_progress_dialog.dart';

class ExtractCard extends StatefulWidget {
  const ExtractCard({super.key});

  @override
  State<ExtractCard> createState() => _ExtractCardState();
}

class _ExtractCardState extends State<ExtractCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      child: InkWell(
        borderRadius: m.radius12,
        onTap: () => _onTap(context),
        child: Container(
          width: 200,
          padding: EdgeInsets.all(m.kSpace16),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              Container(
                width: m.kSpace48,
                height: m.kSpace48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(25),
                  borderRadius: m.radius12,
                ),
                child: Icon(
                  Icons.folder_zip_outlined,
                  color: theme.colorScheme.primary,
                  size: m.iconSize24,
                ),
              ),
              SizedBox(height: m.kSpace12),
              Text('解压工具', style: theme.textTheme.titleMedium),
              SizedBox(height: m.kSpace4),
              Text('批量解压压缩包', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
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