import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryBookCard extends StatefulWidget {
  final NovelMetadata metadata;
  final NovelLibraryViewModel viewModel;

  const LibraryBookCard({super.key, required this.metadata, required this.viewModel});

  @override
  State<LibraryBookCard> createState() => _LibraryBookCardState();
}

class _LibraryBookCardState extends State<LibraryBookCard> {
  bool _hovering = false;

  void _onTap() {
    NovelReaderRoute($extra: widget.metadata).go(context);
    widget.viewModel.loadNovels();
  }

  @override
  Widget build(BuildContext context) {
    print(widget.metadata.progress);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: appMetrics.radius8),
      child: InkWell(
        onTap: _onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[200]),
            child: Stack(
              children: [
                // 封面作为整个卡片背景
                if (widget.metadata.coverPath != null) _buildCoverImage() else _buildDefaultCover(),

                // 格式标签（磨砂玻璃质感）
                Positioned(
                  top: 8,
                  right: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.black.withAlpha(89),
                        child: Text(
                          widget.metadata.format.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 底部磨砂栏：始终底部对齐，hover 时通过高度动画展开显示更多信息
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        height: _hovering ? 120 : 70,
                        color: Colors.black.withAlpha(89),
                        clipBehavior: Clip.none,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 阅读进度条（在底部标题上方显示）
                            if (widget.metadata.progress > 0)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: SizedBox(
                                  height: 4,
                                  child: LinearProgressIndicator(
                                    value: widget.metadata.progress,
                                    backgroundColor: Colors.black.withAlpha(38),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.greenAccent.withAlpha(180),
                                    ),
                                  ),
                                ),
                              ),
                            // 标题和作者靠上排列
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.metadata.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.metadata.author ?? "",
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 额外信息在底部对齐，通过 AnimatedSwitcher 切换，避免占用布局空间
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 360),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeOut,
                                child: KeyedSubtree(
                                  key: UniqueKey(),
                                  child: _hovering
                                      ? Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withAlpha(20),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                widget.metadata.format.toString(),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (widget.metadata.progress > 0)
                                              Text(
                                                '${(widget.metadata.progress * 100).toStringAsFixed(0)}% 阅读',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    try {
      final file = File(widget.metadata.coverPath!);
      if (file.existsSync()) {
        return Positioned.fill(
          child: ClipRect(
            child: AnimatedScale(
              scale: _hovering ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
        );
      }
    } catch (_) {}
    return _buildDefaultCover();
  }

  Widget _buildDefaultCover() {
    return Container(
      color: Colors.grey[300],
      child: const Center(child: Icon(Icons.book, size: 40, color: Colors.white70)),
    );
  }
}
