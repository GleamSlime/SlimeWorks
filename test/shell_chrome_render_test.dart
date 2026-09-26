import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/widgets/breadcrumb.dart';

import 'helpers/page_golden.dart';

// 顶栏标题格的两张脸
//
// 同一个格子：单级页渲染标题，有父链的页渲染面包屑，面包屑的上级取侧栏的叫法、
// 叶子取页面自己报的名字。这三条只在像素上才看得出来对不对，所以出图。

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
  });
  tearDown(Get.reset);

  testWidgets('顶层页：标题格是单级标题', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountTopBar(tester, location: const DashboardRoute().location, title: '概览');
    await advance(tester, steps: 6);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(DesktopTopBar),
      matchesGoldenFile('goldens/shell_topbar_title_light.png'),
    );
    await unmountPage(tester);
  });

  testWidgets('子页：标题格换成面包屑，上级跟侧栏同名', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountTopBar(
      tester,
      location: const GameCategoriesRoute().location,
      title: '游戏分类',
    );
    await advance(tester, steps: 6);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(DesktopTopBar),
      matchesGoldenFile('goldens/shell_topbar_breadcrumb_light.png'),
    );
    await unmountPage(tester);
  });

  // 详情页那一级：静态路由名（"游戏详情"）在那儿是废话，页面报的实体名才有用
  testWidgets('详情页：面包屑叶子用页面报名', tags: 'golden', (tester) async {
    await loadAppFonts();
    await _mountTopBar(
      tester,
      location: const GameDetailRoute(gameId: 'still-sea').location,
      title: '寂静之海',
    );
    await advance(tester, steps: 6);

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Breadcrumb),
      matchesGoldenFile('goldens/shell_topbar_breadcrumb_leaf_light.png'),
    );
    await unmountPage(tester);
  });
}

/// 只挂顶栏 + 一个报出 chrome 的空页面：标题格要按真机那条链路来判定，
/// 直接在图上摆 Breadcrumb 只能证明它自己没画歪，证明不了选错了脸。
Future<void> _mountTopBar(
  WidgetTester tester, {
  required String location,
  required String title,
}) async {
  final controller = SidebarController();
  controller.isExpanded.value = true;
  controller.selectedRoute.value = location;
  Get.put<SidebarController>(controller, permanent: true);

  await pumpAppPage(
    tester,
    ScreenChrome(data: ScreenChromeData(title: title), child: const SizedBox.expand()),
    withTopBar: true,
  );
}
