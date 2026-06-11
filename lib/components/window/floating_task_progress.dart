import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 应用边缘悬浮任务进度指示器
///
/// 显示在右下角，有任务时展开，无任务时隐藏
class FloatingTaskProgress extends StatelessWidget {
  const FloatingTaskProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = getIt<TranscriptionTaskQueue>();

    return Obx(() {
      // 访问 .value 确保 Obx 追踪变化
      final completed = queue.completedCount.value;
      final total = queue.totalCount.value;
      final current = queue.currentTask.value;
      final taskList = queue.tasks;
      final hasActive = current != null || completed < total;

      // 无任务时不显示
      if (total == 0) return const SizedBox.shrink();

      // 全部完成且没有失败的也不显示
      final allDone = completed >= total && current == null;
      if (allDone) {
        final hasFailed = taskList.any((t) => t.state.value == TranscriptionTaskState.failed);
        if (!hasFailed) return const SizedBox.shrink();
      }

      final progress = total == 0 ? 0.0 : completed / total;

      return Positioned(
        right: AppTheme.metrics.kSpace16,
        bottom: AppTheme.metrics.kSpace16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace12),
          child: Container(
            width: 280,
            padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace12),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Icon(
                      Icons.record_voice_over_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace6),
                    Expanded(
                      child: Text(
                        hasActive ? '语音识别中...' : '识别完成',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      '$completed/$total',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace2),
                  child: LinearProgressIndicator(
                    value: hasActive ? progress : 1.0,
                    minHeight: 4,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.green,
                    ),
                  ),
                ),
                // 当前任务名称和进度
                if (current != null) ...[
                  SizedBox(height: AppTheme.metrics.kSpace6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          current.displayName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Obx(() {
                        final p = current.progress.value;
                        if (p > 0) {
                          return Text(
                            '${(p * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                  ),
                  // 单任务进度条
                  Obx(() {
                    final p = current.progress.value;
                    if (p > 0) {
                      return Padding(
                        padding: EdgeInsets.only(top: AppTheme.metrics.kSpace4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace2),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 2,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                ],
                // 完成后显示汇总
                if (!hasActive) ...[
                  SizedBox(height: AppTheme.metrics.kSpace6),
                  _buildSummary(context, taskList),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSummary(BuildContext context, List<TranscriptionTask> tasks) {
    final completed = tasks.where((t) => t.state.value == TranscriptionTaskState.completed).length;
    final failed = tasks.where((t) => t.state.value == TranscriptionTaskState.failed).length;

    return Row(
      children: [
        if (completed > 0)
          Text(
            '成功 $completed 首',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.green,
                ),
          ),
        if (completed > 0 && failed > 0)
          SizedBox(width: AppTheme.metrics.kSpace8),
        if (failed > 0)
          Text(
            '失败 $failed 首',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
      ],
    );
  }
}
