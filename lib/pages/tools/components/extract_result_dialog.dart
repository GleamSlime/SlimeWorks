import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/draw_icon.dart';

class ExtractResultDialog extends StatelessWidget {
  final ExtractResultInfo result;

  const ExtractResultDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final service = getIt.get<ExtractService>();

    final icon = result.success ? StrokeIcons.checkCircleOutline : StrokeIcons.errorOutline;
    final iconColor = result.success ? s.success.color : s.danger.color;
    final title = result.success ? '解压完成' : '解压失败';

    return AlertDialog(
      title: Row(
        children: [
          DrawIcon(icon, color: iconColor, size: m.iconSize24),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize15,
                height: 1.5,
                weight: FontWeight.w600,
                color: s.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: scaleW(400),
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
                  color: s.danger.container,
                  borderRadius: m.radius8,
                ),
                child: Text(
                  result.errorMessage!,
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    height: 1.6,
                    color: s.danger.onContainer,
                  ),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radius12,
        border: Border.all(color: s.hairline, width: AppTheme.metrics.strokeHairline),
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
              tone: s.danger,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value, {AppStatusRole? tone}) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize13,
              height: 1.6,
              color: s.textSecondary,
            ),
          ),
        ),
        SizedBox(width: m.kSpace8),
        // 徽章放 Align 而不是裸挂在行尾：非弹性子件拿到的是无限宽约束，
        // 用户字号拉到 2.0 时它不会截断而是把整行顶破。
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
              decoration: BoxDecoration(
                color: tone?.container ?? s.accentContainer,
                borderRadius: m.radius6,
              ),
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize13,
                  height: 1.6,
                  weight: FontWeight.w600,
                  color: tone == null ? s.accentText : tone.onContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedList(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('失败列表:', style: AppTextStyles.cardTitle(context)),
        SizedBox(height: m.kSpace4),
        Container(
          constraints: BoxConstraints(maxHeight: scaleW(120)),
          decoration: BoxDecoration(
            color: s.danger.container,
            borderRadius: m.radius8,
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: result.failedArchives.length,
            itemBuilder: (_, index) => Padding(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
              child: Text(
                result.failedArchives[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  height: 1.6,
                  color: s.danger.onContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
