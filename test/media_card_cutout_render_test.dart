// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/media_collection_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_folder_card.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/pages/collection/picture/components/smart_folder_card.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

import 'helpers/page_golden.dart';

/// 媒体库镂空卡离屏出图
///
/// 真机要跑进媒体库、凑齐有封面/无封面/丢失/悬停几种状态才拍得全，这里一张
/// PNG 一档状态，改完卡片跑一次就能肉眼验收。
/// `flutter test --update-goldens test/media_card_cutout_render_test.dart`
/// 产出 test/goldens/mc_*.png。
///
/// 一帧一个 test：出过图之后同一 test 里后续的悬停/定时器变更不会再被拍到。
void main() {
  final dirPath = '${Directory.systemTemp.path}/mc_cutout_golden';
  late String warmCover;
  late String coolCover;
  late String altCover;

  setUpAll(() async {
    await loadAppFonts();
    final dir = Directory(dirPath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    // 封面用真文件：镂空接缝只有在真实照片上才看得出对没对齐
    warmCover = await _writeImage('$dirPath/warm', colors: const [_c1, _c2, _c3]);
    coolCover = await _writeImage('$dirPath/cool', colors: const [_c4, _c5, _c6]);
    altCover = await _writeImage('$dirPath/alt', colors: const [_c7, _c8, _c1]);
    // 真机常驻这个服务，出图也一律挂上（不调 init，走字段默认值）
    if (!getIt.isRegistered<MediaPrefsService>()) {
      getIt.registerSingleton<MediaPrefsService>(MediaPrefsService());
    }
  });

  tearDownAll(() {
    AppTheme.fontScaleObs.value = 1.0;
    if (getIt.isRegistered<MediaPrefsService>()) {
      getIt.unregister<MediaPrefsService>();
    }
    final dir = Directory(dirPath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('浏览卡一行：集合 / 文件夹 / 智能文件夹（浅色静止）', (tester) async {
    await _shoot(
      tester,
      name: 'mc_browse_light',
      cards: [_collectionCard(warmCover), _folderCard(warmCover), _smartFolderCard(warmCover)],
    );
  });

  testWidgets('浏览卡一行（深色静止）', (tester) async {
    await _shoot(
      tester,
      name: 'mc_browse_dark',
      dark: true,
      cards: [_collectionCard(warmCover), _folderCard(warmCover), _smartFolderCard(warmCover)],
    );
  });

  testWidgets('集合卡悬停：封面推近 + 翻封面进度条 + 收藏按钮浮出', (tester) async {
    await _mount(
      tester,
      cards: [_collectionCard(warmCover, favorited: true, hoverCovers: [warmCover, coolCover, altCover])],
    );
    final at = tester.getCenter(find.byType(MediaCollectionCard).first);
    final gesture = await _hover(tester, at);
    // 悬停 3s 才进预览态，按 30ms 一档推过阈值
    await advance(tester, steps: 120);
    await _flushRealIo(tester);
    await advance(tester, steps: 8);
    await _capture(tester, 'mc_collection_hover');
    await _moveAway(tester, gesture);
  });

  testWidgets('集合卡选中态（accent 描边）', (tester) async {
    await _mount(tester, cards: [_collectionCard(warmCover, selected: true)]);
    await _capture(tester, 'mc_collection_selected');
  });

  testWidgets('集合卡丢失态（占位图标 + 丢失徽标）', (tester) async {
    await _mount(tester, cards: [_collectionCard(warmCover, lost: true)]);
    await _capture(tester, 'mc_collection_lost');
  });

  testWidgets('集合卡无封面（空图区 + 居中图标）', (tester) async {
    await _mount(tester, cards: [_collectionCard(warmCover, noCover: true)]);
    await _capture(tester, 'mc_collection_nocover');
  });

  testWidgets('远程集合卡 + 已收藏常驻按钮', (tester) async {
    await _mount(tester, cards: [_collectionCard(warmCover, remote: true, favorited: true)]);
    await _capture(tester, 'mc_collection_remote');
  });

  testWidgets('资源卡一行：图片 / 视频 / 丢失（浅色静止）', (tester) async {
    await _shoot(
      tester,
      name: 'mc_item_light',
      withFoot: false,
      cards: [
        _itemTile(kind: media_api.MediaKind.image, source: warmCover, width: 3840, height: 2160),
        _itemTile(
          kind: media_api.MediaKind.video,
          source: coolCover,
          durationMs: BigInt.from(3725000),
          width: 1920,
          height: 1080,
        ),
        _itemTile(kind: media_api.MediaKind.video, source: altCover, lost: true),
      ],
    );
  });

  testWidgets('资源卡一行（深色静止）', (tester) async {
    await _shoot(
      tester,
      name: 'mc_item_dark',
      dark: true,
      withFoot: false,
      cards: [
        _itemTile(kind: media_api.MediaKind.image, source: warmCover, width: 3840, height: 2160),
        _itemTile(
          kind: media_api.MediaKind.video,
          source: coolCover,
          durationMs: BigInt.from(3725000),
          width: 1920,
          height: 1080,
        ),
        _itemTile(kind: media_api.MediaKind.video, source: altCover, lost: true),
      ],
    );
  });

  testWidgets('视频资源卡悬停：抽帧切换 + 底部进度条', (tester) async {
    await _mount(
      tester,
      withFoot: false,
      cards: [
        _itemTile(
          kind: media_api.MediaKind.video,
          source: coolCover,
          durationMs: BigInt.from(3725000),
          scrubFrames: [warmCover, altCover, coolCover],
        ),
      ],
    );
    final rect = tester.getRect(find.byType(MediaItemTile).first);
    // 停在 60% 处：抽帧索引和进度条读数都应跟着这个位置
    final gesture = await _hover(tester, Offset(rect.left + rect.width * 0.6, rect.center.dy));
    await advance(tester, steps: 8);
    await _flushRealIo(tester);
    await advance(tester, steps: 8);
    await _capture(tester, 'mc_item_video_hover');
    await _moveAway(tester, gesture);
  });

  testWidgets('隐私模式：封面打码 + 居中锁标', (tester) async {
    getIt<MediaPrefsService>().privacyMode.value = true;
    addTearDown(() => getIt<MediaPrefsService>().privacyMode.value = false);
    await _mount(tester, cards: [_itemTile(kind: media_api.MediaKind.image, source: warmCover)]);
    await _capture(tester, 'mc_item_privacy');
  });

  testWidgets('关掉叠加信息：图上不留空标签', (tester) async {
    await _mount(
      tester,
      withFoot: false,
      cards: [
        _itemTile(
          kind: media_api.MediaKind.video,
          source: warmCover,
          durationMs: BigInt.from(260000),
          showOverlay: false,
        ),
      ],
    );
    await _capture(tester, 'mc_item_overlay_off');
  });

  testWidgets('字号放大 1.5× 时文字区不被挤出', (tester) async {
    // 文字区高度吃字号族：字号档拉满后卡片总高跟着长，正文不会被挤出格子
    AppTheme.fontScaleObs.value = 1.5;
    addTearDown(() => AppTheme.fontScaleObs.value = 1.0);
    await _mount(tester, cards: [_collectionCard(warmCover)]);
    await _capture(tester, 'mc_browse_fontscale');
  });

  testWidgets('几何自证：封面严格 1.5 横幅、正文不被页脚挤掉、封面真的解出来了', (tester) async {
    await _mount(tester, cards: [_collectionCard(warmCover)]);
    final card = tester.getRect(find.byType(MediaCutoutCard).first);
    final body = tester.getRect(find.text('/Users/shilaimu/Movies/黄昏城市实拍集'));
    final foot = tester.getRect(find.text('本机'));
    // 网格按 aspectFor 反推高度，排出来的封面段必须还是 1.5，否则网格和卡片不同源
    expect(
      card.width / (card.height - MediaCutoutGeometry.contentExtent()),
      closeTo(MediaCutoutGeometry.mediaRatio, 0.01),
    );
    // 正文底边落在页脚上方那道间隔之内 = 两行没被裁
    expect(body.bottom, lessThanOrEqualTo(foot.top - appMetrics.kSpace10 + 1));
    for (final element in find.byType(RawImage).evaluate()) {
      expect((element.widget as RawImage).image, isNotNull, reason: '封面未解码，出图等于没拍到图');
    }
    // debug 徽标只许报真实解码尺寸：曾经它对远程源发 HEAD 取 Content-Length，
    // 而节点 /node/media 只路由 GET，于是每张卡都报那枚 404 响应体的长度（恒定 37B）
    final decoded = (find.byType(RawImage).evaluate().first.widget as RawImage).image!;
    expect(find.text('${decoded.width}×${decoded.height}'), findsWidgets,
        reason: '徽标数字与解码尺寸不符 = 又在报某个响应头，不是图本身');
  });
}

// ── 出图铺垫 ──────────────────────────────────────────────────────────────

/// 真机桌面档的设计稿尺寸：窗口 1440×900 折出 scaleW 系数 0.75
const _designSize = Size(1920, 1080);

Future<void> _mount(
  WidgetTester tester, {
  required List<Widget> cards,
  bool dark = false,
  bool withFoot = true,
}) async {
  getIt<MediaPrefsService>().privacyMode.value = false;
  await pumpAppPage(
    tester,
    Center(child: _CardRow(cards: cards, withFoot: withFoot)),
    dark: dark,
    designSize: _designSize,
  );
  await tester.pump();
  await _flushRealIo(tester);
  await advance(tester);
}

Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required List<Widget> cards,
  bool dark = false,
  bool withFoot = true,
}) async {
  await _mount(tester, cards: cards, dark: dark, withFoot: withFoot);
  await _capture(tester, name);
}

/// 图片解码走真实 I/O，假异步里推不到
///
/// 读文件、解码头、回调落帧各要一次真实事件循环 + 一次 pump，实测要 5 轮上下
/// 才见得到帧；这里一路推到树里没有待解码的图为止。
Future<void> _flushRealIo(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 16));
    final images = find.byType(RawImage).evaluate();
    if (images.isNotEmpty && images.every((e) => (e.widget as RawImage).image != null)) {
      return;
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await expectLater(find.byType(_CardRow), matchesGoldenFile('goldens/$name.png'));
  expect(tester.takeException(), isNull);
  await unmountPage(tester);
}

Future<TestGesture> _hover(WidgetTester tester, Offset at) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(at);
  await tester.pump();
  return gesture;
}

Future<void> _moveAway(WidgetTester tester, TestGesture gesture) async {
  await gesture.moveTo(const Offset(4, 4));
  await tester.pump();
  await gesture.removePointer();
}

/// 一排卡片：宽高和网格发给卡片的两条约束一致，溢出一眼能看见
///
/// 出图按这个 Widget 的边界裁，所以留白必须算在它自己身上（外层 Padding
/// 不属于它的 bounds，投影会被裁掉一截）。
class _CardRow extends StatelessWidget {
  const _CardRow({required this.cards, required this.withFoot});

  final List<Widget> cards;

  /// 资源卡不带页脚，文字区矮一截，格子高度跟着走
  final bool withFoot;

  @override
  Widget build(BuildContext context) {
    // ScreenUtil 要进树才初始化，格宽只能在 build 里量
    final cellWidth = MediaCutoutGeometry.maxCellWidth;
    final cellHeight = cellWidth / MediaCutoutGeometry.aspectFor(cellWidth, withFoot: withFoot);
    return Padding(
      padding: EdgeInsets.all(appMetrics.kSpace16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) SizedBox(width: appMetrics.kSpace12),
            SizedBox(width: cellWidth, height: cellHeight, child: card),
          ],
        ],
      ),
    );
  }
}

// ── 卡片夹具 ──────────────────────────────────────────────────────────────

Widget _collectionCard(
  String cover, {
  bool selected = false,
  bool remote = false,
  bool favorited = false,
  bool lost = false,
  bool noCover = false,
  List<String>? hoverCovers,
}) {
  return MediaCollectionCard(
    collection: media_api.MediaCollection(
      id: 'c-1',
      title: remote ? '黄昏城市实拍集' : '黄昏城市实拍作品集',
      folderPath: remote ? '/mnt/nas/media/黄昏城市实拍集' : '/Users/shilaimu/Movies/黄昏城市实拍集',
      itemCount: BigInt.from(128),
      createdAt: 0,
      updatedAt: 0,
    ),
    // lost 时封面文件仍在，卡片靠 isLost 走占位；noCover 走"压根没封面"
    coverSource: noCover ? null : cover,
    isSelected: selected,
    isSelecting: false,
    isRemote: remote,
    nodeName: remote ? 'M2 影音节点' : null,
    resourceCount: 96,
    totalSize: BigInt.from(8123456789),
    isFavorited: favorited,
    isLost: lost,
    hoverCoverSources: hoverCovers,
    onTap: () {},
    onLongPress: () {},
    onRename: () {},
    onDelete: () {},
    onMove: () {},
    onOpenFolder: () {},
    onToggleFavorite: () {},
  );
}

Widget _folderCard(String cover) {
  return MediaFolderCard(
    folder: media_api.MediaFolder(id: 'f-1', name: '2026 春季扫街', createdAt: 0, order: 0),
    coverSource: cover,
    itemCount: 7,
    resourceCount: 214,
    totalSize: BigInt.from(34567890123),
    typeLabel: '文件夹',
    isSelected: false,
    isRemote: false,
    nodeName: null,
    onTap: () {},
    onLongPress: () {},
    onRename: () {},
    onDelete: () {},
  );
}

Widget _smartFolderCard(String cover) {
  return SmartFolderCard(
    smartFolder: SmartFolder(
      id: 's-1',
      name: '4K 视频精选',
      regexPattern: r'^(?!.*_raw).*4k$',
      keywords: const ['4K', 'uhd'],
      regexTarget: SmartFolderRegexTarget.collectionName,
    ),
    matchCount: 12,
    resourceCount: 340,
    totalSize: BigInt.from(118786218393),
    isSelected: false,
    coverSource: cover,
    nodeName: null,
    onTap: () {},
    onLongPress: () {},
    onEdit: () {},
  );
}

Widget _itemTile({
  required media_api.MediaKind kind,
  required String source,
  int? width,
  int? height,
  BigInt? durationMs,
  bool lost = false,
  bool showOverlay = true,
  List<String>? scrubFrames,
}) {
  return MediaItemTile(
    item: media_api.MediaItem(
      id: 'i-${kind.name}-1',
      collectionId: 'c-1',
      title: switch (kind) {
        media_api.MediaKind.image => 'IMG_2087 巷口剪影',
        media_api.MediaKind.video => 'SUNSET_AERIAL_4K 航拍',
        media_api.MediaKind.audio => 'BGM_lofi_loop',
      },
      filePath: switch (kind) {
        media_api.MediaKind.image => '/Users/shilaimu/Movies/IMG_2087.png',
        media_api.MediaKind.video => '/Users/shilaimu/Movies/SUNSET_AERIAL_4K.mp4',
        media_api.MediaKind.audio => '/Users/shilaimu/Music/BGM_lofi_loop.flac',
      },
      kind: kind,
      fileSize: BigInt.from(kind == media_api.MediaKind.image ? 6433792 : 2148853760),
      modifiedAt: 1759200000,
      width: width,
      height: height,
      durationMs: durationMs,
      order: 0,
    ),
    source: source,
    isLost: lost,
    showOverlay: showOverlay,
    onRequestScrubFrames: scrubFrames == null ? null : () async => scrubFrames,
    onTap: () {},
  );
}

// ── 合成封面 ──────────────────────────────────────────────────────────────

const _c1 = Color(0xFF2B3A67);
const _c2 = Color(0xFFE8A02C);
const _c3 = Color(0xFFD1495B);
const _c4 = Color(0xFF1B5E4B);
const _c5 = Color(0xFFA7C4A0);
const _c6 = Color(0xFF3A5A40);
const _c7 = Color(0xFF6D597A);
const _c8 = Color(0xFFE56B6F);

/// 画一张带硬边的渐变图：接缝错位、缩放抖动在这类图上一眼能看出来
Future<String> _writeImage(String stem, {required List<Color> colors, Size size = const Size(640, 427)}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, size.width, size.height);
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width, size.height),
        colors,
        List.generate(colors.length, (i) => i / (colors.length - 1)),
      ),
  );
  // 左下和右上各留一条高对比横带：两块镂空标签的垫角正压在这两处
  final band = ui.Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(Rect.fromLTWH(0, size.height - 90, size.width * 0.45, 26), band);
  canvas.drawRect(Rect.fromLTWH(size.width * 0.55, 0, size.width * 0.45, 22), band);
  final grid = ui.Paint()
    ..color = const Color(0x33000000)
    ..strokeWidth = 2;
  for (var x = 0.0; x < size.width; x += 64) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
  for (var y = 0.0; y < size.height; y += 64) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
  }
  final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$stem.png');
  file.writeAsBytesSync(data!.buffer.asUint8List());
  return file.path;
}
