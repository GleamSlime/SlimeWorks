import 'dart:io';

import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/glass_menu.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

/// 音乐列表条目
class MusicListItem extends StatelessWidget {
  final music_api.MusicItem item;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onDeleteTap;
  final VoidCallback? onTranscribeTap;
  final VoidCallback? onRevealTap;

  const MusicListItem({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onFavoriteTap,
    required this.onDeleteTap,
    this.onTranscribeTap,
    this.onRevealTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return ListTile(
      dense: true,
      leading: _buildCover(context),
      title: Text(
        item.title,
        // 从 AppTextStyles 派生而不是裸 TextStyle：裸构造拿不到字号，
        // dense 行里会按 ListTile 默认的 bodyLarge（16）撑高。
        style: AppTextStyles.rowTitle(context).copyWith(
          color: isCurrent ? s.accent : s.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [if (item.artist != null) item.artist!, if (item.album != null) item.album!].join(' - '),
        style: AppTextStyles.caption(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // CUE 文件标识
          if (item.hasCue)
            Padding(
              padding: EdgeInsets.only(right: m.kSpace4),
              child: Tooltip(
                message: '有 CUE 歌词',
                child: Icon(
                  Icons.subtitles_rounded,
                  size: m.iconSize14,
                  color: s.textTertiary,
                ),
              ),
            ),
          // 播放指示器
          if (isCurrent && isPlaying)
            SizedBox(
              width: m.iconSize20,
              height: m.iconSize20,
              child: _PlayingIndicator(color: s.accent),
            ),
          // 收藏按钮
          IconButton(
            icon: Icon(
              item.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: m.iconSize18,
            ),
            onPressed: onFavoriteTap,
            // 收藏是"选中"而非"危险"，用强调色，和底部播放条上的那颗心一致。
            color: item.isFavorite ? s.accent : s.textTertiary,
          ),
          // 时长
          if (item.durationMs != null)
            Text(
              _formatDuration(item.durationMs!.toInt()),
              style: AppTextStyles.caption(context),
            ),
          // 更多操作
          PopupMenuButton<String>(
            // 行尾三个控件要有主次：菜单按钮是常规操作，压到次级灰，
            // 否则它比收藏那颗心还抢眼（golden 里实测就是反过来的）。
            icon: Icon(
              Icons.more_vert_rounded,
              size: AppTheme.metrics.iconSize18,
              color: s.textSecondary,
            ),
            onSelected: (action) {
              switch (action) {
                case 'delete':
                  onDeleteTap();
                  break;
                case 'transcribe':
                  onTranscribeTap?.call();
                  break;
                case 'reveal':
                  onRevealTap?.call();
                  break;
              }
            },
            itemBuilder: (ctx) {
              final items = <PopupMenuEntry<String>>[
                GlassMenuItem(
                  value: 'transcribe',
                  label: '语音识别',
                  icon: Icons.graphic_eq_rounded,
                ),
              ];
              // 仅本地文件可「在资源管理器打开」
              final isLocal = !item.filePath.startsWith('http') && File(item.filePath).existsSync();
              if (isLocal) {
                items.add(
                  GlassMenuItem(
                    value: 'reveal',
                    label: '在资源管理器打开',
                    icon: Icons.folder_open_rounded,
                  ),
                );
              }
              // 删除是这条菜单里唯一的不可逆操作，单独染成危险色，不靠位置区分。
              items.add(
                GlassMenuItem(
                  value: 'delete',
                  label: '删除',
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                ),
              );
              return items;
            },
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildCover(BuildContext context) {
    final size = scaleW(40);
    final radius = AppTheme.metrics.radius4;
    if (item.coverPath != null && File(item.coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          File(item.coverPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildDefaultCover(context, size),
        ),
      );
    }
    return _buildDefaultCover(context, size);
  }

  Widget _buildDefaultCover(BuildContext context, double size) {
    final s = AppSemantic.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 占位底要"凹下去"：surfaceContainerHighest 在亮色下就是白，
        // 白色列表行里的这块占位等于凭空消失。
        color: s.surfaceSunken,
        borderRadius: AppTheme.metrics.radius4,
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.5,
        color: s.textTertiary,
      ),
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
            final height =
                scaleW(6) + scaleW(8) * ((0.5 + 0.5 * (_controller.value * (i + 1) % 1.0)));
            return Container(
              width: scaleW(2.5),
              height: height,
              margin: EdgeInsets.symmetric(horizontal: scaleW(1)),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(scaleW(1.25)),
              ),
            );
          }),
        );
      },
    );
  }
}
