import 'package:flutter/material.dart';
import 'package:slime_works/pages/capture_screen/models/recording_task.dart';
import 'package:slime_works/pages/capture_screen/widgets/stat_widgets.dart';

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
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                        const SizedBox(width: 12),
                        _buildThumbnail(),
                        const SizedBox(width: 16),
                      ],
                    ),
                  if (isNarrow)
                    Column(
                      children: [
                        Row(
                          children: [
                            Checkbox(value: task.isSelected, onChanged: onSelectChanged),
                            Expanded(child: _buildThumbnail()),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  Expanded(child: _buildTaskInfo(context)),
                  if (!isNarrow) const SizedBox(width: 12),
                  if (!isNarrow) _buildActions(context),
                  if (isNarrow)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
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

  Widget _buildThumbnail() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 140,
            height: 79,
            color: Colors.grey[300],
            child: task.thumbnail.isNotEmpty
                ? Image.network(
                    task.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.videocam, size: 32);
                    },
                  )
                : const Icon(Icons.videocam, size: 32),
          ),
        ),
        if (task.status == RecordingStatus.recording)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Center(child: Icon(Icons.fiber_manual_record, color: Colors.red, size: 32)),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(task.status),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            InfoChip(icon: Icons.aspect_ratio, label: task.resolution, color: Colors.blue),
            InfoChip(icon: Icons.speed, label: task.frameRate, color: Colors.green),
            InfoChip(icon: Icons.signal_cellular_alt, label: task.bitrate, color: Colors.orange),
          ],
        ),
        const SizedBox(height: 8),
        if (task.status == RecordingStatus.recording) ...[
          LinearProgressIndicator(
            value: task.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${(task.progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(width: 12),
              Text(task.fileSizeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('时长: ${task.duration}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('大小: ${task.fileSizeStr}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ],
        if (task.status == RecordingStatus.error && task.errorMessage != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 14, color: Colors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.errorMessage!,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
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
        const PopupMenuItem(
          value: 'edit',
          child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('修改名称')]),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('复制链接')]),
        ),
        if (task.status == RecordingStatus.completed)
          const PopupMenuItem(
            value: 'open',
            child: Row(children: [Icon(Icons.folder_open, size: 18), SizedBox(width: 8), Text('打开文件夹')]),
          ),
        if (task.status == RecordingStatus.completed || task.status == RecordingStatus.error)
          const PopupMenuItem(
            value: 'rerecord',
            child: Row(children: [Icon(Icons.refresh, size: 18), SizedBox(width: 8), Text('重新录制')]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(RecordingStatus status) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
