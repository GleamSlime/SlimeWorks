// 游戏库服务层可测逻辑单测（GameLibraryService + GameLibraryMetadataApi）。
//
// 可测性结论（先读码验证过）：
// - GameLibraryService 的 CRUD 方法确实全部经 FRB 调用 Rust（rust_api.gameLibrary*），
//   但 FRB 2.11 提供官方 mock 注入点 `RustLib.initMock(api: ...)`：
//   本文件用 noSuchMethod 桩实现 RustLibApi，按方法名注入返回值，
//   从而把 Dart 侧的 JSON 解析容错 / 字段加工 / 集合差分逻辑全部变为可观察行为。
// - init() 的"DB 路径注入(约L40)"验证属实：_resolveDbPath 是私有方法，
//   但可通过 PathProviderPlatform fake + mock 后端捕获 gameLibraryInit 入参观察。
// - GameLibraryMetadataApi 的 Dio 不可注入（私有 _dio、URL 硬编码外网），
//   但其 4 个底层 HTTP 方法（searchSteam/getSteamAppDetails/searchVndb/searchBangumi）
//   是公开的，子类覆写后即可完整驱动 searchByName 的择优/清洗/容错管线
//   （_pickVndbTitle、_buildSearchCandidates 等私有纯函数借此可达）。
// - 真实 HTTP 层的非 200 / 坏 JSON 降级不可测（client 不可注入），
//   以"任意异常都被 searchByName 吞掉并降级为 null"等价覆盖。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

// ── FRB mock 后端 ────────────────────────────────────────────────────────────

/// 把 `gameLibraryXxx` 顶层函数名映射到生成的 `crateApiGameLibraryGameLibraryXxx` 方法名。
String fn(String apiName) =>
    'crateApiGameLibrary${apiName[0].toUpperCase()}${apiName.substring(1)}';

String _symbolName(Symbol symbol) {
  final String text = symbol.toString();
  final RegExpMatch? match = RegExp(r'Symbol\("(.+?)"\)').firstMatch(text);
  return match?.group(1) ?? text;
}

/// 一次 mock 调用记录（方法名 + 具名参数）。
class _MockCall {
  _MockCall(this.method, this.args);

  final String method;
  final Map<Symbol, Object?> args;
}

/// FRB mock 后端：GameLibraryService 用到的全部 Rust 入口按方法名逐个桩。
/// 未配置的方法直接抛错，避免桩写错方法名时"静默通过"。
class _MockGameLibraryApi implements RustLibApi {
  /// key = crateApi 方法名；value = 注入返回值（必须与声明返回类型一致）。
  final Map<String, Object?> responses = <String, Object?>{};

  /// 需要按入参分发返回值的方法（如按 gameId 返回不同分类集合）。
  final Map<String, Object? Function(Map<Symbol, Object?> args)> responders =
      <String, Object? Function(Map<Symbol, Object?> args)>{};

  final List<_MockCall> calls = <_MockCall>[];

  List<_MockCall> callsOf(String method) =>
      calls.where((_MockCall c) => c.method == method).toList(growable: false);

  Map<String, Object?>? lastJsonArg(String method, Symbol key) {
    final List<_MockCall> list = callsOf(method);
    if (list.isEmpty) return null;
    return jsonDecode(list.last.args[key]! as String) as Map<String, Object?>;
  }

  void stubJson(String apiName, String json) {
    responses[fn(apiName)] = Future<String>.value(json);
  }

  void stubVoid(String apiName) {
    responses[fn(apiName)] = Future<void>.value();
  }

  void stubStrings(String apiName, List<String> value) {
    responses[fn(apiName)] = Future<List<String>>.value(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final String method = _symbolName(invocation.memberName);
    final Map<Symbol, Object?> named = invocation.namedArguments;
    calls.add(_MockCall(method, named));
    if (responses.containsKey(method)) return responses[method];
    final Object? Function(Map<Symbol, Object?>)? responder = responders[method];
    if (responder != null) return responder(named);
    throw StateError('mock 后端未配置该 FFI 方法: $method');
  }
}

// ── path_provider fake ──────────────────────────────────────────────────────

/// 只伪造 application-support 目录，用于观察 _resolveDbPath 的落点。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.supportDir);

  final String supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

// ── 元数据 API 脚本桩 ────────────────────────────────────────────────────────

/// 覆写 4 个公开 HTTP 原语，把 GameLibraryMetadataApi 变成纯内存解析管线。
class _ScriptedMetadataApi extends GameLibraryMetadataApi {
  _ScriptedMetadataApi({
    Map<String, dynamic> Function(String query)? steam,
    Map<String, dynamic> Function(String appId)? details,
    Map<String, dynamic> Function(String query)? vndb,
    Map<String, dynamic> Function(String query)? bangumi,
  }) {
    if (steam != null) steamSearch = steam;
    if (details != null) steamDetails = details;
    if (vndb != null) vndbSearch = vndb;
    if (bangumi != null) bangumiSearch = bangumi;
  }

  Map<String, dynamic> Function(String query) steamSearch =
      (String q) => <String, dynamic>{};
  Map<String, dynamic> Function(String appId) steamDetails =
      (String id) => <String, dynamic>{};
  Map<String, dynamic> Function(String query) vndbSearch =
      (String q) => <String, dynamic>{};
  Map<String, dynamic> Function(String query) bangumiSearch =
      (String q) => <String, dynamic>{};

  final List<String> steamQueries = <String>[];
  final List<String> detailAppIds = <String>[];
  final List<String> vndbQueries = <String>[];
  final List<String> bangumiQueries = <String>[];

  @override
  Future<Map<String, dynamic>> searchSteam(String query) async {
    steamQueries.add(query);
    return steamSearch(query);
  }

  @override
  Future<Map<String, dynamic>> getSteamAppDetails(String appId) async {
    detailAppIds.add(appId);
    return steamDetails(appId);
  }

  @override
  Future<Map<String, dynamic>> searchVndb(String query) async {
    vndbQueries.add(query);
    return vndbSearch(query);
  }

  @override
  Future<Map<String, dynamic>> searchBangumi(String query) async {
    bangumiQueries.add(query);
    return bangumiSearch(query);
  }
}

// ── 测试数据构造 ─────────────────────────────────────────────────────────────

Map<String, Object?> gameJson([Map<String, Object?> overrides = const <String, Object?>{}]) {
  return <String, Object?>{
    'id': 'g1',
    'name': '测试游戏',
    'coverPath': '',
    'company': '社',
    'summary': '简介',
    'rating': 8.5,
    'releaseDate': '2024-01-01',
    'path': '/apps/game',
    'status': 'playing',
    'createdAt': 1700000000000,
    'updatedAt': 1700000001000,
    'lastPlayedAt': null,
    'totalPlayTimeSec': 3600,
    'tags': <String>[],
    'exePaths': <String>[],
    'gameDir': '',
    ...overrides,
  };
}

Map<String, Object?> categoryJson([Map<String, Object?> overrides = const <String, Object?>{}]) {
  return <String, Object?>{
    'id': 'c1',
    'name': '分类',
    'emoji': '🎮',
    'isSystem': false,
    'createdAt': 1700000000000,
    'gameCount': 2,
    ...overrides,
  };
}

Map<String, dynamic> steamSearchPayload({String id = '440', String name = 'TF2'}) {
  return <String, dynamic>{
    'items': <dynamic>[
      <String, dynamic>{'id': id, 'name': name, 'tiny_image': 'https://tiny/$id'},
    ],
  };
}

Map<String, dynamic> steamDetailsPayload(
  String appId,
  Map<String, dynamic> data, {
  bool success = true,
}) {
  return <String, dynamic>{
    appId: <String, dynamic>{'success': success, 'data': data},
  };
}

Map<String, dynamic> vndbResult(
  Map<String, Object?> fields, {
  String rootTitle = 'Root',
}) {
  return <String, dynamic>{
    'results': <dynamic>[
      <String, dynamic>{'id': 'g123', 'title': rootTitle, ...fields},
    ],
  };
}

void main() {
  final _MockGameLibraryApi mock = _MockGameLibraryApi();

  setUpAll(() {
    // 官方 mock 注入：不加载 Rust 动态库，全部 crateApi 方法走 noSuchMethod。
    RustLib.initMock(api: mock);
  });

  setUp(() {
    mock.responses.clear();
    mock.responders.clear();
    mock.calls.clear();
    // 同步方法 gameLibraryIsReady 默认返回 false（各用例可覆盖）。
    mock.responses[fn('gameLibraryIsReady')] = false;
    mock.responses[fn('gameLibraryInit')] = null; // 同步 void
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GameLibraryService（经 mock 后端驱动 Dart 侧加工逻辑）
  // ═════════════════════════════════════════════════════════════════════════

  group('GameLibraryService - 初始化', () {
    test('Rust 侧已就绪时 init 只置位标志，不再建库', () async {
      mock.responses[fn('gameLibraryIsReady')] = true;
      final GameLibraryService service = GameLibraryService();
      expect(service.initialized, isFalse);

      await service.init();

      expect(service.initialized, isTrue);
      expect(mock.callsOf(fn('gameLibraryInit')), isEmpty);
    });

    test('未就绪时按 application-support 目录推导 dbPath 并注入', () async {
      final Directory tmp = Directory.systemTemp.createTempSync('game_lib_db_path');
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {
          // 清理失败不影响断言
        }
      });
      PathProviderPlatform.instance = _FakePathProvider(tmp.path);
      addTearDown(() => PathProviderPlatform.instance = _FakePathProvider(''));

      final GameLibraryService service = GameLibraryService();
      await service.init();

      final List<_MockCall> inits = mock.callsOf(fn('gameLibraryInit'));
      expect(inits, hasLength(1));
      final String dbPath = inits.last.args[#dbPath]! as String;
      expect(dbPath, '${tmp.path}/game_library/game_library.db');
      // 目录确实被创建（_resolveDbPath 的 create(recursive:true) 副作用）
      expect(Directory('${tmp.path}/game_library').existsSync(), isTrue);
    });

    test('init 幂等：二次调用直接返回', () async {
      mock.responses[fn('gameLibraryIsReady')] = true;
      final GameLibraryService service = GameLibraryService();
      await service.init();
      await service.init();
      expect(service.initialized, isTrue);
    });
  });

  group('GameLibraryService - 游戏 CRUD 的 JSON 容错', () {
    test('getGames 过滤非 Map 坏条目并解析合法项', () async {
      mock.stubJson(
        'gameLibraryGetGamesJson',
        jsonEncode(<Object?>[
          gameJson(),
          '坏条目',
          42,
          null,
          gameJson(<String, Object?>{'id': 'g2'}),
        ]),
      );
      final List<GameItem> games = await GameLibraryService().getGames();
      expect(games.map((GameItem g) => g.id), <String>['g1', 'g2']);
      expect(games.first.name, '测试游戏');
      expect(games.first.status, GameStatus.playing);
    });

    test('getGames 空数组返回空列表', () async {
      mock.stubJson('gameLibraryGetGamesJson', '[]');
      expect(await GameLibraryService().getGames(), isEmpty);
    });

    test('getGameById 空串→null，非空→对象', () async {
      mock.stubJson('gameLibraryGetGameByIdJson', '');
      expect(await GameLibraryService().getGameById('nope'), isNull);

      mock.stubJson(
        'gameLibraryGetGameByIdJson',
        jsonEncode(gameJson(<String, Object?>{'id': 'g9'})),
      );
      final GameItem? item = await GameLibraryService().getGameById('g9');
      expect(item?.id, 'g9');
      expect(item?.rating, 8.5);
    });

    test('addGame 在 Dart 侧完成 trim/默认值后才发给 Rust', () async {
      mock.stubJson(
        'gameLibraryAddGameJson',
        jsonEncode(gameJson(<String, Object?>{'id': 'new-1'})),
      );

      final GameItem added = await GameLibraryService().addGame(
        name: '  视觉小说  ',
        company: ' 制作组 ',
        summary: ' 简介 ',
        rating: 7.7,
        releaseDate: ' 2024 ',
        path: ' /game.exe ',
        status: GameStatus.completed,
        coverPath: '  /cover.jpg ',
        gameDir: ' /dir ',
      );

      final Map<String, Object?> sent =
          mock.lastJsonArg(fn('gameLibraryAddGameJson'), #gameJson)!;
      expect(sent['name'], '视觉小说');
      expect(sent['company'], '制作组');
      expect(sent['summary'], '简介');
      expect(sent['releaseDate'], '2024');
      expect(sent['path'], '/game.exe');
      expect(sent['coverPath'], '/cover.jpg');
      expect(sent['gameDir'], '/dir');
      // 默认值：id 空、时长 0、创建/更新时间一致、标签与 exe 列表默认为空
      expect(sent['id'], '');
      expect(sent['totalPlayTimeSec'], 0);
      expect(sent['createdAt'], sent['updatedAt']);
      expect(sent['status'], 'completed');
      expect(sent['tags'], isEmpty);
      expect(sent['exePaths'], isEmpty);
      // 返回值来自 Rust 回填的 JSON
      expect(added.id, 'new-1');
    });

    test('updateGame/deleteGame 透传序列化参数', () async {
      mock.stubVoid('gameLibraryUpdateGameJson');
      mock.stubVoid('gameLibraryDeleteGame');
      final GameLibraryService service = GameLibraryService();

      await service.updateGame(GameItem.fromJson(gameJson(<String, Object?>{'id': 'u1'})));
      expect(mock.lastJsonArg(fn('gameLibraryUpdateGameJson'), #gameJson)!['id'], 'u1');

      await service.deleteGame('u1');
      expect(mock.callsOf(fn('gameLibraryDeleteGame')).last.args[#gameId], 'u1');
    });
  });

  group('GameLibraryService - 分类', () {
    test('getCategories 过滤非 Map 坏条目', () async {
      mock.stubJson(
        'gameLibraryGetCategoriesJson',
        jsonEncode(<Object?>[categoryJson(), null, 3, categoryJson(<String, Object?>{'id': 'c2'})]),
      );
      final List<GameCategory> cats = await GameLibraryService().getCategories();
      expect(cats.map((GameCategory c) => c.id), <String>['c1', 'c2']);
      expect(cats.first.gameCount, 2);
    });

    test('upsertCategory 序列化入参并解析返回', () async {
      mock.stubJson(
        'gameLibraryUpsertCategoryJson',
        jsonEncode(categoryJson(<String, Object?>{'id': 'saved'})),
      );
      final GameCategory result = await GameLibraryService().upsertCategory(
        GameCategory(
          id: '',
          name: '新建',
          emoji: '📁',
          isSystem: false,
          createdAt: DateTime(2024),
          gameCount: 0,
        ),
      );
      expect(
        mock.lastJsonArg(fn('gameLibraryUpsertCategoryJson'), #categoryJson)!['name'],
        '新建',
      );
      expect(result.id, 'saved');
    });

    test('deleteCategory 透传 ID', () async {
      mock.stubVoid('gameLibraryDeleteCategory');
      await GameLibraryService().deleteCategory('cX');
      expect(mock.callsOf(fn('gameLibraryDeleteCategory')).last.args[#categoryId], 'cX');
    });

    test('getCategoryIdsByGameId 返回去重集合', () async {
      mock.stubStrings('gameLibraryGetGameCategoryIds', <String>['a', 'b', 'a']);
      final Set<String> ids = await GameLibraryService().getCategoryIdsByGameId('g1');
      expect(ids, <String>{'a', 'b'});
    });

    test('setGameCategories 只对差集做增删，公共项不动', () async {
      mock.stubStrings('gameLibraryGetGameCategoryIds', <String>['a', 'b']);
      mock.stubVoid('gameLibraryAddGameToCategory');
      mock.stubVoid('gameLibraryRemoveGameFromCategory');

      await GameLibraryService().setGameCategories('g1', <String>{'b', 'c'});

      final List<_MockCall> adds = mock.callsOf(fn('gameLibraryAddGameToCategory'));
      final List<_MockCall> removes = mock.callsOf(fn('gameLibraryRemoveGameFromCategory'));
      // current={a,b}, target={b,c} → 只加 c、只删 a，公共项 b 不动
      expect(adds.map((_MockCall c) => c.args[#categoryId]), <String>['c']);
      expect(removes.map((_MockCall c) => c.args[#categoryId]), <String>['a']);
      expect(adds.every((_MockCall c) => c.args[#gameId] == 'g1'), isTrue);
      expect(removes.any((_MockCall c) => c.args[#categoryId] == 'b'), isFalse);
    });

    test('getGamesByCategory 并行查分类并过滤命中项', () async {
      mock.stubJson(
        'gameLibraryGetGamesJson',
        jsonEncode(<Object?>[gameJson(<String, Object?>{'id': 'g1'}), gameJson(<String, Object?>{'id': 'g2'})]),
      );
      mock.responders[fn('gameLibraryGetGameCategoryIds')] =
          (Map<Symbol, Object?> args) => Future<List<String>>.value(
                args[#gameId] == 'g2' ? <String>['hot'] : <String>['cold'],
              );

      final List<GameItem> hit = await GameLibraryService().getGamesByCategory('hot');
      expect(hit.map((GameItem g) => g.id), <String>['g2']);
    });

    test('游戏列表为空时短路，不发分类查询', () async {
      mock.stubJson('gameLibraryGetGamesJson', '[]');
      final List<GameItem> hit = await GameLibraryService().getGamesByCategory('hot');
      expect(hit, isEmpty);
      expect(mock.callsOf(fn('gameLibraryGetGameCategoryIds')), isEmpty);
    });
  });

  group('GameLibraryService - 收藏/游玩记录/进度', () {
    test('isFavorite/toggleFavorite 透传', () async {
      mock.responses[fn('gameLibraryIsFavorite')] = Future<bool>.value(true);
      expect(await GameLibraryService().isFavorite('g1'), isTrue);

      mock.stubVoid('gameLibraryToggleFavorite');
      await GameLibraryService().toggleFavorite('g1', true);
      final _MockCall call = mock.callsOf(fn('gameLibraryToggleFavorite')).last;
      expect(call.args[#gameId], 'g1');
      expect(call.args[#favorite], isTrue);
    });

    test('addPlaySession 时长<=0 直接跳过，不发 FFI', () async {
      final GameLibraryService service = GameLibraryService();
      final DateTime start = DateTime(2024, 5, 1, 10);

      await service.addPlaySession(gameId: 'g1', startTime: start, endTime: start);
      await service.addPlaySession(
        gameId: 'g1',
        startTime: start,
        endTime: start.add(const Duration(seconds: -1)),
      );
      expect(mock.callsOf(fn('gameLibraryAddPlaySessionJson')), isEmpty);
    });

    test('addPlaySession 正常时长序列化秒数与时间戳', () async {
      mock.stubVoid('gameLibraryAddPlaySessionJson');
      final GameLibraryService service = GameLibraryService();
      final DateTime start = DateTime(2024, 5, 1, 10);
      final DateTime end = start.add(const Duration(minutes: 2));

      await service.addPlaySession(gameId: 'g7', startTime: start, endTime: end);

      final Map<String, Object?> sent = mock.lastJsonArg(
        fn('gameLibraryAddPlaySessionJson'),
        #sessionJson,
      )!;
      expect(sent['gameId'], 'g7');
      expect(sent['durationSec'], 120);
      expect(sent['startTime'], start.millisecondsSinceEpoch);
      expect(sent['endTime'], end.millisecondsSinceEpoch);
    });

    test('getPlaySessionsByGameId 过滤坏条目', () async {
      mock.stubJson(
        'gameLibraryGetPlaySessionsJson',
        jsonEncode(<Object?>[
          <String, Object?>{'id': 's1', 'gameId': 'g1', 'startTime': 1, 'endTime': 2, 'durationSec': 1},
          '坏',
        ]),
      );
      final List<PlaySession> sessions = await GameLibraryService().getPlaySessionsByGameId('g1');
      expect(sessions, hasLength(1));
      expect(sessions.first.id, 's1');
    });

    test('upsertProgress 已存在时复用旧 id，否则空串', () async {
      // 借用 gameJson 的 Map 形状：进度解析只读取其中的 id 字段
      mock.stubJson('gameLibraryGetProgressJson', jsonEncode(<Object?>[gameJson()]));
      // 注意：Rust 侧 upsertProgressJson 声明返回 Future<String>（回填后的记录）
      mock.stubJson('gameLibraryUpsertProgressJson', '{}');
      await GameLibraryService().upsertProgress(gameId: 'g1', chapter: '第一章', route: 'A', note: 'n');
      Map<String, Object?> sent = mock.lastJsonArg(
        fn('gameLibraryUpsertProgressJson'),
        #progressJson,
      )!;
      expect(sent['id'], 'g1'); // 命中已有记录 → 复用
      expect(sent['chapter'], '第一章');

      mock.calls.clear();
      mock.stubJson('gameLibraryGetProgressJson', '[]');
      await GameLibraryService().upsertProgress(gameId: 'g1', chapter: 'c', route: '', note: '');
      sent = mock.lastJsonArg(fn('gameLibraryUpsertProgressJson'), #progressJson)!;
      expect(sent['id'], ''); // 无已有记录 → 新增
    });

    test('getProgressByGameId 空列表→null，非空取首条', () async {
      mock.stubJson('gameLibraryGetProgressJson', '[]');
      expect(await GameLibraryService().getProgressByGameId('g1'), isNull);

      mock.stubJson(
        'gameLibraryGetProgressJson',
        jsonEncode(<Object?>[
          <String, Object?>{'id': 'p1', 'gameId': 'g1', 'chapter': '终章', 'route': 'True', 'note': '', 'updatedAt': 5},
        ]),
      );
      final GameProgress? progress = await GameLibraryService().getProgressByGameId('g1');
      expect(progress?.id, 'p1');
      expect(progress?.chapter, '终章');
    });
  });

  group('GameLibraryService - 首页/统计/设置', () {
    test('getHomeData 缺字段全部落默认值', () async {
      mock.stubJson('gameLibraryGetHomePageDataJson', '{}');
      final GameLibraryHomeData data = await GameLibraryService().getHomeData();
      expect(data.lastPlayedGame, isNull);
      expect(data.todayPlayTimeSec, 0);
      expect(data.weekPlayTimeSec, 0);
      expect(data.totalGames, 0);
      expect(data.totalPlayTimeSec, 0);
    });

    test('getHomeData 正常解析 lastPlayedGame，非 Map 时置 null', () async {
      mock.stubJson(
        'gameLibraryGetHomePageDataJson',
        jsonEncode(<String, Object?>{'lastPlayedGame': gameJson(<String, Object?>{'id': 'last'}), 'totalGames': 3}),
      );
      expect((await GameLibraryService().getHomeData()).lastPlayedGame?.id, 'last');

      mock.stubJson(
        'gameLibraryGetHomePageDataJson',
        jsonEncode(<String, Object?>{'lastPlayedGame': '坏数据'}),
      );
      expect((await GameLibraryService().getHomeData()).lastPlayedGame, isNull);
    });

    test('getStats 毫秒转秒 + timeline 坏条目过滤与日期兜底', () async {
      mock.stubJson(
        'gameLibraryGetStatsJson',
        jsonEncode(<String, Object?>{
          'totalPlayTimeSec': 300,
          'sessionCount': 2,
          'timeline': <Object?>[
            <String, Object?>{'date': '2024-03-05', 'durationSec': 100},
            <String, Object?>{'date': '坏日期'},
            '坏',
            <String, Object?>{},
          ],
        }),
      );
      final DateTime start = DateTime(2024, 3, 1);
      final GameStatsData stats = await GameLibraryService().getStats(
        start: start,
        end: start.add(const Duration(days: 7)),
      );

      final _MockCall call = mock.callsOf(fn('gameLibraryGetStatsJson')).last;
      expect(call.args[#startTsSec], start.millisecondsSinceEpoch ~/ 1000);

      expect(stats.totalPlayTimeSec, 300);
      expect(stats.sessionCount, 2);
      // 4 条记录：非 Map 被 whereType 过滤，坏日期/缺字段按默认值兜底
      expect(stats.timeline, hasLength(3));
      expect(stats.timeline[0].date, DateTime(2024, 3, 5));
      expect(stats.timeline[0].durationSec, 100);
      expect(stats.timeline[1].date, DateTime(1970, 1, 1)); // '坏日期' → 1970/1/1 兜底
      expect(stats.timeline[2].durationSec, 0);
    });

    test('getStats timeline 字段缺失时按空列表处理', () async {
      mock.stubJson('gameLibraryGetStatsJson', '{"sessionCount": 1}');
      final GameStatsData stats = await GameLibraryService().getStats(
        start: DateTime(2024),
        end: DateTime(2024),
      );
      expect(stats.timeline, isEmpty);
      expect(stats.totalPlayTimeSec, 0);
    });

    test('getSettings/updateSettings 缺字段走模型默认值 + 序列化往返', () async {
      mock.stubJson('gameLibraryGetSettingsJson', '{}');
      final GameLibrarySettings loaded = await GameLibraryService().getSettings();
      expect(loaded.autoTrackPlayTime, isTrue);
      expect(loaded.defaultSort, 'updatedAt_desc');
      expect(loaded.useOpenOnMacos, isFalse);

      mock.stubVoid('gameLibrarySaveSettingsJson');
      await GameLibraryService().updateSettings(loaded.copyWith(defaultSort: 'rating_desc'));
      expect(
        mock.lastJsonArg(fn('gameLibrarySaveSettingsJson'), #settingsJson)!['defaultSort'],
        'rating_desc',
      );
    });
  });

  group('GameLibraryService - 元数据搜索衔接（不触 FFI）', () {
    test('searchMetadataByName 原样转发给注入的 MetadataApi', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{'id': '1'}, rootTitle: 'N'),
      );

      final GameSearchMetadata? result =
          await GameLibraryService(metadataApi: api).searchMetadataByName('  N  ');
      expect(result?.name, 'N');
      expect(result?.source, 'vndb');
      // 候选词经过去空格/归一化，任何查询都不应带首尾空白
      expect(api.vndbQueries.every((String q) => q == q.trim()), isTrue);
    });

    test('元数据抓取全线异常被吞掉，返回 null 而不抛出（不阻断入库流程）', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => throw StateError('Steam 挂了'),
        vndb: (String q) => throw StateError('VNDB 挂了'),
        bangumi: (String q) => throw StateError('Bangumi 挂了'),
      );
      expect(await GameLibraryService(metadataApi: api).searchMetadataByName('任何名字'), isNull);
    });

    test('全空白名字不触发任何网络搜索', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi();
      expect(await GameLibraryService(metadataApi: api).searchMetadataByName('   '), isNull);
      expect(api.steamQueries + api.vndbQueries + api.bangumiQueries, isEmpty);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GameLibraryMetadataApi 解析管线（经公开原语子类覆写驱动私有解析函数）
  // ═════════════════════════════════════════════════════════════════════════

  group('MetadataApi - Steam 解析', () {
    test('完整字段映射：metacritic 87 → 8.7', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => steamSearchPayload(),
        details: (String id) => steamDetailsPayload(id, <String, dynamic>{
          'name': '军团要塞2',
          'developers': <dynamic>['Valve', ' Hub '],
          'metacritic': <String, dynamic>{'score': 87},
          'header_image': 'https://header',
          'short_description': '简介',
          'release_date': <String, dynamic>{'date': '2007年10月10日'},
        }),
      );

      final GameSearchMetadata? meta = await api.searchByName('tf2');
      expect(meta, isNotNull);
      expect(meta!.name, '军团要塞2');
      expect(meta.coverUrl, 'https://header');
      expect(meta.company, 'Valve, Hub');
      expect(meta.rating, closeTo(8.7, 1e-9));
      expect(meta.releaseDate, '2007年10月10日');
      expect(meta.source, 'steam');
      expect(meta.sourceId, '440');
      expect(api.detailAppIds, <String>['440']);
    });

    test('details 缺 name/图 时回退搜索项字段', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => steamSearchPayload(name: 'SearchName'),
        details: (String id) => steamDetailsPayload(id, <String, dynamic>{}),
      );
      final GameSearchMetadata? meta = await api.searchByName('x');
      expect(meta?.name, 'SearchName');
      expect(meta?.coverUrl, 'https://tiny/440');
      expect(meta?.rating, 0);
    });

    test('success!=true 视为未命中', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => steamSearchPayload(),
        details: (String id) => steamDetailsPayload(id, <String, dynamic>{'name': 'N'}, success: false),
      );
      expect(await api.searchByName('x'), isNull);
    });

    test('items 空/id 缺失时不再请求 details', () async {
      final _ScriptedMetadataApi noItems = _ScriptedMetadataApi(
        steam: (String q) => <String, dynamic>{'items': <dynamic>[]},
      );
      expect(await noItems.searchByName('x'), isNull);

      final _ScriptedMetadataApi noId = _ScriptedMetadataApi(
        steam: (String q) => <String, dynamic>{'items': <dynamic>[<String, dynamic>{'name': '无ID'}]},
      );
      expect(await noId.searchByName('x'), isNull);
      expect(noId.detailAppIds, isEmpty);
    });
  });

  group('MetadataApi - VNDB 解析（含 _pickVndbTitle 择优）', () {
    test('标题择优：main+official 得分最高者优先', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{
          'image': <String, dynamic>{'url': 'https://img'},
          'description': '描述',
          'rating': 9.5,
          'released': '2020-01-01',
          'developers': <dynamic>[
            <String, dynamic>{'name': '社A'},
            <String, dynamic>{'name': '社B'},
          ],
          'titles': <dynamic>[
            <String, dynamic>{'title': '普通英文名', 'latin': '', 'main': false, 'official': false},
            <String, dynamic>{'title': '主官方名', 'latin': '', 'main': true, 'official': true},
            <String, dynamic>{'title': '主非官方', 'latin': '', 'main': true, 'official': false},
          ],
        }),
      );
      final GameSearchMetadata? meta = await api.searchByName('y');
      expect(meta?.name, '主官方名');
      expect(meta?.company, '社A, 社B');
      expect(meta?.coverUrl, 'https://img');
      expect(meta?.rating, 9.5);
      expect(meta?.source, 'vndb');
      expect(meta?.sourceId, 'g123');
    });

    test('择优标题 title 空时回退 latin', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{
          'titles': <dynamic>[
            <String, dynamic>{'title': '', 'latin': 'Latin主名', 'main': true, 'official': true},
          ],
        }),
      );
      expect((await api.searchByName('y'))?.name, 'Latin主名');
    });

    test('titles 全空/缺字段时回退根 title', () async {
      final _ScriptedMetadataApi emptyTitles = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{
          'titles': <dynamic>[
            <String, dynamic>{'title': '', 'latin': '', 'main': true, 'official': true},
          ],
        }),
      );
      expect((await emptyTitles.searchByName('y'))?.name, 'Root');

      final _ScriptedMetadataApi noTitles = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{}),
      );
      expect((await noTitles.searchByName('y'))?.name, 'Root');
    });

    test('rating 越界钳制：>10→10，负数→0；字符串数字可解析', () async {
      Future<double> ratingOf(Object? rating) async {
        final _ScriptedMetadataApi api = _ScriptedMetadataApi(
          vndb: (String q) => vndbResult(<String, Object?>{'rating': rating}),
        );
        final GameSearchMetadata? meta = await api.searchByName('y');
        return meta?.rating ?? -1;
      }

      expect(await ratingOf(15.2), 10);
      expect(await ratingOf(-3), 0);
      expect(await ratingOf('8.5'), 8.5);
      expect(await ratingOf('非数字'), 0);
    });

    test('results 形状坏（非列表/全非 Map）返回 null', () async {
      final _ScriptedMetadataApi notList = _ScriptedMetadataApi(
        vndb: (String q) => <String, dynamic>{'results': '不是列表'},
      );
      expect(await notList.searchByName('z'), isNull);

      final _ScriptedMetadataApi badItems = _ScriptedMetadataApi(
        vndb: (String q) => <String, dynamic>{'results': <dynamic>[1, 2]},
      );
      expect(await badItems.searchByName('z'), isNull);
    });
  });

  group('MetadataApi - Bangumi 解析（含 _extractBangumiCompany）', () {
    Map<String, dynamic> bangumiPayload(Map<String, dynamic> first) {
      return <String, dynamic>{'list': <dynamic>[first]};
    }

    test('name_cn 优先、large 图优先、score 归一、infobox 字符串值开发社', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        bangumi: (String q) => bangumiPayload(<String, dynamic>{
          'id': 99,
          'name': 'EnglishName',
          'name_cn': '中文名',
          'images': <String, dynamic>{'large': 'https://large', 'common': 'https://common'},
          'summary': '简介',
          'score': 8.2,
          'air_date': '2021-04-01',
          'infobox': <dynamic>[
            <String, dynamic>{'key': '发行', 'value': '不该命中'},
            <String, dynamic>{'key': '开发', 'value': ' 社A '},
          ],
        }),
      );
      final GameSearchMetadata? meta = await api.searchByName('b');
      expect(meta?.name, '中文名');
      expect(meta?.coverUrl, 'https://large');
      expect(meta?.company, '社A');
      expect(meta?.rating, closeTo(8.2, 1e-9));
      expect(meta?.source, 'bangumi');
      expect(meta?.sourceId, '99');
    });

    test('name_cn 空回退 name；large 空回退 common；infobox 列表值拼接', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        bangumi: (String q) => bangumiPayload(<String, dynamic>{
          'id': 1,
          'name': 'OnlyEn',
          'name_cn': '',
          'images': <String, dynamic>{'common': 'https://common'},
          'infobox': <dynamic>[
            <String, dynamic>{
              'key': '制作公司',
              'value': <dynamic>[
                <String, dynamic>{'v': '社X'},
                <String, dynamic>{'v': ''},
                <String, dynamic>{'v': '社Y'},
              ],
            },
          ],
        }),
      );
      final GameSearchMetadata? meta = await api.searchByName('b');
      expect(meta?.name, 'OnlyEn');
      expect(meta?.coverUrl, 'https://common');
      expect(meta?.company, '社X, 社Y');
      expect(meta?.rating, 0);
    });

    test('无命中名称或列表为空返回 null', () async {
      final _ScriptedMetadataApi emptyList = _ScriptedMetadataApi(
        bangumi: (String q) => <String, dynamic>{'list': <dynamic>[]},
      );
      expect(await emptyList.searchByName('b'), isNull);

      final _ScriptedMetadataApi noName = _ScriptedMetadataApi(
        bangumi: (String q) => bangumiPayload(<String, dynamic>{'name': '', 'name_cn': ''}),
      );
      expect(await noName.searchByName('b'), isNull);
    });
  });

  group('MetadataApi - 搜索编排与容错', () {
    test('数据源顺序：steam > vndb > bangumi', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => steamSearchPayload(),
        details: (String id) => steamDetailsPayload(id, <String, dynamic>{'name': 'Steam命中'}),
        vndb: (String q) => vndbResult(<String, Object?>{}, rootTitle: 'VNDB命中'),
        bangumi: (String q) => <String, dynamic>{
          'list': <dynamic>[<String, dynamic>{'id': 1, 'name': 'B命中'}],
        },
      );
      expect((await api.searchByName('q'))?.name, 'Steam命中');
      expect(api.vndbQueries, isEmpty);
    });

    test('steam 抛异常不影响 vndb 命中', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => throw StateError('网络错误'),
        vndb: (String q) => vndbResult(<String, Object?>{}, rootTitle: 'VNDB命中'),
      );
      final GameSearchMetadata? meta = await api.searchByName('q');
      expect(meta?.name, 'VNDB命中');
      expect(meta?.source, 'vndb');
    });

    test('候选查询：归一化去括号，长变体优先逐个重试', () async {
      final Map<String, dynamic> hit = vndbResult(<String, Object?>{}, rootTitle: '第二候补命中');
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        vndb: (String q) => q == '视觉小说' ? hit : <String, dynamic>{},
      );

      final GameSearchMetadata? meta = await api.searchByName(' 视觉小说 [完] ');
      expect(meta?.name, '第二候补命中');
      // 首轮全部未命中 → 第二轮规范化名命中；长变体排在前面
      expect(api.vndbQueries, <String>['视觉小说 [完]', '视觉小说']);
    });

    test('空格/下划线/连字符产生多种候选词', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi();
      await api.searchByName('a-b_c');
      expect(api.steamQueries.toSet(), <String>{'a b c', 'a-b_c', 'a-b-c'});
    });

    test('description 为数字等坏类型时用 toString 兜底而非抛错', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        vndb: (String q) => vndbResult(<String, Object?>{
          'description': 123,
          'image': '不是Map',
        }, rootTitle: 'T'),
      );
      final GameSearchMetadata? meta = await api.searchByName('q');
      expect(meta?.summary, '123');
      expect(meta?.coverUrl, '');
      expect(meta?.sourceId, 'g123');
    });

    test('三源全挂时 searchByName 返回 null 不抛异常', () async {
      final _ScriptedMetadataApi api = _ScriptedMetadataApi(
        steam: (String q) => throw Exception('a'),
        vndb: (String q) => throw Exception('b'),
        bangumi: (String q) => throw Exception('c'),
      );
      expect(await api.searchByName('名字'), isNull);
    });
  });
}
