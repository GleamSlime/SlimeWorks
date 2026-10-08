import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/tools/components/extract_result_dialog.dart';

class ExtractProgressDialog extends StatefulWidget {
  const ExtractProgressDialog({super.key});

  @override
  State<ExtractProgressDialog> createState() => _ExtractProgressDialogState();
}

class _ExtractProgressDialogState extends State<ExtractProgressDialog> {
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    final service = getIt.get<ExtractService>();
    _worker = ever(service.isExtracting, (isExtracting) {
      if (!isExtracting && mounted) {
        final result = service.lastResult.value;
        Navigator.of(context).pop();
        if (result != null && mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => ExtractResultDialog(result: result),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final service = getIt.get<ExtractService>();

    return AlertDialog(
      title: Row(
        children: [
          SizedBox(
            width: m.iconSize20,
            height: m.iconSize20,
            child: CircularProgressIndicator(strokeWidth: scaleW(2)),
          ),
          SizedBox(width: m.kSpace12),
          const Text('正在解压'),
        ],
      ),
      content: Obx(() {
        final progress = service.progress.value;
        return SizedBox(
          width: scaleW(420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '总体进度',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  height: 1.6,
                  color: s.textTertiary,
                ),
              ),
              SizedBox(height: m.kSpace4),
              _buildProgressBar(
                context,
                progress.totalProgress,
                '${(progress.totalProgress * 100).toStringAsFixed(1)}%',
              ),
              SizedBox(height: m.kSpace16),

              if (progress.currentArchiveName.isNotEmpty) ...[
                Text(
                  '当前: ${progress.currentArchiveName}',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    height: 1.6,
                    color: s.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: m.kSpace4),
                _buildProgressBar(
                  context,
                  progress.currentArchiveProgress,
                  '${(progress.currentArchiveProgress * 100).toStringAsFixed(1)}%',
                ),
                SizedBox(height: m.kSpace16),
              ],

              _buildStatsRow(context, service, progress),
            ],
          ),
        );
      }),
      actions: [
        TextButton(
          onPressed: () {
            service.cancelExtract();
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context, double value, String label) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: m.radius4,
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: m.kSpace8,
            ),
          ),
        ),
        SizedBox(width: m.kSpace8),
        SizedBox(
          width: m.kSpace48,
          child: Text(
            label,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.6,
              color: s.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    ExtractService service,
    ExtractProgressInfo progress,
  ) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radius8,
        border: Border.all(color: s.hairline),
      ),
      child: Column(
        children: [
          _buildStatItem(
            context,
            '压缩包总数',
            '${progress.currentArchiveIndex}/${progress.totalArchives}',
          ),
          SizedBox(height: m.kSpace4),
          _buildStatItem(context, '文件大小', service.formatFileSize(progress.totalFileSize)),
          SizedBox(height: m.kSpace4),
          _buildStatItem(context, '已用时间', service.formatDuration(progress.elapsedSeconds)),
          SizedBox(height: m.kSpace4),
          _buildStatItem(
            context,
            '预计剩余',
            service.formatDuration(progress.estimatedRemainingSeconds),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            height: 1.6,
            color: s.textTertiary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.6,
              weight: FontWeight.w600,
              color: s.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
