// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/sidebar_resize_handle.dart';
import 'package:slime_works/core/theme/app_semantics.dart';

/// 侧栏把手的离屏渲染 + 宽度换算
///
/// 对折这件事只有几像素宽，靠肉眼在整窗里判断不出来，这里把静止/折到一半/
/// 折满/拖拽四帧一次性出图，用像素量它的宽和高怎么此消彼长；另外单独验一遍
/// "指针位移 → 设计宽度"的换算、拖到最窄自动收起、收起态往右拖能拉回来。
void main() {
  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final path =
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    if (flutterRoot == null || !File(path).existsSync()) return;
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  });

  testWidgets('静止 / 悬停 / 拖拽三档状态分明（浅色）', (tester) async {
    await _renderHandle(
      tester,
      dark: false,
      prefix: 'goldens/resize_handle_light',
      captureMidFold: true,
    );
  });

  testWidgets('同一套口径（深色）', (tester) async {
    await _renderHandle(tester, dark: true, prefix: 'goldens/resize_handle_dark');
  });

  testWidgets('收起态折成反向箭头（›）', (tester) async {
    await _renderHandle(
      tester,
      dark: false,
      collapsed: true,
      prefix: 'goldens/resize_handle_collapsed',
    );
  });

  // 光标这件事屏幕上看不出来，只能收平台通道收到的那串 kind
  testWidgets('光标分三档：竖线左右拖、箭头可点、按住即拖', (tester) async {
    // 命中区放大到 60：真布局里把手钉在侧栏/内容区的缝上，缝会跟着指针一起走，
    // 指针基本出不了这条带子；这里侧栏是静态的，22 宽带子一拖就跑出去了
    await _mountHandle(tester, hitWidth: 60);

    final kinds = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        if (call.method == 'activateSystemCursor') {
          kinds.add((call.arguments as Map)['kind'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.mouseCursor, null),
    );

    final center = tester.getCenter(find.byType(SidebarResizeHandle));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();

    kinds.clear();
    await pointer.moveTo(center);
    await tester.pump();
    // 刚进来还是那根竖线，说的是"这里能左右拖"
    expect(kinds, isNotEmpty);
    expect(kinds.first, 'resizeLeftRight');
    // 折过 60% 变成箭头，身份也跟着换成"点我"
    await tester.pumpAndSettle();
    expect(kinds.last, 'click');

    // 只按下还没越过 touch slop，拖拽手势没认，光标仍是箭头；挪出 20 才算拖
    await pointer.down(center);
    await pointer.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(kinds.last, 'grabbing');
    await pointer.up();
    await tester.pumpAndSettle();
    expect(kinds.last, 'click');

    // 挪开之后不能把箭头光标赖在原地
    await pointer.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    debugPrint('cursor kinds: $kinds');
    expect(kinds.last, isNot('click'));
  });

  testWidgets('拖拽换算、拖到最窄自动收起、收起态往右拖拉回展开', (tester) async {
    // 宽度要落盘，先把偏好层垫上，否则平台通道直接抛
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

    // 直接 new：不走 Get.put，onInit 不触发，也就不会去碰 SharedPreferences
    final controller = SidebarController();
    // 展开态是平台默认值，测试里显式钉住，免得出图环境和 CI 走到不同分支
    controller.isExpanded.value = true;
    expect(controller.expandedWidth.value, SidebarController.kDefaultExpandedWidth);

    controller.beginResize();
    expect(controller.resizing.value, isTrue);

    // 指针右移 60 逻辑像素，落到设计稿上按 scaleW 系数等比折算
    controller.resizeBy(60);
    final gained = controller.expandedWidth.value -
        SidebarController.kDefaultExpandedWidth;
    expect(gained, greaterThan(0));
    expect(gained, lessThanOrEqualTo(60 / ratio));

    // 往右顶到上限：只是钳住，不动展开态
    controller.resizeBy(9999);
    expect(controller.expandedWidth.value, SidebarController.kMaxExpandedWidth);
    expect(controller.isExpanded.value, isTrue);

    // 往左拖到最窄：不是停在 160，而是当场收成图标条，宽度回到默认
    controller.resizeBy(-9999);
    expect(controller.isExpanded.value, isFalse);
    expect(controller.resizing.value, isFalse);
    expect(controller.expandedWidth.value, SidebarController.kDefaultExpandedWidth);

    // 收起态继续往左拖没有意义，不该把状态又翻回去
    controller.resizeBy(-10);
    expect(controller.isExpanded.value, isFalse);

    // 收起态往右拖等于把它拉回来
    controller.resizeBy(10);
    expect(controller.isExpanded.value, isTrue);

    controller.endResize();
    expect(controller.resizing.value, isFalse);

    // toggleSidebar 要等宽度动画跑完才亮扩展内容，不推进 fake 时钟就留个挂起的 Timer
    await tester.pump(SidebarController.kWidthAnimation + const Duration(milliseconds: 100));
  });
}

/// 复刻真布局：把手挂在内容区左缘，左边那条 1px 线才是侧栏的边界
Future<_Probe> _mountHandle(
  WidgetTester tester, {
  AppSemantic semantic = AppSemantic.light,
  bool collapsed = false,
  double hitWidth = 22,
}) async {
  tester.view.physicalSize = const Size(300, 360);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final deltas = <double>[];
  var toggles = 0;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(extensions: [semantic]),
      home: Scaffold(
        backgroundColor: semantic.canvas,
        body: Center(
          child: SizedBox(
            width: 220,
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: semantic.surface)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: 1,
                    child: ColoredBox(color: semantic.border),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: SidebarResizeHandle(
                    collapsed: collapsed,
                    hitWidth: hitWidth,
                    onDragStart: () {},
                    onDragUpdate: deltas.add,
                    onDragEnd: () {},
                    onToggle: () => toggles++,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Probe(deltas, () => toggles);
}

class _Probe {
  _Probe(this.deltas, this.toggleCount);
  final List<double> deltas;
  final int Function() toggleCount;
}

/// 悬停出箭头，中途再取一帧证明"正在折"，按下摊回竖线（不加粗不变色）
Future<void> _renderHandle(
  WidgetTester tester, {
  required bool dark,
  required String prefix,
  bool collapsed = false,
  bool captureMidFold = false,
}) async {
  final probe = await _mountHandle(
    tester,
    semantic: dark ? AppSemantic.dark : AppSemantic.light,
    collapsed: collapsed,
  );

  final target = find.byType(Scaffold);
  await expectLater(target, matchesGoldenFile('$prefix.png'));

  // 悬停要真实鼠标指针，MouseRegion 才认
  final center = tester.getCenter(find.byType(SidebarResizeHandle));
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  addTearDown(pointer.removePointer);
  await tester.pump();
  await pointer.moveTo(center);
  if (captureMidFold) {
    // 先空走一帧把 hover 事件送进 MouseRegion，对折才开始跑；
    // 220ms 的动画只推进 45ms，取的就是"折了一半"那一档
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    await expectLater(target, matchesGoldenFile('${prefix}_mid.png'));
  }
  await tester.pumpAndSettle();
  await expectLater(target, matchesGoldenFile('${prefix}_hover.png'));

  // 一次大跳只够越过 touch slop、认下拖拽本身，事件里不带增量，
  // 所以要拆成几小步走，onDragUpdate 才真的收到 delta
  await pointer.down(center);
  for (var i = 0; i < 4; i++) {
    await pointer.moveBy(const Offset(12, 0));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  await expectLater(target, matchesGoldenFile('${prefix}_drag.png'));
  expect(probe.deltas.fold<double>(0, (a, b) => a + b), greaterThan(0));
  await pointer.up();
  await tester.pumpAndSettle();

  // 点一下是切展开/收起，不该被拖拽手势吃掉
  await tester.tap(find.byType(SidebarResizeHandle));
  await tester.pumpAndSettle();
  expect(probe.toggleCount(), 1);
}
