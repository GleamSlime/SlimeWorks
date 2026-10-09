import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/ncm_decrypt_service.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/ncm_decrypt/components/ncm_folder_picker_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class NcmDecryptScreen extends StatefulWidget {
  const NcmDecryptScreen({super.key});

  @override
  State<NcmDecryptScreen> createState() => _NcmDecryptScreenState();
}

class _NcmDecryptScreenState extends State<NcmDecryptScreen> {
  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final service = getIt.get<NcmDecryptService>();

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(m.kSpace24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部操作栏
            _buildActionBar(context, service),
            SizedBox(height: m.kSpace20),
            // 任务队列/进度区域
            _buildTaskArea(context, service),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, NcmDecryptService service) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Obx(() {
      final isDecrypting = service.isDecrypting.value;
      return Row(
        children: [
          ElevatedButton.icon(
            onPressed: isDecrypting ? null : () => _showFolderPickerDialog(context),
            icon: DrawIcon(StrokeIcons.folderOpen, size: m.iconSize18),
            label: const Text('选择文件夹'),
          ),
          if (isDecrypting) ...[
            SizedBox(width: m.kSpace12),
            // 取消属于中止一次进行中的破坏性写入，走 danger 而不是常规线框按钮
            OutlinedButton.icon(
              onPressed: () => service.cancelDecrypt(),
              icon: DrawIcon(StrokeIcons.stop, size: m.iconSize18),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                foregroundColor: s.danger.color,
                side: BorderSide(color: s.danger.color),
              ),
            ),
          ],
          // 统计文字放 Expanded 而不是 Spacer：Spacer 不吸收文字变长的压力，
          // 字号比例拉到 2.0 时这行会被顶破；Expanded + 右对齐结果一样但可截断。
          Expanded(
            child: service.lastResult.value == null
                ? const SizedBox.shrink()
                : Text(
                    '上次: ${service.lastResult.value!.successCount}/${service.lastResult.value!.totalFiles} 成功',
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
    });
  }

  Widget _buildTaskArea(BuildContext context, NcmDecryptService service) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Obx(() {
      final progress = service.progress.value;
      final result = service.lastResult.value;
      final isDecrypting = service.isDecrypting.value;
      final status = progress.status;

      // 空状态
      if (status == NcmDecryptStatus.idle && result == null) {
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: m.kSpace48),
            child: Column(
              children: [
                DrawIcon(
                  StrokeIcons.lockOutline,
                  size: m.iconSize64,
                  color: s.textTertiary.withValues(alpha: 0.31),
                ),
                SizedBox(height: m.kSpace16),
                Text(
                  '选择文件夹开始解密 NCM 文件',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize14,
                    height: 1.7,
                    color: s.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度条
          if (isDecrypting || status == NcmDecryptStatus.completed || status == NcmDecryptStatus.failed)
            _buildProgressBar(context, service, progress),

          // 扫描中提示
          if (status == NcmDecryptStatus.scanning)
            Padding(
              padding: EdgeInsets.symmetric(vertical: m.kSpace16),
              child: Row(
                children: [
                  SizedBox(
                    width: m.iconSize20,
                    height: m.iconSize20,
                    child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular, color: s.accent),
                  ),
                  SizedBox(width: m.kSpace12),
                  Text('正在扫描 NCM 文件...', style: AppTextStyles.body(context)),
                ],
              ),
            ),

          // 解密中详情
          if (status == NcmDecryptStatus.decrypting) ...[
            SizedBox(height: m.kSpace12),
            _buildProgressDetail(context, service, progress),
          ],

          // 结果展示
          if (result != null && !isDecrypting) ...[
            SizedBox(height: m.kSpace20),
            _buildResultCard(context, service, result),
          ],
        ],
      );
    });
  }

  Widget _buildProgressBar(
    BuildContext context,
    NcmDecryptService service,
    NcmDecryptProgressInfo progress,
  ) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final percent = (progress.totalProgress / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: m.radius4,
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: m.kSpace8,
                  backgroundColor: s.accentContainer,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress.status == NcmDecryptStatus.failed
                        ? s.danger.color
                        : progress.status == NcmDecryptStatus.completed
                            ? s.success.color
                            : s.accent,
                  ),
                ),
              ),
            ),
            SizedBox(width: m.kSpace12),
            Text(
              '${progress.totalProgress.toStringAsFixed(1)}%',
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
          ],
        ),
      ],
    );
  }

  Widget _buildProgressDetail(
    BuildContext context,
    NcmDecryptService service,
    NcmDecryptProgressInfo progress,
  ) {
    final m = AppTheme.metrics;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在解密', style: AppTextStyles.cardTitle(context)),
            SizedBox(height: m.kSpace12),
            _buildInfoRow(context, '进度', '${progress.currentFileIndex}/${progress.totalFiles}'),
            if (progress.currentFileName.isNotEmpty)
              _buildInfoRow(context, '当前文件', progress.currentFileName),
            _buildInfoRow(context, '已用时间', service.formatDuration(progress.elapsedSeconds)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    NcmDecryptService service,
    NcmDecryptResultInfo result,
  ) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Card(
      color: result.success
          ? s.success.container
          : result.failedCount > 0
              ? s.warning.container
              : s.danger.container,
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrawIcon(
                  result.success ? StrokeIcons.check : StrokeIcons.warningAmber,
                  color: result.success ? s.success.color : s.warning.color,
                  size: m.iconSize24,
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  result.success ? '解密完成' : '解密完成（部分失败）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize13,
                    height: 1.5,
                    weight: FontWeight.w600,
                    color: result.success ? s.success.color : s.warning.color,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            _buildInfoRow(context, '总文件数', '${result.totalFiles}'),
            _buildInfoRow(context, '成功', '${result.successCount}'),
            if (result.failedCount > 0)
              _buildInfoRow(
                context,
                '失败',
                '${result.failedCount}',
                valueColor: s.danger.color,
              ),
            _buildInfoRow(context, '耗时', service.formatDuration(result.elapsedSeconds)),
            if (result.errorMessage != null)
              _buildInfoRow(
                context,
                '错误',
                result.errorMessage!,
                valueColor: s.danger.color,
              ),
            // 失败文件列表
            if (result.failedFiles.isNotEmpty) ...[
              SizedBox(height: m.kSpace12),
              Text(
                '失败文件:',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  height: 1.6,
                  weight: FontWeight.w600,
                  color: s.textPrimary,
                ),
              ),
              SizedBox(height: m.kSpace4),
              ...result.failedFiles.map(
                (f) => Padding(
                  padding: EdgeInsets.only(left: m.kSpace8, top: m.kSpace2),
                  child: Text(
                    '${f.path}: ${f.reason}',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      height: 1.6,
                      color: s.danger.onContainer,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {Color? valueColor}) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace2),
      child: Row(
        children: [
          // 标签列定宽是为了一列数值对齐；宽度族定宽 + 单行截断，
          // 否则字号比例拉大时这四五个字会把整行顶破。
          SizedBox(
            width: scaleW(80),
            child: Text(
              label,
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
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                height: 1.6,
                weight: FontWeight.w500,
                color: valueColor ?? s.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showFolderPickerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const NcmFolderPickerDialog(),
    );
  }
}
