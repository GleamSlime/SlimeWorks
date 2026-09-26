// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/music_player/components/music_list_item.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

import 'helpers/page_golden.dart';

/// 音乐播放器歌曲列表的离屏渲染
///
/// 这一页在 macOS 上要启真实应用才能看到，而它的行样式（标题字重、悬停水洗、
/// 占位封面、时长小字）正是最容易改出"看着不对但说不上来"的地方。这里把
/// MusicListItem 直接摆出来截图，悬停态也一起看。
void main() {
  setUpAll(() async {
    // 中文、图标字形都要真字体才看得出对齐，铺垫统一走 helper
    await loadAppFonts();
  });

  testWidgets('浅色歌曲列表', (tester) async {
    await _renderList(tester, dark: false, file: 'goldens/music_list_light.png');
  });

  testWidgets('深色歌曲列表', (tester) async {
    await _renderList(tester, dark: true, file: 'goldens/music_list_dark.png');
  });
}

music_api.MusicItem _item(String title, {String? artist, bool fav = false}) =>
    music_api.MusicItem(
      id: title,
      playlistId: 'p1',
      title: title,
      artist: artist,
      filePath: '/tmp/$title.mp3',
      fileSize: BigInt.from(8000000),
      modifiedAt: 0,
      order: 0,
      isFavorite: fav,
      hasCue: false,
      durationMs: BigInt.from(214000),
    );

Future<void> _renderList(
  WidgetTester tester, {
  required bool dark,
  required String file,
}) async {
  tester.view.physicalSize = const Size(520, 420);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final items = [
    _item('雨天电台', artist: '陈三', fav: true),
    _item('夜航西飞'),
    _item('一首标题非常长的歌，用来验证省略号而不是把行撑破', artist: '佚名'),
  ];

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(520, 420),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, _) {
        AppTheme.resetMetrics();
        final theme = dark
            ? AppTheme.buildCustomDark(AppTheme.kFollowThemeAccent, 1.0)
            : AppTheme.buildCustomLight(AppTheme.kFollowThemeAccent, 1.0);
        final semantic = dark ? AppSemantic.dark : AppSemantic.light;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            backgroundColor: semantic.canvas,
            body: Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++)
                    MusicListItem(
                      item: items[i],
                      // 第 2 行当"正在播放"：验证强调色与跳动指示条
                      isCurrent: i == 1,
                      isPlaying: i == 1,
                      onTap: () {},
                      onFavoriteTap: () {},
                      onDeleteTap: () {},
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  // 不能 pumpAndSettle：正在播放的那行有个无限循环的跳动指示条，永远 settle 不下来。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // 悬停第 1 行：状态层必须是"朝底色方向"的水洗，亮色下不能像以前那样是白压白。
  final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await hover.addPointer();
  await hover.moveTo(tester.getCenter(find.text('雨天电台')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
  await hover.removePointer();
}
