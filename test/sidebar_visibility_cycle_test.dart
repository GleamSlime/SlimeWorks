import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/components/window/sidebar_resize_handle.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

import 'helpers/page_golden.dart';

// 侧栏三态（展开/收起/隐藏）的循环与"默认隐藏页"的进出恢复。
// 直接 new 控制器：不走 Get.put，onInit 不触发，也就不会去碰 SharedPreferences。

void main() {
  testWidgets('指示条三态循环：展开 → 收起 → 隐藏 → 展开', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _build();

    controller.cycleVisibility();
    expect(controller.isExpanded.value, isFalse);
    expect(controller.isHidden.value, isFalse);

    controller.cycleVisibility();
    expect(controller.isHidden.value, isTrue);

    controller.cycleVisibility();
    expect(controller.isHidden.value, isFalse);
    expect(controller.isExpanded.value, isTrue);

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  testWidgets('默认隐藏页：进入强制隐藏，离开恢复进页前的展开态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _build();

    controller.applyVisibilityForPath('/novel-reader', defaultHidden: true);
    expect(controller.isHidden.value, isTrue);
    expect(controller.isExpanded.value, isFalse);

    controller.applyVisibilityForPath('/dashboard', defaultHidden: false);
    expect(controller.isHidden.value, isFalse);
    expect(controller.isExpanded.value, isTrue);

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  testWidgets('普通页手动隐藏后，导航去别的普通页不自动恢复', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = _build();

    controller.cycleVisibility(); // 展开→收起
    controller.cycleVisibility(); // 收起→隐藏（手动）
    controller.applyVisibilityForPath('/dashboard', defaultHidden: false);
    expect(controller.isHidden.value, isTrue);

    // 进默认隐藏页再离开：恢复的是"隐藏"本身，不是被路由翻出来
    controller.applyVisibilityForPath('/novel-reader', defaultHidden: true);
    controller.applyVisibilityForPath('/dashboard', defaultHidden: false);
    expect(controller.isHidden.value, isTrue);

    controller.cycleVisibility(); // 指示条点一下才回展开
    expect(controller.isExpanded.value, isTrue);

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  testWidgets('隐藏态起拖：先跟手，过半松手才展开，不过半弹回隐藏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late double ratio;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1440, 900),
        builder: (context, _) {
          ratio = ScreenUtil().setWidth(100) / 100;
          return const SizedBox.shrink();
        },
      ),
    );
    final controller = _build();
    expect(ratio, greaterThan(0));

    controller.applyVisibilityForPath('/novel-reader', defaultHidden: true);

    // 拖一点（10 设计像素，还不到图标条宽）：宽度在跟手，仍是隐藏态
    controller.beginResize();
    controller.resizeBy(10 * ratio);
    expect(controller.following.value, isTrue);
    expect(controller.isExpanded.value, isFalse);
    expect(controller.isHidden.value, isTrue);
    controller.endResize();
    expect(controller.isHidden.value, isTrue);

    // 拖过图标条宽（75）：隐藏态当场翻掉，不用等松手
    controller.beginResize();
    controller.resizeBy(120 * ratio);
    expect(controller.isHidden.value, isFalse);
    expect(controller.isExpanded.value, isFalse);
    controller.endResize();
    expect(controller.isHidden.value, isFalse);
    expect(controller.isExpanded.value, isTrue);
    expect(
      controller.expandedWidth.value,
      greaterThanOrEqualTo(SidebarController.kMinExpandedWidth),
    );

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  testWidgets('收起态往回拖过图标条宽以下：当场进隐藏态，不等松手', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late double ratio;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1440, 900),
        builder: (context, _) {
          ratio = ScreenUtil().setWidth(100) / 100;
          return const SizedBox.shrink();
        },
      ),
    );
    final controller = _build();
    controller.toggleSidebar(); // 展开→收起

    // 从图标条宽往回拖 40 设计像素：落到 75 以下，立刻就是隐藏态
    controller.beginResize();
    controller.resizeBy(-40 * ratio);
    expect(controller.followWidth.value, lessThan(SidebarController.kCollapsedWidth));
    expect(controller.isHidden.value, isTrue);

    controller.endResize();
    expect(controller.isHidden.value, isTrue);
    expect(controller.isExpanded.value, isFalse);

    // 再往右拖过图标条宽：当场从隐藏回到可见，继续过半松手就展开
    controller.beginResize();
    controller.resizeBy(200 * ratio);
    expect(controller.isHidden.value, isFalse);
    controller.endResize();
    expect(controller.isExpanded.value, isTrue);

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  testWidgets('收起态指示条：点箭头是展开，悬停浮出闭眼、点它才隐藏', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    final controller = SidebarController();
    controller.isExpanded.value = false;
    Get.put<SidebarController>(controller, permanent: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 40,
            height: 300,
            child: Stack(
              children: const [
                Positioned(left: 0, top: 0, bottom: 0, child: SidebarResizeStrip()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final eye = find.byWidgetPredicate(
      (w) => w is DrawIcon && w.icon == StrokeIcons.visibilityOff,
    );
    // 没悬停就没有闭眼，那一条缝上只有箭头
    expect(eye, findsNothing);

    final center = tester.getCenter(find.byType(SidebarResizeHandle));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(center);
    await tester.pumpAndSettle();
    expect(eye, findsOneWidget);

    await tester.tap(eye);
    await tester.pump();
    expect(controller.isHidden.value, isTrue);
    expect(controller.isExpanded.value, isFalse);

    // 隐藏态下闭眼这个入口就该收掉（onHide 已经不再传）
    await pointer.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(eye, findsNothing);

    // 隐藏态点箭头 = 展开；toggleSidebar 的延时要排干
    await tester.tap(find.byType(SidebarResizeHandle));
    expect(controller.isHidden.value, isFalse);
    expect(controller.isExpanded.value, isTrue);
    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });

  test('sidebarDefaultHidden 按路径段匹配，不误伤同前缀路由', () {
    expect(sidebarDefaultHidden('/novel-reader'), isTrue);
    expect(sidebarDefaultHidden('/manga/read/12/3'), isTrue);
    expect(sidebarDefaultHidden('/game/category/abc'), isTrue);
    expect(sidebarDefaultHidden('/game/categories'), isFalse);
    expect(sidebarDefaultHidden('/manga'), isFalse);
    expect(sidebarDefaultHidden('/manga/history'), isFalse);
    expect(sidebarDefaultHidden('/motion-lab'), isFalse);
    expect(sidebarDefaultHidden('/dashboard'), isFalse);
  });

  // 跟手/点击动画的每一个中间宽度都逐档排一遍版：溢出藏不住；
  // 并且拖过最小展开宽那一刻，展开态的文字就该已经在栏里了。
  testWidgets('跟手展开全程：中间宽度不顶破，过最小展开宽文字当场出现', (tester) async {
    final (controller, ratio) = await _mountRealSidebar(tester);

    controller.beginResize();
    // 图标条宽以内：还是收起态的图标排在裁出来的窄栏里，没有文字
    for (final width in <double>[10, 56, 90]) {
      await _dragTo(tester, controller, ratio, width);
      expect(tester.takeException(), isNull, reason: '跟手到 $width 设计像素时排版溢出');
      expect(find.text('游戏库'), findsNothing, reason: '$width 还不该出展开文字');
    }
    // 过最小展开宽：不用等松手，文字就该出来了
    for (final width in <double>[160, 240, 320]) {
      await _dragTo(tester, controller, ratio, width);
      expect(tester.takeException(), isNull, reason: '跟手到 $width 设计像素时排版溢出');
      expect(find.text('游戏库'), findsWidgets, reason: '过了 $width 展开文字还没出现');
    }

    controller.endResize();
    expect(controller.isExpanded.value, isTrue);
    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
    // 列表项是拖出宽度那一刻才建出来的，各组的入场延时要排干再卸载
    await advance(tester, steps: 35);
    await unmountPage(tester);
  });

  // 点指示条从隐藏直接跳展开：AnimatedContainer 一路从 0 宽动画过去，
  // 中间帧全是"比内容固有宽更窄"的宽度，真机报的 RenderFlex overflowed 就是这几帧。
  testWidgets('隐藏态点击展开：宽度动画中间帧不顶破内容', (tester) async {
    final (controller, _) = await _mountRealSidebar(tester);

    controller.cycleVisibility(); // 隐藏 → 展开（走宽度动画）
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull, reason: '展开动画第 $i 帧排版溢出');
    }

    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
    await advance(tester, steps: 35);
    await unmountPage(tester);
  });
}

/// 按真实渲染路径挂一条带全部注册分组的侧栏，返回控制器和 scaleW 系数
Future<(SidebarController, double)> _mountRealSidebar(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  Get.reset();
  AppTheme.fontScaleObs.value = 1.0;
  registerPageServices();

  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ScreenUtilInit(
      designSize: Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      child: SizedBox.shrink(),
    ),
  );
  AppTheme.resetMetrics();

  final controller = SidebarController();
  controller.isExpanded.value = false;
  controller.isHidden.value = true;
  Get.put<SidebarController>(controller, permanent: true);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Material(
            color: AppSemantic.of(context).canvas,
            child: Row(
              children: [
                CollapsibleSidebar(groups: DesktopLayout.getDefaultSidebarGroups()),
                Expanded(child: ColoredBox(color: AppSemantic.of(context).surface)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await advance(tester, steps: 35);
  return (controller, scaleW(100) / 100);
}

/// 把跟手宽度挪到目标设计像素并排版一帧：走的就是把手那条 resizeBy 路径
Future<void> _dragTo(
  WidgetTester tester,
  SidebarController controller,
  double ratio,
  double targetDesignWidth,
) async {
  controller.resizeBy((targetDesignWidth - controller.followWidth.value) * ratio);
  await tester.pump();
}

SidebarController _build() {
  final controller = SidebarController();
  // 展开态是平台默认值，测试里显式钉住，免得出图环境和 CI 走到不同分支
  controller.isExpanded.value = true;
  return controller;
}
