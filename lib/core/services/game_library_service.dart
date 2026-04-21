import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

const String _kGamesKey = 'game_library_games';
const String _kCategoriesKey = 'game_library_categories';
const String _kGameCategoryMapKey = 'game_library_game_category_map';
const String _kPlaySessionsKey = 'game_library_play_sessions';
const String _kProgressKey = 'game_library_progress';
const String _kSettingsKey = 'game_library_settings';
const String _kHasSeededKey = 'game_library_has_seeded';

const String systemFavoritesId = 'system:favorites';

final Loggers _gameLibraryLogger = Loggers(name: '游戏库服务');

class GameLibraryService {
  GameLibraryService({GameLibraryMetadataApi? metadataApi})
    : _metadataApi = metadataApi ?? GameLibraryMetadataApi();

  final Uuid _uuid = const Uuid();
  final GameLibraryMetadataApi _metadataApi;

  SharedPreferences? _prefs;
  final List<GameItem> _games = <GameItem>[];
  final List<GameCategory> _categories = <GameCategory>[];
  final List<PlaySession> _sessions = <PlaySession>[];
  final List<GameProgress> _progress = <GameProgress>[];
  final Map<String, Set<String>> _gameCategoryMap = <String, Set<String>>{};
  GameLibrarySettings _settings = GameLibrarySettings.defaultValue();

  bool _initialized = false;

  bool get initialized => _initialized;

  List<GameItem> get games => List<GameItem>.unmodifiable(_games);

  List<GameCategory> get categories {
    return _categories
        .map(
          (GameCategory c) => c.copyWith(
            gameCount: _gameCategoryMap.values
                .where((Set<String> ids) => ids.contains(c.id))
                .length,
          ),
        )
        .toList(growable: false);
  }

  GameLibrarySettings get settings => _settings;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _prefs = await SharedPreferences.getInstance();
    _loadFromPrefs();
    await _ensureSystemCategory();
    await _seedIfNeeded();
    _initialized = true;
    _gameLibraryLogger.info('游戏库服务初始化完成，games=${_games.length}');
  }

  Future<void> _ensureSystemCategory() async {
    final bool exists = _categories.any((GameCategory c) => c.id == systemFavoritesId);
    if (exists) {
      return;
    }

    _categories.add(
      GameCategory(
        id: systemFavoritesId,
        name: '最喜欢的游戏',
        emoji: '⭐',
        isSystem: true,
        createdAt: DateTime.now(),
        gameCount: 0,
      ),
    );
    await _persistCategories();
  }

  Future<void> _seedIfNeeded() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    final bool hasSeeded = prefs.getBool(_kHasSeededKey) ?? false;
    if (hasSeeded) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<GameItem> seeded = <GameItem>[
      GameItem(
        id: _uuid.v4(),
        name: '示例：Summer Pockets',
        coverPath: '',
        company: 'Key',
        summary: '用于演示迁移后游戏库功能的示例数据。',
        rating: 9.2,
        releaseDate: '2018-06-29',
        path: '',
        status: GameStatus.playing,
        createdAt: now,
        updatedAt: now,
        totalPlayTimeSec: 3600 * 12,
        lastPlayedAt: now.subtract(const Duration(hours: 2)),
        tags: const <String>['催泪', '校园'],
      ),
      GameItem(
        id: _uuid.v4(),
        name: '示例：CLANNAD',
        coverPath: '',
        company: 'Key',
        summary: '经典视觉小说示例条目。',
        rating: 9.5,
        releaseDate: '2004-04-28',
        path: '',
        status: GameStatus.completed,
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 1)),
        totalPlayTimeSec: 3600 * 40,
        lastPlayedAt: now.subtract(const Duration(days: 4)),
        tags: const <String>['亲情', '成长'],
      ),
    ];

    _games.addAll(seeded);

    for (final GameItem game in seeded) {
      _gameCategoryMap[game.id] = <String>{if (game.rating >= 9) systemFavoritesId};
      _sessions.add(
        PlaySession(
          id: _uuid.v4(),
          gameId: game.id,
          startTime: now.subtract(const Duration(days: 1, hours: 3)),
          endTime: now.subtract(const Duration(days: 1, hours: 1)),
          durationSec: 7200,
        ),
      );
    }

    await _persistAll();
    await prefs.setBool(_kHasSeededKey, true);
  }

  Future<void> _persistAll() async {
    await _persistGames();
    await _persistCategories();
    await _persistCategoryMap();
    await _persistSessions();
    await _persistProgress();
    await _persistSettings();
  }

  void _loadFromPrefs() {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }

    final String gamesJson = prefs.getString(_kGamesKey) ?? '[]';
    final String categoriesJson = prefs.getString(_kCategoriesKey) ?? '[]';
    final String mapJson = prefs.getString(_kGameCategoryMapKey) ?? '{}';
    final String sessionsJson = prefs.getString(_kPlaySessionsKey) ?? '[]';
    final String progressJson = prefs.getString(_kProgressKey) ?? '[]';
    final String settingsJson = prefs.getString(_kSettingsKey) ?? '{}';

    final List<dynamic> gameList = jsonDecode(gamesJson) as List<dynamic>;
    final List<dynamic> categoryList = jsonDecode(categoriesJson) as List<dynamic>;
    final Map<String, dynamic> categoryMap = jsonDecode(mapJson) as Map<String, dynamic>;
    final List<dynamic> sessionList = jsonDecode(sessionsJson) as List<dynamic>;
    final List<dynamic> progressList = jsonDecode(progressJson) as List<dynamic>;
    final Map<String, dynamic> settingsMap = jsonDecode(settingsJson) as Map<String, dynamic>;

    _games
      ..clear()
      ..addAll(
        gameList
            .whereType<Map>()
            .map((Map e) => GameItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _categories
      ..clear()
      ..addAll(
        categoryList
            .whereType<Map>()
            .map((Map e) => GameCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _gameCategoryMap
      ..clear()
      ..addAll(
        categoryMap.map(
          (String key, dynamic value) => MapEntry(
            key,
            ((value as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toSet(),
          ),
        ),
      );

    _sessions
      ..clear()
      ..addAll(
        sessionList
            .whereType<Map>()
            .map((Map e) => PlaySession.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _progress
      ..clear()
      ..addAll(
        progressList
            .whereType<Map>()
            .map((Map e) => GameProgress.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    if (settingsMap.isNotEmpty) {
      _settings = GameLibrarySettings.fromJson(settingsMap);
    }
  }

  Future<void> _persistGames() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    final String encoded = jsonEncode(_games.map((GameItem e) => e.toJson()).toList());
    await prefs.setString(_kGamesKey, encoded);
  }

  Future<void> _persistCategories() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    final String encoded = jsonEncode(_categories.map((GameCategory e) => e.toJson()).toList());
    await prefs.setString(_kCategoriesKey, encoded);
  }

  Future<void> _persistCategoryMap() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    final Map<String, List<String>> map = _gameCategoryMap.map(
      (String key, Set<String> value) => MapEntry(key, value.toList(growable: false)),
    );
    await prefs.setString(_kGameCategoryMapKey, jsonEncode(map));
  }

  Future<void> _persistSessions() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString(
      _kPlaySessionsKey,
      jsonEncode(_sessions.map((PlaySession e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistProgress() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString(
      _kProgressKey,
      jsonEncode(_progress.map((GameProgress e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistSettings() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString(_kSettingsKey, jsonEncode(_settings.toJson()));
  }

  Future<GameItem> addGame({
    required String name,
    required String company,
    required String summary,
    required double rating,
    required String releaseDate,
    required String path,
    required GameStatus status,
    required String coverPath,
  }) async {
    final DateTime now = DateTime.now();
    final GameItem item = GameItem(
      id: _uuid.v4(),
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
      tags: const <String>[],
    );
    _games.add(item);
    await _persistGames();
    return item;
  }

  Future<void> updateGame(GameItem game) async {
    final int idx = _games.indexWhere((GameItem e) => e.id == game.id);
    if (idx < 0) {
      return;
    }
    _games[idx] = game.copyWith(updatedAt: DateTime.now());
    await _persistGames();
  }

  Future<void> deleteGame(String gameId) async {
    _games.removeWhere((GameItem e) => e.id == gameId);
    _sessions.removeWhere((PlaySession e) => e.gameId == gameId);
    _progress.removeWhere((GameProgress e) => e.gameId == gameId);
    _gameCategoryMap.remove(gameId);
    await _persistGames();
    await _persistSessions();
    await _persistProgress();
    await _persistCategoryMap();
  }

  GameItem? getGameById(String gameId) {
    try {
      return _games.firstWhere((GameItem e) => e.id == gameId);
    } catch (_) {
      return null;
    }
  }

  Future<GameCategory> addCategory({required String name, required String emoji}) async {
    final GameCategory category = GameCategory(
      id: _uuid.v4(),
      name: name.trim(),
      emoji: emoji.trim().isEmpty ? '📁' : emoji.trim(),
      isSystem: false,
      createdAt: DateTime.now(),
      gameCount: 0,
    );
    _categories.add(category);
    await _persistCategories();
    return category;
  }

  Future<void> updateCategory(GameCategory category) async {
    final int idx = _categories.indexWhere((GameCategory c) => c.id == category.id);
    if (idx < 0 || _categories[idx].isSystem) {
      return;
    }
    _categories[idx] = category;
    await _persistCategories();
  }

  Future<void> deleteCategory(String categoryId) async {
    final int index = _categories.indexWhere((GameCategory c) => c.id == categoryId);
    if (index < 0 || _categories[index].isSystem) {
      return;
    }

    _categories.removeWhere((GameCategory c) => c.id == categoryId);
    for (final Set<String> value in _gameCategoryMap.values) {
      value.remove(categoryId);
    }
    await _persistCategories();
    await _persistCategoryMap();
  }

  Set<String> getCategoryIdsByGameId(String gameId) {
    return _gameCategoryMap[gameId] ?? <String>{};
  }

  Future<void> setGameCategories(String gameId, Set<String> categoryIds) async {
    _gameCategoryMap[gameId] = categoryIds;
    await _persistCategoryMap();
  }

  List<GameItem> getGamesByCategory(String categoryId) {
    return _games
        .where((GameItem game) => (_gameCategoryMap[game.id] ?? <String>{}).contains(categoryId))
        .toList();
  }

  Future<void> addPlaySession({
    required String gameId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final int duration = endTime.difference(startTime).inSeconds;
    if (duration <= 0) {
      return;
    }
    final PlaySession session = PlaySession(
      id: _uuid.v4(),
      gameId: gameId,
      startTime: startTime,
      endTime: endTime,
      durationSec: duration,
    );
    _sessions.add(session);
    final int idx = _games.indexWhere((GameItem e) => e.id == gameId);
    if (idx >= 0) {
      final GameItem old = _games[idx];
      _games[idx] = old.copyWith(
        lastPlayedAt: endTime,
        totalPlayTimeSec: old.totalPlayTimeSec + duration,
        status: old.status == GameStatus.notStarted ? GameStatus.playing : old.status,
        updatedAt: DateTime.now(),
      );
    }
    await _persistSessions();
    await _persistGames();
  }

  List<PlaySession> getPlaySessionsByGameId(String gameId) {
    final List<PlaySession> list =
        _sessions.where((PlaySession e) => e.gameId == gameId).toList(growable: false)
          ..sort((PlaySession a, PlaySession b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  Future<void> upsertProgress({
    required String gameId,
    required String chapter,
    required String route,
    required String note,
  }) async {
    final int idx = _progress.indexWhere((GameProgress e) => e.gameId == gameId);
    final GameProgress next = GameProgress(
      id: idx >= 0 ? _progress[idx].id : _uuid.v4(),
      gameId: gameId,
      chapter: chapter,
      route: route,
      note: note,
      updatedAt: DateTime.now(),
    );

    if (idx >= 0) {
      _progress[idx] = next;
    } else {
      _progress.add(next);
    }
    await _persistProgress();
  }

  GameProgress? getProgressByGameId(String gameId) {
    try {
      return _progress.firstWhere((GameProgress e) => e.gameId == gameId);
    } catch (_) {
      return null;
    }
  }

  GameLibraryHomeData getHomeData() {
    GameItem? lastPlayed;
    if (_games.isNotEmpty) {
      final List<GameItem> sorted = List<GameItem>.from(_games)
        ..sort((GameItem a, GameItem b) {
          final DateTime at = a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime bt = b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      lastPlayed = sorted.first;
    }

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final int weekDayOffset = now.weekday - DateTime.monday;
    final DateTime weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: weekDayOffset));

    int todaySec = 0;
    int weekSec = 0;
    int totalSec = 0;

    for (final PlaySession s in _sessions) {
      totalSec += s.durationSec;
      if (s.startTime.isAfter(todayStart)) {
        todaySec += s.durationSec;
      }
      if (s.startTime.isAfter(weekStart)) {
        weekSec += s.durationSec;
      }
    }

    return GameLibraryHomeData(
      lastPlayedGame: lastPlayed,
      todayPlayTimeSec: todaySec,
      weekPlayTimeSec: weekSec,
      totalGames: _games.length,
      totalPlayTimeSec: totalSec,
    );
  }

  GameStatsData getStats({required DateTime start, required DateTime end}) {
    final DateTime startDay = DateTime(start.year, start.month, start.day);
    final DateTime endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);

    final List<PlaySession> range = _sessions
        .where(
          (PlaySession s) =>
              s.startTime.isAfter(startDay.subtract(const Duration(seconds: 1))) &&
              s.startTime.isBefore(endDay.add(const Duration(seconds: 1))),
        )
        .toList(growable: false);

    int total = 0;
    final Map<String, int> dayMap = <String, int>{};
    for (final PlaySession s in range) {
      total += s.durationSec;
      final DateTime d = DateTime(s.startTime.year, s.startTime.month, s.startTime.day);
      final String key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dayMap[key] = (dayMap[key] ?? 0) + s.durationSec;
    }

    final List<DayPlayTime> timeline =
        dayMap.entries
            .map((MapEntry<String, int> e) {
              final List<String> parts = e.key.split('-');
              final int year = int.tryParse(parts[0]) ?? 1970;
              final int month = int.tryParse(parts[1]) ?? 1;
              final int day = int.tryParse(parts[2]) ?? 1;
              return DayPlayTime(date: DateTime(year, month, day), durationSec: e.value);
            })
            .toList(growable: false)
          ..sort((DayPlayTime a, DayPlayTime b) => a.date.compareTo(b.date));

    return GameStatsData(totalPlayTimeSec: total, sessionCount: range.length, timeline: timeline);
  }

  Future<void> updateSettings(GameLibrarySettings settings) async {
    _settings = settings;
    await _persistSettings();
  }

  String exportBackupJson() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'games': _games.map((GameItem e) => e.toJson()).toList(growable: false),
      'categories': _categories.map((GameCategory e) => e.toJson()).toList(growable: false),
      'gameCategoryMap': _gameCategoryMap.map(
        (String key, Set<String> value) => MapEntry(key, value.toList(growable: false)),
      ),
      'sessions': _sessions.map((PlaySession e) => e.toJson()).toList(growable: false),
      'progress': _progress.map((GameProgress e) => e.toJson()).toList(growable: false),
      'settings': _settings.toJson(),
    };
    return jsonEncode(payload);
  }

  Future<void> importBackupJson(String jsonText) async {
    final Map<String, dynamic> root = Map<String, dynamic>.from(jsonDecode(jsonText) as Map);
    final List<dynamic> gamesList = (root['games'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> categoriesList = (root['categories'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      (root['gameCategoryMap'] as Map?) ?? <dynamic, dynamic>{},
    );
    final List<dynamic> sessionsList = (root['sessions'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> progressList = (root['progress'] as List<dynamic>?) ?? <dynamic>[];
    final Map<String, dynamic> settingsMap = Map<String, dynamic>.from(
      (root['settings'] as Map?) ?? <dynamic, dynamic>{},
    );

    _games
      ..clear()
      ..addAll(
        gamesList
            .whereType<Map>()
            .map((Map e) => GameItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _categories
      ..clear()
      ..addAll(
        categoriesList
            .whereType<Map>()
            .map((Map e) => GameCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _gameCategoryMap
      ..clear()
      ..addAll(
        map.map(
          (String key, dynamic value) => MapEntry(
            key,
            ((value as List<dynamic>?) ?? <dynamic>[]).map((dynamic e) => e.toString()).toSet(),
          ),
        ),
      );

    _sessions
      ..clear()
      ..addAll(
        sessionsList
            .whereType<Map>()
            .map((Map e) => PlaySession.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _progress
      ..clear()
      ..addAll(
        progressList
            .whereType<Map>()
            .map((Map e) => GameProgress.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );

    _settings = settingsMap.isEmpty
        ? GameLibrarySettings.defaultValue()
        : GameLibrarySettings.fromJson(settingsMap);

    await _ensureSystemCategory();
    await _persistAll();
  }

  bool isFavorite(String gameId) {
    return (_gameCategoryMap[gameId] ?? <String>{}).contains(systemFavoritesId);
  }

  Future<void> toggleFavorite(String gameId, bool favorite) async {
    final Set<String> target = _gameCategoryMap[gameId] ?? <String>{};
    if (favorite) {
      target.add(systemFavoritesId);
    } else {
      target.remove(systemFavoritesId);
    }
    _gameCategoryMap[gameId] = target;
    await _persistCategoryMap();
  }

  Future<GameSearchMetadata?> searchMetadataByName(String rawName) async {
    final List<String> queries = _buildSearchCandidates(rawName);
    if (queries.isEmpty) {
      return null;
    }

    final List<Future<GameSearchMetadata?> Function(String)> searchers =
        <Future<GameSearchMetadata?> Function(String)>[_searchSteam, _searchVndb, _searchBangumi];

    for (final String query in queries) {
      for (final Future<GameSearchMetadata?> Function(String) searcher in searchers) {
        try {
          final GameSearchMetadata? result = await searcher(query);
          if (result != null) {
            return result;
          }
        } catch (e) {
          _gameLibraryLogger.info('元数据搜索失败(query=$query): $e');
        }
      }
    }

    return null;
  }

  Future<GameSearchMetadata?> _searchVndb(String query) async {
    final Map<String, dynamic> root = await _metadataApi.searchVndb(query);
    final List<dynamic> results = _asList(root['results']);
    if (results.isEmpty) {
      return null;
    }

    final Map<String, dynamic> first = _asMap(results.first);
    final String title = _pickVndbTitle(first);
    if (title.isEmpty) {
      return null;
    }

    final List<dynamic> developers = _asList(first['developers']);
    final String company = developers
        .map((dynamic e) => _asString(_asMap(e)['name']))
        .where((String e) => e.isNotEmpty)
        .join(', ');

    return GameSearchMetadata(
      name: title,
      coverUrl: _asString(_asMap(first['image'])['url']),
      company: company,
      summary: _asString(first['description']),
      rating: _normalizeTenScore(_asDouble(first['rating'])),
      releaseDate: _asString(first['released']),
      source: 'vndb',
      sourceId: _asString(first['id']),
    );
  }

  Future<GameSearchMetadata?> _searchSteam(String query) async {
    final Map<String, dynamic> searchRoot = await _metadataApi.searchSteam(query);
    final List<dynamic> items = _asList(searchRoot['items']);
    if (items.isEmpty) {
      return null;
    }

    final Map<String, dynamic> firstItem = _asMap(items.first);
    final String appId = _asString(firstItem['id']);
    if (appId.isEmpty) {
      return null;
    }

    final Map<String, dynamic> detailRoot = await _metadataApi.getSteamAppDetails(appId);
    final Map<String, dynamic> appRoot = _asMap(detailRoot[appId]);
    final bool success = appRoot['success'] == true;
    if (!success) {
      return null;
    }

    final Map<String, dynamic> data = _asMap(appRoot['data']);
    final List<dynamic> developers = _asList(data['developers']);
    final String company = developers
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .join(', ');

    double rating = _asDouble(_asMap(data['metacritic'])['score']);
    if (rating > 0) {
      rating = rating / 10.0;
    }

    final String title = _asString(data['name']).isEmpty
        ? _asString(firstItem['name'])
        : _asString(data['name']);
    if (title.isEmpty) {
      return null;
    }

    final String cover = _asString(data['header_image']).isEmpty
        ? _asString(firstItem['tiny_image'])
        : _asString(data['header_image']);

    return GameSearchMetadata(
      name: title,
      coverUrl: cover,
      company: company,
      summary: _asString(data['short_description']),
      rating: _normalizeTenScore(rating),
      releaseDate: _asString(_asMap(data['release_date'])['date']),
      source: 'steam',
      sourceId: appId,
    );
  }

  Future<GameSearchMetadata?> _searchBangumi(String query) async {
    final Map<String, dynamic> root = await _metadataApi.searchBangumi(query);
    final List<dynamic> list = _asList(root['list']);
    if (list.isEmpty) {
      return null;
    }

    final Map<String, dynamic> first = _asMap(list.first);
    final String nameCn = _asString(first['name_cn']);
    final String name = nameCn.isEmpty ? _asString(first['name']) : nameCn;
    if (name.isEmpty) {
      return null;
    }

    final Map<String, dynamic> images = _asMap(first['images']);
    final String cover = _asString(images['large']).isEmpty
        ? _asString(images['common'])
        : _asString(images['large']);

    return GameSearchMetadata(
      name: name,
      coverUrl: cover,
      company: _extractBangumiCompany(_asList(first['infobox'])),
      summary: _asString(first['summary']),
      rating: _normalizeTenScore(_asDouble(first['score'])),
      releaseDate: _asString(first['air_date']),
      source: 'bangumi',
      sourceId: _asString(first['id']),
    );
  }

  String _pickVndbTitle(Map<String, dynamic> result) {
    final List<dynamic> titles = _asList(result['titles']);
    if (titles.isNotEmpty) {
      final List<Map<String, dynamic>> list = titles.map(_asMap).toList(growable: false);
      list.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
        int score(Map<String, dynamic> item) {
          int value = 0;
          if (item['main'] == true) {
            value += 2;
          }
          if (item['official'] == true) {
            value += 1;
          }
          return value;
        }

        return score(b).compareTo(score(a));
      });
      for (final Map<String, dynamic> titleItem in list) {
        final String title = _asString(titleItem['title']);
        if (title.isNotEmpty) {
          return title;
        }
        final String latin = _asString(titleItem['latin']);
        if (latin.isNotEmpty) {
          return latin;
        }
      }
    }
    return _asString(result['title']);
  }

  String _extractBangumiCompany(List<dynamic> infobox) {
    for (final dynamic raw in infobox) {
      final Map<String, dynamic> item = _asMap(raw);
      final String key = _asString(item['key']).toLowerCase();
      if (key.contains('开发') ||
          key.contains('制作') ||
          key.contains('厂商') ||
          key.contains('company')) {
        final dynamic value = item['value'];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
        if (value is List<dynamic>) {
          final String joined = value
              .map((dynamic e) => _asString(_asMap(e)['v']))
              .where((String e) => e.isNotEmpty)
              .join(', ');
          if (joined.isNotEmpty) {
            return joined;
          }
        }
      }
    }
    return '';
  }

  String _normalizeSearchKeyword(String rawName) {
    String value = rawName.trim();
    if (value.isEmpty) {
      return '';
    }

    value = value
        .replaceAll(RegExp(r'[\[\(【（].*?[\]\)】）]'), ' ')
        .replaceAll(RegExp(r'[_\.-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (value.length > 80) {
      value = value.substring(0, 80).trim();
    }
    return value;
  }

  List<String> _buildSearchCandidates(String rawName) {
    final Set<String> set = <String>{};

    void add(String value) {
      final String v = value.trim();
      if (v.isNotEmpty) {
        set.add(v);
      }
    }

    final String normalized = _normalizeSearchKeyword(rawName);
    add(normalized);
    add(rawName);
    add(normalized.replaceAll('-', ' '));
    add(normalized.replaceAll(' ', '-'));
    add(normalized.replaceAll('  ', ' '));

    final List<String> list = set.toList(growable: false);
    list.sort((String a, String b) => b.length.compareTo(a.length));
    return list;
  }

  double _normalizeTenScore(double score) {
    if (score.isNaN || score.isInfinite) {
      return 0;
    }
    if (score < 0) {
      return 0;
    }
    if (score > 10) {
      return 10;
    }
    return score;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
  }

  String _asString(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    return value.toString().trim();
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(_asString(value)) ?? 0;
  }
}

class GameSearchMetadata {
  const GameSearchMetadata({
    required this.name,
    required this.coverUrl,
    required this.company,
    required this.summary,
    required this.rating,
    required this.releaseDate,
    required this.source,
    required this.sourceId,
  });

  final String name;
  final String coverUrl;
  final String company;
  final String summary;
  final double rating;
  final String releaseDate;
  final String source;
  final String sourceId;
}
