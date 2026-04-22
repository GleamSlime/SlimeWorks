import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/src/rust/api/game_library.dart' as rust_api;
import 'package:slime_works/src/rust/frb_generated.dart';

final Loggers _log = Loggers(name: '游戏库服务');

/// 游戏库服务：数据持久化全部委托给 Rust/SQLite 层，Flutter 只处理 UI 相关数据转换。
class GameLibraryService {
  GameLibraryService({GameLibraryMetadataApi? metadataApi})
    : _metadataApi = metadataApi ?? GameLibraryMetadataApi();

  final GameLibraryMetadataApi _metadataApi;
  bool _initialized = false;

  bool get initialized => _initialized;

  /// 初始化：确保 Rust 库已加载并打开数据库
  Future<void> init() async {
    if (_initialized) return;
    if (!RustLib.instance.initialized) {
      await RustLib.init();
    }
    if (!rust_api.gameLibraryIsReady()) {
      final String dbPath = await _resolveDbPath();
      rust_api.gameLibraryInit(dbPath: dbPath);
      _log.info('游戏库数据库已初始化: $dbPath');
    }
    _initialized = true;
    _log.info('游戏库服务初始化完成');
  }

  /// 数据库文件路径
  Future<String> _resolveDbPath() async {
    final Directory dir = await getApplicationSupportDirectory();
    final String dbDir = '${dir.path}/game_library';
    await Directory(dbDir).create(recursive: true);
    return '$dbDir/game_library.db';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 游戏 CRUD
  // ───────────────────────────────────────────────────────────────────────────

  /// 获取所有游戏列表
  Future<List<GameItem>> getGames() async {
    final String json = await rust_api.gameLibraryGetGamesJson();
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list
        .whereType<Map>()
        .map((Map e) => GameItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// 根据 ID 获取游戏，不存在时返回 null
  Future<GameItem?> getGameById(String gameId) async {
    final String json = await rust_api.gameLibraryGetGameByIdJson(gameId: gameId);
    if (json.isEmpty) return null;
    return GameItem.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 新增游戏，返回带 id 的 GameItem
  Future<GameItem> addGame({
    required String name,
    required String company,
    required String summary,
    required double rating,
    required String releaseDate,
    required String path,
    required GameStatus status,
    required String coverPath,
    List<String> tags = const <String>[],
    List<String> exePaths = const <String>[],
    String gameDir = '',
  }) async {
    final DateTime now = DateTime.now();
    final GameItem item = GameItem(
      id: '',
      name: name.trim(),
      coverPath: coverPath.trim(),
      company: company.trim(),
      summary: summary.trim(),
      rating: rating,
      releaseDate: releaseDate.trim(),
      path: path.trim(),
      status: status,
      createdAt: now,
      updatedAt: now,
      totalPlayTimeSec: 0,
      tags: tags,
      exePaths: exePaths,
      gameDir: gameDir.trim(),
    );
    final String resultJson = await rust_api.gameLibraryAddGameJson(
      gameJson: jsonEncode(item.toJson()),
    );
    return GameItem.fromJson(jsonDecode(resultJson) as Map<String, dynamic>);
  }

  /// 更新游戏信息
  Future<void> updateGame(GameItem game) async {
    await rust_api.gameLibraryUpdateGameJson(gameJson: jsonEncode(game.toJson()));
  }

  /// 删除游戏及其关联数据
  Future<void> deleteGame(String gameId) async {
    await rust_api.gameLibraryDeleteGame(gameId: gameId);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 分类
  // ───────────────────────────────────────────────────────────────────────────

  /// 获取所有分类（含 gameCount）
  Future<List<GameCategory>> getCategories() async {
    final String json = await rust_api.gameLibraryGetCategoriesJson();
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list
        .whereType<Map>()
        .map((Map e) => GameCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// 新增或更新分类
  Future<GameCategory> upsertCategory(GameCategory category) async {
    final String resultJson = await rust_api.gameLibraryUpsertCategoryJson(
      categoryJson: jsonEncode(category.toJson()),
    );
    return GameCategory.fromJson(jsonDecode(resultJson) as Map<String, dynamic>);
  }

  /// 删除分类
  Future<void> deleteCategory(String categoryId) async {
    await rust_api.gameLibraryDeleteCategory(categoryId: categoryId);
  }

  /// 获取某游戏所属的分类 ID 集合
  Future<Set<String>> getCategoryIdsByGameId(String gameId) async {
    final List<String> ids = await rust_api.gameLibraryGetGameCategoryIds(gameId: gameId);
    return ids.toSet();
  }

  /// 设置游戏的分类（全量替换）
  Future<void> setGameCategories(String gameId, Set<String> categoryIds) async {
    final Set<String> current = await getCategoryIdsByGameId(gameId);
    final Set<String> toAdd = categoryIds.difference(current);
    final Set<String> toRemove = current.difference(categoryIds);
    for (final String id in toAdd) {
      await rust_api.gameLibraryAddGameToCategory(gameId: gameId, categoryId: id);
    }
    for (final String id in toRemove) {
      await rust_api.gameLibraryRemoveGameFromCategory(gameId: gameId, categoryId: id);
    }
  }

  /// 获取某分类下的游戏列表（先拿全量再过滤，避免 N+1 也不增加 Rust API）
  Future<List<GameItem>> getGamesByCategory(String categoryId) async {
    final List<GameItem> all = await getGames();
    final List<String> allIds = all.map((GameItem g) => g.id).toList(growable: false);
    final Set<String> matching = <String>{};
    for (final String id in allIds) {
      final Set<String> cats = await getCategoryIdsByGameId(id);
      if (cats.contains(categoryId)) matching.add(id);
    }
    return all.where((GameItem g) => matching.contains(g.id)).toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 收藏
  // ───────────────────────────────────────────────────────────────────────────

  Future<bool> isFavorite(String gameId) async {
    return rust_api.gameLibraryIsFavorite(gameId: gameId);
  }

  Future<void> toggleFavorite(String gameId, bool favorite) async {
    await rust_api.gameLibraryToggleFavorite(gameId: gameId, favorite: favorite);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 游玩记录
  // ───────────────────────────────────────────────────────────────────────────

  /// 新增游玩会话记录
  Future<void> addPlaySession({
    required String gameId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final int duration = endTime.difference(startTime).inSeconds;
    if (duration <= 0) return;
    final Map<String, dynamic> sessionJson = <String, dynamic>{
      'id': '',
      'gameId': gameId,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationSec': duration,
    };
    await rust_api.gameLibraryAddPlaySessionJson(sessionJson: jsonEncode(sessionJson));
    _log.info('游玩记录已保存: gameId=$gameId, 时长=${duration}s');
  }

  /// 获取某游戏的游玩记录
  Future<List<PlaySession>> getPlaySessionsByGameId(String gameId) async {
    final String json = await rust_api.gameLibraryGetPlaySessionsJson(gameId: gameId);
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    return list
        .whereType<Map>()
        .map((Map e) => PlaySession.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 游戏进度
  // ───────────────────────────────────────────────────────────────────────────

  /// 保存游戏进度（新增或更新，每个游戏只保留一条）
  Future<void> upsertProgress({
    required String gameId,
    required String chapter,
    required String route,
    required String note,
  }) async {
    final GameProgress? existing = await getProgressByGameId(gameId);
    final Map<String, dynamic> progressJson = <String, dynamic>{
      'id': existing?.id ?? '',
      'gameId': gameId,
      'chapter': chapter,
      'route': route,
      'note': note,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await rust_api.gameLibraryUpsertProgressJson(progressJson: jsonEncode(progressJson));
  }

  /// 获取某游戏的进度（返回最新一条，没有则返回 null）
  Future<GameProgress?> getProgressByGameId(String gameId) async {
    final String json = await rust_api.gameLibraryGetProgressJson(gameId: gameId);
    final List<dynamic> list = jsonDecode(json) as List<dynamic>;
    if (list.isEmpty) return null;
    return GameProgress.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 统计 & 首页
  // ───────────────────────────────────────────────────────────────────────────

  /// 获取首页数据
  Future<GameLibraryHomeData> getHomeData() async {
    final String json = await rust_api.gameLibraryGetHomePageDataJson();
    final Map<String, dynamic> m = jsonDecode(json) as Map<String, dynamic>;
    GameItem? lastGame;
    final dynamic lg = m['lastPlayedGame'];
    if (lg is Map) {
      lastGame = GameItem.fromJson(Map<String, dynamic>.from(lg));
    }
    return GameLibraryHomeData(
      lastPlayedGame: lastGame,
      todayPlayTimeSec: (m['todayPlayTimeSec'] as num?)?.toInt() ?? 0,
      weekPlayTimeSec: (m['weekPlayTimeSec'] as num?)?.toInt() ?? 0,
      totalGames: (m['totalGames'] as num?)?.toInt() ?? 0,
      totalPlayTimeSec: (m['totalPlayTimeSec'] as num?)?.toInt() ?? 0,
    );
  }

  /// 获取统计数据
  Future<GameStatsData> getStats({required DateTime start, required DateTime end}) async {
    final int startTs = start.millisecondsSinceEpoch ~/ 1000;
    final int endTs = end.millisecondsSinceEpoch ~/ 1000;
    final String json = await rust_api.gameLibraryGetStatsJson(
      startTsSec: startTs,
      endTsSec: endTs,
    );
    final Map<String, dynamic> m = jsonDecode(json) as Map<String, dynamic>;
    final List<dynamic> tl = (m['timeline'] as List<dynamic>?) ?? <dynamic>[];
    final List<DayPlayTime> timeline = tl
        .whereType<Map>()
        .map((Map e) {
          final String dateStr = e['date'] as String? ?? '';
          final List<String> parts = dateStr.split('-');
          final int year = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1970;
          final int month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
          final int day = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 1;
          return DayPlayTime(
            date: DateTime(year, month, day),
            durationSec: (e['durationSec'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);

    return GameStatsData(
      totalPlayTimeSec: (m['totalPlayTimeSec'] as num?)?.toInt() ?? 0,
      sessionCount: (m['sessionCount'] as num?)?.toInt() ?? 0,
      timeline: timeline,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 设置
  // ───────────────────────────────────────────────────────────────────────────

  /// 读取游戏库设置
  Future<GameLibrarySettings> getSettings() async {
    final String json = await rust_api.gameLibraryGetSettingsJson();
    return GameLibrarySettings.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// 保存游戏库设置
  Future<void> updateSettings(GameLibrarySettings settings) async {
    await rust_api.gameLibrarySaveSettingsJson(settingsJson: jsonEncode(settings.toJson()));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 元数据搜索（HTTP 网络层，保留在 Dart 层）
  // ───────────────────────────────────────────────────────────────────────────

  Future<GameSearchMetadata?> searchMetadataByName(String rawName) =>
      _metadataApi.searchByName(rawName);
}
