import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slime_works/pages/capture_screen/models/recording_task.dart';
import 'package:slime_works/pages/capture_screen/widgets/stat_widgets.dart';

/// 可录制视频卡片
class AvailableVideoCard extends StatelessWidget {
  final RecordingTask video;
  final VoidCallback onTap;
  final Function(bool?) onSelectChanged;
  final VoidCallback onCopy;

  const AvailableVideoCard({super.key, required this.video, required this.onTap, required this.onSelectChanged, required this.onCopy});

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
                            Checkbox(value: video.isSelected, onChanged: onSelectChanged),
                            Expanded(child: _buildThumbnail()),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  Expanded(child: _buildVideoInfo(context)),
                  if (!isNarrow) const SizedBox(width: 12),
                  if (!isNarrow) IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: onCopy, tooltip: '复制链接'),
                  if (isNarrow)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: onCopy, tooltip: '复制链接'),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 120,
        height: 68,
        color: Colors.grey[300],
        child: video.thumbnail.isNotEmpty
            ? Image.network(
                video.thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.videocam, size: 32);
                },
              )
            : const Icon(Icons.videocam, size: 32),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            InfoChip(icon: Icons.aspect_ratio, label: video.resolution, color: Colors.blue),
            InfoChip(icon: Icons.speed, label: video.frameRate, color: Colors.green),
            InfoChip(icon: Icons.signal_cellular_alt, label: video.bitrate, color: Colors.orange),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          video.url,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
