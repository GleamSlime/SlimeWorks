import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final RxList<GameItem> games = <GameItem>[].obs;
  final RxString searchQuery = ''.obs;
  final Rxn<GameStatus> selectedStatus = Rxn<GameStatus>();
  final RxString selectedSort = 'updatedAt_desc'.obs;
  final RxString selectedTag = ''.obs;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    selectedSort.value = _service.settings.defaultSort;
    await refresh();
  }

  @override
  Future<void> refresh() async {
    games.assignAll(_service.games);
  }

  List<GameItem> get filteredGames {
    List<GameItem> result = List<GameItem>.from(games);

    final String keyword = searchQuery.value.trim().toLowerCase();
    if (keyword.isNotEmpty) {
      result = result
          .where((GameItem game) {
            return game.name.toLowerCase().contains(keyword) ||
                game.company.toLowerCase().contains(keyword) ||
                game.tags.any((String e) => e.toLowerCase().contains(keyword));
          })
          .toList(growable: false);
    }

    final GameStatus? status = selectedStatus.value;
    if (status != null) {
      result = result.where((GameItem game) => game.status == status).toList(growable: false);
    }

    final String tagFilter = selectedTag.value.trim();
    if (tagFilter.isNotEmpty) {
      result = result
          .where((GameItem game) => game.tags.contains(tagFilter))
          .toList(growable: false);
    }

    final String sortKey = selectedSort.value;
    result.sort((GameItem a, GameItem b) {
      switch (sortKey) {
        case 'name_asc':
          return a.name.compareTo(b.name);
        case 'name_desc':
          return b.name.compareTo(a.name);
        case 'rating_desc':
          return b.rating.compareTo(a.rating);
        case 'rating_asc':
          return a.rating.compareTo(b.rating);
        case 'release_desc':
          return b.releaseDate.compareTo(a.releaseDate);
        case 'release_asc':
          return a.releaseDate.compareTo(b.releaseDate);
        case 'last_played_desc':
          return (b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        case 'last_played_asc':
          return (a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        case 'updatedAt_asc':
          return a.updatedAt.compareTo(b.updatedAt);
        case 'updatedAt_desc':
        default:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });

    return result;
  }

  Set<String> getAllTags() {
    final Set<String> tags = <String>{};
    for (final GameItem game in games) {
      tags.addAll(game.tags);
    }
    return tags;
  }

  List<GameItem> getGamesByCategory(String categoryId) {
    return _service.getGamesByCategory(categoryId);
  }

  Future<GameItem?> addGame({
    required String name,
    required String company,
    required String summary,
    required double rating,
    required String releaseDate,
    required String path,
    required GameStatus status,
    required String coverPath,
  }) async {
    if (name.trim().isEmpty) {
      setError('游戏名不能为空');
      return null;
    }
    final GameItem game = await _service.addGame(
      name: name,
      company: company,
      summary: summary,
      rating: rating,
      releaseDate: releaseDate,
      path: path,
      status: status,
      coverPath: coverPath,
    );
    await refresh();
    // 异步拉取元数据并回填（不阻塞返回）
    unawaited(_fetchAndApplyMetadata(game));
    return game;
  }

  Future<void> _fetchAndApplyMetadata(GameItem game) async {
    final GameSearchMetadata? meta = await _service.searchMetadataByName(game.name);
    if (meta == null) {
      return;
    }
    final GameItem updated = game.copyWith(
      name: meta.name.trim().isNotEmpty ? meta.name.trim() : game.name,
      company: meta.company.trim().isNotEmpty ? meta.company.trim() : game.company,
      summary: meta.summary.trim().isNotEmpty ? meta.summary.trim() : game.summary,
      rating: meta.rating > 0 ? meta.rating : game.rating,
      releaseDate: meta.releaseDate.trim().isNotEmpty ? meta.releaseDate.trim() : game.releaseDate,
      coverPath: meta.coverUrl.trim().isNotEmpty ? meta.coverUrl.trim() : game.coverPath,
    );
    await _service.updateGame(updated);
    await refresh();
  }

  Future<int> batchImportFromDirectory() async {
    final String? directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择包含游戏的目录',
      lockParentWindow: true,
    );
    if (directory == null || directory.trim().isEmpty) {
      return 0;
    }

    return _batchImportFromPaths(<String>[directory], sourceLabel: '批量导入自目录: $directory');
  }

  Future<int> batchImportFromDroppedPaths(List<String> droppedPaths) async {
    if (droppedPaths.isEmpty) {
      return 0;
    }
    return _batchImportFromPaths(droppedPaths, sourceLabel: '拖拽导入');
  }

  Future<int> _batchImportFromPaths(List<String> inputPaths, {required String sourceLabel}) async {
    final Set<String> executablePathSet = _collectExecutableTargets(inputPaths);
    if (executablePathSet.isEmpty) {
      return 0;
    }

    final List<String> executablePaths = executablePathSet.toList(growable: false)
      ..sort((String a, String b) => a.compareTo(b));

    final Set<String> existingPaths = games
        .map((GameItem g) => g.path.trim().toLowerCase())
        .where((String p) => p.isNotEmpty)
        .toSet();
    final Set<String> existingNames = games
        .map((GameItem g) => g.name.trim().toLowerCase())
        .toSet();

    int imported = 0;
    for (final String executablePath in executablePaths) {
      final String gameName = _deriveGameName(executablePath);
      if (gameName.isEmpty) {
        continue;
      }

      final String pathKey = executablePath.toLowerCase();
      final String nameKey = gameName.toLowerCase();
      final int existingIndex = games.indexWhere(
        (GameItem g) =>
            g.path.trim().toLowerCase() == pathKey || g.name.trim().toLowerCase() == nameKey,
      );
      if (existingIndex >= 0) {
        final GameItem existingGame = games[existingIndex];
        await _tryBackfillMetadata(existingGame, gameName);
        continue;
      }

      final GameSearchMetadata? metadata = await _service.searchMetadataByName(gameName);
      final String finalName = metadata?.name.trim().isNotEmpty == true
          ? metadata!.name.trim()
          : gameName;
      final String finalCompany = metadata?.company.trim().isNotEmpty == true
          ? metadata!.company.trim()
          : '未知';
      final String finalSummary = metadata?.summary.trim().isNotEmpty == true
          ? metadata!.summary.trim()
          : '$sourceLabel：$gameName';

      await _service.addGame(
        name: finalName,
        company: finalCompany,
        summary: finalSummary,
        rating: metadata?.rating ?? 0,
        releaseDate: metadata?.releaseDate ?? '',
        path: executablePath,
        status: GameStatus.notStarted,
        coverPath: metadata?.coverUrl ?? '',
      );
      imported += 1;

      existingPaths.add(pathKey);
      existingNames.add(finalName.toLowerCase());
    }

    await refresh();
    return imported;
  }

  Future<void> _tryBackfillMetadata(GameItem game, String fallbackName) async {
    final bool needCover = game.coverPath.trim().isEmpty;
    final bool needCompany = game.company.trim().isEmpty || game.company.trim() == '未知';
    final bool needSummary = game.summary.trim().isEmpty || game.summary.contains('导入');
    final bool needRelease = game.releaseDate.trim().isEmpty;
    final bool needRating = game.rating <= 0;

    if (!needCover && !needCompany && !needSummary && !needRelease && !needRating) {
      return;
    }

    final String keyword = game.name.trim().isNotEmpty ? game.name.trim() : fallbackName;
    final GameSearchMetadata? metadata = await _service.searchMetadataByName(keyword);
    if (metadata == null) {
      return;
    }

    await _service.updateGame(
      game.copyWith(
        name: metadata.name.trim().isNotEmpty ? metadata.name.trim() : game.name,
        coverPath: needCover ? metadata.coverUrl : game.coverPath,
        company: needCompany
            ? (metadata.company.trim().isEmpty ? game.company : metadata.company)
            : game.company,
        summary: needSummary
            ? (metadata.summary.trim().isEmpty ? game.summary : metadata.summary)
            : game.summary,
        rating: needRating ? metadata.rating : game.rating,
        releaseDate: needRelease
            ? (metadata.releaseDate.trim().isEmpty ? game.releaseDate : metadata.releaseDate)
            : game.releaseDate,
      ),
    );
  }

  Set<String> _collectExecutableTargets(List<String> inputPaths) {
    final Set<String> result = <String>{};
    for (final String rawPath in inputPaths) {
      final String path = rawPath.trim();
      if (path.isEmpty) {
        continue;
      }

      final FileSystemEntityType type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        if (_isExecutablePath(path)) {
          result.add(path);
        }
        continue;
      }

      if (type == FileSystemEntityType.directory) {
        if (path.toLowerCase().endsWith('.app')) {
          result.add(path);
          continue;
        }
        _collectExecutableTargetsFromDirectory(Directory(path), result);
      }
    }
    return result;
  }

  void _collectExecutableTargetsFromDirectory(Directory root, Set<String> output) {
    final List<Directory> pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final Directory current = pending.removeLast();
      List<FileSystemEntity> children;
      try {
        children = current.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final FileSystemEntity child in children) {
        final String childPath = child.path;
        if (child is Directory) {
          if (childPath.toLowerCase().endsWith('.app')) {
            output.add(childPath);
            continue;
          }
          pending.add(child);
          continue;
        }
        if (child is File && _isExecutablePath(childPath)) {
          output.add(childPath);
        }
      }
    }
  }

  bool _isExecutablePath(String path) {
    final String value = path.toLowerCase();
    return value.endsWith('.exe') ||
        value.endsWith('.app') ||
        value.endsWith('.sh') ||
        value.endsWith('.bat') ||
        value.endsWith('.cmd') ||
        value.endsWith('.x86_64');
  }

  /// 公开版，供 UI 层调用（选路径后预填名称）
  String deriveGameName(String executablePath) => _deriveGameName(executablePath);

  String _deriveGameName(String executablePath) {
    final String path = executablePath.trim();
    if (path.isEmpty) {
      return '';
    }

    final String lower = path.toLowerCase();
    if (lower.endsWith('.app')) {
      final String appName = path.split(Platform.pathSeparator).last;
      return appName
          .replaceAll(RegExp(r'\.app$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[_\.]+'), ' ')
          .trim();
    }

    final String normalized = path.replaceAll('\\', '/');
    final List<String> segments = normalized.split('/').where((String s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      final String folderName = segments[segments.length - 2]
          .replaceAll(RegExp(r'[_\.]+'), ' ')
          .trim();
      if (folderName.isNotEmpty) {
        return folderName;
      }
    }

    final String fileName = segments.isEmpty ? path : segments.last;
    return fileName
        .replaceAll(RegExp(r'\.(exe|app|sh|bat|cmd|x86_64)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\.]+'), ' ')
        .trim();
  }

  Future<void> deleteGame(String gameId) async {
    await _service.deleteGame(gameId);
    await refresh();
  }

  Future<void> updateStatus(GameItem game, GameStatus nextStatus) async {
    await _service.updateGame(game.copyWith(status: nextStatus));
    await refresh();
  }

  Future<void> toggleFavorite(GameItem game) async {
    final bool next = !_service.isFavorite(game.id);
    await _service.toggleFavorite(game.id, next);
    await refresh();
  }

  bool isFavorite(String gameId) {
    return _service.isFavorite(gameId);
  }

  Future<String?> pickExecutablePath() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择游戏可执行文件',
      allowMultiple: false,
      type: FileType.any,
      lockParentWindow: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.single.path;
  }

  Future<void> launchGame(GameItem game) async {
    final String path = game.path.trim();
    if (path.isEmpty) {
      setError('未配置启动路径');
      return;
    }
    if (!File(path).existsSync()) {
      setError('启动路径不存在: $path');
      return;
    }
    try {
      await Process.start(path, <String>[]);
      if (_service.settings.autoTrackPlayTime) {
        final DateTime now = DateTime.now();
        await _service.addPlaySession(
          gameId: game.id,
          startTime: now.subtract(const Duration(minutes: 30)),
          endTime: now,
        );
      }
      await refresh();
    } catch (e) {
      setError('启动失败: $e');
    }
  }

  String formatDuration(int seconds) {
    final int hour = seconds ~/ 3600;
    final int minute = (seconds % 3600) ~/ 60;
    if (hour == 0) {
      return '$minute 分钟';
    }
    return '$hour 小时 $minute 分钟';
  }
}
