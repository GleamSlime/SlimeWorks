import 'dart:convert';

import 'package:slime_works/mock/mock_assets.dart';

/// 游戏库演示数据：游戏、分类、游玩会话、进度、设置与统计。
class MockGameData {
  MockGameData._() {
    _seed();
  }

  static final MockGameData instance = MockGameData._();

  final List<Map<String, dynamic>> games = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> categories = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> sessions = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> progress =
      <String, Map<String, dynamic>>{};
  final Map<String, List<String>> gameCategories = <String, List<String>>{};
  final Set<String> favourites = <String>{};
  Map<String, dynamic> settings = <String, dynamic>{};

  int _seq = 0;

  static const List<String> _names = [
    '星海远征',
    '旧日酒馆',
    '机械纪元',
    '山谷回声',
    '雨夜列车',
    '像素农场',
    '深红要塞',
    '浮岛物语',
    '无声之城',
    '潮汐之心',
    '蒸汽工坊',
    '纸上王国',
    '北境传说',
    '午夜书店',
    '光与影',
    '远方信号',
  ];

  static const List<String> _companies = [
    'Kite Studio',
    'Nova Works',
    '青空游戏',
    'Pixel Forge',
    'Lumen Team',
  ];

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    categories.addAll([
      {'id': 'cat-action', 'name': '动作', 'emoji': '⚔️', 'isSystem': false, 'createdAt': now, 'gameCount': 4},
      {'id': 'cat-rpg', 'name': '角色扮演', 'emoji': '🧭', 'isSystem': false, 'createdAt': now, 'gameCount': 5},
      {'id': 'cat-indie', 'name': '独立', 'emoji': '💡', 'isSystem': false, 'createdAt': now, 'gameCount': 3},
      {'id': 'cat-strategy', 'name': '策略', 'emoji': '♟️', 'isSystem': false, 'createdAt': now, 'gameCount': 2},
      {'id': 'cat-adventure', 'name': '冒险', 'emoji': '🗺️', 'isSystem': false, 'createdAt': now, 'gameCount': 2},
    ]);

    for (var i = 0; i < _names.length; i++) {
      final id = 'game-${++_seq}';
      final status = switch (i % 4) {
        0 => 'playing',
        1 => 'completed',
        2 => 'not_started',
        _ => 'on_hold',
      };
      final playSec = status == 'not_started' ? 0 : (i + 1) * 5400;
      games.add({
        'id': id,
        'name': _names[i],
        'coverPath': MockAssets.imagePath(
          'game-$id',
          width: 460,
          height: 640,
          style: 1,
        ),
        'company': _companies[i % _companies.length],
        'summary': '《${_names[i]}》演示条目：用于离线展示游戏库的浏览、分类、统计与详情流程。',
        'rating': 6.5 + (i % 4),
        'releaseDate': '202${i % 5}-0${1 + i % 9}-1${i % 9}',
        'path': '/mock/games/${_names[i]}.app',
        'status': status,
        'createdAt': now - (i + 1) * 86400000,
        'updatedAt': now - i * 3600000,
        'lastPlayedAt': status == 'not_started' ? null : now - (i + 1) * 7200000,
        'totalPlayTimeSec': playSec,
        'tags': <String>['演示', _companies[i % _companies.length]],
        'exePaths': <String>[],
        'gameDir': '/mock/games/${_names[i]}',
      });
      gameCategories[id] = [
        ['cat-action', 'cat-rpg', 'cat-indie', 'cat-strategy', 'cat-adventure'][i % 5],
      ];
      if (i % 5 == 0) favourites.add(id);
      for (var s = 0; s < 6; s++) {
        final start = now - (s + 1) * 86400000 - i * 3600000;
        sessions.add({
          'id': 'sess-$id-$s',
          'gameId': id,
          'startTime': start,
          'endTime': start + (2400 + s * 600) * 1000,
          'durationSec': 2400 + s * 600,
        });
      }
      progress[id] = {
        'id': 'prog-$id',
        'gameId': id,
        'chapter': '第 ${1 + i % 6} 章',
        'route': i.isEven ? '主线' : '支线',
        'note': '演示进度备注',
        'updatedAt': now - i * 600000,
      };
    }

    settings = {
      'autoTrackPlayTime': true,
      'defaultSort': 'updatedAt_desc',
      'autoSave': true,
      'enableDesktopLaunch': true,
      'useOpenOnMacos': false,
    };
  }

  Map<String, dynamic>? byId(String id) {
    for (final g in games) {
      if (g['id'] == id) return g;
    }
    return null;
  }

  String getGamesJson() => jsonEncode(games);

  String getGameByIdJson(String id) => jsonEncode(byId(id) ?? {});

  String addGameJson(String gameJson) {
    final map = jsonDecode(gameJson) as Map<String, dynamic>;
    final id = (map['id'] as String?)?.isNotEmpty == true
        ? map['id'] as String
        : 'game-${++_seq}';
    map['id'] = id;
    map['coverPath'] = (map['coverPath'] as String?)?.isNotEmpty == true
        ? map['coverPath']
        : MockAssets.imagePath('game-$id', width: 460, height: 640, style: 1);
    map['createdAt'] ??= DateTime.now().millisecondsSinceEpoch;
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    map['totalPlayTimeSec'] ??= 0;
    map['tags'] ??= <String>[];
    map['exePaths'] ??= <String>[];
    games.insert(0, map);
    return jsonEncode(map);
  }

  void updateGameJson(String gameJson) {
    final map = jsonDecode(gameJson) as Map<String, dynamic>;
    final i = games.indexWhere((g) => g['id'] == map['id']);
    if (i >= 0) games[i] = {...games[i], ...map};
  }

  void deleteGame(String id) {
    games.removeWhere((g) => g['id'] == id);
    sessions.removeWhere((s) => s['gameId'] == id);
    progress.remove(id);
  }

  String getCategoriesJson() {
    for (final c in categories) {
      c['gameCount'] = gameCategories.values
          .where((ids) => ids.contains(c['id']))
          .length;
    }
    return jsonEncode(categories);
  }

  String upsertCategoryJson(String categoryJson) {
    final map = jsonDecode(categoryJson) as Map<String, dynamic>;
    final id = (map['id'] as String?)?.isNotEmpty == true
        ? map['id'] as String
        : 'cat-${++_seq}';
    map['id'] = id;
    map['createdAt'] ??= DateTime.now().millisecondsSinceEpoch;
    map['isSystem'] = map['isSystem'] ?? false;
    map['gameCount'] = 0;
    final i = categories.indexWhere((c) => c['id'] == id);
    if (i >= 0) {
      categories[i] = {...categories[i], ...map};
    } else {
      categories.add(map);
    }
    return jsonEncode(map);
  }

  void deleteCategory(String id) {
    categories.removeWhere((c) => c['id'] == id);
    for (final ids in gameCategories.values) {
      ids.remove(id);
    }
  }

  void addGameToCategory(String gameId, String categoryId) {
    final ids = gameCategories.putIfAbsent(gameId, () => <String>[]);
    if (!ids.contains(categoryId)) ids.add(categoryId);
  }

  void removeGameFromCategory(String gameId, String categoryId) {
    gameCategories[gameId]?.remove(categoryId);
  }

  List<String> categoryIdsOf(String gameId) => gameCategories[gameId] ?? const [];

  void toggleFavorite(String gameId, bool value) {
    if (value) {
      favourites.add(gameId);
    } else {
      favourites.remove(gameId);
    }
  }

  bool isFavorite(String gameId) => favourites.contains(gameId);

  void addSession(String sessionJson) {
    final map = jsonDecode(sessionJson) as Map<String, dynamic>;
    map['id'] ??= 'sess-${++_seq}';
    sessions.add(map);
    final gameId = map['gameId'] as String? ?? '';
    final i = games.indexWhere((g) => g['id'] == gameId);
    if (i >= 0) {
      games[i]['totalPlayTimeSec'] =
          (games[i]['totalPlayTimeSec'] as int? ?? 0) +
          (map['durationSec'] as int? ?? 0);
      games[i]['lastPlayedAt'] = map['startTime'];
    }
  }

  String getSessionsJson(String gameId) => jsonEncode(
    sessions.where((s) => s['gameId'] == gameId).toList(),
  );

  void upsertProgress(String progressJson) {
    final map = jsonDecode(progressJson) as Map<String, dynamic>;
    map['id'] ??= 'prog-${++_seq}';
    final gameId = map['gameId'] as String? ?? '';
    map['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    progress[gameId] = map;
  }

  String getProgressJson(String gameId) {
    final p = progress[gameId];
    return jsonEncode(p == null ? <Map<String, dynamic>>[] : [p]);
  }

  String getStatsJson(int startTsSec, int endTsSec) {
    final start = DateTime.fromMillisecondsSinceEpoch(startTsSec * 1000);
    final end = DateTime.fromMillisecondsSinceEpoch(endTsSec * 1000);
    final timeline = <Map<String, dynamic>>[];
    var total = 0;
    var count = 0;
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      final key = DateTime(d.year, d.month, d.day);
      final daySessions = sessions.where((s) {
        final t = DateTime.fromMillisecondsSinceEpoch(s['startTime'] as int);
        return t.year == key.year && t.month == key.month && t.day == key.day;
      });
      final duration = daySessions.fold<int>(
        0,
        (sum, s) => sum + (s['durationSec'] as int? ?? 0),
      );
      timeline.add({
        'date': '${key.year.toString().padLeft(4, '0')}-'
            '${key.month.toString().padLeft(2, '0')}-'
            '${key.day.toString().padLeft(2, '0')}',
        'durationSec': duration,
      });
      total += duration;
      count += daySessions.length;
    }
    return jsonEncode({
      'totalPlayTimeSec': total,
      'sessionCount': count,
      'timeline': timeline,
    });
  }

  String getHomePageDataJson() {
    final now = DateTime.now();
    final today = sessions.where((s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s['startTime'] as int);
      return t.year == now.year && t.month == now.month && t.day == now.day;
    });
    final week = sessions.where((s) {
      final t = DateTime.fromMillisecondsSinceEpoch(s['startTime'] as int);
      return now.difference(t).inDays <= 7;
    });
    final sorted = List<Map<String, dynamic>>.of(games)
      ..sort(
        (a, b) => ((b['lastPlayedAt'] as int?) ?? 0).compareTo(
          (a['lastPlayedAt'] as int?) ?? 0,
        ),
      );
    return jsonEncode({
      'lastPlayedGame': sorted.isEmpty ? null : sorted.first,
      'todayPlayTimeSec': today.fold<int>(
        0,
        (sum, s) => sum + (s['durationSec'] as int? ?? 0),
      ),
      'weekPlayTimeSec': week.fold<int>(
        0,
        (sum, s) => sum + (s['durationSec'] as int? ?? 0),
      ),
      'totalGames': games.length,
      'totalPlayTimeSec': games.fold<int>(
        0,
        (sum, g) => sum + (g['totalPlayTimeSec'] as int? ?? 0),
      ),
    });
  }

  String scanDirectoryJson(List<String> paths) {
    final added = <Map<String, dynamic>>[];
    for (final p in paths) {
      final parts = p.split(RegExp(r'[/\\]')).where((e) => e.isNotEmpty).toList();
      final name = parts.isEmpty ? '扫描到的游戏' : parts.last;
      final json = addGameJson(jsonEncode({'name': name, 'path': p, 'status': 'not_started'}));
      added.add(jsonDecode(json) as Map<String, dynamic>);
    }
    return jsonEncode(added);
  }

  String deriveName(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '未命名游戏' : parts.last;
  }

  String getSettingsJson() => jsonEncode(settings);

  void saveSettingsJson(String json) {
    settings = jsonDecode(json) as Map<String, dynamic>;
  }
}
