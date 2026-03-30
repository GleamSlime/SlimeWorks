import 'dart:io';

import 'package:flutter/gestures.dart';
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

  /// 触摸板/手指滑动累计偏移量：超过阈值才触发翻页，避免误触
  double _scrollAccum = 0.0;

  /// 每次翻页后的冷却，防止连续多次触发
  static const double _kScrollThreshold = 60.0;

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

  /// 处理触摸板/鼠标滚轮事件。
  /// - 鼠标滚轮（scrollDelta.dy 较大、单次离散事件）：立即翻页
  /// - 触摸板（scrollDelta.dy 较小、连续事件）：累积偏移超阈值才翻页
  void _handlePointerScroll(PointerScrollEvent event) {
    final dy = event.scrollDelta.dy;
    final absDy = dy.abs();

    // 鼠标滚轮单次偏移通常 >= 100，直接翻页
    if (absDy >= 100) {
      _scrollAccum = 0;
      if (dy > 0) {
        _jump(1);
      } else {
        _jump(-1);
      }
      return;
    }

    // 触摸板：累积偏移
    _scrollAccum += dy;
    if (_scrollAccum.abs() >= _kScrollThreshold) {
      final direction = _scrollAccum > 0 ? 1 : -1;
      _scrollAccum = 0;
      _jump(direction);
    }
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
        child: Column(
          children: [
            // 导航条：紧贴内容顶部，不遮挡播放器控制栏
            ColoredBox(
              color: Colors.black87,
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    if (_currentIndex > 0)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _jump(-1),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                        label: const Text('上一项'),
                      ),
                    const Spacer(),
                    if (_currentIndex < widget.items.length - 1)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _jump(1),
                        icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                        label: const Text('下一项'),
                      ),
                  ],
                ),
              ),
            ),
            // 内容区：支持鼠标滚轮（含触摸板累积阈值）+ 移动端/触控板手势上下滑动翻页
            Expanded(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _handlePointerScroll(event);
                  }
                },
                child: GestureDetector(
                  // 竖向拖动手势：累积偏移超阈值才翻页（适配移动端手指滑动）
                  onVerticalDragUpdate: (details) {
                    _scrollAccum -= details.delta.dy;
                    if (_scrollAccum.abs() >= _kScrollThreshold) {
                      final direction = _scrollAccum > 0 ? 1 : -1;
                      _scrollAccum = 0;
                      _jump(direction);
                    }
                  },
                  onVerticalDragEnd: (_) {
                    _scrollAccum = 0;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    // 禁用 PageView 自身物理效果，改由上层 GestureDetector 统一处理
                    physics: const NeverScrollableScrollPhysics(),
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
                ),
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
    return Video(controller: controller);
  }
}
