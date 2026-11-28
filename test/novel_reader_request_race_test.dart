import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:get/get.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/src/rust/frb_generated.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';

class _DeferredNovelApi implements RustLibApi {
  final Map<int, Completer<String>> chapters = <int, Completer<String>>{};

  @override
  Future<String> crateApiNovelReaderGetChapterContent({
    required String filePath,
    required BigInt chapterIndex,
  }) {
    return chapters[chapterIndex.toInt()]!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final api = _DeferredNovelApi();

  setUpAll(() {
    RustLib.initMock(api: api);
  });

  test('本机旧章节响应不能覆盖新正文或错误保存进度', () async {
    final first = Completer<String>();
    final second = Completer<String>();
    api.chapters[0] = first;
    api.chapters[1] = second;
    final vm = NovelReaderViewModel(
      NovelMetadata(
        id: 'race-book',
        title: '竞态测试书',
        filePath: '/books/race.txt',
        format: NovelFormat.txt,
        fileSize: BigInt.from(1024),
        modifiedAt: 0,
        addedAt: 0,
        progress: 0,
        isFavorite: false,
        tags: const <String>[],
      ),
    );
    vm.chapters.assignAll(<NovelChapter>[
      NovelChapter(
        id: 'chapter-0',
        title: '第一章',
        index: BigInt.zero,
        content: '第一章',
      ),
      NovelChapter(
        id: 'chapter-1',
        title: '第二章',
        index: BigInt.one,
        content: '第二章',
      ),
    ]);

    final oldLoad = vm.loadChapterContent(0);
    vm.currentChapterIndex.value = 1;
    final newLoad = vm.loadChapterContent(1);
    second.complete('新章节正文');
    await newLoad;
    expect(vm.currentContent.value, '新章节正文');

    first.complete('旧章节正文');
    await oldLoad;
    expect(vm.currentContent.value, '新章节正文');
    expect(vm.currentChapterIndex.value, 1);
    expect(vm.errorMessage.value, isEmpty);
    vm.onClose();
  });
}
