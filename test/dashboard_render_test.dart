// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/pages/dashboard_screen.dart';

import 'helpers/page_golden.dart';

/// 概览页的离屏渲染
///
/// 这一页是启动后的第一眼，也是全站自定义样式最密的地方（卡片底、描边、投影、
/// 渐变图表色各自为政）。迁到语义层前后各出一版，改动有没有走样只看图。
void main() {
  setUpAll(loadAppFonts);
  // SidebarController.onInit 会去读持久化的栏宽，测试环境没有插件通道，先给它一层假 prefs
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('概览页：浅色', (tester) async {
    await _mount(tester, dark: false, file: 'goldens/dashboard_light.png');
  });

  testWidgets('概览页：深色', (tester) async {
    await _mount(tester, dark: true, file: 'goldens/dashboard_dark.png');
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required bool dark,
  required String file,
}) async {
  registerPageServices();
  // 顶栏的面包屑要读侧栏的当前选中项：真机由 createRouter() 注册，这里补一颗钉，
  // 只给本文件用——放进公共铺垫会把别的用例里自己配好的控制器顶掉
  Get.put(SidebarController()..selectedRoute.value = const DashboardRoute().location);
  // 曲线要有形状才有验收意义：真实数据要跑 FFI，这里直接往历史里塞一段斜坡
  final metrics = pageMetrics();
  metrics.cpuHistory
    ..clear()
    ..addAll([for (var i = 0; i < 40; i++) 20.0 + (i % 7) * 9.0]);
  metrics.memHistory
    ..clear()
    ..addAll([for (var i = 0; i < 40; i++) 1200.0 + i * 12.0]);
  metrics.rxHistory
    ..clear()
    ..addAll([for (var i = 0; i < 40; i++) (i.isEven ? 800.0 : 120.0)]);
  metrics.txHistory
    ..clear()
    ..addAll([for (var i = 0; i < 40; i++) 60.0 + (i % 5) * 20.0]);

  await pumpAppPage(tester, const DashboardScreen(), dark: dark, withTopBar: true);
  // 入场是 120ms 起跳 + 900ms 主控 + 每张卡再错开 6%，45 小步才走完
  await advance(tester, steps: 45);

  await expectLater(
    find.byType(DashboardScreen),
    matchesGoldenFile(file),
  );

  await unmountPage(tester);
}
