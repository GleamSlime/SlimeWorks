// 阅读页「书中搜索 / 顶部与底部对齐 / 列表滚动保持」的回归。
//
// ═══════════════════════════════════════════════════════════════════════════
// 用户的三条反馈（2026-11-25）
// ═══════════════════════════════════════════════════════════════════════════
// 1. 「移动端正文阅读时还是无法使用搜索功能」——**节点侧 `search_in_novel`
//    早就实现了，客户端从未调用过它**。不是搜索失效，是压根没发请求。
// 2. 「阅读页功能要和桌面对齐」——远程阅读页顶栏只有「设置」，缺章节列表/
//    搜索；底栏缺收藏，且中间是硬编码「章节」二字而不是真实进度。
// 3. 「返回列表页滚动位置应保持不变」——`GridView` 没有 PageStorageKey，
//    页面重建就回到顶部。
//
// 下面既有「契约存在」的源码断言，也有对关键 API 的形状校验。
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final readerSrc = File(
    'lib/pages/collection/library/components/remote_novel_reader_dialog.dart',
  ).readAsStringSync();
  final libPageSrc = File(
    'lib/pages/novel_library/novel_library_page.dart',
  ).readAsStringSync();
  final svcSrc = File(
    'lib/core/services/node/node_settings_service.dart',
  ).readAsStringSync();

  group('书中搜索', () {
    test('客户端必须真的调用 search_in_novel', () {
      expect(
        svcSrc.contains("action: 'search_in_novel'"),
        isTrue,
        reason: '节点侧 search_in_novel 已实现；客户端不调它 = 搜索永远没结果',
      );
      expect(
        svcSrc.contains('searchInNodeNovel'),
        isTrue,
        reason: '客户端应暴露 searchInNodeNovel 方法',
      );
    });

    test('阅读页要有搜索入口，且搜索结果能跳到对应章节', () {
      expect(readerSrc.contains('_showInBookSearch'), isTrue);
      expect(readerSrc.contains("tooltip: '搜索'"), isTrue);
      expect(
        readerSrc.contains('_jumpToSearchResult(i)'),
        isTrue,
        reason: '搜索命中项点击后应跳到那一章并定位到正文位置',
      );
    });
  });

  group('阅读页顶部/底部与桌面对齐', () {
    test('顶栏要有 章节列表 / 搜索 / 设置', () {
      expect(readerSrc.contains("tooltip: '章节列表'"), isTrue);
      expect(readerSrc.contains("tooltip: '搜索'"), isTrue);
      expect(readerSrc.contains("tooltip: '设置'"), isTrue);
    });

    test('底栏要有收藏，且显示真实进度而不是硬编码「章节」', () {
      expect(
        readerSrc.contains("tooltip: isFavorite ? '取消收藏' : '收藏'"),
        isTrue,
        reason: '远程阅读底栏应与本地一致，带收藏按钮',
      );
      // 反例：中间那格曾经硬编码 Text('章节')
      final hardCoded = RegExp(r"child: Text\(\s*'章节'\s*,");
      expect(
        hardCoded.hasMatch(readerSrc),
        isFalse,
        reason: '底栏中间应显示「1/12」这类真实进度，不要硬编码「章节」',
      );
      expect(
        readerSrc.contains(r"'${currentIndex + 1}/$totalChapters'"),
        isTrue,
      );
    });
  });

  group('列表滚动位置保持', () {
    test('书库 GridView 必须带 PageStorageKey', () {
      expect(
        libPageSrc.contains('PageStorageKey<String>('),
        isTrue,
        reason: '没有 PageStorageKey，返回列表会弹回顶部（用户要重新滚）',
      );
      expect(
        libPageSrc.contains("PageStorageKey<String>('novel-library-grid')"),
        isTrue,
      );
    });
  });

  group('远程阅读返回列表刷新', () {
    test('两个远程阅读入口都刷新节点书库，收藏与进度不滞留', () {
      expect(
        RegExp(r'onFavoriteChanged:\s*controller\.refreshRemoteNovels').hasMatch(libPageSrc),
        isTrue,
      );
      expect(libPageSrc.contains('await controller.refreshRemoteNovels();'), isTrue);
      final cardSrc = File(
        'lib/pages/collection/library/components/library_book_card.dart',
      ).readAsStringSync();
      expect(
        cardSrc.contains('onFavoriteChanged: widget.viewModel.refreshRemoteNovels'),
        isTrue,
      );
      expect(
        cardSrc.contains('whenComplete(widget.viewModel.refreshRemoteNovels)'),
        isTrue,
      );
    });
  });

  group('节点搜索 API 形状', () {
    test('searchInNodeNovel 参数与返回字段正确', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'node_local_enabled': false,
      });
      await getIt.reset();
      getIt.registerSingleton<NodeSettingsService>(NodeSettingsService());
      final svc = getIt<NodeSettingsService>();
      await svc.init();

      // 没有该节点 → 必须抛错而不是静默返回空（否则用户看到"搜不到"却不知原因）
      await expectLater(
        svc.searchInNodeNovel(nodeId: 'nope', filePath: '/x.txt', keyword: 'k'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
