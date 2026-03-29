import 'dart:convert';

import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

/// A virtual folder that uses an optional regex pattern to filter media collections.
/// [targetFolderIds] scopes the filter to specific regular folders (empty = all folders).
/// Smart folders are stored locally in SharedPreferences (not in the Rust DB).
class SmartFolder {
  final String id;
  final String name;

  /// Regex pattern applied (case-insensitively) to collection title and folderPath.
  /// Empty string means "no filter" – all collections in [targetFolderIds] are shown.
  final String regexPattern;

  /// When non-empty, only collections whose folderId is in this list are included.
  /// Empty list means "all folders" (no scope restriction).
  final List<String> targetFolderIds;

  const SmartFolder({
    required this.id,
    required this.name,
    required this.regexPattern,
    this.targetFolderIds = const [],
  });

  SmartFolder copyWith({
    String? id,
    String? name,
    String? regexPattern,
    List<String>? targetFolderIds,
  }) {
    return SmartFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      regexPattern: regexPattern ?? this.regexPattern,
      targetFolderIds: targetFolderIds ?? this.targetFolderIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'regexPattern': regexPattern,
    'targetFolderIds': targetFolderIds,
  };

  factory SmartFolder.fromJson(Map<String, dynamic> json) {
    // Migration: old format had 'targetFolderId' (single String?)
    List<String> ids;
    if (json.containsKey('targetFolderIds')) {
      ids = (json['targetFolderIds'] as List<dynamic>).cast<String>();
    } else if (json['targetFolderId'] != null) {
      ids = [json['targetFolderId'] as String];
    } else {
      ids = const [];
    }
    return SmartFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      regexPattern: (json['regexPattern'] as String?) ?? '',
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

  /// Returns true if [collection] matches this smart folder.
  /// • If [targetFolderIds] is non-empty, the collection must belong to one of those folders.
  /// • If [regexPattern] is non-empty, it is applied case-insensitively to
  ///   both the collection title and folderPath.
  /// • An empty pattern with non-empty targetFolderIds shows all collections in those folders.
  bool matches(media_api.MediaCollection collection) {
    // Folder scope check
    if (targetFolderIds.isNotEmpty && !targetFolderIds.contains(collection.folderId)) return false;
    // Regex check (empty = no filter)
    if (regexPattern.isEmpty) return true;
    try {
      final re = RegExp(regexPattern, caseSensitive: false, unicode: true);
      return re.hasMatch(collection.title) || re.hasMatch(collection.folderPath);
    } catch (_) {
      return true; // invalid regex → show all (rather than silently hiding everything)
    }
  }
}
