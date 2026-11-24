// 「远程阅读按章流式取内容」的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 用户报的问题（2026-11-24）
// ═══════════════════════════════════════════════════════════════════════════
// 「即便是 txt 或者 epub，远程节点阅读时应该也是发送当前章节内容，
//   而不是等待全书下载完毕」
//
// 根因：节点 `get_novel_content` 把每章 `content` 一并塞进响应。
// TXT 解析器（parser_txt.rs）给**每一章**都填了 `Some(本章片段)`，
// 于是一本 5MB 的 txt 就是 5MB 全量下载后才渲染第一屏——移动端/弱网下
// 表现为「打开书一直转圈、很久才出字」。
//
// EPUB 本来就是 `content: None`（延迟加载），所以问题只在 TXT 上暴露；
// 但两条路径的契约必须一致，否则「哪天 EPUB 也内联了」就会重演。
//
// 修法：`get_novel_content` 默认只下发章节骨架（id/title/index），
// 正文一律由 `get_chapter_content` 按章取。`with_content=true` 保留全量语义。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/e2e_headless_node.dart';

void main() {
  final isolatedHome = e2eIsolatedHome;
  if (isolatedHome == null) {
    test('懒加载端到端已跳过（未隔离 HOME）', () {
      // ignore: avoid_print
      print(kNeedIsolatedHomeHint);
    }, skip: kNeedIsolatedHomeHint);
    return;
  }

  late RealHeadlessNode node;

  setUpAll(() async {
    node = await RealHeadlessNode.start(sandboxRoot: Directory(isolatedHome));
  });

  tearDownAll(() async {
    await node.dispose();
  });

  test('get_novel_content 默认不下发正文，只给章节骨架', () async {
    // 造一本「大书」：正文体积必须明显大于骨架，才能证明没被内联
    final booksDir = Directory('${node.dataDir}/books')..createSync(recursive: true);
    final book = File('${booksDir.path}/懒加载验证.txt');
    final buf = StringBuffer();
    for (var i = 1; i <= 30; i++) {
      buf.writeln('第$i章 标题');
      buf.writeln('正文内容。' * 400);
    }
    book.writeAsStringSync(buf.toString());
    final bookSize = book.lengthSync();
    expect(bookSize, greaterThan(100 * 1024), reason: '样本要够大，否则证明不了没内联');

    final imported = await node.call('scan_novel_folder', <String, dynamic>{
      'folder_path': booksDir.path,
    });
    expect(imported['success'], isTrue, reason: '导入失败: $imported');

    // 1) 骨架响应：必须远小于书体积
    final skeleton = await node.call('get_novel_content', <String, dynamic>{
      'file_path': book.path,
    });
    expect(skeleton['success'], isTrue, reason: '取章节骨架失败: $skeleton');
    final chapters = (skeleton['data'] as Map)['chapters'] as List;
    expect(chapters.length, greaterThan(1), reason: '应切出多章');

    for (final raw in chapters) {
      final ch = raw as Map;
      expect(
        ch['content'],
        isNull,
        reason: '默认不得下发章节正文（否则等于全书下载）；'
            '章节 ${ch['title']} 带了 ${ch['content'].toString().length} 字符',
      );
    }

    // 骨架 JSON 体积应远小于书体积（量级差至少 10 倍）
    final skeletonBytes = skeleton.toString().length;
    expect(
      skeletonBytes * 10,
      lessThan(bookSize),
      reason: '骨架体积($skeletonBytes)应远小于书体积($bookSize)',
    );

    // 2) 按章取正文仍然可用
    final firstChapter = await node.call('get_chapter_content', <String, dynamic>{
      'file_path': book.path,
      'chapter_index': 0,
    });
    expect(firstChapter['success'], isTrue, reason: '按章取正文失败: $firstChapter');
    final text = (firstChapter['data'] ?? '').toString();
    expect(text.length, greaterThan(100), reason: '第 0 章正文不该为空');
    expect(text, contains('第1章'));

    // 3) with_content=true 仍能拿到全量（保留给调试/导出）
    final full = await node.call('get_novel_content', <String, dynamic>{
      'file_path': book.path,
      'with_content': true,
    });
    expect(full['success'], isTrue);
    final fullChapters = (full['data'] as Map)['chapters'] as List;
    expect(
      (fullChapters.first as Map)['content'],
      isNotNull,
      reason: '显式 with_content=true 时应保留全量语义',
    );
  });
}
