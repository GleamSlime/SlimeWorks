import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/components/window/window_drag_region.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 顶栏拖拽区：按住空白走拖动，按住控件走点击
///
/// 这组用例锁的是「Windows 上没有系统标题栏兜底」那条路：顶栏标题格由
/// [WindowDragRegion] 显式接管拖拽，而不是指望压在页面之下的 ScreenTopBar
/// 接到指针。用 `debugForceSupportedForTest` 在 macOS 上把这层打开来验，
/// 否则这条分支在 CI 上永远走不到。
void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    WindowDragRegion.debugForceSupportedForTest = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          calls.add(call.method);
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    WindowDragRegion.debugForceSupportedForTest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    Get.reset();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool withButton = false,
    bool doubleTapToMaximize = false,
  }) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1440, 900),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 800,
                  height: 60,
                  child: WindowDragRegion(
                    doubleTapToMaximize: doubleTapToMaximize,
                    child: Row(
                      children: [
                        const SizedBox(width: 200),
                        const Text('媒体库'),
                        const Spacer(),
                        if (withButton)
                          TextButton(
                            onPressed: () => calls.add('tapped'),
                            child: const Text('返回'),
                          ),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('按住标题区拖过阈值：交给系统拖窗口', (tester) async {
    await mount(tester);

    // 从标题文字上起按——正是 Windows 上原先完全拖不动的那个位置
    final g = await tester.startGesture(
      tester.getCenter(find.text('媒体库')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(0, 12));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(calls, contains('startDragging'));
  });

  testWidgets('按下但没动：不算拖动，点击照常落到控件上', (tester) async {
    await mount(tester, withButton: true);

    await tester.tap(find.text('返回'));
    await tester.pump();

    expect(calls, isNot(contains('startDragging')));
    expect(calls, contains('tapped'));
  });

  testWidgets('拖动起点在控件上：起拖后不再触发该控件的点击', (tester) async {
    await mount(tester, withButton: true);

    final g = await tester.startGesture(
      tester.getCenter(find.text('返回')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(calls, contains('startDragging'));
    // 作废指针序列的效果：控件不该在拖动收尾时补一次点击
    expect(calls, isNot(contains('tapped')));
  });

  testWidgets('空白处起拖：不误报点击，也不留悬挂计时器', (tester) async {
    await mount(tester, withButton: true);

    final g = await tester.startGesture(
      // 标题文字右侧的纯空白（Spacer 占着的那一段）
      const Offset(500, 30),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(calls, contains('startDragging'));
    expect(calls, isNot(contains('tapped')));
  });

  testWidgets('双击开关打开时，双击触发最大化/还原', (tester) async {
    await mount(tester, doubleTapToMaximize: true);

    await tester.tapAt(const Offset(500, 30));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(500, 30));
    await tester.pumpAndSettle();

    expect(calls, contains('maximize'));
  });

  testWidgets('小于阈值的抖动不拖窗口', (tester) async {
    await mount(tester);

    final g = await tester.startGesture(
      tester.getCenter(find.text('媒体库')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(2, 2));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(calls, isNot(contains('startDragging')));
  });

  testWidgets('平台不支持时（如 macOS 有系统标题栏）整层不干预', (tester) async {
    WindowDragRegion.debugForceSupportedForTest = false;
    await mount(tester, withButton: true);

    final g = await tester.startGesture(
      tester.getCenter(find.text('媒体库')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(calls, isNot(contains('startDragging')));
  });
}
