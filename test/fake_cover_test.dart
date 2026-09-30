import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';

/// 一张 1x1 的 PNG，够 Image 解码成功，又不用真准备两张不同的图
final List<int> _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 顺着 ResizeImage 往里剥，拿到最终那张本地图片的路径
String? _fileOf(ImageProvider<Object> provider) {
  if (provider is ResizeImage) return _fileOf(provider.imageProvider);
  if (provider is FileImage) return provider.file.path;
  return null;
}

/// 卡片上实际挂出来的所有本地图片路径
List<String> _shownFiles(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => _fileOf(i.image))
    .whereType<String>()
    .toList();

void main() {
  late Directory dir;
  late String realPath;
  late String fakePath;
  late MediaPrefsService prefs;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('fake_cover_test');
    realPath = '${dir.path}/real.png';
    fakePath = '${dir.path}/fake.png';
    File(realPath).writeAsBytesSync(_png);
    File(fakePath).writeAsBytesSync(_png);
  });

  setUp(() {
    prefs = MediaPrefsService();
    prefs.fakeCoverPath.value = fakePath;
    GetIt.instance.registerSingleton<MediaPrefsService>(prefs);
  });

  tearDown(() => GetIt.instance.reset());

  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<void> pumpCover(WidgetTester tester) async {
    // 先挂一个空壳把 ScreenUtil 初始化好：debug 徽标那条分支会取 appMetrics，
    // 而 ThemeMetrics 要求 ScreenUtil 已经拿到屏幕尺寸。
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    ScreenUtil.init(
      tester.element(find.byType(MaterialApp)),
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 150,
            child: MediaCardCover(
              source: realPath,
              placeholderIcon: StrokeIcons.lockOutline,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('伪封面关闭：封面照常解码真实图片', (tester) async {
    await pumpCover(tester);
    expect(_shownFiles(tester), contains(realPath));
    expect(_shownFiles(tester), isNot(contains(fakePath)));
  });

  testWidgets('伪封面开启：真实封面被顶掉，连解码都不参与', (tester) async {
    prefs.fakeCover.value = true;
    await pumpCover(tester);
    expect(_shownFiles(tester), contains(fakePath));
    expect(_shownFiles(tester), isNot(contains(realPath)));
  });

  testWidgets('隐私模式 + 伪封面同时开启：伪封面优先，不走高斯模糊', (tester) async {
    prefs.privacyMode.value = true;
    prefs.fakeCover.value = true;
    await pumpCover(tester);
    expect(_shownFiles(tester), contains(fakePath));
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('伪封面图片读不到：退成纯色底，不回落到真实封面', (tester) async {
    prefs.fakeCover.value = true;
    prefs.fakeCoverPath.value = '${dir.path}/missing.png';
    await pumpCover(tester);
    expect(_shownFiles(tester), isNot(contains(realPath)));
  });
}
