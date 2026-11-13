// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/components/window/sidebar_resize_handle.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/style_showcase_screen.dart';

/// 样式总览页的离屏渲染
///
/// 令牌层（色彩角色 / 圆角 / 阴影 / 字号）改一处就会牵动整页排版，
/// 靠肉眼在 macOS 窗口里翻页不现实。这里把明暗两版一次性截下来做像素对照。
///
/// 字体由 flutter_test_config.dart 的全局 setUpAll 统一载入，这里不再各加载一遍。
void main() {
  testWidgets('明暗双版并排：整套组件一次性出图', (tester) async {
    // 两块 720 面板 + 24 间距 + 24 外边距；外壳行 800 + 控制台行 1040
    tester.view.physicalSize = const Size(1512, 1912);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_showcase());
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

    await tester.pumpWidget(_showcase());
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

/// 页面 build 第一行就读 AppTheme.metrics，而度量是按 ScreenUtil 折算的：
/// 不先 ScreenUtilInit 把 _data 配上，第一帧就抛 LateInitializationError。
/// designSize 取窗口实际尺寸，系数为 1，定宽面板的排版才可复现。
Widget _showcase() {
  return ScreenUtilInit(
    designSize: const Size(1512, 1912),
    minTextAdapt: true,
    splitScreenMode: false,
    builder: (context, _) {
      AppTheme.resetMetrics();
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const StyleShowcaseScreen(),
      );
    },
  );
}