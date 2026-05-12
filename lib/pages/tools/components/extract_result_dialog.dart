import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';

class ExtractResultDialog extends StatelessWidget {
  final ExtractResultInfo result;

  const ExtractResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final service = getIt.get<ExtractService>();

    final icon = result.success ? Icons.check_circle_outline : Icons.error_outline;
    final iconColor = result.success ? Colors.green : theme.colorScheme.error;
    final title = result.success ? '解压完成' : '解压失败';

    return AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: iconColor, size: m.iconSize24),
          SizedBox(width: m.kSpace12),
          Text(title, style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsCard(context, service),
            if (result.failedArchives.isNotEmpty) ...[
              SizedBox(height: m.kSpace16),
              _buildFailedList(context),
            ],
            if (result.errorMessage != null && !result.success) ...[
              SizedBox(height: m.kSpace16),
              Container(
                padding: EdgeInsets.all(m.kSpace12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withAlpha(50),
                  borderRadius: m.radius8,
                ),
                child: Text(
                  result.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }

  Widget _buildStatsCard(BuildContext context, ExtractService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: m.radius12,
        border: Border.all(color: theme.dividerColor.withAlpha(30)),
      ),
      child: Column(
        children: [
          _buildStatRow(context, '压缩包总数', '${result.totalArchives} 个'),
          SizedBox(height: m.kSpace8),
          _buildStatRow(context, '压缩包总大小', service.formatFileSize(result.totalFileSize)),
          SizedBox(height: m.kSpace8),
          _buildStatRow(context, '解压后大小', service.formatFileSize(result.extractedSize)),
          SizedBox(height: m.kSpace8),
          _buildStatRow(context, '解压耗时', service.formatDuration(result.elapsedSeconds)),
          if (result.failedArchives.isNotEmpty) ...[
            SizedBox(height: m.kSpace8),
            _buildStatRow(
              context,
              '失败数量',
              '${result.failedArchives.length} 个',
              valueColor: theme.colorScheme.error,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value, {Color? valueColor}) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
          decoration: BoxDecoration(
            color: (valueColor ?? theme.colorScheme.primary).withAlpha(15),
            borderRadius: m.radius6,
          ),
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor ?? theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedList(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('失败列表:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: m.kSpace4),
        Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withAlpha(30),
            borderRadius: m.radius8,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: result.failedArchives.length,
            itemBuilder: (_, index) => Padding(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
              child: Text(
                result.failedArchives[index],
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
