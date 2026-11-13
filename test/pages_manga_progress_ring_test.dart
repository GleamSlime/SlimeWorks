// P3-1：漫画假进度环到 99% 必须停表。
//
// 旧实现 Timer.periodic 永不取消：图片一直不回来（节点挂起/解码卡住）时，
// 这个纯装饰动画会每秒重建 12 次直到 widget 被移出树。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';

Future<void> mountRing(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(400, 400),
      builder: (context, _) {
        AppTheme.resetMetrics();
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0),
          home: Scaffold(
            backgroundColor: AppSemantic.light.canvas,
            body: const Center(child: MangaProgressRing()),
          ),
        );
      },
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('进度抵近 99% 后定时器自行取消', (tester) async {
    await mountRing(tester);

    // 指数衰减 0.025/档：约 190 档后逼近 99%（取 320 档留足余量）
    for (int i = 0; i < 320; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('99%'), findsOneWidget);
    // 表已停：假定时器若还活着，这里会因「pending timer」报错
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('dispose 兜底取消（未到 99% 就离开）', (tester) async {
    await mountRing(tester);
    await tester.pump(const Duration(milliseconds: 240));
    // 换掉整棵树触发 dispose；有残留 Timer 时 flutter_test 会在收尾报错
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(find.byType(MangaProgressRing), findsNothing);
  });
}
