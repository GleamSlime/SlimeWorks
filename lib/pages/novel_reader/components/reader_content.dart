import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'dart:convert';
import 'dart:io';

/// 阅读内容区域组件
class ReaderContent extends StatefulWidget {
  final NovelReaderViewModel controller;

  const ReaderContent({super.key, required this.controller});

  @override
  State<ReaderContent> createState() => _ReaderContentState();
}

class _ReaderContentState extends State<ReaderContent> {
  late final ScrollController _scrollController;
  bool _showPlainTextMode = false;
  int _lastChapterIndex = -1;
  final GlobalKey _searchTargetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // (调试临时代码已移除) 保持默认不强制纯文本，允许 HTML 渲染分支输出调试信息

    // 监听搜索结果滚动触发
    ever(widget.controller.searchScrollTrigger, (_) {
      // 调试日志：记录搜索触发时的匹配数量与当前选中索引
      try {
        final matchCount = widget.controller.searchMatches.length;
        final sel = widget.controller.selectedSearchIndex.value;
        debugPrint('[Reader] searchScrollTrigger fired: matches=$matchCount selectedIndex=$sel');
      } catch (e) {
        debugPrint('[Reader] searchScrollTrigger log error: $e');
      }
      _scrollToCurrentSearchResult();
    });

    // 当选中搜索索引变化时强制重建以确保高亮更新（某些 .isNotEmpty 访问可能未触发 Obx 重建）
    ever(widget.controller.selectedSearchIndex, (_) {
      try {
        debugPrint(
          '[Reader] selectedSearchIndex changed: ${widget.controller.selectedSearchIndex.value}',
        );
      } catch (e) {}
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && mounted) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  // 滚动到搜索结果位置
  void _scrollToSearchResult(int position) {
    debugPrint('[Reader] _scrollToSearchResult: position=$position, using ensureVisible');

    // 使用 GlobalKey + ensureVisible，避免手动计算offset
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final context = _searchTargetKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.25, // 将目标显示在屏幕上方25%的位置
          );
          debugPrint('[Reader] Scrolled to search target using ensureVisible');
        } else {
          debugPrint('[Reader] Search target key context is null, falling back to estimation');
          // 如果Key找不到context，回退到简单估算
          _scrollToSearchResultFallback(position);
        }
      } catch (e) {
        debugPrint('[Reader] ensureVisible error: $e, fallback to estimation');
        _scrollToSearchResultFallback(position);
      }
    });
  }

  // 备用滚动方法：简单估算
  void _scrollToSearchResultFallback(int position) {
    if (!mounted || !_scrollController.hasClients) return;

    final controller = widget.controller;
    final fontSize = controller.fontSize.value;
    final lineHeight = fontSize * 1.8;
    final charsPerLine = (MediaQuery.of(context).size.width - 96) / fontSize;
    final estimatedLine = position / charsPerLine;
    final estimatedOffset = estimatedLine * lineHeight;
    final targetOffset = (estimatedOffset - lineHeight * 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // 滚动到当前选中的搜索结果
  void _scrollToCurrentSearchResult() {
    final controller = widget.controller;
    if (controller.searchMatches.isEmpty || controller.selectedSearchIndex.value < 0) return;

    final selectedMatch = controller.searchMatches[controller.selectedSearchIndex.value];
    final currentChapterIndex = controller.currentChapterIndex.value;

    // 只有当搜索结果在当前章节时才滚动
    if (selectedMatch.chapterIndex.toInt() == currentChapterIndex) {
      _scrollToSearchResult(selectedMatch.position.toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Obx(() {
      final buildStart = DateTime.now();
      debugPrint('[Novel UI] ReaderContent build started');

      final currentContent = controller.currentContent.value;

      if (currentContent.isEmpty) {
        debugPrint('[Novel UI] Content is empty');
        return const Center(
          child: Text('暂无内容', style: TextStyle(color: Colors.grey)),
        );
      }

      debugPrint('[Novel UI] Building content view, length: ${currentContent.length} chars');

      // 调试日志：输出 content 中是否包含 class 与 img 引用，便于定位样式和图片问题
      try {
        final previewLen = currentContent.length > 300 ? 300 : currentContent.length;
        debugPrint('[Novel UI] content preview: ${currentContent.substring(0, previewLen)}');
        if (currentContent.contains('class="') || currentContent.contains("class='")) {
          debugPrint('[Novel UI] content contains class attributes');
        }
        final imgReg = RegExp(r'''<img[^>]*src=["']([^"']+)["']''', caseSensitive: false);
        final imgs = imgReg
            .allMatches(currentContent)
            .map((m) => m.group(1))
            .whereType<String>()
            .toList();
        if (imgs.isNotEmpty) {
          debugPrint('[Novel UI] Found image srcs: ${imgs.join(', ')}');
        }
      } catch (e) {
        debugPrint('[Novel UI] content debug error: $e');
      }

      // 是否包含 HTML 标签或图片（用于决定默认使用 HTML 渲染或允许切换为纯文本）
      final containsHtmlTags = RegExp(
        r'<\s*(p|br|div|span|img|style|h[1-6])\b',
        caseSensitive: false,
      ).hasMatch(currentContent);
      final hasImages = currentContent.contains('<img');
      final shouldRenderHtml = containsHtmlTags || hasImages;

      // 仅在章节变化时滚动到顶部（避免每次 rebuild 都滚动）
      final currentIndex = controller.currentChapterIndex.value;
      if (currentIndex != _lastChapterIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTop();
        });
        _lastChapterIndex = currentIndex;
      }

      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.all(isNarrow ? 16 : 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 章节标题
              if (controller.chapters.isNotEmpty)
                Container(
                  padding: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.chapters[controller.currentChapterIndex.value].title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '第 ${controller.currentChapterIndex.value + 1} / ${controller.chapters.length} 章',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '本章 ${currentContent.length} 字',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '进度 ${((controller.currentChapterIndex.value + 1) * 100 / controller.chapters.length).toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // 如果内容包含 HTML 图片，允许切换为纯文本模式以便选择复制文本
              if (hasImages)
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showPlainTextMode = !_showPlainTextMode;
                        });
                      },
                      icon: Icon(_showPlainTextMode ? Icons.visibility : Icons.code),
                      label: Text(_showPlainTextMode ? '显示 HTML 视图' : '显示纯文本（可选择）'),
                    ),
                    if (kDebugMode) const SizedBox(width: 8),
                    if (kDebugMode)
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showPlainTextMode = true;
                          });
                          debugPrint('[Reader][PlainDebug] forced plain mode by debug button');
                        },
                        icon: const Icon(Icons.bug_report),
                        label: const Text('强制纯文本'),
                      ),
                  ],
                ),

              // 正文内容（支持搜索高亮）
              Builder(
                builder: (context) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final duration = DateTime.now().difference(buildStart);
                    debugPrint(
                      '[Novel UI] ReaderContent fully rendered in ${duration.inMilliseconds}ms',
                    );

                    // 如果有选中的搜索结果，滚动到该位置
                    if (controller.selectedSearchIndex.value >= 0 &&
                        controller.searchMatches.isNotEmpty) {
                      final match = controller.searchMatches[controller.selectedSearchIndex.value];
                      if (match.chapterIndex.toInt() == controller.currentChapterIndex.value) {
                        _scrollToSearchResult(match.position.toInt());
                      }
                    }
                  });

                  // 检查是否有搜索关键词需要高亮
                  final hasSearch = controller.searchMatches.isNotEmpty;
                  // 调试：记录 searchMatches 长度与当前章节索引，方便定位高亮是否会被执行
                  try {
                    debugPrint(
                      '[Reader] build: hasSearch=$hasSearch searchMatches=${controller.searchMatches.length} currentChapter=${controller.currentChapterIndex.value} selectedIndex=${controller.selectedSearchIndex.value}',
                    );
                    if (controller.searchMatches.isNotEmpty) {
                      final first = controller.searchMatches.first;
                      debugPrint(
                        '[Reader] build: firstMatch chapterIndex=${first.chapterIndex} position=${first.position} snippet="${first.snippet}"',
                      );
                    }
                  } catch (e) {
                    debugPrint('[Reader] build log error: $e');
                  }

                  // 检查是否包含图片标签（epub内容）
                  // final hasImages 已在外部计算

                  // 如果内容包含 HTML（或图片），使用 HTML 渲染（优先级最高）
                  if (shouldRenderHtml) {
                    debugPrint(
                      '[Reader] Rendering HTML content (containsHtml=$containsHtmlTags, hasImages=$hasImages)',
                    );

                    // 检查是否有缓存的已处理HTML
                    final currentChapterIdx = controller.currentChapterIndex.value;
                    String? cachedHtml = controller.getCachedHtml(currentChapterIdx);
                    String embeddedHtml;

                    if (cachedHtml != null && !hasSearch) {
                      // 使用缓存（仅在无搜索时使用缓存）
                      embeddedHtml = cachedHtml;
                      debugPrint('[Reader] Using cached HTML for chapter $currentChapterIdx');
                    } else {
                      // 处理HTML
                      final htmlProcessStart = DateTime.now();
                      String htmlData = currentContent;

                      if (hasSearch && controller.searchMatches.isNotEmpty) {
                        final chapterMatches = controller.searchMatches
                            .where(
                              (m) => m.chapterIndex.toInt() == controller.currentChapterIndex.value,
                            )
                            .toList();
                        if (chapterMatches.isNotEmpty) {
                          // 若当前有选中的搜索结果并且在本章节，计算它是本章节中第几个匹配
                          int? selectedOccurrence;
                          if (controller.selectedSearchIndex.value >= 0 &&
                              controller.selectedSearchIndex.value <
                                  controller.searchMatches.length) {
                            final sel =
                                controller.searchMatches[controller.selectedSearchIndex.value];
                            if (sel.chapterIndex.toInt() == controller.currentChapterIndex.value) {
                              // 计算选中的是本章节的第几个匹配（从0开始）
                              int occurrenceInChapter = 0;
                              for (int i = 0; i < controller.selectedSearchIndex.value; i++) {
                                if (controller.searchMatches[i].chapterIndex.toInt() ==
                                    controller.currentChapterIndex.value) {
                                  occurrenceInChapter++;
                                }
                              }
                              selectedOccurrence = occurrenceInChapter;
                            }
                          }
                          // 优先使用用户原始搜索词，若为空则回退到 snippet
                          final keyword = controller.lastSearchQuery.value.trim().isNotEmpty
                              ? controller.lastSearchQuery.value.trim()
                              : chapterMatches.first.snippet.trim();
                          debugPrint(
                            '[Reader] Preparing HTML highlight: keyword="$keyword" selectedOccurrence=$selectedOccurrence chapterMatches=${chapterMatches.length}',
                          );
                          htmlData = _highlightHtml(
                            htmlData,
                            keyword,
                            selectedOccurrence: selectedOccurrence,
                          );
                        }
                      }
                      // 将本地 file:// 图片替换为 base64 data URL，以避免依赖 flutter_html 的不同版本自定义图片 API
                      embeddedHtml = _embedLocalImages(htmlData);

                      // 如果 HTML 中没有段落/换行/div 标签，说明内容可能是带换行的纯文本。
                      // 把连续空行转换为段落 (<p>..</p>)，并把单个换行转换为 <br/> ，以便 flutter_html 正确渲染段落。
                      final hasParagraphLike = RegExp(
                        r'<\s*(p|br|div)\b',
                        caseSensitive: false,
                      ).hasMatch(embeddedHtml);
                      if (!hasParagraphLike) {
                        try {
                          String t = embeddedHtml.trim();
                          // 将多个连续空行作为段落分隔
                          t = t.replaceAll(RegExp(r'\r?\n\s*\r?\n+'), '</p><p>');
                          // 将剩余单个换行转为 <br/>
                          t = t.replaceAll(RegExp(r'\r?\n'), '<br/>');
                          embeddedHtml = '<p>$t</p>';
                          debugPrint(
                            '[Reader][HTMLTransform] converted plain newlines to <p>/<br/>',
                          );
                        } catch (e) {
                          debugPrint('[Reader][HTMLTransform] failed: $e');
                        }
                      }

                      final htmlProcessDuration = DateTime.now()
                          .difference(htmlProcessStart)
                          .inMilliseconds;
                      debugPrint('[Reader] HTML processing took ${htmlProcessDuration}ms');

                      // 缓存处理后的HTML（仅在无搜索时缓存）
                      if (!hasSearch) {
                        controller.cacheHtml(currentChapterIdx, embeddedHtml);
                      }
                    }

                    debugPrint(
                      '[Reader] Embedded HTML length=${embeddedHtml.length} contains_mark_selected=${embeddedHtml.contains("<mark_selected>")}',
                    );
                    // 提供“纯文本模式”切换：如果用户需要选择/复制文本，可切换为纯文本视图（丢失部分 HTML 格式）
                    if (_showPlainTextMode) {
                      String plain = embeddedHtml;

                      // 将常见的块级或换行标签替换为换行符，保留段落分隔
                      plain = plain.replaceAll(
                        RegExp(r'</p>|<br\s*/?>|</div>|</h[1-6]>', caseSensitive: false),
                        '\n\n',
                      );
                      plain = plain.replaceAll(
                        RegExp(r'<p[^>]*>|<div[^>]*>|<h[1-6][^>]*>', caseSensitive: false),
                        '\n\n',
                      );

                      // 移除剩余的 HTML 标签
                      plain = plain.replaceAll(RegExp(r'<[^>]+>'), '');

                      // 解码常见 HTML 实体（简单实现）
                      plain = plain.replaceAll('&nbsp;', ' ');
                      plain = plain.replaceAll('&amp;', '&');
                      plain = plain.replaceAll('&lt;', '<');
                      plain = plain.replaceAll('&gt;', '>');
                      plain = plain.replaceAll('&quot;', '"');
                      plain = plain.replaceAll('&apos;', "'");

                      // 解码数字实体，如 &#1234; 或 &#x1F60A;
                      plain = plain.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
                        try {
                          final code = int.parse(m[1]!);
                          return String.fromCharCode(code);
                        } catch (_) {
                          return '';
                        }
                      });
                      plain = plain.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
                        try {
                          final code = int.parse(m[1]!, radix: 16);
                          return String.fromCharCode(code);
                        } catch (_) {
                          return '';
                        }
                      });

                      // 合并连续的空白行并修剪首尾
                      plain = plain.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

                      // 调试输出：记录纯文本长度、是否包含换行，以及前 400 字符样例
                      try {
                        debugPrint(
                          '[Reader][PlainDebug] length=${plain.length} containsNewline=${plain.contains('\n')}',
                        );
                        debugPrint(
                          '[Reader][PlainDebug] sample=${plain.substring(0, plain.length.clamp(0, 400))}',
                        );
                      } catch (e) {
                        debugPrint('[Reader][PlainDebug] debug print failed: $e');
                      }

                      // 在纯文本模式下复用高亮构建逻辑
                      return _buildHighlightedText(plain, context);
                    }

                    // Debug: 统计嵌入 HTML 中的段落/换行标签数量，帮助定位为何没有换行
                    try {
                      final pOpen = RegExp(
                        r'<p\b',
                        caseSensitive: false,
                      ).allMatches(embeddedHtml).length;
                      final pClose = RegExp(
                        r'</p>',
                        caseSensitive: false,
                      ).allMatches(embeddedHtml).length;
                      final brs = RegExp(
                        r'<br\b',
                        caseSensitive: false,
                      ).allMatches(embeddedHtml).length;
                      final divs = RegExp(
                        r'<div\b',
                        caseSensitive: false,
                      ).allMatches(embeddedHtml).length;
                      debugPrint(
                        '[Reader][HTMLDebug] tags: pOpen=$pOpen pClose=$pClose brs=$brs divs=$divs',
                      );
                      debugPrint(
                        '[Reader][HTMLDebug] sample=${embeddedHtml.substring(0, embeddedHtml.length.clamp(0, 800))}',
                      );
                    } catch (e) {
                      debugPrint('[Reader][HTMLDebug] failed to analyze embeddedHtml: $e');
                    }

                    return SelectionArea(
                      child: Html(
                        data: embeddedHtml,
                        onLinkTap: (url, _, _) {
                          if (url == null) return;
                          try {
                            final uri = Uri.tryParse(url);
                            final path = uri?.path ?? url;
                            final basename =
                                path.split('/').where((s) => s.isNotEmpty).toList().isNotEmpty
                                ? path.split('/').last
                                : path;
                            final target = controller.chapters.indexWhere(
                              (c) =>
                                  c.id.endsWith(basename) ||
                                  c.id.contains(basename) ||
                                  c.title.contains(basename),
                            );
                            if (target != -1) {
                              if (target == controller.currentChapterIndex.value) {
                                // If it's the same chapter, do nothing (or could scroll to anchor if implemented)
                                debugPrint(
                                  '[Reader] Link tapped points to current chapter: $basename',
                                );
                              } else {
                                debugPrint(
                                  '[Reader] Link tapped, navigating to chapter index $target (basename=$basename)',
                                );
                                controller.goToChapter(target);
                              }
                            } else {
                              Get.snackbar('提示', '未找到目标章节: $url');
                            }
                          } catch (e) {
                            debugPrint('[Reader] onLinkTap error: $e');
                          }
                        },
                        style: {
                          'body': Style(
                            fontSize: FontSize(controller.fontSize.value),
                            lineHeight: LineHeight(1.8),
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          'p': Style(
                            display: Display.block,
                            lineHeight: LineHeight(2.8),
                            padding: HtmlPaddings.only(bottom: 16),
                          ),
                          'div': Style(
                            display: Display.block,
                            lineHeight: LineHeight(1.8),
                            padding: HtmlPaddings.only(bottom: 16),
                          ),
                          'span': Style(display: Display.inline),
                          'strong': Style(fontWeight: FontWeight.bold),
                          'b': Style(fontWeight: FontWeight.bold),
                          'em': Style(fontStyle: FontStyle.italic),
                          'i': Style(fontStyle: FontStyle.italic),
                          'u': Style(textDecoration: TextDecoration.underline),
                          'mark': Style(
                            backgroundColor: Colors.yellow.withOpacity(0.5),
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                          'mark_selected': Style(
                            backgroundColor: Colors.orange.withOpacity(0.5),
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        },
                        extensions: [
                          TagExtension(
                            tagsToExtend: {'mark_selected'},
                            builder: (extensionContext) {
                              // 给选中的搜索结果添加Key，用于滚动定位
                              return Container(
                                key: _searchTargetKey,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  extensionContext.innerHtml,
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: controller.fontSize.value,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  // 如果有搜索结果，显示高亮
                  if (hasSearch) {
                    return _buildHighlightedText(currentContent, context);
                  }

                  // 默认使用可选择文本
                  return SelectableText(
                    currentContent,
                    style: TextStyle(
                      fontSize: controller.fontSize.value,
                      height: 1.8,
                      letterSpacing: 0.5,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // 底部导航提示
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (controller.hasPreviousChapter())
                    TextButton.icon(
                      onPressed: controller.previousChapter,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一章'),
                    ),
                  if (controller.hasPreviousChapter() && controller.hasNextChapter())
                    const SizedBox(width: 16),
                  if (controller.hasNextChapter())
                    TextButton.icon(
                      onPressed: controller.nextChapter,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('下一章'),
                    ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    });
  }

  // 构建带高亮的文本
  Widget _buildHighlightedText(String content, BuildContext context) {
    final controller = widget.controller;
    final currentChapterIndex = controller.currentChapterIndex.value;

    // 获取当前章节的搜索匹配
    final chapterMatches = controller.searchMatches
        .where((m) => m.chapterIndex.toInt() == currentChapterIndex)
        .toList();

    if (chapterMatches.isEmpty) {
      return SelectableText(
        content,
        style: TextStyle(
          fontSize: controller.fontSize.value,
          height: 1.8,
          letterSpacing: 0.5,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      );
    }

    // 调试：记录匹配信息与选中索引，帮助定位高亮为何未出现
    try {
      final selIdx = controller.selectedSearchIndex.value;
      debugPrint(
        '[Reader] _buildHighlightedText: chapterMatches=${chapterMatches.length} selectedSearchIndex=$selIdx',
      );
      for (int i = 0; i < chapterMatches.length; i++) {
        final m = chapterMatches[i];
        debugPrint('[Reader] match[$i] pos=${m.position} snippet="${m.snippet}"');
      }
    } catch (e) {
      debugPrint('[Reader] _buildHighlightedText log error: $e');
    }

    // 构建高亮文本片段
    final spans = <TextSpan>[];
    int lastEnd = 0;
    final selectedIndex = controller.selectedSearchIndex.value;

    // 按位置排序匹配结果
    chapterMatches.sort((a, b) => a.position.compareTo(b.position));

    // 获取当前选中匹配在章节匹配列表中的索引
    int? currentSelectedInChapter;
    if (selectedIndex >= 0 && selectedIndex < controller.searchMatches.length) {
      final selectedMatch = controller.searchMatches[selectedIndex];
      currentSelectedInChapter = chapterMatches.indexWhere(
        (m) => m.position == selectedMatch.position,
      );
    }

    for (int i = 0; i < chapterMatches.length; i++) {
      final match = chapterMatches[i];
      int matchStart = match.position.toInt();

      // 优先使用用户原始搜索词（若存在），否则从snippet中提取首个非空 token 作为回退
      String searchKeyword = controller.lastSearchQuery.value.trim();
      if (searchKeyword.isEmpty) {
        final snippetLines = match.snippet.split(RegExp(r'[\n\r]'));
        if (snippetLines.isNotEmpty) {
          final firstLine = snippetLines.first;
          final tokenMatch = RegExp(r'\S+').firstMatch(firstLine ?? '');
          searchKeyword = tokenMatch != null ? tokenMatch.group(0)!.trim() : firstLine.trim();
        }
      }

      // 估算关键词长度
      int keywordLength = searchKeyword.length;
      if (matchStart < content.length) {
        final remainingContent = content.substring(matchStart);
        final keywordMatch = RegExp.escape(searchKeyword);
        final regex = RegExp(keywordMatch, caseSensitive: false);
        final actualMatch = regex.firstMatch(remainingContent);
        if (actualMatch != null) {
          keywordLength = actualMatch.group(0)?.length ?? keywordLength;
        }
      }

      int matchEnd = (matchStart + keywordLength).clamp(0, content.length);

      // 如果计算得到的高亮长度为 0（或 end<=start），尝试通过多种回退方式定位实际文本：
      // 1) 在整个正文中查找关键词（不区分大小写）；
      // 2) 在剩余内容中查找第一个非空 token；
      // 若都失败，则跳过该匹配的高亮（避免产生 start==end 的空 span）。
      if (matchEnd <= matchStart) {
        bool resolved = false;
        if (searchKeyword.isNotEmpty) {
          final lowerContent = content.toLowerCase();
          final lowerKey = searchKeyword.toLowerCase();
          final idx = lowerContent.indexOf(lowerKey, matchStart);
          if (idx >= 0) {
            matchStart = idx;
            matchEnd = (idx + searchKeyword.length).clamp(0, content.length);
            resolved = true;
          }
        }

        if (!resolved) {
          // 使用之前计算的 remainingContent（从原始 matchStart 开始）查找第一个非空 token
          if (matchStart < content.length) {
            final remainingContent = content.substring(matchStart);
            final tokenMatch = RegExp(r'\S+').firstMatch(remainingContent);
            if (tokenMatch != null) {
              final realStart = matchStart + tokenMatch.start;
              matchStart = realStart;
              matchEnd = (realStart + tokenMatch.group(0)!.length).clamp(0, content.length);
              resolved = true;
            }
          }
        }

        if (!resolved) {
          debugPrint(
            '[Reader] Warning: could not resolve non-empty highlight for match at pos=${match.position}. Skipping highlight.',
          );
          continue;
        }
      }

      // 添加普通文本
      if (matchStart > lastEnd) {
        spans.add(
          TextSpan(
            text: content.substring(lastEnd, matchStart),
            style: TextStyle(
              fontSize: controller.fontSize.value,
              height: 1.8,
              letterSpacing: 0.5,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        );
      }

      // 添加高亮文本（黄色文字+淡黄色背景）
      final isSelected = i == currentSelectedInChapter;
      debugPrint(
        '[Reader] building span for match[$i]: start=$matchStart end=$matchEnd isSelected=$isSelected',
      );
      spans.add(
        TextSpan(
          text: content.substring(matchStart, matchEnd),
          style: TextStyle(
            fontSize: controller.fontSize.value,
            height: 1.8,
            letterSpacing: 0.5,
            backgroundColor: isSelected
                ? Colors.orange.withOpacity(0.5)
                : Colors.yellow.withOpacity(0.3),
            color: isSelected ? Colors.orange.shade900 : Colors.yellow.shade900,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      );

      lastEnd = matchEnd;
    }

    // 添加剩余文本
    if (lastEnd < content.length) {
      spans.add(
        TextSpan(
          text: content.substring(lastEnd),
          style: TextStyle(
            fontSize: controller.fontSize.value,
            height: 1.8,
            letterSpacing: 0.5,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      );
    }

    debugPrint(
      '[Reader] built spans count=${spans.length} lastEnd=$lastEnd contentLength=${content.length} currentSelectedInChapter=$currentSelectedInChapter',
    );
    return SelectableText.rich(TextSpan(children: spans), textAlign: TextAlign.justify);
  }

  // 对HTML内容做关键词高亮（插入<mark>标签）
  // 将 HTML 中的关键词替换为 <mark>，并可选将某一选中匹配项替换为 <mark_selected>
  String _highlightHtml(String html, String keyword, {int? selectedOccurrence}) {
    if (keyword.isEmpty) return html;
    final escaped = RegExp.escape(keyword);

    try {
      debugPrint(
        '[Reader] _highlightHtml start: keyword="$keyword" selectedOccurrence=$selectedOccurrence',
      );

      // 构建纯文本到 HTML 索引的映射：plainIndex -> htmlIndex
      final plainBuffer = StringBuffer();
      final List<int> plainToHtml = [];
      final src = html;
      int i = 0;
      while (i < src.length) {
        final ch = src[i];
        if (ch == '<') {
          // 跳过标签
          final endTag = src.indexOf('>', i);
          if (endTag == -1) break;
          i = endTag + 1;
          continue;
        }

        if (ch == '&') {
          // HTML 实体，尽可能把整个实体作为一个字符处理
          final endEnt = src.indexOf(';', i);
          final entEnd = endEnt == -1 ? i : endEnt;
          // 将实体当作单个字符
          plainToHtml.add(i);
          plainBuffer.write(src.substring(i, entEnd + 1));
          i = entEnd + 1;
          continue;
        }

        // 普通字符
        plainToHtml.add(i);
        plainBuffer.write(ch);
        i++;
      }

      final plain = plainBuffer.toString();

      // 在纯文本中查找所有匹配
      final allMatches = RegExp('($escaped)', caseSensitive: false).allMatches(plain).toList();

      // 使用传入的选中序号
      final selectedOccurrenceIndex = selectedOccurrence;

      debugPrint(
        '[Reader] _highlightHtml: plainLen=${plain.length} matches=${allMatches.length} selectedOcc=$selectedOccurrenceIndex',
      );

      // 将纯文本匹配映射回 HTML 索引区间
      final List<Map<String, dynamic>> intervals = [];
      for (int idx = 0; idx < allMatches.length; idx++) {
        final m = allMatches[idx];
        final pStart = m.start;
        final pEnd = m.end; // exclusive
        if (pStart < 0 || pEnd <= pStart || pEnd - 1 >= plainToHtml.length) continue;
        final htmlStart = plainToHtml[pStart];
        final htmlEndIndex = plainToHtml[pEnd - 1];
        final htmlEnd = htmlEndIndex + 1; // exclusive
        intervals.add({
          'start': htmlStart,
          'end': htmlEnd,
          'selected': selectedOccurrenceIndex == idx,
          'occurrence': idx,
        });
      }

      if (intervals.isEmpty) return html;

      // 合并并按顺序处理 intervals（防止重叠）
      intervals.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

      final sb = StringBuffer();
      int pos = 0;
      for (final it in intervals) {
        final s = it['start'] as int;
        final e = it['end'] as int;
        if (s >= e || s < 0 || e > src.length) continue;
        if (s > pos) sb.write(src.substring(pos, s));
        final bool isSel = it['selected'] as bool;
        final occ = it['occurrence'] as int;
        if (isSel) {
          // 将选中标记加上特殊的ID，用于后续定位
          sb.write('<mark_selected id="search-target" data-occur="$occ">');
        } else {
          sb.write('<mark>');
        }
        sb.write(src.substring(s, e));
        if (isSel) {
          sb.write('</mark_selected>');
        } else {
          sb.write('</mark>');
        }
        pos = e;
      }
      if (pos < src.length) sb.write(src.substring(pos));

      final result = sb.toString();
      debugPrint('[Reader] _highlightHtml done: produced length=${result.length}');
      return result;
    } catch (e) {
      debugPrint('[Reader] _highlightHtml error: $e');
      // 兜底：回退到简单替换
      return html.replaceAllMapped(
        RegExp('($escaped)', caseSensitive: false),
        (m) => '<mark>${m[0]}</mark>',
      );
    }
  }

  // 将本地 file:// 或 file:/// 路径的图片内联为 base64 data URL
  String _embedLocalImages(String html) {
    try {
      String out = html;
      int idx = 0;
      while (true) {
        final imgIdx = out.toLowerCase().indexOf('<img', idx);
        if (imgIdx == -1) break;

        final srcKey = 'src=';
        final srcPos = out.toLowerCase().indexOf(srcKey, imgIdx);
        if (srcPos == -1) {
          idx = imgIdx + 4;
          continue;
        }

        int q = srcPos + srcKey.length;
        while (q < out.length &&
            (out[q] == ' ' || out[q] == '\t' || out[q] == '\n' || out[q] == '\r')) {
          q++;
        }
        if (q >= out.length) break;
        final quote = out[q];
        if (quote != '"' && quote != "'") {
          idx = srcPos + srcKey.length;
          continue;
        }
        final endQuote = out.indexOf(quote, q + 1);
        if (endQuote == -1) break;

        final src = out.substring(q + 1, endQuote);
        if (src.isEmpty) {
          idx = endQuote + 1;
          continue;
        }

        try {
          final lower = src.toLowerCase();
          if (lower.startsWith('data:') ||
              lower.startsWith('http:') ||
              lower.startsWith('https:')) {
            idx = endQuote + 1;
            continue;
          }

          String path = '';
          if (lower.startsWith('file:')) {
            try {
              final uri = Uri.parse(src);
              path = uri.toFilePath(windows: Platform.isWindows);
            } catch (_) {
              path = src.replaceFirst(RegExp(r'^file:///?'), '');
              if (Platform.isWindows && path.startsWith('/')) path = path.substring(1);
            }
          } else {
            path = src.replaceAll('\\', '/');
            if (!File(path).existsSync()) {
              final cwdPath = '${Directory.current.path}/$path';
              if (File(cwdPath).existsSync()) path = cwdPath;
            }
          }

          File file = File(path);
          if (!file.existsSync()) {
            // 尝试在同一 epub_images/<id> 目录下按文件名搜索（处理内部存在额外目录如 OPS 的情况）
            final baseLower = path.toLowerCase();
            final marker = '${Platform.pathSeparator}epub_images${Platform.pathSeparator}';
            final markerIdx = baseLower.indexOf(marker);
            if (markerIdx >= 0) {
              final after = path.substring(markerIdx + marker.length);
              final parts = after.split(Platform.pathSeparator);
              if (parts.isNotEmpty) {
                final novelId = parts[0];
                final baseDir = Directory(
                  '${path.substring(0, markerIdx + marker.length)}$novelId',
                );
                if (baseDir.existsSync()) {
                  final basename = path.split(Platform.pathSeparator).last;
                  try {
                    final found = baseDir
                        .listSync(recursive: true)
                        .whereType<File>()
                        .firstWhere(
                          (f) => f.path.split(Platform.pathSeparator).last == basename,
                          orElse: () => File(''),
                        );
                    if (found.path.isNotEmpty && found.existsSync()) {
                      file = found;
                      path = file.path;
                    }
                  } catch (_) {}
                }
              }
            }
          }
          if (!file.existsSync()) {
            debugPrint('[Reader] Image file not found: $path');
            idx = endQuote + 1;
            continue;
          }

          final bytes = file.readAsBytesSync();
          final b64 = base64Encode(bytes);
          final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
          final mime =
              {
                'png': 'image/png',
                'jpg': 'image/jpeg',
                'jpeg': 'image/jpeg',
                'gif': 'image/gif',
                'webp': 'image/webp',
                'svg': 'image/svg+xml',
              }[ext] ??
              'application/octet-stream';
          final dataUrl = 'data:$mime;base64,$b64';

          out = out.substring(0, q + 1) + dataUrl + out.substring(endQuote);
          idx = q + 1 + dataUrl.length;
        } catch (e) {
          debugPrint('[Reader] Failed to embed image src="$src": $e');
          idx = endQuote + 1;
          continue;
        }
      }
      return out;
    } catch (e) {
      debugPrint('[Reader] _embedLocalImages error: $e');
      return html;
    }
  }
}
