import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart' show SearchMatch;

/// 构建纯文本模式下带搜索高亮的文本
Widget buildHighlightedText({
  required BuildContext context,
  required String content,
  required NovelReaderViewModel controller,
}) {
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

  try {
    final selIdx = controller.selectedSearchIndex.value;
    debugPrint(
      '[Reader] buildHighlightedText: chapterMatches=${chapterMatches.length} selectedSearchIndex=$selIdx',
    );
    for (int i = 0; i < chapterMatches.length; i++) {
      final m = chapterMatches[i];
      debugPrint('[Reader] match[$i] pos=${m.position} snippet="${m.snippet}"');
    }
  } catch (e) {
    debugPrint('[Reader] buildHighlightedText log error: $e');
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

    // 优先使用用户原始搜索词（若存在），否则从snippet中提取首个非空 token
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
          '[Reader] Warning: could not resolve non-empty highlight for match at pos=${match.position}. Skipping.',
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

    // 添加高亮文本
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

/// 对 HTML 内容做关键词高亮（插入 <mark>/<mark_selected> 标签）
String highlightHtml(String html, String keyword, {int? selectedOccurrence}) {
  if (keyword.isEmpty) return html;

  final highlightStart = DateTime.now();
  final htmlLen = html.length;
  final escaped = RegExp.escape(keyword);

  try {
    debugPrint(
      '[Reader] highlightHtml start: htmlLen=$htmlLen, keyword="$keyword" selectedOccurrence=$selectedOccurrence',
    );

    // 构建纯文本到 HTML 索引的映射
    final plainBuffer = StringBuffer();
    final List<int> plainToHtml = [];
    final src = html;
    int i = 0;
    while (i < src.length) {
      final ch = src[i];
      if (ch == '<') {
        final endTag = src.indexOf('>', i);
        if (endTag == -1) break;
        i = endTag + 1;
        continue;
      }

      if (ch == '&') {
        final endEnt = src.indexOf(';', i);
        final entEnd = endEnt == -1 ? i : endEnt;
        plainToHtml.add(i);
        plainBuffer.write(src.substring(i, entEnd + 1));
        i = entEnd + 1;
        continue;
      }

      plainToHtml.add(i);
      plainBuffer.write(ch);
      i++;
    }

    final plain = plainBuffer.toString();

    final allMatches = RegExp('($escaped)', caseSensitive: false).allMatches(plain).toList();
    final selectedOccurrenceIndex = selectedOccurrence;

    debugPrint(
      '[Reader] highlightHtml: plainLen=${plain.length} matches=${allMatches.length} selectedOcc=$selectedOccurrenceIndex',
    );

    // 将纯文本匹配映射回 HTML 索引区间
    final List<Map<String, dynamic>> intervals = [];
    for (int idx = 0; idx < allMatches.length; idx++) {
      final m = allMatches[idx];
      final pStart = m.start;
      final pEnd = m.end;
      if (pStart < 0 || pEnd <= pStart || pEnd - 1 >= plainToHtml.length) continue;
      final htmlStart = plainToHtml[pStart];
      final htmlEndIndex = plainToHtml[pEnd - 1];
      final htmlEnd = htmlEndIndex + 1;
      intervals.add({
        'start': htmlStart,
        'end': htmlEnd,
        'selected': selectedOccurrenceIndex == idx,
        'occurrence': idx,
      });
    }

    if (intervals.isEmpty) {
      final ms = DateTime.now().difference(highlightStart).inMilliseconds;
      debugPrint('[Reader] highlightHtml: no intervals found, took ${ms}ms');
      return html;
    }

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
    final ms = DateTime.now().difference(highlightStart).inMilliseconds;
    debugPrint(
      '[Reader] highlightHtml done in ${ms}ms: produced length=${result.length}, added ${intervals.length} highlights',
    );
    return result;
  } catch (e) {
    final ms = DateTime.now().difference(highlightStart).inMilliseconds;
    debugPrint('[Reader] highlightHtml error after ${ms}ms: $e');
    return html.replaceAllMapped(
      RegExp('($escaped)', caseSensitive: false),
      (m) => '<mark>${m[0]}</mark>',
    );
  }
}

/// 将本地 file:// 图片路径内联为 base64 data URL
String embedLocalImages(String html) {
  final embedStart = DateTime.now();
  int embeddedCount = 0;
  int totalBytes = 0;

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
        if (lower.startsWith('data:') || lower.startsWith('http:') || lower.startsWith('https:')) {
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
          final baseLower = path.toLowerCase();
          final marker = '${Platform.pathSeparator}epub_images${Platform.pathSeparator}';
          final markerIdx = baseLower.indexOf(marker);
          if (markerIdx >= 0) {
            final after = path.substring(markerIdx + marker.length);
            final parts = after.split(Platform.pathSeparator);
            if (parts.isNotEmpty) {
              final novelId = parts[0];
              final baseDir = Directory('${path.substring(0, markerIdx + marker.length)}$novelId');
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
        totalBytes += bytes.length;
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
        embeddedCount++;
      } catch (e) {
        debugPrint('[Reader] Failed to embed image src="$src": $e');
        idx = endQuote + 1;
        continue;
      }
    }

    final embedMs = DateTime.now().difference(embedStart).inMilliseconds;
    final totalKB = (totalBytes / 1024).toStringAsFixed(1);
    if (embeddedCount > 0) {
      debugPrint(
        '[Reader] embedLocalImages: $embeddedCount images, ${totalKB}KB total, took ${embedMs}ms',
      );
    }

    return out;
  } catch (e) {
    final embedMs = DateTime.now().difference(embedStart).inMilliseconds;
    debugPrint('[Reader] embedLocalImages error after ${embedMs}ms: $e');
    return html;
  }
}

/// Top-level helper to run highlight + image embedding inside an isolate via `compute()`.
/// Accepts a Map with keys: 'html' (String), 'keyword' (String), 'selectedOccurrence' (int|null), 'embedImages' (bool)
String processHtmlForCompute(Map params) {
  final isolateStart = DateTime.now();
  try {
    String html = params['html']?.toString() ?? '';
    final htmlLen = html.length;
    final htmlLenKB = (htmlLen / 1024).toStringAsFixed(1);
    final String keyword = params['keyword']?.toString() ?? '';
    final int? selectedOccurrence = params['selectedOccurrence'] is int
        ? params['selectedOccurrence'] as int
        : null;
    final bool embedImages = params['embedImages'] == true;

    debugPrint(
      '[Isolate] processHtmlForCompute started: ${htmlLenKB}KB, keyword="${keyword}", embedImages=$embedImages',
    );

    // Step 1: Highlight
    if (keyword.isNotEmpty) {
      final highlightStart = DateTime.now();
      html = highlightHtml(html, keyword, selectedOccurrence: selectedOccurrence);
      final highlightMs = DateTime.now().difference(highlightStart).inMilliseconds;
      debugPrint('[Isolate] highlightHtml took ${highlightMs}ms');
    }

    // Step 2: Embed images
    if (embedImages) {
      final embedStart = DateTime.now();
      html = embedLocalImages(html);
      final embedMs = DateTime.now().difference(embedStart).inMilliseconds;
      debugPrint('[Isolate] embedLocalImages took ${embedMs}ms');
    }

    // Step 3: Ensure paragraphs for plain-text-like content
    final paragraphStart = DateTime.now();
    final hasParagraphLike = RegExp(r'<\s*(p|br|div)\b', caseSensitive: false).hasMatch(html);
    if (!hasParagraphLike) {
      try {
        String t = html.trim();
        t = t.replaceAll(RegExp(r'\r?\n\s*\r?\n+'), '</p><p>');
        t = t.replaceAll(RegExp(r'\r?\n'), '<br/>');
        html = '<p>$t</p>';
      } catch (_) {}
    }
    final paragraphMs = DateTime.now().difference(paragraphStart).inMilliseconds;
    debugPrint(
      '[Isolate] paragraph processing took ${paragraphMs}ms (hasParagraphLike=$hasParagraphLike)',
    );

    final totalMs = DateTime.now().difference(isolateStart).inMilliseconds;
    final outputLenKB = (html.length / 1024).toStringAsFixed(1);
    debugPrint(
      '[Isolate] processHtmlForCompute completed: ${outputLenKB}KB output in ${totalMs}ms',
    );

    return html;
  } catch (e) {
    final errorMs = DateTime.now().difference(isolateStart).inMilliseconds;
    debugPrint('[Isolate] *** processHtmlForCompute ERROR after ${errorMs}ms: $e ***');
    return params['html']?.toString() ?? '';
  }
}
