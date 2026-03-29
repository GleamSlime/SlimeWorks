import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';

class MediaViewerPage extends StatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.collectionId,
    required this.viewModel,
  });

  final List<media_api.MediaItem> items;
  final int initialIndex;
  final String collectionId;
  final MediaLibraryViewModel viewModel;

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  void _jump(int delta) {
    final nextIndex = (_currentIndex + delta).clamp(0, widget.items.length - 1);
    if (nextIndex == _currentIndex) {
      return;
    }
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: appMetrics.kSpace16),
            child: Center(
              child: Text(
                '${_currentIndex + 1}/${widget.items.length}',
                style: TextStyle(fontSize: appMetrics.fontSize14),
              ),
            ),
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _jump(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _jump(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: widget.items.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final currentItem = widget.items[index];
                final source = widget.viewModel.buildMediaSource(
                  currentItem,
                  collectionId: widget.collectionId,
                );
                if (currentItem.kind == media_api.MediaKind.video) {
                  return _VideoPreview(source: source);
                }
                if (source == null || source.isEmpty) {
                  return const Center(
                    child: Text('无法加载图片', style: TextStyle(color: Colors.white)),
                  );
                }
                final child = source.startsWith('http')
                    ? Image.network(source, fit: BoxFit.contain)
                    : Image.file(File(source), fit: BoxFit.contain);
                return InteractiveViewer(child: Center(child: child));
              },
            ),
            if (_currentIndex > 0)
              Positioned(
                left: appMetrics.kSpace16,
                bottom: appMetrics.kSpace24,
                child: FilledButton.icon(
                  onPressed: () => _jump(-1),
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('上一项'),
                ),
              ),
            if (_currentIndex < widget.items.length - 1)
              Positioned(
                right: appMetrics.kSpace16,
                bottom: appMetrics.kSpace24,
                child: FilledButton.icon(
                  onPressed: () => _jump(1),
                  icon: const Icon(Icons.arrow_downward),
                  label: const Text('下一项'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.source});

  final String? source;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    if (source == null || source.isEmpty) return;
    _player = Player();
    _videoController = VideoController(_player!);
    final uri = source.startsWith('http') ? source : Uri.file(source).toString();
    _player!.open(Media(uri));
    _player!.setPlaylistMode(PlaylistMode.loop);
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final controller = _videoController;
    if (player == null || controller == null) {
      return const Center(
        child: Text('无法加载视频', style: TextStyle(color: Colors.white)),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Video(controller: controller),
        Positioned(
          bottom: appMetrics.kSpace24,
          child: StreamBuilder<bool>(
            stream: player.stream.playing,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;
              return IconButton.filled(
                onPressed: () {
                  if (isPlaying) {
                    player.pause();
                  } else {
                    player.play();
                  }
                },
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              );
            },
          ),
        ),
      ],
    );
  }
}
