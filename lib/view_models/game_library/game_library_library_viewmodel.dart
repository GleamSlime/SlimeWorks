import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

/// 游戏文件夹扫描结果（内部数据类）
class _GameFolderInfo {
  const _GameFolderInfo({
    required this.folderPath,
    required this.folderName,
    required this.exePaths,
  });

  final String folderPath;
  final String folderName;
  final List<String> exePaths;
}

final Loggers _logger = Loggers(name: '游戏库ViewModel');

class GameLibraryViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();
  final GameProcessTracker _processTracker = getIt<GameProcessTracker>();

  final RxList<GameItem> games = <GameItem>[].obs;
  final RxString searchQuery = ''.obs;
  final Rxn<GameStatus> selectedStatus = Rxn<GameStatus>();
  final RxString selectedSort = 'updatedAt_desc'.obs;
  final RxString selectedTag = ''.obs;

  /// 多选模式下已选中的游戏 ID 集合
  final RxSet<String> selectedIds = <String>{}.obs;

  /// 是否处于多选模式
  bool get isSelecting => selectedIds.isNotEmpty;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    selectedSort.value = _service.settings.defaultSort;
    await refresh();
    // 监听游玩会话保存事件，自动刷新列表（游戏进程退出后触发）
    ever(_processTracker.sessionSavedCount, (_) => refresh());
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
      dialogTitle: '选择包含多个游戏的上级目录',
      lockParentWindow: true,
    );
    if (directory == null || directory.trim().isEmpty) {
      return 0;
    }
    return _batchImportGameFolders(directory);
  }

  Future<int> batchImportFromDroppedPaths(List<String> droppedPaths) async {
    if (droppedPaths.isEmpty) {
      return 0;
    }
    int total = 0;
    for (final String path in droppedPaths) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        total += await _batchImportGameFolders(path);
      }
    }
    return total;
  }

  /// 扫描 [parentDir] 的直属子目录，将包含 exe 的子目录视为候选游戏文件夹，
  /// 调用元数据 API 搜索游戏信息，有匹配结果则导入，无匹配则以文件夹名直接添加。
  Future<int> _batchImportGameFolders(String parentDir) async {
    final List<_GameFolderInfo> candidates = _scanGameFolders(parentDir);
    if (candidates.isEmpty) {
      _logger.info('批量导入：未在 $parentDir 的直属子目录中找到含 exe 的文件夹');
      return 0;
    }

    // 已存在的游戏目录和名称（用于去重）
    final Set<String> existingDirs = games
        .map((GameItem g) => g.gameDir.trim().toLowerCase())
        .where((String d) => d.isNotEmpty)
        .toSet();
    final Set<String> existingNames = games
        .map((GameItem g) => g.name.trim().toLowerCase())
        .toSet();

    int imported = 0;
    for (final _GameFolderInfo folder in candidates) {
      // 跳过已录入游戏的目录
      if (existingDirs.contains(folder.folderPath.toLowerCase())) {
        _logger.info('批量导入跳过（目录已存在）: ${folder.folderPath}');
        continue;
      }

      _logger.info('批量导入：搜索游戏信息 "${folder.folderName}"');
      final GameSearchMetadata? metadata = await _service.searchMetadataByName(folder.folderName);

      if (metadata == null) {
        _logger.info('批量导入：API 未找到匹配游戏，跳过 "${folder.folderName}"');
        continue;
      }

      final String finalName = metadata.name.trim().isNotEmpty
          ? metadata.name.trim()
          : folder.folderName;

      // 跳过同名游戏
      if (existingNames.contains(finalName.toLowerCase())) {
        _logger.info('批量导入跳过（游戏名已存在）: $finalName');
        existingDirs.add(folder.folderPath.toLowerCase());
        continue;
      }

      // 选择默认启动 exe（优先选与文件夹同名或名称最短的）
      final String defaultExe = _pickDefaultExe(folder.exePaths, folder.folderName);

      await _service.addGame(
        name: finalName,
        company: metadata.company.trim().isNotEmpty ? metadata.company.trim() : '未知',
        summary: metadata.summary.trim(),
        rating: metadata.rating,
        releaseDate: metadata.releaseDate.trim(),
        path: defaultExe,
        status: GameStatus.notStarted,
        coverPath: metadata.coverUrl.trim(),
        exePaths: folder.exePaths,
        gameDir: folder.folderPath,
      );

      imported++;
      existingDirs.add(folder.folderPath.toLowerCase());
      existingNames.add(finalName.toLowerCase());
      _logger.info('批量导入成功: $finalName (${folder.folderPath})');
    }

    await refresh();
    return imported;
  }

  /// 扫描 [parentDir] 的子目录（最多向下 [maxDepth] 层），
  /// 将包含可执行文件的目录视为候选游戏文件夹，支持「出版商/游戏/exe」等嵌套结构。
  List<_GameFolderInfo> _scanGameFolders(String parentDir, {int maxDepth = 3}) {
    final List<_GameFolderInfo> result = <_GameFolderInfo>[];
    final Directory parent = Directory(parentDir);
    List<FileSystemEntity> entries;
    try {
      entries = parent.listSync(followLinks: false);
    } catch (e) {
      _logger.error('扫描游戏目录失败: $parentDir, error=$e');
      return result;
    }
    _scanRecursive(entries, result, currentDepth: 1, maxDepth: maxDepth);
    return result;
  }

  void _scanRecursive(
    List<FileSystemEntity> entries,
    List<_GameFolderInfo> result, {
    required int currentDepth,
    required int maxDepth,
  }) {
    for (final FileSystemEntity entry in entries) {
      if (entry is! Directory) continue;

      // macOS .app 包本身即一个游戏
      if (entry.path.toLowerCase().endsWith('.app')) {
        final String name = _cleanFolderName(
          entry.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'\.app$', caseSensitive: false), ''),
        );
        result.add(
          _GameFolderInfo(folderPath: entry.path, folderName: name, exePaths: <String>[entry.path]),
        );
        continue;
      }

      // 当前目录直接包含 exe → 视为游戏文件夹，不再向下递归
      final List<String> topLevelExes = _findTopLevelExes(entry);
      if (topLevelExes.isNotEmpty) {
        final String rawName = entry.path.split(Platform.pathSeparator).last;
        result.add(
          _GameFolderInfo(
            folderPath: entry.path,
            folderName: _cleanFolderName(rawName),
            exePaths: topLevelExes,
          ),
        );
        continue;
      }

      // 当前目录没有 exe，若还未到最大深度则继续向下扫描
      if (currentDepth < maxDepth) {
        List<FileSystemEntity> children;
        try {
          children = entry.listSync(followLinks: false);
        } catch (_) {
          continue;
        }
        _scanRecursive(children, result, currentDepth: currentDepth + 1, maxDepth: maxDepth);
      }
    }
  }

  /// 获取 [dir] 顶层（不含子目录）的可执行文件路径列表
  List<String> _findTopLevelExes(Directory dir) {
    final List<String> exes = <String>[];
    try {
      for (final FileSystemEntity entry in dir.listSync(followLinks: false)) {
        if (entry is File && _isExecutablePath(entry.path)) {
          exes.add(entry.path);
        }
      }
    } catch (_) {}
    return exes;
  }

  /// 清理文件夹名中的括号、版本号等无关符号，用于更精准的 API 搜索
  String _cleanFolderName(String name) {
    return name.replaceAll(RegExp(r'[\[\]（）()【】_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 从 exe 列表中挑选最合适的默认启动文件
  /// 优先选名称与 [gameHint] 接近的，其次选最短文件名（通常是主程序）
  String _pickDefaultExe(List<String> exePaths, String gameHint) {
    if (exePaths.isEmpty) {
      return '';
    }
    if (exePaths.length == 1) {
      return exePaths.first;
    }

    final String hintLower = gameHint.toLowerCase().replaceAll(RegExp(r'\s+'), '');

    // 优先选文件名与游戏名相近的
    for (final String p in exePaths) {
      final String fileName = p.split(Platform.pathSeparator).last.toLowerCase();
      if (fileName.contains(hintLower) || hintLower.contains(fileName.replaceAll('.exe', ''))) {
        return p;
      }
    }

    // 其次选文件名最短（主程序通常命名最简洁）
    return exePaths.reduce((String a, String b) {
      final String aName = a.split(Platform.pathSeparator).last;
      final String bName = b.split(Platform.pathSeparator).last;
      return aName.length <= bName.length ? a : b;
    });
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

  /// 启动游戏。若 [overrideExePath] 不为空则启动指定 exe，否则自动选择默认 exe。
  Future<void> launchGame(GameItem game, {String? overrideExePath}) async {
    final String exePath = (overrideExePath?.trim().isNotEmpty == true)
        ? overrideExePath!.trim()
        : _resolveDefaultExe(game);

    if (exePath.isEmpty) {
      setError('未配置启动路径，请在「编辑」标签中填写');
      return;
    }

    if (!File(exePath).existsSync()) {
      setError('启动文件不存在: $exePath');
      return;
    }

    // 工作目录：优先用游戏根目录，其次用 exe 所在目录
    final String workDir = _resolveWorkingDirectory(game, exePath);

    _logger.info('启动游戏: ${game.name}, exe=$exePath, workDir=$workDir');
    final bool ok = await _processTracker.launchAndTrack(
      gameId: game.id,
      exePath: exePath,
      workingDirectory: workDir,
    );
    if (!ok) {
      setError('启动失败，请确认可执行文件是否有效');
    }
  }

  /// 判断当前游戏是否正在运行
  bool isGameRunning(String gameId) => _processTracker.isRunning(gameId);

  /// 获取游戏所有可用的 exe 路径（供 UI 展示多 exe 选择）
  List<String> getGameExePaths(GameItem game) {
    if (game.exePaths.isNotEmpty) {
      return game.exePaths;
    }
    if (game.path.trim().isNotEmpty) {
      return <String>[game.path.trim()];
    }
    return <String>[];
  }

  /// 解析默认启动 exe
  String _resolveDefaultExe(GameItem game) {
    // 优先使用 path（已设置的默认 exe）
    final String primary = game.path.trim();
    if (primary.isNotEmpty && File(primary).existsSync()) {
      return primary;
    }
    // 从 exePaths 里找第一个有效的
    for (final String p in game.exePaths) {
      if (File(p).existsSync()) {
        return p;
      }
    }
    return primary;
  }

  /// 解析工作目录：优先游戏根目录，其次 exe 父目录
  String _resolveWorkingDirectory(GameItem game, String exePath) {
    final String dir = game.gameDir.trim();
    if (dir.isNotEmpty && Directory(dir).existsSync()) {
      return dir;
    }
    final File exe = File(exePath);
    return exe.parent.path;
  }

  /// 设置游戏默认启动 exe，并持久化到 Service
  Future<void> setDefaultExe(GameItem game, String exePath) async {
    await _service.updateGame(game.copyWith(path: exePath));
    await refresh();
  }

  /// 切换单个游戏的选中状态
  void toggleSelect(String gameId) {
    if (selectedIds.contains(gameId)) {
      selectedIds.remove(gameId);
    } else {
      selectedIds.add(gameId);
    }
  }

  /// 全选/取消全选
  void selectAll() {
    if (selectedIds.length == filteredGames.length) {
      selectedIds.clear();
    } else {
      selectedIds.assignAll(filteredGames.map((GameItem g) => g.id).toSet());
    }
  }

  /// 取消所有选中
  void clearSelection() => selectedIds.clear();

  /// 框选：用索引列表直接替换当前选中集合（供 UI 框选时调用）
  void setSelectedFromIndices(List<int> indices, List<GameItem> sourceList) {
    final Set<String> next = <String>{};
    for (final int i in indices) {
      if (i >= 0 && i < sourceList.length) {
        next.add(sourceList[i].id);
      }
    }
    selectedIds.value = next;
  }

  /// 批量删除已选中游戏
  Future<void> batchDelete() async {
    final List<String> ids = selectedIds.toList();
    for (final String id in ids) {
      await _service.deleteGame(id);
    }
    selectedIds.clear();
    await refresh();
    _logger.info('批量删除完成，共删除 ${ids.length} 个游戏');
  }

  /// 批量刷新元数据（选中游戏）
  Future<void> batchRefreshMetadata() async {
    final List<GameItem> targets = games.where((GameItem g) => selectedIds.contains(g.id)).toList();
    for (final GameItem game in targets) {
      final GameSearchMetadata? meta = await _service.searchMetadataByName(game.name);
      if (meta == null) {
        continue;
      }
      await _service.updateGame(
        game.copyWith(
          name: meta.name.trim().isNotEmpty ? meta.name.trim() : game.name,
          company: meta.company.trim().isNotEmpty ? meta.company.trim() : game.company,
          summary: meta.summary.trim().isNotEmpty ? meta.summary.trim() : game.summary,
          rating: meta.rating > 0 ? meta.rating : game.rating,
          releaseDate: meta.releaseDate.trim().isNotEmpty
              ? meta.releaseDate.trim()
              : game.releaseDate,
          coverPath: meta.coverUrl.trim().isNotEmpty ? meta.coverUrl.trim() : game.coverPath,
        ),
      );
      _logger.info('批量刷新元数据完成: ${game.name}');
    }
    selectedIds.clear();
    await refresh();
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
