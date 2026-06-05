import 'dart:io';

import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

/// 音乐列表条目
class MusicListItem extends StatelessWidget {
  final music_api.MusicItem item;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onDeleteTap;

  const MusicListItem({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onFavoriteTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: _buildCover(context),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? Theme.of(context).colorScheme.primary : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [if (item.artist != null) item.artist!, if (item.album != null) item.album!].join(' - '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放指示器
          if (isCurrent && isPlaying)
            SizedBox(
              width: 20,
              height: 20,
              child: _PlayingIndicator(color: Theme.of(context).colorScheme.primary),
            ),
          // 收藏按钮
          IconButton(
            icon: Icon(
              item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 18,
              color: item.isFavorite ? Colors.redAccent : null,
            ),
            onPressed: onFavoriteTap,
          ),
          // 时长
          if (item.durationMs != null)
            Text(
              _formatDuration(item.durationMs!.toInt()),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // 更多操作
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            onSelected: (action) {
              switch (action) {
                case 'delete':
                  onDeleteTap();
                  break;
              }
            },
            itemBuilder: (ctx) => [const PopupMenuItem(value: 'delete', child: Text('删除'))],
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildCover(BuildContext context) {
    const size = 40.0;
    if (item.coverPath != null && File(item.coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace4),
        child: Image.file(
          File(item.coverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildDefaultCover(context, size),
        ),
      );
    }
    return _buildDefaultCover(context, size);
  }

  Widget _buildDefaultCover(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.metrics.kSpace4),
      ),
      child: Icon(Icons.music_note_rounded, size: size * 0.5, color: Theme.of(context).hintColor),
    );
  }

  String _formatDuration(int ms) {
    final sec = ms ~/ 1000;
    final min = sec ~/ 60;
    final s = sec % 60;
    return '${min.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 播放指示器动效（三条跳动的竖线）
class _PlayingIndicator extends StatefulWidget {
  final Color color;
  const _PlayingIndicator({required this.color});

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final height = 6.0 + 8.0 * ((0.5 + 0.5 * (_controller.value * (i + 1) % 1.0)));
            return Container(
              width: 2.5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.25),
              ),
            );
          }),
        );
      },
    );
  }
}
