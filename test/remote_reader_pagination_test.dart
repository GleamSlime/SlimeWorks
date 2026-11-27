import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/pages/collection/library/components/remote_novel_reader_dialog.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

import 'helpers/page_golden.dart';

const _phoneSize = Size(390, 844);

String _longChapter(String prefix) {
  final buffer = StringBuffer();
  for (var i = 0; i < 80; i++) {
    buffer.writeln('$prefix${i + 1}。山间的风把整片竹林都吹得沙沙作响，这是很久以前的故事了。');
  }
  return buffer.toString();
}

int _totalPages(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.byKey(const ValueKey<String>('reader-page-indicator')),
  );
  final match = RegExp(r'\d+/(\d+) 页').firstMatch(text.data!);
  return int.parse(match!.group(1)!);
}

int _currentPage(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.byKey(const ValueKey<String>('reader-page-indicator')),
  );
  final match = RegExp(r'(\d+)/\d+ 页').firstMatch(text.data!);
  return int.parse(match!.group(1)!);
}

Future<_StubNodeSettingsService> _mountReader(
  WidgetTester tester, {
  double progress = 0,
  String firstChapter = '',
  String secondChapter = '第二章正文很短。',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await getIt.reset();
  final service = _StubNodeSettingsService(
    firstChapter: firstChapter.isEmpty ? _longChapter('甲') : firstChapter,
    secondChapter: secondChapter,
  );
  getIt.registerSingleton<NodeSettingsService>(service);

  final metadata = NovelMetadata(
    id: 'remote:node-1:raw-book',
    title: '分页测试书',
    filePath: '/books/test.txt',
    format: NovelFormat.txt,
    fileSize: BigInt.from(1024),
    modifiedAt: 0,
    addedAt: 0,
    progress: progress,
    isFavorite: false,
    tags: const <String>[],
  );
  await pumpAppPage(
    tester,
    RemoteNovelReaderPage(
      metadata: metadata,
      nodeId: 'node-1',
      nodeName: '测试节点',
    ),
    size: _phoneSize,
    designSize: _phoneSize,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return service;
}

Future<void> _tapReader(WidgetTester tester, double x) async {
  await tester.tapAt(Offset(x, _phoneSize.height * 0.45));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('正文按真实排版分页，中央点击与左右手势都能翻页', (tester) async {
    await _mountReader(tester);

    expect(
      find.byKey(const ValueKey<String>('remote-reader-pages')),
      findsOneWidget,
    );
    expect(_totalPages(tester), greaterThan(1));
    final firstText = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data;
    expect(
      tester.getSize(find.byType(SelectableText).first).width,
      greaterThan(300),
    );

    await _tapReader(tester, _phoneSize.width / 2);
    final slides = tester
        .widgetList<AnimatedSlide>(find.byType(AnimatedSlide))
        .toList();
    expect(slides.any((slide) => slide.offset.dy < 0), isTrue);
    expect(slides.any((slide) => slide.offset.dy > 0), isTrue);

    await _tapReader(tester, _phoneSize.width / 2);
    final restoredSlides = tester
        .widgetList<AnimatedSlide>(find.byType(AnimatedSlide))
        .toList();
    expect(
      restoredSlides.every((slide) => slide.offset == Offset.zero),
      isTrue,
    );

    await _tapReader(tester, _phoneSize.width * 0.9);
    expect(_currentPage(tester), 2);
    final secondText = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data;
    expect(secondText, isNot(firstText));

    await tester.drag(
      find.byKey(const ValueKey<String>('remote-reader-gestures')),
      const Offset(-140, 0),
    );
    await tester.pumpAndSettle();
    expect(_currentPage(tester), 3);

    await tester.drag(
      find.byKey(const ValueKey<String>('remote-reader-gestures')),
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();
    expect(_currentPage(tester), 2);
  });

  testWidgets('首末页继续滑动会切章，进入上一章时落在末页', (tester) async {
    final service = await _mountReader(tester);
    final firstChapterPages = _totalPages(tester);

    for (
      var i = 0;
      i < firstChapterPages + 2 && service.chapterRequests.last == 0;
      i++
    ) {
      await _tapReader(tester, _phoneSize.width * 0.9);
    }

    expect(service.chapterRequests.last, 1);
    expect(find.text('第二章'), findsOneWidget);
    expect(_currentPage(tester), 1);
    expect(_totalPages(tester), 1);

    await _tapReader(tester, _phoneSize.width * 0.1);
    expect(service.chapterRequests.last, 0);
    expect(_currentPage(tester), firstChapterPages);
    expect(_totalPages(tester), firstChapterPages);
  });

  testWidgets('正文相同的相邻章节也会重置到正确的首末页', (tester) async {
    final sameChapter = _longChapter('相同');
    await _mountReader(tester, secondChapter: sameChapter);
    final pages = _totalPages(tester);

    for (var i = 1; i < pages; i++) {
      await _tapReader(tester, _phoneSize.width * 0.9);
    }
    await _tapReader(tester, _phoneSize.width * 0.9);
    expect(find.text('第二章'), findsOneWidget);
    expect(_currentPage(tester), 1);

    await _tapReader(tester, _phoneSize.width * 0.1);
    expect(find.text('第一章'), findsOneWidget);
    expect(_currentPage(tester), pages);
  });

  testWidgets('恢复章内进度并在关页时写回真实页码', (tester) async {
    final service = await _mountReader(tester, progress: 0.12);
    final pages = _totalPages(tester);
    final current = _currentPage(tester);
    expect(current, greaterThan(1));
    expect(current, lessThan(pages));

    await unmountPage(tester);
    final expected = ((current - 1) / (pages - 1)) / 2;
    expect(service.progressWrites, isNotEmpty);
    expect(service.progressWrites.last, closeTo(expected, 0.000001));
  });

  testWidgets('字号设置会重排页数，目录显示当前位置和已读章节', (tester) async {
    final service = await _mountReader(tester);
    final initialPages = _totalPages(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    final fontSizeSlider = tester.widget<Slider>(find.byType(Slider).first);
    fontSizeSlider.onChanged!(28);
    await tester.pumpAndSettle();
    expect(_totalPages(tester), greaterThan(initialPages));
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('章节列表'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reader-catalog-position')),
      findsOneWidget,
    );
    expect(
      find.textContaining('正在阅读 · 1/${_totalPages(tester)} 页'),
      findsWidgets,
    );

    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();
    expect(service.chapterRequests.last, 1);

    await tester.tap(find.byTooltip('章节列表'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reader-catalog-read-0')),
      findsOneWidget,
    );
    expect(find.text('已读'), findsOneWidget);
  });

  testWidgets('长按正文只提供复制和全选菜单', (tester) async {
    await _mountReader(tester);

    await tester.longPress(find.byType(SelectableText).first);
    await tester.pumpAndSettle();

    final toolbar = tester.widget<AdaptiveTextSelectionToolbar>(
      find.byType(AdaptiveTextSelectionToolbar),
    );
    final types = toolbar.buttonItems!.map((item) => item.type).toList();
    expect(types, contains(ContextMenuButtonType.copy));
    expect(types, contains(ContextMenuButtonType.selectAll));
    expect(types, hasLength(2));

    await _tapReader(tester, _phoneSize.width * 0.9);
    expect(_currentPage(tester), 1);
    await _tapReader(tester, _phoneSize.width * 0.9);
    expect(_currentPage(tester), 2);
  });

  testWidgets('无图片 HTML 章节转成纯文本后同样分页', (tester) async {
    await _mountReader(
      tester,
      firstChapter: '<P>${_longChapter('HTML')}&#128512;</P>',
    );

    expect(_totalPages(tester), greaterThan(1));
    final page = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data!;
    expect(page, isNot(contains('<P>')));
    expect(page, contains('HTML1。'));
  });
}

class _StubNodeSettingsService extends NodeSettingsService {
  _StubNodeSettingsService({
    required this.firstChapter,
    this.secondChapter = '第二章正文很短。',
  });

  final String firstChapter;
  final String secondChapter;
  final List<int> chapterRequests = <int>[];
  final List<double> progressWrites = <double>[];

  @override
  Future<List<Map<String, dynamic>>> fetchNodeNovelContent({
    required String nodeId,
    required String filePath,
  }) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{'title': '第一章', 'index': 0},
      <String, dynamic>{'title': '第二章', 'index': 1},
    ];
  }

  @override
  Future<String> fetchNodeChapterContent({
    required String nodeId,
    required String filePath,
    required int chapterIndex,
  }) async {
    chapterRequests.add(chapterIndex);
    return chapterIndex == 0 ? firstChapter : secondChapter;
  }

  @override
  Future<void> updateNodeNovelProgress({
    required String nodeId,
    required String novelId,
    required double progress,
  }) async {
    progressWrites.add(progress);
  }
}
