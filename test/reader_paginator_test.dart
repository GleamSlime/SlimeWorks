// 分页引擎的正确性验证。
//
// 分页是「微信读书式左右翻页」的地基：切错页会直接表现成
// 「翻页后重复一段字」或「漏字」。这里用可判定的性质来验证，
// 不依赖具体字号/机型的像素值。
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/utils/reader_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 16, height: 1.8);
  const pageSize = Size(360, 600);

  /// 造一段有足够长度的中文（分页至少要能切出多页）
  String makeText(int paragraphs) {
    final buf = StringBuffer();
    for (var i = 0; i < paragraphs; i++) {
      buf.writeln('第${i + 1}段。山间的风把整片竹林都吹得沙沙作响，这是很久以前的故事了。');
    }
    return buf.toString();
  }

  test('切页后拼回去必须与原文一致（不丢字、不重复字）', () {
    final text = makeText(30);
    final pages = ReaderPaginator.paginate(text: text, size: pageSize, style: style);

    expect(pages.length, greaterThan(1), reason: '这段文字应该被切成多页');

    // ★ 最关键的性质：所有页拼起来 == 原文（去掉各自尾部空白）
    final rejoined = pages.join('').replaceAll(RegExp(r'\s'), '');
    final original = text.replaceAll(RegExp(r'\s'), '');
    expect(
      rejoined,
      original,
      reason: '拼回去必须与原文逐字一致；不一致说明切点把字劈开或漏了字',
    );
  });

  test('每页内容高度都不得超过页高', () {
    final text = makeText(30);
    final pages = ReaderPaginator.paginate(text: text, size: pageSize, style: style);

    for (var i = 0; i < pages.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: pages[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: pageSize.width);
      expect(
        painter.height,
        lessThanOrEqualTo(pageSize.height + 1),
        reason: '第 ${i + 1} 页高度 ${painter.height} 超过页高 ${pageSize.height}，'
            '渲染时会被裁掉一截',
      );
      painter.dispose();
    }
  });

  test('空文本返回单页空串，不返回空列表', () {
    final pages = ReaderPaginator.paginate(text: '', size: pageSize, style: style);
    expect(pages.length, 1);
    expect(pages.first, '');
  });

  test('短文本只占一页，不做无意义切分', () {
    final pages = ReaderPaginator.paginate(
      text: '只有一句话。',
      size: pageSize,
      style: style,
    );
    expect(pages.length, 1);
    expect(pages.first.trim(), '只有一句话。');
  });

  test('字号变大时页数必须变多（分页真的跟着排版走）', () {
    final text = makeText(30);
    final small = ReaderPaginator.paginate(
      text: text,
      size: pageSize,
      style: const TextStyle(fontSize: 14, height: 1.6),
    );
    final large = ReaderPaginator.paginate(
      text: text,
      size: pageSize,
      style: const TextStyle(fontSize: 24, height: 1.8),
    );
    expect(
      large.length,
      greaterThan(small.length),
      reason: '字号调大后每页能放的字变少，页数必须增加',
    );
  });
}
