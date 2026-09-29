import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';

// 一次性出图脚本（跑完即删）：把伪封面开启后的卡片渲染成 PNG 供肉眼验收
final List<int> _red = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('出图', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    ScreenUtil.init(
      tester.element(find.byType(MaterialApp)),
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
    );
    final dir = await Directory.systemTemp.createTemp('shot');
    final real = '${dir.path}/real.png';
    File(real).writeAsBytesSync(_red);
    final prefs = MediaPrefsService();
    prefs.fakeCover.value = true;
    GetIt.instance.registerSingleton<MediaPrefsService>(prefs);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: SizedBox(
                width: 440,
                height: 300,
                child: MediaCardCover(
                  source: real,
                  placeholderIcon: StrokeIcons.lockOutline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('H:/SlimeWorks/build/fake-cover-shot.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
    GetIt.instance.reset();
    dir.deleteSync(recursive: true);
  });
}
