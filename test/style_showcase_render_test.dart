// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/components/window/sidebar_resize_handle.dart';
import 'package:slime_works/pages/style_showcase_screen.dart';

/// 样式总览页的离屏渲染
///
/// 令牌层（色彩角色 / 圆角 / 阴影 / 字号）改一处就会牵动整页排版，
/// 靠肉眼在 macOS 窗口里翻页不现实。这里把明暗两版一次性截下来做像素对照。
void main() {
  setUpAll(() async {
    final fonts = <String, String>{'Inter': 'assets/fonts/Inter-Regular.ttf'};
    final iconFont = _materialIconsPath();
    if (iconFont != null) fonts['MaterialIcons'] = iconFont;
    for (final entry in fonts.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
    }
  });

  testWidgets('明暗双版并排：整套组件一次性出图', (tester) async {
    // 两块 720 面板 + 24 间距 + 24 外边距；外壳行 800 + 控制台行 1040
    tester.view.physicalSize = const Size(1512, 1912);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const StyleShowcaseScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(StyleShowcaseScreen),
      matchesGoldenFile('goldens/style_showcase.png'),
    );
  });

  testWidgets('点把手：同一条侧栏收成图标态', (tester) async {
    tester.view.physicalSize = const Size(1512, 1912);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const StyleShowcaseScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // 两块面板各点一下，明暗两版一起进收起态。
    // 动画要一小步一小步推进：一次 pump 到位只会渲染终态，途中那些窄宽度
    // 根本没排过版，溢出这类问题就藏住了
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(SidebarResizeHandle).at(i));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(StyleShowcaseScreen),
      matchesGoldenFile('goldens/style_showcase_collapsed.png'),
    );

    // 再点回来：展开途中容器只有几十像素宽，标签提前进来就会溢出
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(SidebarResizeHandle).at(i));
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
  });
}

/// 测试进程里图标字体默认不加载，全是方框，排版根本没法验收。
/// FLUTTER_ROOT 在部分 shell 下为空，再从 dart-sdk 可执行路径回溯一层兜底。
String? _materialIconsPath() {
  final candidates = <String>[
    for (final root in [
      Platform.environment['FLUTTER_ROOT'] ?? '',
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.absolute.path,
    ])
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
