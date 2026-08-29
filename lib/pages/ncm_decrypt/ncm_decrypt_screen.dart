import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/services/ncm_decrypt_service.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/pages/ncm_decrypt/components/ncm_folder_picker_dialog.dart';

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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Obx(() {
      final isDecrypting = service.isDecrypting.value;
      return Row(
        children: [
          ElevatedButton.icon(
            onPressed: isDecrypting ? null : () => _showFolderPickerDialog(context),
            icon: Icon(Icons.folder_open, size: m.iconSize18),
            label: const Text('选择文件夹'),
          ),
          if (isDecrypting) ...[
            SizedBox(width: m.kSpace12),
            OutlinedButton.icon(
              onPressed: () => service.cancelDecrypt(),
              icon: Icon(Icons.stop, size: m.iconSize18),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
          const Spacer(),
          if (service.lastResult.value != null)
            Text(
              '上次: ${service.lastResult.value!.successCount}/${service.lastResult.value!.totalFiles} 成功',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
        ],
      );
    });
  }

  Widget _buildTaskArea(BuildContext context, NcmDecryptService service) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

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
                Icon(Icons.lock_outline, size: 64, color: theme.hintColor.withAlpha(80)),
                SizedBox(height: m.kSpace16),
                Text(
                  '选择文件夹开始解密 NCM 文件',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                  ),
                  SizedBox(width: m.kSpace12),
                  Text('正在扫描 NCM 文件...', style: theme.textTheme.bodyMedium),
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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
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
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.primary.withAlpha(30),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress.status == NcmDecryptStatus.failed
                        ? Colors.red
                        : progress.status == NcmDecryptStatus.completed
                            ? Colors.green
                            : theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(width: m.kSpace12),
            Text(
              '${progress.totalProgress.toStringAsFixed(1)}%',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在解密', style: theme.textTheme.titleSmall),
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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return Card(
      color: result.success
          ? Colors.green.withAlpha(10)
          : result.failedCount > 0
              ? Colors.orange.withAlpha(10)
              : Colors.red.withAlpha(10),
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.warning_amber,
                  color: result.success ? Colors.green : Colors.orange,
                  size: m.iconSize24,
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  result.success ? '解密完成' : '解密完成（部分失败）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: result.success ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            _buildInfoRow(context, '总文件数', '${result.totalFiles}'),
            _buildInfoRow(context, '成功', '${result.successCount}'),
            if (result.failedCount > 0)
              _buildInfoRow(context, '失败', '${result.failedCount}', valueColor: Colors.red),
            _buildInfoRow(context, '耗时', service.formatDuration(result.elapsedSeconds)),
            if (result.errorMessage != null)
              _buildInfoRow(context, '错误', result.errorMessage!, valueColor: Colors.red),
            // 失败文件列表
            if (result.failedFiles.isNotEmpty) ...[
              SizedBox(height: m.kSpace12),
              Text('失败文件:', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: m.kSpace4),
              ...result.failedFiles.map(
                (f) => Padding(
                  padding: EdgeInsets.only(left: m.kSpace8, top: m.kSpace2),
                  child: Text(
                    '${f.path}: ${f.reason}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.withAlpha(180)),
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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
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
