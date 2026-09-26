import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

import 'helpers/page_golden.dart';

// 收起态图标条的宽度不变量
//
// 图标条只有 75 设计像素宽，一层层 padding 剥完只剩 30 出头，而图标原先走的是
// 字号族（scaleS，还要再乘用户在设置里调的字号比例）：栏宽不动、图标跟着字体长，
// 比例不是 1 就把这一行顶破，真机报的就是那一下 RenderFlex overflowed。
// 这里按布局回归来测（跑得快、CI 也跑），另外留一张图看图标本身。

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    AppTheme.fontScaleObs.value = 1.0;
  });
  tearDown(Get.reset);

  // 字号比例从"缩到一半"到"放大一倍"，图标条都不许溢出
  for (final fontScale in <double>[0.5, 0.9, 1.0, 1.25, 2.0]) {
    testWidgets('收起态菜单图标在字号比例 $fontScale 下不溢出', (tester) async {
      await _mountSidebar(tester, fontScale: fontScale);
      await _runEntrance(tester);

      final error = tester.takeException();
      expect(error, isNull, reason: '字号比例 $fontScale 时排版溢出');
      await unmountPage(tester);
    });
  }

  // 换遍窗口尺寸（很扁的超宽屏、竖长的窄屏都算），图标条依旧不许溢出
  for (final size in <Size>[
    Size(1440, 900),
    Size(1920, 1080),
    Size(2560, 1080),
    Size(900, 1400),
  ]) {
    testWidgets('收起态在 ${size.width.toInt()}x${size.height.toInt()} 窗口下不溢出',
        (tester) async {
      await _mountSidebar(tester, window: size, fontScale: 1.5);
      await _runEntrance(tester);

      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });
  }

  // 图标条的样子只有打上 golden 标签才出图：CI 用 --exclude-tags golden 跳过
  testWidgets('收起态图标条出图', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountSidebar(tester, fontScale: 1.0);
    await _runEntrance(tester);

    await expectLater(
      find.byType(CollapsibleSidebar),
      matchesGoldenFile('goldens/sidebar_collapsed_strip.png'),
    );
    await unmountPage(tester);
  });

  // 收起态展开一族：75 设计像素里没有横枝的容身位置，子项退成纯图标行，
  // 但整族仍要留在父项下面、不许把图标条顶破
  for (final fontScale in <double>[1.0, 2.0]) {
    testWidgets('收起态展开子项在字号比例 $fontScale 下不溢出', (tester) async {
      await _mountSidebar(tester, fontScale: fontScale, expandTree: true);
      await _runEntrance(tester);

      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });
  }

  // 展开态明暗各一张：选中项抬成卡片、指示条、分组标题这套只在展开时才看得到
  for (final dark in <bool>[false, true]) {
    testWidgets(
      '${dark ? '深色' : '浅色'}展开态侧栏出图',
      tags: 'golden',
      (tester) async {
        await loadAppFonts();
        await _mountSidebar(
          tester,
          fontScale: 1.0,
          expanded: true,
          dark: dark,
        );
        await _runEntrance(tester);

        await expectLater(
          find.byType(CollapsibleSidebar),
          matchesGoldenFile(
            dark
                ? 'goldens/sidebar_expanded_dark.png'
                : 'goldens/sidebar_expanded_light.png',
          ),
        );
        await unmountPage(tester);
      },
    );
  }

  // 展开的子项：连接线 + 子项行，同样不许被字号或窄窗顶破
  for (final fontScale in <double>[0.5, 1.0, 2.0]) {
    testWidgets('子项连接线在字号比例 $fontScale 下不溢出', (tester) async {
      await _mountSidebar(
        tester,
        fontScale: fontScale,
        expanded: true,
        expandTree: true,
      );
      await _runEntrance(tester);

      expect(tester.takeException(), isNull);
      await unmountPage(tester);
    });
  }

  testWidgets('子项连接线出图', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountSidebar(tester, fontScale: 1.0, expanded: true, expandTree: true);
    await _runEntrance(tester);

    await expectLater(
      find.byType(CollapsibleSidebar),
      matchesGoldenFile('goldens/sidebar_tree_light.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('收起态展开子项出图', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountSidebar(tester, fontScale: 1.0, expandTree: true);
    await _runEntrance(tester);

    await expectLater(
      find.byType(CollapsibleSidebar),
      matchesGoldenFile('goldens/sidebar_tree_collapsed.png'),
    );
    await unmountPage(tester);
  });
}

/// 入场动画一小步一小步走完（每组错开 80ms，最后那组要 900ms 多才起跳）。
/// 中途每一帧都排过版，窄宽度下的溢出才藏不住。
Future<void> _runEntrance(WidgetTester tester) =>
    advance(tester, steps: 35);

Future<void> _mountSidebar(
  WidgetTester tester, {
  Size window = const Size(1440, 900),
  required double fontScale,
  bool expanded = false,
  bool dark = false,
  bool expandTree = false,
}) async {
  registerPageServices();

  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  AppTheme.fontScaleObs.value = fontScale;

  // 先把 ScreenUtil 按目标窗口初始化，再重算度量表：AppTheme.metrics 是缓存下来的
  // 常量，真机靠窗口变化回调刷新，测试里不换这一刀就会拿上一台"窗口"的数排版，
  // 报出来的是铺垫造成的假溢出。
  await tester.pumpWidget(
    const ScreenUtilInit(
      designSize: Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      child: SizedBox.shrink(),
    ),
  );
  AppTheme.resetMetrics();

  // 直接 new：不走 Get.put 的 onInit，省掉真实窗口通道的依赖
  final controller = SidebarController();
  controller.isExpanded.value = expanded;
  // 选中一项，卡片态和指示条才会画出来
  controller.selectedRoute.value = const DashboardRoute().location;
  if (expandTree) {
    // 连接线的几何只在展开时才成立，两张有子项的父项都打开才盖得住
    // （展开键是 route.title，不是 sidebarLabel）
    controller.expandedItems['游戏库'] = true;
    controller.expandedItems['Manga'] = true;
  }
  Get.put<SidebarController>(controller, permanent: true);

  await tester.pumpWidget(
    ScreenUtilInit(
      // 和 main.dart 桌面端同一套参数，否则 scaleW/scaleS 的系数对不上真机
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(
          // 真机这一层外面是 Scaffold，展开态的分组头里有 InkResponse，
          // 少了 Material 祖先直接断言炸
          builder: (context) => Material(
            color: AppSemantic.of(context).canvas,
            child: Row(
              children: [
                CollapsibleSidebar(
                  groups: DesktopLayout.getDefaultSidebarGroups(),
                ),
                Expanded(
                  child: ColoredBox(color: AppSemantic.of(context).surface),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

}
