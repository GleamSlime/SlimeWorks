import 'package:flutter/material.dart';
import 'package:slime_works/pages/backup/capture_screen/models/recording_task.dart';
import 'package:slime_works/pages/backup/capture_screen/widgets/stat_widgets.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 可录制视频卡片
class AvailableVideoCard extends StatelessWidget {
  final RecordingTask video;
  final VoidCallback onTap;
  final Function(bool?) onSelectChanged;
  final VoidCallback onCopy;

  const AvailableVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.onSelectChanged,
    required this.onCopy,
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
              final isNarrow = constraints.maxWidth < 500;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isNarrow)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(value: video.isSelected, onChanged: onSelectChanged),
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
                            Checkbox(value: video.isSelected, onChanged: onSelectChanged),
                            Expanded(child: _buildThumbnail(context)),
                          ],
                        ),
                        SizedBox(height: AppTheme.metrics.kSpace12),
                      ],
                    ),
                  Expanded(child: _buildVideoInfo(context)),
                  if (!isNarrow) SizedBox(width: AppTheme.metrics.kSpace12),
                  if (!isNarrow)
                    IconButton(
                      icon: Icon(Icons.copy, size: AppTheme.metrics.iconSize20),
                      onPressed: onCopy,
                      tooltip: '复制链接',
                    ),
                  if (isNarrow)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: Icon(Icons.copy, size: AppTheme.metrics.iconSize20),
                        onPressed: onCopy,
                        tooltip: '复制链接',
                      ),
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
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius8,
      child: Container(
        width: 120,
        height: 68,
        color: Theme.of(context).colorScheme.outline,
        child: video.thumbnail.isNotEmpty
            ? Image.network(
                video.thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.videocam, size: AppTheme.metrics.iconSize32);
                },
              )
            : Icon(Icons.videocam, size: AppTheme.metrics.iconSize32),
      ),
    );
  }

  Widget _buildVideoInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          video.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            InfoChip(icon: Icons.aspect_ratio, label: video.resolution, color: Colors.blue),
            InfoChip(
              icon: Icons.speed,
              label: video.frameRate,
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? DarkColors.success
                  : LightColors.success,
            ),
            InfoChip(icon: Icons.signal_cellular_alt, label: video.bitrate, color: Colors.orange),
          ],
        ),
        SizedBox(height: AppTheme.metrics.kSpace8),
        Text(
          video.url,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
