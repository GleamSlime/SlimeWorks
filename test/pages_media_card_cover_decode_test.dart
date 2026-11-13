// P2-2：远程封面必须带解码上限，且宽度跟着布局格子走。
//
// 节点 URL 不带 width 时会直传原图（兜底原图 / 清晰度设成原图档），
// 不设 cacheWidth 就是整张 4K 解码进 ImageCache。这里断言 MediaCardCover
// 对 http 源产出的 provider 是 ResizeImage，且 targetWidth 约等于
// 「格子布局宽 × dpr」而不是 null。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/pages/collection/picture/components/media_cutout_card.dart';

const double kCellWidth = 320;

Future<void> mountCover(
  WidgetTester tester, {
  required String src,
  double dpr = 2.0,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(800, 600),
      builder: (context, _) {
        AppTheme.resetMetrics();
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0),
          home: Scaffold(
            backgroundColor: AppSemantic.light.canvas,
            body: Center(
              child: SizedBox(
                width: kCellWidth,
                height: 200,
                child: MediaCardCover(
                  source: src,
                  placeholderIcon: StrokeIcons.image,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    if (!getIt.isRegistered<MediaPrefsService>()) {
      getIt.registerSingleton<MediaPrefsService>(MediaPrefsService());
    }
  });

  tearDown(() {
    if (getIt.isRegistered<MediaPrefsService>()) {
      getIt.unregister<MediaPrefsService>();
    }
  });

  testWidgets('http 源：provider 是 ResizeImage，宽度 = 格子宽 × dpr', (tester) async {
    await mountCover(tester, src: 'http://127.0.0.1:1/node/media?path=/a.jpg');
    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image;
    expect(provider, isA<ResizeImage>(),
        reason: '远程源没给 cacheWidth 就是按原图整张解码');
    final resize = provider as ResizeImage;
    expect(resize.width, isNotNull);
    // 布局宽度 320 × dpr 2 = 640；允许一点余量（屏幕适配系数可能介入）
    expect(resize.width!, inInclusiveRange(300, 700));
    // 内层仍然是 NetworkImage（不是被换成了别的 provider）
    expect(resize.imageProvider, isA<NetworkImage>());
  });

  testWidgets('dpr 变小时解码尺寸跟着变小（不是写死常量）', (tester) async {
    await mountCover(tester, src: 'http://127.0.0.1:1/node/media?path=/a.jpg', dpr: 1.0);
    final resize = tester.widget<Image>(find.byType(Image).first).image as ResizeImage;
    expect(resize.width!, inInclusiveRange(150, 400));
  });

  testWidgets('本地文件源仍用「本地图片清晰度」档位', (tester) async {
    await mountCover(tester, src: '/tmp/definitely-not-a-real-file.png');
    final provider = tester.widget<Image>(find.byType(Image).first).image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<FileImage>());
  });
}
