import 'dart:async';

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
  bool failFavorite = false,
  bool resetPreferences = true,
  Future<void> Function()? onFavoriteChanged,
}) async {
  if (resetPreferences) {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
  await getIt.reset();
  final service = _StubNodeSettingsService(
    firstChapter: firstChapter.isEmpty ? _longChapter('甲') : firstChapter,
    secondChapter: secondChapter,
    failFavorite: failFavorite,
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
      onFavoriteChanged: onFavoriteChanged,
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

List<Offset> _toolbarOffsets(WidgetTester tester) {
  return tester
      .widgetList<AnimatedSlide>(find.byType(AnimatedSlide))
      .map((slide) => slide.offset)
      .toList();
}

final _readerGestures = find.byKey(
  const ValueKey<String>('remote-reader-gestures'),
);

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

    await tester.drag(_readerGestures, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(_currentPage(tester), 3);

    await tester.drag(_readerGestures, const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(_currentPage(tester), 2);
  });

  testWidgets('上下滑动不切换沉浸工具栏，也不翻页', (tester) async {
    await _mountReader(tester);
    final offsets = _toolbarOffsets(tester);
    final page = _currentPage(tester);

    await tester.drag(_readerGestures, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(_toolbarOffsets(tester), offsets);
    expect(_currentPage(tester), page);

    await tester.drag(_readerGestures, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(_toolbarOffsets(tester), offsets);
    expect(_currentPage(tester), page);
  });

  testWidgets('沉浸工具栏切换不改变分页、当前页与正文', (tester) async {
    await _mountReader(tester);
    final totalPages = _totalPages(tester);
    final currentPage = _currentPage(tester);
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data;

    await _tapReader(tester, _phoneSize.width / 2);
    expect(_toolbarOffsets(tester).any((offset) => offset.dy != 0), isTrue);
    expect(_totalPages(tester), totalPages);
    expect(_currentPage(tester), currentPage);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText).first).data,
      text,
    );

    await _tapReader(tester, _phoneSize.width / 2);
    expect(_toolbarOffsets(tester), everyElement(Offset.zero));
    expect(_totalPages(tester), totalPages);
    expect(_currentPage(tester), currentPage);
  });

  testWidgets('拖动时页面跟手位移，末页继续滑动切下一章', (tester) async {
    final service = await _mountReader(tester);
    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey<String>('remote-reader-pages')),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(_readerGestures),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    final controller = pageView.controller!;
    expect(controller.page, greaterThan(0.0));
    expect(controller.page, lessThan(1.0));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_currentPage(tester), 2);

    final pages = _totalPages(tester);
    for (var i = _currentPage(tester); i < pages; i++) {
      await _tapReader(tester, _phoneSize.width * 0.9);
    }
    expect(_currentPage(tester), pages);

    await tester.drag(_readerGestures, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(service.chapterRequests.last, 1);
    expect(find.text('第二章'), findsOneWidget);
    expect(_currentPage(tester), 1);

    await tester.drag(_readerGestures, const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(service.chapterRequests.last, 0);
    expect(find.text('第一章'), findsOneWidget);
    expect(_currentPage(tester), pages);
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

  testWidgets('搜索历史与结果重开保留，悬浮导航可上下切换', (tester) async {
    final service = await _mountReader(tester);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '山间');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('命中一'), findsOneWidget);
    expect(find.text('命中二'), findsOneWidget);

    await tester.tap(find.text('命中一'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reader-search-navigator')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('reader-search-position')),
          )
          .data,
      '1/2',
    );

    await tester.tap(find.byTooltip('下一个搜索结果'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('reader-search-position')),
          )
          .data,
      '2/2',
    );
    expect(_currentPage(tester), greaterThan(1));

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('命中一'), findsOneWidget);
    expect(find.text('命中二'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '山间'), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();

    await unmountPage(tester);
    await _mountReader(tester, resetPreferences: false);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '山间'), findsOneWidget);
    expect(service.searchKeywords, <String>['山间']);
  });

  testWidgets('搜索请求乱序返回时，旧响应不能覆盖新结果', (tester) async {
    final service = await _mountReader(tester);
    final oldRequest = Completer<List<Map<String, dynamic>>>();
    final newRequest = Completer<List<Map<String, dynamic>>>();
    service.searchOverrides['旧词'] = oldRequest;
    service.searchOverrides['新词'] = newRequest;

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '旧词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '新词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    newRequest.complete(<Map<String, dynamic>>[
      <String, dynamic>{
        'chapter_index': 0,
        'chapter_title': '第一章',
        'snippet': '新结果',
        'position': 0,
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);

    oldRequest.complete(<Map<String, dynamic>>[
      <String, dynamic>{
        'chapter_index': 0,
        'chapter_title': '第一章',
        'snippet': '旧结果',
        'position': 0,
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    expect(find.widgetWithText(ActionChip, '新词'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '旧词'), findsNothing);
  });

  testWidgets('HTML 与表情章节按节点字符下标定位搜索命中', (tester) async {
    final before = List.generate(
      80,
      (i) => '<p>😀第${i + 1}段，山间的风穿过竹林。</p>',
    ).join();
    final after = List.generate(
      80,
      (i) => '<p>第${i + 81}段，远处传来脚步声。</p>',
    ).join();
    final html = '<p>$before山间目标$after</p>';
    final clean = html.replaceAll(RegExp(r'<[^>]+>', dotAll: true), '');
    final position = clean.indexOf('山间目标');
    final service = await _mountReader(tester, firstChapter: html);
    service.searchResultsOverride = <Map<String, dynamic>>[
      <String, dynamic>{
        'chapter_index': 0,
        'chapter_title': '第一章',
        'snippet': '命中目标',
        'position': position,
      },
    ];

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '山间目标');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('命中目标'));
    await tester.pumpAndSettle();

    final pages = _totalPages(tester);
    final fraction = position / clean.runes.length;
    final expected = (fraction * (pages - 1)).round();
    expect(_currentPage(tester), inInclusiveRange(expected, expected + 1));
    expect(_currentPage(tester), greaterThan(1));
  });

  testWidgets('连续跳转搜索结果时，旧章节响应不能覆盖新章节', (tester) async {
    final service = await _mountReader(tester);
    final first = Completer<String>();
    final second = Completer<String>();
    service.chapterOverrides[0] = first;
    service.chapterOverrides[1] = second;
    service.secondResultChapter = 1;

    Future<void> pumpFrames() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Future<void> openResults() async {
      await tester.tap(find.byTooltip('搜索'));
      await pumpFrames();
      await tester.enterText(find.byType(TextField), '山间');
      await tester.tap(find.text('搜索'));
      await pumpFrames();
    }

    await openResults();
    await tester.tap(find.text('命中一'));
    await pumpFrames();
    await openResults();
    await tester.tap(find.text('命中二'));
    await pumpFrames();

    second.complete('第二章正文很短。');
    await pumpFrames();
    expect(find.text('第二章'), findsOneWidget);

    first.complete(_longChapter('旧响应'));
    await pumpFrames();
    expect(find.text('第二章'), findsOneWidget);
    expect(service.progressWrites, <double>[0.5]);
  });

  testWidgets('远程收藏立即播放动画，成功后通知书库刷新', (tester) async {
    var refreshes = 0;
    final service = await _mountReader(
      tester,
      onFavoriteChanged: () async {
        refreshes++;
      },
    );
    expect(
      find.descendant(
        of: find.byTooltip('收藏'),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();

    expect(service.favoriteWrites, <bool>[true]);
    expect(refreshes, 1);
    expect(find.byTooltip('取消收藏'), findsOneWidget);
  });

  testWidgets('远程收藏失败回滚图标并显示错误', (tester) async {
    final service = await _mountReader(tester, failFavorite: true);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();

    expect(service.favoriteWrites, <bool>[true]);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.textContaining('收藏操作失败'), findsOneWidget);
  });

  testWidgets('翻页立即保存进度，重新打开恢复到同一页', (tester) async {
    final service = await _mountReader(tester);
    final initial = _currentPage(tester);
    await _tapReader(tester, _phoneSize.width * 0.9);
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.progressWrites.last, greaterThan(0));
    await unmountPage(tester);
    final saved = service.progressWrites.last;

    await _mountReader(tester, progress: saved, resetPreferences: false);
    expect(_currentPage(tester), initial + 1);
  });

  testWidgets('单页章节保存章节起点，不跳到下一章', (tester) async {
    final service = await _mountReader(tester);
    await tester.tap(find.byTooltip('章节列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();
    await unmountPage(tester);

    expect(service.progressWrites.last, 0.5);
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
    this.failFavorite = false,
  });

  final String firstChapter;
  final String secondChapter;
  final bool failFavorite;
  final List<int> chapterRequests = <int>[];
  final List<double> progressWrites = <double>[];
  final List<bool> favoriteWrites = <bool>[];
  final List<String> searchKeywords = <String>[];
  int secondResultChapter = 0;
  List<Map<String, dynamic>>? searchResultsOverride;
  final Map<String, Completer<List<Map<String, dynamic>>>> searchOverrides =
      <String, Completer<List<Map<String, dynamic>>>>{};
  final Map<int, Completer<String>> chapterOverrides =
      <int, Completer<String>>{};

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
    final pending = chapterOverrides[chapterIndex];
    if (pending != null) return pending.future;
    return chapterIndex == 0 ? firstChapter : secondChapter;
  }

  @override
  Future<List<Map<String, dynamic>>> searchInNodeNovel({
    required String nodeId,
    required String filePath,
    required String keyword,
  }) async {
    searchKeywords.add(keyword);
    final pending = searchOverrides[keyword];
    if (pending != null) return pending.future;
    if (searchResultsOverride != null) return searchResultsOverride!;
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'chapter_index': 0,
        'chapter_title': '第一章',
        'snippet': '命中一',
        'position': 0,
      },
      <String, dynamic>{
        'chapter_index': secondResultChapter,
        'chapter_title': '第二章',
        'snippet': '命中二',
        'position': firstChapter.length ~/ 2,
      },
    ];
  }

  @override
  Future<void> setNodeNovelFavorite({
    required String nodeId,
    required String novelId,
    required bool isFavorite,
  }) async {
    favoriteWrites.add(isFavorite);
    if (failFavorite) throw StateError('节点离线');
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
