library;

/// PicACG 下载相关数据模型

import 'dart:convert';

import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 单个章节的下载状态
enum PicAcgDownloadStatus {
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
class PicAcgDownloadEpsInfo {
  final int epsOrder;
  final String epsTitle;
  int totalPages;
  int downloadedPages;
  PicAcgDownloadStatus status;
  String? errorMsg;

  PicAcgDownloadEpsInfo({
    required this.epsOrder,
    required this.epsTitle,
    this.totalPages = 0,
    this.downloadedPages = 0,
    this.status = PicAcgDownloadStatus.waiting,
    this.errorMsg,
  });

  bool get isCompleted => status == PicAcgDownloadStatus.completed;

  double get progress => totalPages > 0 ? downloadedPages / totalPages : 0.0;

  Map<String, dynamic> toJson() => {
    'epsOrder': epsOrder,
    'epsTitle': epsTitle,
    'totalPages': totalPages,
    'downloadedPages': downloadedPages,
    'status': status.name,
    'errorMsg': errorMsg,
  };

  factory PicAcgDownloadEpsInfo.fromJson(Map<String, dynamic> json) => PicAcgDownloadEpsInfo(
    epsOrder: json['epsOrder'] as int,
    epsTitle: json['epsTitle'] as String? ?? '',
    totalPages: json['totalPages'] as int? ?? 0,
    downloadedPages: json['downloadedPages'] as int? ?? 0,
    status: PicAcgDownloadStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => PicAcgDownloadStatus.waiting,
    ),
    errorMsg: json['errorMsg'] as String?,
  );
}

/// 漫画下载条目（包含多章节）
class PicAcgDownloadEntry {
  final String comicId;
  String comicTitle;
  PicAcgImage? thumb;

  /// 章节序号 → 下载信息
  final Map<int, PicAcgDownloadEpsInfo> episodes;
  DateTime createdAt;

  PicAcgDownloadEntry({
    required this.comicId,
    required this.comicTitle,
    this.thumb,
    Map<int, PicAcgDownloadEpsInfo>? episodes,
    DateTime? createdAt,
  }) : episodes = episodes ?? {},
       createdAt = createdAt ?? DateTime.now();

  /// 全部章节是否完成
  bool get isFullyComplete =>
      episodes.isNotEmpty &&
      episodes.values.every((e) => e.status == PicAcgDownloadStatus.completed);

  /// 总章节数
  int get totalEps => episodes.length;

  /// 已完成的章节数
  int get completedEps =>
      episodes.values.where((e) => e.status == PicAcgDownloadStatus.completed).length;

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

  factory PicAcgDownloadEntry.fromJson(Map<String, dynamic> json) {
    final thumbJson = json['thumb'] as Map<String, dynamic>?;
    final epsJson = json['episodes'] as Map<String, dynamic>? ?? {};
    return PicAcgDownloadEntry(
      comicId: json['comicId'] as String,
      comicTitle: json['comicTitle'] as String? ?? '',
      thumb: thumbJson != null ? PicAcgImage.fromJson(thumbJson) : null,
      episodes: {
        for (final e in epsJson.entries)
          int.parse(e.key): PicAcgDownloadEpsInfo.fromJson(e.value as Map<String, dynamic>),
      },
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static Map<String, PicAcgDownloadEntry> decodeAll(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        e.key: PicAcgDownloadEntry.fromJson(e.value as Map<String, dynamic>),
    };
  }

  static String encodeAll(Map<String, PicAcgDownloadEntry> entries) {
    return jsonEncode({for (final e in entries.entries) e.key: e.value.toJson()});
  }
}
