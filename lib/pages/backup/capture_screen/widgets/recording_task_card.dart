import 'package:flutter/material.dart';
import 'package:slime_works/pages/backup/capture_screen/models/recording_task.dart';
import 'package:slime_works/pages/backup/capture_screen/widgets/stat_widgets.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 录制任务卡片
class RecordingTaskCard extends StatelessWidget {
  final RecordingTask task;
  final VoidCallback? onTap;
  final Function(bool?) onSelectChanged;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback? onReRecord;
  final VoidCallback? onOpenFolder;
  final VoidCallback onDelete;

  const RecordingTaskCard({
    super.key,
    required this.task,
    this.onTap,
    required this.onSelectChanged,
    required this.onEdit,
    required this.onCopy,
    this.onReRecord,
    this.onOpenFolder,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.metrics.radius12,
        child: Padding(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 响应式布局
              final isNarrow = constraints.maxWidth < 500;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isNarrow)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(value: task.isSelected, onChanged: onSelectChanged),
                        SizedBox(width: AppTheme.metrics.kSpace12),
                        _buildThumbnail(context),
                        SizedBox(width: AppTheme.metrics.kSpace16),
                      ],
                    ),
                  if (isNarrow)
                    Column(
                      children: [
                        Row(
                          children: [
                            Checkbox(value: task.isSelected, onChanged: onSelectChanged),
                            Expanded(child: _buildThumbnail(context)),
                          ],
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace12),
                      ],
                    ),
                  Expanded(child: _buildTaskInfo(context)),
                  if (!isNarrow) SizedBox(width: AppTheme.metrics.kSpace12),
                  if (!isNarrow) _buildActions(context),
                  if (isNarrow)
                    Padding(
                      padding: EdgeInsets.only(top: AppTheme.metrics.kSpace8),
                      child: Align(alignment: Alignment.centerRight, child: _buildActions(context)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: AppTheme.metrics.radius8,
          child: Container(
            width: 140,
            height: 79,
            color: Theme.of(context).colorScheme.outline,
            child: task.thumbnail.isNotEmpty
                ? Image.network(
                    task.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.videocam, size: AppTheme.metrics.iconSize32);
                    },
                  )
                : Icon(Icons.videocam, size: AppTheme.metrics.iconSize32),
          ),
        ),
        if (task.status == RecordingStatus.recording)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: Center(
                child: Icon(
                  Icons.fiber_manual_record,
                  color: Theme.of(context).colorScheme.error,
                  size: AppTheme.metrics.iconSize32,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTaskInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: AppTheme.metrics.kSpace8),
            _buildStatusBadge(task.status, context),
          ],
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            InfoChip(icon: Icons.aspect_ratio, label: task.resolution, color: Colors.blue),
            InfoChip(
              icon: Icons.speed,
              label: task.frameRate,
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? DarkColors.success
                  : LightColors.success,
            ),
            InfoChip(icon: Icons.signal_cellular_alt, label: task.bitrate, color: Colors.orange),
          ],
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        if (task.status == RecordingStatus.recording) ...[
          LinearProgressIndicator(
            value: task.progress,
            backgroundColor: Theme.of(context).colorScheme.outline,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          SizedBox(height: AppTheme.metrics.kSpace4),
          Row(
            children: [
              Text(
                '${(task.progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).colorScheme.outline),
              ),
              SizedBox(width: AppTheme.metrics.kSpace12),
              Text(
                task.fileSizeStr,
                style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ],
        if (task.status == RecordingStatus.completed) ...[
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: AppTheme.metrics.iconSize14, color: Theme.of(context).colorScheme.outline),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  Text(
                    '时长: ${task.duration}',
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storage, size: AppTheme.metrics.iconSize14, color: Theme.of(context).colorScheme.outline),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  Text(
                    '大小: ${task.fileSizeStr}',
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ],
        if (task.status == RecordingStatus.error && task.errorMessage != null) ...[
          SizedBox(height: AppTheme.metrics.kSpace4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              borderRadius: AppTheme.metrics.radius4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: AppTheme.metrics.iconSize14, color: Theme.of(context).colorScheme.error),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Expanded(
                  child: Text(
                    task.errorMessage!,
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).colorScheme.error),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: '更多操作',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'copy':
            onCopy();
            break;
          case 'rerecord':
            onReRecord?.call();
            break;
          case 'open':
            onOpenFolder?.call();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [Icon(Icons.edit, size: AppTheme.metrics.iconSize18), SizedBox(width: AppTheme.metrics.kSpace8), const Text('修改名称')]),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(children: [Icon(Icons.copy, size: AppTheme.metrics.iconSize18), SizedBox(width: AppTheme.metrics.kSpace8), const Text('复制链接')]),
        ),
        if (task.status == RecordingStatus.completed)
          PopupMenuItem(
            value: 'open',
            child: Row(
              children: [Icon(Icons.folder_open, size: AppTheme.metrics.iconSize18), SizedBox(width: AppTheme.metrics.kSpace8), const Text('打开文件夹')],
            ),
          ),
        if (task.status == RecordingStatus.completed || task.status == RecordingStatus.error)
          PopupMenuItem(
            value: 'rerecord',
            child: Row(children: [Icon(Icons.refresh, size: AppTheme.metrics.iconSize18), SizedBox(width: AppTheme.metrics.kSpace8), const Text('重新录制')]),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: AppTheme.metrics.iconSize18, color: Theme.of(context).colorScheme.error),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(RecordingStatus status, BuildContext context) {
    Color color;
    IconData icon;
    String text;

    switch (status) {
      case RecordingStatus.idle:
        color = Colors.grey;
        icon = Icons.pending;
        text = '待录制';
        break;
      case RecordingStatus.recording:
        color = Colors.orange;
        icon = Icons.fiber_manual_record;
        text = '录制中';
        break;
      case RecordingStatus.completed:
        color = Colors.green;
        icon = Icons.check_circle;
        text = '已完成';
        break;
      case RecordingStatus.error:
        color = Colors.red;
        icon = Icons.error;
        text = '录制异常';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize14, color: color),
          SizedBox(width: AppTheme.metrics.kSpace4),
          Text(
            text,
            style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
