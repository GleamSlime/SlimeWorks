import 'dart:convert';

enum GameStatus {
  notStarted,
  playing,
  completed,
  onHold,
  dropped;

  String get value {
    switch (this) {
      case GameStatus.notStarted:
        return 'not_started';
      case GameStatus.playing:
        return 'playing';
      case GameStatus.completed:
        return 'completed';
      case GameStatus.onHold:
        return 'on_hold';
      case GameStatus.dropped:
        return 'dropped';
    }
  }

  String get label {
    switch (this) {
      case GameStatus.notStarted:
        return '未开始';
      case GameStatus.playing:
        return '游玩中';
      case GameStatus.completed:
        return '已通关';
      case GameStatus.onHold:
        return '搁置中';
      case GameStatus.dropped:
        return '弃坑';
    }
  }

  static GameStatus fromValue(String value) {
    return GameStatus.values.firstWhere(
      (GameStatus e) => e.value == value,
      orElse: () => GameStatus.notStarted,
    );
  }
}

class GameItem {
  const GameItem({
    required this.id,
    required this.name,
    required this.coverPath,
    required this.company,
    required this.summary,
    required this.rating,
    required this.releaseDate,
    required this.path,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lastPlayedAt,
    required this.totalPlayTimeSec,
    this.tags = const <String>[],
    this.exePaths = const <String>[],
    this.gameDir = '',
  });

  final String id;
  final String name;
  final String coverPath;
  final String company;
  final String summary;
  final double rating;
  final String releaseDate;

  /// 默认启动 exe 路径（手动添加时为用户选择的 exe；批量导入时为首选 exe）
  final String path;
  final GameStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastPlayedAt;
  final int totalPlayTimeSec;
  final List<String> tags;

  /// 游戏目录下扫描到的所有顶层可执行文件列表（批量导入时填写）
  final List<String> exePaths;

  /// 游戏根目录路径（用于启动时设置工作目录）
  final String gameDir;

  GameItem copyWith({
    String? id,
    String? name,
    String? coverPath,
    String? company,
    String? summary,
    double? rating,
    String? releaseDate,
    String? path,
    GameStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastPlayedAt,
    int? totalPlayTimeSec,
    List<String>? tags,
    List<String>? exePaths,
    String? gameDir,
  }) {
    return GameItem(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPath: coverPath ?? this.coverPath,
      company: company ?? this.company,
      summary: summary ?? this.summary,
      rating: rating ?? this.rating,
      releaseDate: releaseDate ?? this.releaseDate,
      path: path ?? this.path,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      totalPlayTimeSec: totalPlayTimeSec ?? this.totalPlayTimeSec,
      tags: tags ?? this.tags,
      exePaths: exePaths ?? this.exePaths,
      gameDir: gameDir ?? this.gameDir,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'coverPath': coverPath,
      'company': company,
      'summary': summary,
      'rating': rating,
      'releaseDate': releaseDate,
      'path': path,
      'status': status.value,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'lastPlayedAt': lastPlayedAt?.millisecondsSinceEpoch,
      'totalPlayTimeSec': totalPlayTimeSec,
      'tags': tags,
      'exePaths': exePaths,
      'gameDir': gameDir,
    };
  }

  static GameItem fromJson(Map<String, dynamic> json) {
    final List<dynamic> tagsJson = (json['tags'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> exePathsJson = (json['exePaths'] as List<dynamic>?) ?? <dynamic>[];
    return GameItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coverPath: json['coverPath'] as String? ?? '',
      company: json['company'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      releaseDate: json['releaseDate'] as String? ?? '',
      path: json['path'] as String? ?? '',
      status: GameStatus.fromValue(json['status'] as String? ?? ''),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
      lastPlayedAt: (json['lastPlayedAt'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['lastPlayedAt'] as int),
      totalPlayTimeSec: json['totalPlayTimeSec'] as int? ?? 0,
      tags: tagsJson.map((dynamic e) => e.toString()).toList(),
      exePaths: exePathsJson.map((dynamic e) => e.toString()).toList(),
      gameDir: json['gameDir'] as String? ?? '',
    );
  }
}

class GameCategory {
  const GameCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.isSystem,
    required this.createdAt,
    required this.gameCount,
  });

  final String id;
  final String name;
  final String emoji;
  final bool isSystem;
  final DateTime createdAt;
  final int gameCount;

  GameCategory copyWith({
    String? id,
    String? name,
    String? emoji,
    bool? isSystem,
    DateTime? createdAt,
    int? gameCount,
  }) {
    return GameCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      gameCount: gameCount ?? this.gameCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'emoji': emoji,
      'isSystem': isSystem,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'gameCount': gameCount,
    };
  }

  static GameCategory fromJson(Map<String, dynamic> json) {
    return GameCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      isSystem: json['isSystem'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      gameCount: json['gameCount'] as int? ?? 0,
    );
  }
}

class PlaySession {
  const PlaySession({
    required this.id,
    required this.gameId,
    required this.startTime,
    required this.endTime,
    required this.durationSec,
  });

  final String id;
  final String gameId;
  final DateTime startTime;
  final DateTime endTime;
  final int durationSec;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'gameId': gameId,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationSec': durationSec,
    };
  }

  static PlaySession fromJson(Map<String, dynamic> json) {
    return PlaySession(
      id: json['id'] as String? ?? '',
      gameId: json['gameId'] as String? ?? '',
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime'] as int? ?? 0),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['endTime'] as int? ?? 0),
      durationSec: json['durationSec'] as int? ?? 0,
    );
  }
}

class GameProgress {
  const GameProgress({
    required this.id,
    required this.gameId,
    required this.chapter,
    required this.route,
    required this.note,
    required this.updatedAt,
  });

  final String id;
  final String gameId;
  final String chapter;
  final String route;
  final String note;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'gameId': gameId,
      'chapter': chapter,
      'route': route,
      'note': note,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  static GameProgress fromJson(Map<String, dynamic> json) {
    return GameProgress(
      id: json['id'] as String? ?? '',
      gameId: json['gameId'] as String? ?? '',
      chapter: json['chapter'] as String? ?? '',
      route: json['route'] as String? ?? '',
      note: json['note'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
    );
  }
}

class GameLibrarySettings {
  const GameLibrarySettings({
    required this.autoTrackPlayTime,
    required this.defaultSort,
    required this.autoSave,
    required this.enableDesktopLaunch,
    this.useOpenOnMacos = false,
  });

  final bool autoTrackPlayTime;
  final String defaultSort;
  final bool autoSave;
  final bool enableDesktopLaunch;

  /// macOS 下使用 open 命令启动游戏
  final bool useOpenOnMacos;

  GameLibrarySettings copyWith({
    bool? autoTrackPlayTime,
    String? defaultSort,
    bool? autoSave,
    bool? enableDesktopLaunch,
    bool? useOpenOnMacos,
  }) {
    return GameLibrarySettings(
      autoTrackPlayTime: autoTrackPlayTime ?? this.autoTrackPlayTime,
      defaultSort: defaultSort ?? this.defaultSort,
      autoSave: autoSave ?? this.autoSave,
      enableDesktopLaunch: enableDesktopLaunch ?? this.enableDesktopLaunch,
      useOpenOnMacos: useOpenOnMacos ?? this.useOpenOnMacos,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'autoTrackPlayTime': autoTrackPlayTime,
      'defaultSort': defaultSort,
      'autoSave': autoSave,
      'enableDesktopLaunch': enableDesktopLaunch,
      'useOpenOnMacos': useOpenOnMacos,
    };
  }

  static GameLibrarySettings fromJson(Map<String, dynamic> json) {
    return GameLibrarySettings(
      autoTrackPlayTime: json['autoTrackPlayTime'] as bool? ?? true,
      defaultSort: json['defaultSort'] as String? ?? 'updatedAt_desc',
      autoSave: json['autoSave'] as bool? ?? true,
      enableDesktopLaunch: json['enableDesktopLaunch'] as bool? ?? true,
      useOpenOnMacos: json['useOpenOnMacos'] as bool? ?? false,
    );
  }

  static GameLibrarySettings defaultValue() {
    return const GameLibrarySettings(
      autoTrackPlayTime: true,
      defaultSort: 'updatedAt_desc',
      autoSave: true,
      enableDesktopLaunch: true,
      useOpenOnMacos: false,
    );
  }
}

class GameLibraryHomeData {
  const GameLibraryHomeData({
    required this.lastPlayedGame,
    required this.todayPlayTimeSec,
    required this.weekPlayTimeSec,
    required this.totalGames,
    required this.totalPlayTimeSec,
  });

  final GameItem? lastPlayedGame;
  final int todayPlayTimeSec;
  final int weekPlayTimeSec;
  final int totalGames;
  final int totalPlayTimeSec;
}

class GameStatsData {
  const GameStatsData({
    required this.totalPlayTimeSec,
    required this.sessionCount,
    required this.timeline,
  });

  final int totalPlayTimeSec;
  final int sessionCount;
  final List<DayPlayTime> timeline;
}

class DayPlayTime {
  const DayPlayTime({required this.date, required this.durationSec});

  final DateTime date;
  final int durationSec;
}

String encodeJsonList(List<Map<String, dynamic>> list) {
  return jsonEncode(list);
}
