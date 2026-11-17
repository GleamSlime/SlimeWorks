// 瀑布流网格的分批展开：大集合进入时只建首批卡片。
//
// 回归背景：网格是 SingleChildScrollView + Row(Column) 的非懒加载结构，
// 旧实现超过初始行数后把 visibleCount 一次性设为总数，2991 条的远程集合
// 会在单帧内建出全部卡片，客户端卡死后崩溃。
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/masonry_media_grid.dart';
import 'package:slime_works/pages/collection/picture/components/media_item_tile.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/view_models/media_library_viewmodel.dart';

import 'helpers/page_golden.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('2991 条时只建出首批卡片', (tester) async {
    await loadAppFonts();
    await pumpAppPage(tester, const SizedBox.shrink());
    if (!getIt.isRegistered<MediaPrefsService>()) {
      getIt.registerSingleton<MediaPrefsService>(MediaPrefsService());
    }
    final vm = MediaLibraryViewModel();

    final items = List<media_api.MediaItem>.generate(
      2991,
      (i) => media_api.MediaItem(
        id: 'item$i',
        collectionId: 'c',
        title: 't$i',
        filePath: '/tmp/nonexistent_$i.jpg',
        kind: media_api.MediaKind.image,
        fileSize: BigInt.from(1024),
        modifiedAt: 0,
        width: 300,
        height: 400,
        order: i,
      ),
    );

    await pumpAppPage(
      tester,
      MasonryMediaGrid(
        items: items,
        collectionId: 'c',
        isRemote: true,
        viewModel: vm,
        columnCount: 4,
        onOpenViewer: (_) {},
        onConfirmDelete: (_) async {},
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final built = find.byType(MediaItemTile).evaluate().length;
    // 首屏只展开到 12 行（4 列 = 48 张），远小于 2991
    expect(built, greaterThan(0));
    expect(built, lessThanOrEqualTo(4 * 12));
  });
}
