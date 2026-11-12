// P2-13：拖拽框选每帧全量重排 —— filteredGames 缓存 + 框选只在成员变化时落库。
//
// 验收口径两条：
// 1) 「选择变化」不得引起过滤/排序重算（用计数器桩观测，不靠耗时）；
// 2) 框选重复给出同一批 id 时不写响应式集合（否则整屏卡片每帧重建）。
import 'package:flutter_test/flutter_test.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_library_viewmodel.dart';

GameItem makeGame({
  required String id,
  String name = '测试游戏',
  double rating = 0,
  List<String> tags = const <String>[],
  DateTime? updatedAt,
}) {
  return GameItem(
    id: id,
    name: name,
    coverPath: '',
    company: '',
    summary: '',
    rating: rating,
    releaseDate: '',
    path: '',
    status: GameStatus.notStarted,
    createdAt: DateTime(2026),
    updatedAt: updatedAt ?? DateTime(2026),
    totalPlayTimeSec: 0,
    tags: tags,
    exePaths: const <String>[],
    gameDir: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 构造函数不触 FFI，全程不调 init()
    getIt.registerSingleton<GameLibraryService>(GameLibraryService());
    getIt.registerSingleton<GameProcessTracker>(
      GameProcessTracker(service: getIt<GameLibraryService>()),
    );
  });

  tearDownAll(() {
    getIt.unregister<GameLibraryService>();
    getIt.unregister<GameProcessTracker>();
  });

  group('filteredGames 缓存', () {
    late GameLibraryViewModel vm;

    setUp(() {
      vm = GameLibraryViewModel();
      vm.games.clear();
      vm.selectedIds.clear();
      vm.searchQuery.value = '';
      vm.selectedTag.value = '';
      vm.selectedStatus.value = null;
      vm.selectedSort.value = 'updatedAt_desc';
      vm.games.addAll(<GameItem>[
        makeGame(id: 'a', name: 'Alpha', rating: 9),
        makeGame(id: 'b', name: 'Beta', rating: 7),
        makeGame(id: 'c', name: 'Gamma', rating: 8, tags: const <String>['RPG']),
      ]);
    });

    tearDown(() {
      vm.onClose();
    });

    test('连续两次读取只算一次', () {
      final int before = vm.filteredGamesComputeCount;
      vm.filteredGames;
      vm.filteredGames;
      vm.filteredGames;
      expect(vm.filteredGamesComputeCount - before, 1);
    });

    test('选择变化不触发重算（拖拽期每帧都不重排）', () {
      vm.filteredGames; // 预热，先付一次冷启动
      final int before = vm.filteredGamesComputeCount;

      // 模拟框选拖拽：同一批 id 反复落库 + 成员逐步变化
      for (int i = 0; i < 50; i++) {
        vm.applyBoxSelection(<String>{'a', 'b'});
        vm.filteredGames;
      }
      expect(
        vm.filteredGamesComputeCount - before,
        0,
        reason: '选择不参与指纹：拖拽 50 帧一次都不该重算',
      );

      // 单点选择同样不参与指纹
      vm.toggleSelect('c');
      vm.filteredGames;
      expect(vm.filteredGamesComputeCount - before, 0);
    });

    test('搜索词变化必须重算', () {
      vm.filteredGames;
      final int before = vm.filteredGamesComputeCount;
      vm.searchQuery.value = 'alp';
      final List<GameItem> hits = vm.filteredGames;
      expect(hits.map((GameItem g) => g.id), <String>['a']);
      expect(vm.filteredGamesComputeCount - before, 1);
    });

    test('状态过滤 / 标签 / 排序键变化各自重算', () {
      vm.filteredGames;
      int before = vm.filteredGamesComputeCount;

      vm.selectedStatus.value = GameStatus.notStarted;
      vm.filteredGames;
      expect(vm.filteredGamesComputeCount, before + 1);

      before = vm.filteredGamesComputeCount;
      vm.selectedTag.value = 'RPG';
      final List<GameItem> tagged = vm.filteredGames;
      expect(tagged.map((GameItem g) => g.id), <String>['c']);
      expect(vm.filteredGamesComputeCount, before + 1);

      before = vm.filteredGamesComputeCount;
      vm.selectedSort.value = 'rating_desc';
      final List<GameItem> sorted = vm.filteredGames;
      expect(sorted.first.rating, 8); // 只剩 c，验证确实按新键重排过
      expect(vm.filteredGamesComputeCount, before + 1);
    });

    test('库内容变化后失效（refresh 会清缓存）', () async {
      vm.filteredGames;
      final int before = vm.filteredGamesComputeCount;
      // 直接改 games 后靠长度/首尾 id 指纹认出来
      vm.games.add(makeGame(id: 'd', name: 'Delta'));
      vm.filteredGames;
      expect(vm.filteredGamesComputeCount, before + 1);
    });
  });

  group('框选落点去重', () {
    late GameLibraryViewModel vm;

    setUp(() {
      vm = GameLibraryViewModel();
      vm.games.clear();
      vm.selectedIds.clear();
      vm.games.addAll(<GameItem>[
        makeGame(id: 'a'),
        makeGame(id: 'b'),
        makeGame(id: 'c'),
      ]);
    });

    tearDown(() => vm.onClose());

    test('成员没变时返回 false 且不写响应式集合', () {
      vm.applyBoxSelection(<String>{'a', 'b'});
      expect(vm.selectedIds, <String>{'a', 'b'});
      expect(vm.applyBoxSelection(<String>{'a', 'b'}), isFalse);
      // 顺序无关
      expect(vm.applyBoxSelection(<String>{'b', 'a'}), isFalse);
    });

    test('成员变化时返回 true 并替换旧选中', () {
      vm.applyBoxSelection(<String>{'a'});
      expect(vm.applyBoxSelection(<String>{'a', 'c'}), isTrue);
      expect(vm.selectedIds, <String>{'a', 'c'});
      expect(vm.applyBoxSelection(<String>{}), isTrue);
      expect(vm.selectedIds, isEmpty);
    });

    test('setSelectedFromIndices 越界忽略且走同一条去重路径', () {
      vm.setSelectedFromIndices(<int>[0, 2, 99, -1], vm.games);
      expect(vm.selectedIds, <String>{'a', 'c'});
      // 再来一次相同结果：不应再次 assignAll
      vm.setSelectedFromIndices(<int>[2, 0], vm.games);
      expect(vm.selectedIds, <String>{'a', 'c'});
    });
  });
}
