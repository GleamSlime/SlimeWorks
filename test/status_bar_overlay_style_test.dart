// 移动端系统状态栏配色回归测试
//
// 症状：亮色主题下状态栏的时间/电量图标还是白色，糊在浅色页面上看不清。
// 成因：本项目两套主题的 AppBar 底色都是 transparent，而 AppBar 没显式指定
// systemOverlayStyle 时，会用 `estimateBrightnessForColor(底色亮度)` 去猜图标
// 颜色——透明色亮度为 0，于是被当成深色背景，明暗两档统统发白色图标。
// 修复：把状态栏配色钉进 AppBarTheme，随主题明暗切换。这条约束由本文件守住。
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';

import 'helpers/page_golden.dart';

void main() {
  testWidgets('亮色主题：状态栏图标压黑、底色假设浅色', (tester) async {
    final style = await _statusBarStyle(tester, dark: false);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
  });

  testWidgets('暗色主题：状态栏图标提白、底色假设深色', (tester) async {
    final style = await _statusBarStyle(tester, dark: true);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });

  testWidgets('移动端顶栏与底栏使用比书库底色稍亮的纯色且无投影', (tester) async {
    final light = AppTheme.mobileChromeColor(false);
    final dark = AppTheme.mobileChromeColor(true);
    expect(
      light.computeLuminance(),
      greaterThan(AppSurfaces.lightCanvas.computeLuminance()),
    );
    expect(
      dark.computeLuminance(),
      greaterThan(AppSurfaces.darkCanvas.computeLuminance()),
    );

    final chrome = File(
      'lib/components/window/screen_chrome.dart',
    ).readAsStringSync();
    expect(
      chrome.contains('backgroundColor: AppTheme.mobileChromeColor'),
      isTrue,
    );
    expect(chrome.contains('shadowColor: Colors.transparent'), isTrue);
    expect(chrome.contains('elevation: 0'), isTrue);
    final ledger = File(
      'lib/pages/ledger/components/ledger_shared.dart',
    ).readAsStringSync();
    expect(
      ledger.contains('color: AppTheme.mobileChromeColor(s.isDark)'),
      isTrue,
    );
  });

  testWidgets('主题里的 AppBar 底色仍是透明（钉图标不能顺手改底色）', (tester) async {
    await pumpAppPage(tester, const SizedBox.shrink(), dark: false);
    final theme = AppTheme.lightTheme;
    expect(theme.appBarTheme.backgroundColor, Colors.transparent);
    expect(
      theme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      AppTheme
          .darkTheme
          .appBarTheme
          .systemOverlayStyle
          ?.statusBarIconBrightness,
      Brightness.light,
    );

    // MaterialApp 实际吃的是套了用户强调色/字号之后的这两份，_applyCustomization
    // 里还有一次 appBarTheme.copyWith，配色不能被那次 copyWith 洗掉。
    expect(
      AppTheme.buildCustomLight(
        AppTheme.kFollowThemeAccent,
        1.2,
      ).appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      AppTheme.buildCustomDark(
        AppTheme.kFollowThemeAccent,
        1.2,
      ).appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );
  });
}

/// 取出 AppBar 真正喂给系统的那份配色
///
/// AppBar 会把 overlay 配色包在 `AnnotatedRegion<SystemUiOverlayStyle>` 里，
/// 框架每帧拿状态栏像素点命中的那份区域去调 `setSystemUIOverlayStyle`，
/// 所以断言这一份才等于断言真机上看到的效果。
Future<SystemUiOverlayStyle> _statusBarStyle(
  WidgetTester tester, {
  required bool dark,
}) async {
  await pumpAppPage(
    tester,
    Scaffold(
      appBar: AppBar(title: const Text('概览')),
      body: const SizedBox.expand(),
    ),
    dark: dark,
  );
  await tester.pumpAndSettle();

  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find.byWidgetPredicate(
      (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
    ),
  );
  return region.value;
}
