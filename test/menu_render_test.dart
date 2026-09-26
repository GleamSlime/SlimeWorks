// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/widgets/glass_menu.dart';

import 'helpers/page_golden.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 弹出菜单的离屏渲染
///
/// 主题里的 popupMenuTheme 只作用在真菜单上（Route 里的 Material + 项行），
/// 设计系统总览那种静态拼块看不出效果。这里真的把 PopupMenuButton 点开，
/// 再把整窗截图存成 golden：改一次菜单主题就能看到，不必启 macOS 应用。
void main() {
  setUpAll(() async {
    // 中文、图标字形都要真字体才看得出对齐，铺垫统一走 helper
    await loadAppFonts();
  });

  testWidgets('浅色菜单：紧凑行高 + 图标槽 + 选中/危险态 + 悬停水洗', (tester) async {
    await _renderMenu(tester, dark: false, file: 'goldens/menu_light.png');
  });

  testWidgets('深色菜单：同一套口径', (tester) async {
    await _renderMenu(tester, dark: true, file: 'goldens/menu_dark.png');
  });
}

Future<void> _renderMenu(
  WidgetTester tester, {
  required bool dark,
  required String file,
}) async {
  tester.view.physicalSize = const Size(520, 420);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(520, 420),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, _) {
        AppTheme.resetMetrics();
        final theme = dark
            ? AppTheme.buildCustomDark(AppTheme.kFollowThemeAccent, 1.0)
            : AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0);
        final semantic = dark ? AppSemantic.dark : AppSemantic.light;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            backgroundColor: semantic.canvas,
            body: Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
              child: Align(
                alignment: Alignment.topLeft,
                child: PopupMenuButton<String>(
                  position: PopupMenuPosition.under,
                  itemBuilder: (_) => [
                    GlassMenuItem<String>(
                      value: 'mtime',
                      label: '按修改时间',
                      icon: StrokeIcons.schedule,
                      selected: true,
                    ),
                    GlassMenuItem<String>(
                      value: 'name',
                      label: '按文件名',
                      icon: StrokeIcons.sortByAlpha,
                    ),
                    GlassMenuItem<String>(
                      value: 'pin',
                      label: '固定到侧边栏',
                      icon: StrokeIcons.pushPin,
                    ),
                    const PopupMenuDivider(),
                    GlassMenuItem<String>(
                      value: 'delete',
                      label: '从库中移除',
                      icon: StrokeIcons.deleteOutline,
                      destructive: true,
                    ),
                    GlassMenuItem<String>(
                      value: 'none',
                      label: '已禁用项',
                      icon: StrokeIcons.block,
                      enabled: false,
                    ),
                  ],
                  child: const Text('排序方式'),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('排序方式'));
  await tester.pumpAndSettle();

  // 用鼠标指针悬停第二项：状态层必须是"水洗"，实心色会在磨砂上打洞。
  // createGesture 返回的是 Future<TestGesture>，不 await 后续方法全在 Future 上找。
  final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await hover.addPointer();
  await hover.moveTo(tester.getCenter(find.text('按文件名')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
  await hover.removePointer();
}
