import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_theme.dart';

// 主题文字档是否跟着用户字号滑杆走
//
// 规则：任何浮在内容之上、需要与正文/卡片同档的主题文字（菜单、输入框 hint/label）
// 必须取 AppTheme.metrics.fontSizeNN——它内含 fontScaleObs；裸 scaleS(N) 只乘屏幕
// 自适应系数，字号滑杆一拉就比它服务的内容小一圈。
// 踩过的坑：右键菜单 labelTextStyle 写的是 scaleS(13)，而卡片标题是 metrics.fontSize13，
// 滑杆不在 1.0 时菜单就和它弹出的那张卡对不上。

const Size _kWindowSize = Size(1440, 900);

/// 以给定字号档位重建 metrics 与主题（顺序与真机换字号时一致：先滑杆值，再 resetMetrics）。
Future<({ThemeData theme, ThemeMetrics metrics})> _rebuildAt(
  WidgetTester tester,
  double fontScale,
) async {
  tester.view.physicalSize = _kWindowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  AppTheme.fontScaleObs.value = fontScale;
  late ThemeData theme;
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: _kWindowSize,
      minTextAdapt: true,
      builder: (context, _) {
        AppTheme.resetMetrics();
        theme = AppTheme.buildCustomDark(AppTheme.kFollowThemeAccent, fontScale);
        return MaterialApp(theme: theme, home: const SizedBox.shrink());
      },
    ),
  );
  return (theme: theme, metrics: AppTheme.metrics);
}

double? _menuFontSize(ThemeData theme) =>
    theme.popupMenuTheme.labelTextStyle?.resolve({})?.fontSize;

void main() {
  tearDown(() => AppTheme.fontScaleObs.value = 1.0);

  group('主题文字与用户字号同源', () {
    testWidgets('右键菜单与卡片标题同档', (tester) async {
      final r = await _rebuildAt(tester, 1.5);
      expect(_menuFontSize(r.theme), r.metrics.fontSize13);
    });

    testWidgets('右键菜单随字号滑杆同比缩放', (tester) async {
      final base = _menuFontSize((await _rebuildAt(tester, 1.0)).theme)!;
      final scaled = _menuFontSize((await _rebuildAt(tester, 1.5)).theme)!;
      expect(scaled / base, closeTo(1.5, 0.02));
    });

    testWidgets('输入框 hint 随字号滑杆同比缩放', (tester) async {
      final base = (await _rebuildAt(tester, 1.0)).theme.inputDecorationTheme.hintStyle!.fontSize!;
      final scaled =
          (await _rebuildAt(tester, 1.5)).theme.inputDecorationTheme.hintStyle!.fontSize!;
      expect(scaled / base, closeTo(1.5, 0.02));
    });
  });
}
