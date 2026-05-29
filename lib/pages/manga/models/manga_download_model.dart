library;

/// Manga 下载相关数据模型

import 'dart:convert';

import 'package:slime_works/pages/manga/models/manga_models.dart';

/// 单个章节的下载状态
enum MangaDownloadStatus {
  /// 等待下载
  waiting,

  /// 下载中
  downloading,

  /// 已完成
  completed,

  /// 出错（可重试）
  error,

  /// 已暂停
  paused,
}

/// 单个章节的下载进度信息
class MangaDownloadEpsInfo {
  final int epsOrder;
  final String epsTitle;
  int totalPages;
  int downloadedPages;
  MangaDownloadStatus status;
  String? errorMsg;

  MangaDownloadEpsInfo({
    required this.epsOrder,
    required this.epsTitle,
    this.totalPages = 0,
    this.downloadedPages = 0,
    this.status = MangaDownloadStatus.waiting,
    this.errorMsg,
  });

  bool get isCompleted => status == MangaDownloadStatus.completed;

  double get progress => totalPages > 0 ? downloadedPages / totalPages : 0.0;

  Map<String, dynamic> toJson() => {
    'epsOrder': epsOrder,
    'epsTitle': epsTitle,
    'totalPages': totalPages,
    'downloadedPages': downloadedPages,
    'status': status.name,
    'errorMsg': errorMsg,
  };

  factory MangaDownloadEpsInfo.fromJson(Map<String, dynamic> json) => MangaDownloadEpsInfo(
    epsOrder: json['epsOrder'] as int,
    epsTitle: json['epsTitle'] as String? ?? '',
    totalPages: json['totalPages'] as int? ?? 0,
    downloadedPages: json['downloadedPages'] as int? ?? 0,
    status: MangaDownloadStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => MangaDownloadStatus.waiting,
    ),
    errorMsg: json['errorMsg'] as String?,
  );
}

/// 漫画下载条目（包含多章节）
class MangaDownloadEntry {
  final String comicId;
  String comicTitle;
  MangaImage? thumb;

  /// 章节序号 → 下载信息
  final Map<int, MangaDownloadEpsInfo> episodes;
  DateTime createdAt;

  MangaDownloadEntry({
    required this.comicId,
    required this.comicTitle,
    this.thumb,
    Map<int, MangaDownloadEpsInfo>? episodes,
    DateTime? createdAt,
  }) : episodes = episodes ?? {},
       createdAt = createdAt ?? DateTime.now();

  /// 全部章节是否完成
  bool get isFullyComplete =>
      episodes.isNotEmpty &&
      episodes.values.every((e) => e.status == MangaDownloadStatus.completed);

  /// 总章节数
  int get totalEps => episodes.length;

  /// 已完成的章节数
  int get completedEps =>
      episodes.values.where((e) => e.status == MangaDownloadStatus.completed).length;

  Map<String, dynamic> toJson() => {
    'comicId': comicId,
    'comicTitle': comicTitle,
    'thumb': thumb != null
        ? {
            'originalName': thumb!.originalName,
            'path': thumb!.path,
            'fileServer': thumb!.fileServer,
          }
        : null,
    'episodes': {for (final e in episodes.entries) e.key.toString(): e.value.toJson()},
    'createdAt': createdAt.toIso8601String(),
  };

  factory MangaDownloadEntry.fromJson(Map<String, dynamic> json) {
    final thumbJson = json['thumb'] as Map<String, dynamic>?;
    final epsJson = json['episodes'] as Map<String, dynamic>? ?? {};
    return MangaDownloadEntry(
      comicId: json['comicId'] as String,
      comicTitle: json['comicTitle'] as String? ?? '',
      thumb: thumbJson != null ? MangaImage.fromJson(thumbJson) : null,
      episodes: {
        for (final e in epsJson.entries)
          int.parse(e.key): MangaDownloadEpsInfo.fromJson(e.value as Map<String, dynamic>),
      },
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static Map<String, MangaDownloadEntry> decodeAll(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        e.key: MangaDownloadEntry.fromJson(e.value as Map<String, dynamic>),
    };
  }

  static String encodeAll(Map<String, MangaDownloadEntry> entries) {
    return jsonEncode({for (final e in entries.entries) e.key: e.value.toJson()});
  }
}
