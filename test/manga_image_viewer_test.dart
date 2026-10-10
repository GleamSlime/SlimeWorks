import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/pages/manga/components/image_viewer/manga_image_viewer_page.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';

import 'helpers/page_golden.dart';

/// 图片字节桩：不碰网络也不碰 FFI，任何取字节的请求都回同一张 1x1 PNG
class _StubMangaService implements MangaService {
  @override
  Future<Uint8List> fetchImageBytes(MangaImage image) async => _pngBytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 1x1 透明 PNG
final _pngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

List<MangaPage> _pages(int count) => [
  for (int i = 0; i < count; i++)
    MangaPage(
      id: 'p$i',
      media: MangaImage(
        originalName: 'page$i.png',
        path: 'p$i.png',
        fileServer: 's',
      ),
    ),
];

/// 宿主页：与阅读器一样用 fade+scale 的 PageRouteBuilder 把预览页推上去
class _PushHost extends StatefulWidget {
  const _PushHost({
    required this.pages,
    required this.initialIndex,
    this.chapterTitle = '',
  });

  final List<MangaPage> pages;
  final int initialIndex;
  final String chapterTitle;

  @override
  State<_PushHost> createState() => _PushHostState();
}

class _PushHostState extends State<_PushHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    final route = PageRouteBuilder<void>(
      opaque: true,
      barrierColor: AppSemantic.of(context).scrim,
      pageBuilder: (_, _, _) => MangaImageViewerPage(
        pages: widget.pages,
        initialIndex: widget.initialIndex,
        chapterTitle: widget.chapterTitle,
      ),
      transitionDuration: AppMotion.slow,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.accelerate),
        child: ScaleTransition(
          scale: Tween(begin: AppMotion.scaleStage, end: 1.0)
              .animate(CurvedAnimation(parent: animation, curve: AppMotion.decelerate)),
          child: child,
        ),
      ),
    );
    Navigator.of(context, rootNavigator: true).push(route);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _openViewer(
  WidgetTester tester, {
  required List<MangaPage> pages,
  int initialIndex = 0,
  String chapterTitle = '',
}) async {
  await pumpAppPage(
    tester,
    _PushHost(pages: pages, initialIndex: initialIndex, chapterTitle: chapterTitle),
  );
  await _settle(tester);
}

/// 推进到稳定态
///
/// 不能用 pumpAndSettle：加载进度环是持续动画，会一直转下去把测试挂死。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 当前停在第几页：顶栏标题在无章节名时就是一页一个的文件名
String _currentPage(WidgetTester tester) =>
    tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.startsWith('page'));

/// 页码浮层的"当前页 / 总数"
String _chipText(WidgetTester tester) {
  final nums = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((t) => RegExp(r'^\s*\d+\s*$').hasMatch(t) || RegExp(r'^\s*/\s*\d+\s*$').hasMatch(t))
      .toList();
  return '${nums[0].trim()}${nums[1].trim()}'.replaceAll(' ', '');
}

/// 预览画面中心
Offset _center(WidgetTester tester) =>
    tester.getCenter(find.byType(MangaImageViewerPage).first);

/// 派发一次滚轮事件（dy<0 = 向上滚）。Ctrl 档用于放大，裸滚轮是翻页。
Future<void> _wheel(WidgetTester tester, double dy, {bool ctrl = false}) async {
  if (ctrl) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      device: 1,
      position: _center(tester),
      scrollDelta: Offset(0, dy),
    ),
  );
  await _settle(tester);
  if (ctrl) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    getIt.registerSingleton<MangaService>(_StubMangaService());
  });

  tearDownAll(() {
    getIt.unregister<MangaService>();
  });

  group('漫画页放大预览', () {
    testWidgets('打开就落在点的那一页，并渲染取回的字节', (tester) async {
      await _openViewer(tester, pages: _pages(5), initialIndex: 2);

      expect(_currentPage(tester), 'page2.png');
      expect(_chipText(tester), '3/5');
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('顶栏标题带章节名与该页文件名', (tester) async {
      await _openViewer(
        tester,
        pages: _pages(2),
        initialIndex: 1,
        chapterTitle: '第 1 话',
      );

      expect(find.text('第 1 话 · page1.png'), findsOneWidget);
    });

    testWidgets('方向键翻页：上下走垂直轴、左右走水平轴', (tester) async {
      await _openViewer(tester, pages: _pages(4), initialIndex: 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      expect(_currentPage(tester), 'page1.png');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(_currentPage(tester), 'page2.png');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _settle(tester);
      expect(_currentPage(tester), 'page1.png');
    });

    testWidgets('首尾不越界：第一页往前翻仍是第一页', (tester) async {
      await _openViewer(tester, pages: _pages(3), initialIndex: 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _settle(tester);
      expect(_currentPage(tester), 'page0.png');
      expect(_chipText(tester), '1/3');
    });

    testWidgets('滚轮向上滚是翻回上一页，不是缩放', (tester) async {
      await _openViewer(tester, pages: _pages(4), initialIndex: 2);

      await _wheel(tester, -120);
      expect(_currentPage(tester), 'page1.png');
      expect(find.text('重置缩放'), findsNothing);
    });

    testWidgets('Ctrl+滚轮放大出「重置缩放」，双击复原', (tester) async {
      await _openViewer(tester, pages: _pages(3), initialIndex: 0);
      expect(find.text('重置缩放'), findsNothing);

      await _wheel(tester, -120, ctrl: true);
      expect(find.text('重置缩放'), findsOneWidget);

      // 两下必须落在双击窗口内（300ms），隔太久就变成两次单击
      await tester.tapAt(_center(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_center(tester));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('重置缩放'), findsNothing);
    });

    testWidgets('Esc 退出预览', (tester) async {
      await _openViewer(tester, pages: _pages(3), initialIndex: 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(MangaImageViewerPage), findsNothing);
    });

    testWidgets('左上返回按钮退出预览', (tester) async {
      await _openViewer(tester, pages: _pages(3), initialIndex: 1);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await _settle(tester);
      expect(find.byType(MangaImageViewerPage), findsNothing);
    });
  });
}
