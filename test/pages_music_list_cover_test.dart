// P2-14：MusicListItem 的 40px 封面必须带解码上限，且 build 里不得做磁盘查询。
//
// 断言两件事：
// 1) Image 的 provider 是 ResizeImage，且 targetWidth 约等于显示宽 × dpr；
// 2) build 本身不产生 existsSync（用不存在路径也能正常建出骨架，
//    并且不进任何同步 IO 分支——旧实现会先 existsSync 再决定走哪条）。
import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/music_player/components/music_list_item.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

music_api.MusicItem item({
  String id = 'm1',
  String? coverPath,
  String title = '雨天电台',
}) {
  return music_api.MusicItem(
    id: id,
    playlistId: 'p1',
    title: title,
    artist: '陈三',
    filePath: '/tmp/$id.mp3',
    fileSize: BigInt.from(8000000),
    modifiedAt: 0,
    order: 0,
    isFavorite: false,
    hasCue: false,
    durationMs: BigInt.from(214000),
    coverPath: coverPath,
  );
}

Future<void> mount(WidgetTester tester, music_api.MusicItem it) async {
  tester.view.physicalSize = const Size(520, 260);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(520, 260),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, _) {
        AppTheme.resetMetrics();
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0),
          home: Scaffold(
            backgroundColor: AppSemantic.light.canvas,
            body: MusicListItem(
              item: it,
              isCurrent: false,
              isPlaying: false,
              onTap: () {},
              onFavoriteTap: () {},
              onDeleteTap: () {},
            ),
          ),
        );
      },
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('封面走 ResizeImage 且解码宽约等于显示宽 × dpr', (tester) async {
    await mount(tester, item(coverPath: '/tmp/not-a-real-cover-file.png'));

    // 文件不存在 → 封面最终走 errorBuilder 的占位，但 Image 本身已经建出来过
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty, reason: '封面 Image 必须建出来（文件不存在由 errorBuilder 兜底）');

    final raw = images.first.image;
    expect(
      raw,
      isA<ResizeImage>(),
      reason: '没有 cacheWidth 就是按原图整张解码：专辑封面动辄上千像素',
    );
    final resize = raw as ResizeImage;
    expect(resize.width, isNotNull, reason: '解码宽度必须被钉住');
    // 与 Image 的显示宽等比：dpr 变化时解码尺寸跟着变，说明取的是本帧的 dpr
    final image = tester.widget<Image>(find.byType(Image).first);
    final dpr = MediaQuery.of(tester.element(find.byType(MusicListItem))).devicePixelRatio;
    expect(resize.width, (image.width! * dpr).round().clamp(1, 4096));
  });

  testWidgets('无 coverPath 时直接给占位，不建 Image', (tester) async {
    await mount(tester, item(coverPath: null));
    expect(find.byType(Image), findsNothing);
  });
}
