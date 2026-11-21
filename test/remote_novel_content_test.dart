// 远程书「能列出来但打开没内容」的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 这个 bug 是什么（2026-11-22，用户报「列表能看到书，打开没有内容」）
// ═══════════════════════════════════════════════════════════════════════════
// 节点侧 `get_novel_content` 返回的章节列表里，**EPUB 的 `content` 恒为 `None`**：
//
//   // rust/novel_reader/src/parser/parser_epub.rs
//   chapters.push(NovelChapter {
//       ...
//       content: None, // 延迟加载，由 get_chapter_content 提供
//   });
//
// 正文只能靠 `get_chapter_content(chapter_index)` 单独取。
//
// 而桌面的 `RemoteNovelReaderDialog` 直接读 `_chapters[_selected]['content']`：
//   · TXT 书内联了全文 → 看着正常，把问题盖住；
//   · **EPUB 书 → 正文永远空白**，而且没有任何报错。
// 它还有第二个毛病：点章节列表只 `setState(_selected)`，压根没去加载新正文。
//
// 修法：
//   1. 正文统一取 `_chapterText`，由 `_loadChapter()` 走
//      `fetchNodeChapterContent`（即节点 `get_chapter_content`）填充；
//   2. 章节列表点击改为调 `_loadChapter(index)`；
//   3. 补上 `_chapterLoading` / `_chapterError` 的展示，别让加载中/失败表现成空白。
//
// 移动端的 `RemoteNovelReaderPage` 本来就是走 `_loadChapter` 的（没这个 bug），
// 所以症状只在桌面端明显 —— 但两条路径现在统一了，不会再分叉。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 桌面阅读对话框必须通过 `_loadChapter` + `_chapterText` 渲染正文，
  /// 不能读 payload 里的 `content`（EPUB 恒为 null）。
  test('桌面阅读对话框不得用 payload 的 content 渲染正文', () {
    final src = File(
      'lib/pages/collection/library/components/remote_novel_reader_dialog.dart',
    ).readAsStringSync();

    // 反例形态：直接从章节 payload 取 content 当正文
    final legacyPattern = RegExp(
      r"chapter\?\[\s*'content'\s*\]",
    );
    expect(
      legacyPattern.hasMatch(src),
      isFalse,
      reason: 'EPUB 的章节 content 恒为 None（延迟加载），'
          '直接读它会让 epub 正文永远空白。必须用 _chapterText'
          '（由 _loadChapter 走 get_chapter_content 填充）',
    );

    // 正例必须存在：至少有一处用 _chapterText 渲染
    expect(
      src.contains('_chapterText'),
      isTrue,
      reason: '正文应来自 _chapterText（单独请求章节正文的结果）',
    );

    // 章节切换必须触发加载，不能只 setState
    expect(
      src.contains('_loadChapter(index)'),
      isTrue,
      reason: '点章节列表必须调 _loadChapter，否则切章后正文不跟着变',
    );
  });

  /// 节点侧 `get_chapter_content` must 存在且被客户端使用
  test('客户端必须通过 get_chapter_content 取章节正文', () {
    final svc = File(
      'lib/core/services/node/node_settings_service.dart',
    ).readAsStringSync();
    expect(
      svc.contains("action: 'get_chapter_content'"),
      isTrue,
      reason: 'EPUB 正文只能靠这个 action 按 index 单独取',
    );
    expect(
      svc.contains('fetchNodeChapterContent'),
      isTrue,
    );
  });
}
