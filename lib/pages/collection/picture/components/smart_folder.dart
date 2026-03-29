import 'dart:convert';

import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

/// 正则匹配的目标字段。
enum SmartFolderRegexTarget {
  /// 匹配集合名称与集合路径（原有行为）。
  collectionName,

  /// 匹配集合内媒体文件的文件名。
  fileName;

  String get label => switch (this) {
    collectionName => '集合名称',
    fileName => '文件名称',
  };
}

/// 文件类型过滤（仅 [regexTarget] == [SmartFolderRegexTarget.fileName] 时生效）。
enum SmartFolderFileType {
  all,
  images,
  videos;

  String get label => switch (this) {
    all => '全部',
    images => '仅图片',
    videos => '仅视频',
  };
}

/// 常见图片扩展名集合。
const _imageExts = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
  '.tiff',
  '.tif',
  '.heic',
  '.heif',
  '.avif',
  '.svg',
};

/// 常见视频扩展名集合。
const _videoExts = {
  '.mp4',
  '.mkv',
  '.mov',
  '.avi',
  '.wmv',
  '.flv',
  '.webm',
  '.m4v',
  '.ts',
  '.rmvb',
  '.rm',
  '.3gp',
};

/// A virtual folder that uses an optional regex pattern to filter media collections.
/// [targetFolderIds] scopes the filter to specific regular folders (empty = all folders).
/// Smart folders are stored locally in the app support directory.
class SmartFolder {
  final String id;
  final String name;

  /// Regex pattern applied to [regexTarget].
  /// Empty string means "no filter" – all collections in [targetFolderIds] are shown.
  final String regexPattern;

  /// 正则匹配目标字段。
  final SmartFolderRegexTarget regexTarget;

  /// 文件类型过滤（仅 regexTarget == fileName 时生效）。
  final SmartFolderFileType fileTypeFilter;

  /// When non-empty, only collections whose folderId is in this list are included.
  /// Empty list means "all folders" (no scope restriction).
  final List<String> targetFolderIds;

  const SmartFolder({
    required this.id,
    required this.name,
    required this.regexPattern,
    this.regexTarget = SmartFolderRegexTarget.collectionName,
    this.fileTypeFilter = SmartFolderFileType.all,
    this.targetFolderIds = const [],
  });

  SmartFolder copyWith({
    String? id,
    String? name,
    String? regexPattern,
    SmartFolderRegexTarget? regexTarget,
    SmartFolderFileType? fileTypeFilter,
    List<String>? targetFolderIds,
  }) {
    return SmartFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      regexPattern: regexPattern ?? this.regexPattern,
      regexTarget: regexTarget ?? this.regexTarget,
      fileTypeFilter: fileTypeFilter ?? this.fileTypeFilter,
      targetFolderIds: targetFolderIds ?? this.targetFolderIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'regexPattern': regexPattern,
    'regexTarget': regexTarget.name,
    'fileTypeFilter': fileTypeFilter.name,
    'targetFolderIds': targetFolderIds,
  };

  factory SmartFolder.fromJson(Map<String, dynamic> json) {
    // 迁移：旧格式使用 targetFolderId（单个 String?）
    List<String> ids;
    if (json.containsKey('targetFolderIds')) {
      ids = (json['targetFolderIds'] as List<dynamic>).cast<String>();
    } else if (json['targetFolderId'] != null) {
      ids = [json['targetFolderId'] as String];
    } else {
      ids = const [];
    }

    SmartFolderRegexTarget regexTarget;
    try {
      regexTarget = SmartFolderRegexTarget.values.byName(
        (json['regexTarget'] as String?) ?? 'collectionName',
      );
    } catch (_) {
      regexTarget = SmartFolderRegexTarget.collectionName;
    }

    SmartFolderFileType fileTypeFilter;
    try {
      fileTypeFilter = SmartFolderFileType.values.byName(
        (json['fileTypeFilter'] as String?) ?? 'all',
      );
    } catch (_) {
      fileTypeFilter = SmartFolderFileType.all;
    }

    return SmartFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      regexPattern: (json['regexPattern'] as String?) ?? '',
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: ids,
    );
  }

  static List<SmartFolder> listFromJson(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => SmartFolder.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<SmartFolder> folders) {
    return jsonEncode(folders.map((f) => f.toJson()).toList());
  }

  /// 判断集合名称模式下是否匹配。
  /// 外部调用方无需关心文件名模式时可直接用此方法。
  bool matchesCollection(media_api.MediaCollection collection) {
    // 文件夹范围过滤
    if (targetFolderIds.isNotEmpty && !targetFolderIds.contains(collection.folderId)) return false;
    if (regexTarget == SmartFolderRegexTarget.fileName) {
      // 文件名模式下集合本身始终通过范围检查，具体文件过滤由 ViewModel 完成
      return true;
    }
    // 正则过滤（空 = 不过滤）
    if (regexPattern.isEmpty) return true;
    try {
      final re = RegExp(regexPattern, caseSensitive: false, unicode: true);
      return re.hasMatch(collection.title) || re.hasMatch(collection.folderPath);
    } catch (_) {
      return true;
    }
  }

  /// 判断文件名模式下，给定文件路径列表中是否有满足条件的文件。
  /// [itemPaths] 为集合内所有媒体文件的路径。
  bool matchesFileNames(List<String> itemPaths) {
    // 根据文件类型过滤
    final filtered = _filterByType(itemPaths);
    if (filtered.isEmpty) return false;
    if (regexPattern.isEmpty) return true;
    try {
      final re = RegExp(regexPattern, caseSensitive: false, unicode: true);
      return filtered.any((p) {
        final name = p.split(RegExp(r'[/\\]')).last;
        return re.hasMatch(name);
      });
    } catch (_) {
      return true;
    }
  }

  List<String> _filterByType(List<String> paths) {
    if (fileTypeFilter == SmartFolderFileType.all) return paths;
    return paths.where((p) {
      final ext = '.${p.split('.').last.toLowerCase()}';
      return fileTypeFilter == SmartFolderFileType.images
          ? _imageExts.contains(ext)
          : _videoExts.contains(ext);
    }).toList();
  }
}
