import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/src/rust/api/game_library.dart' as rust_api;

final Loggers _logger = Loggers(name: '游戏库ViewModel');

class GameLibraryViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();
  final GameProcessTracker _processTracker = getIt<GameProcessTracker>();

  final RxList<GameItem> games = <GameItem>[].obs;
  final RxString searchQuery = ''.obs;
  final Rxn<GameStatus> selectedStatus = Rxn<GameStatus>();
  final RxString selectedSort = 'updatedAt_desc'.obs;
  final RxString selectedTag = ''.obs;

  /// 收藏游戏 ID 集合（随 refresh 同步，供 UI 同步读取）
  final RxSet<String> favoriteIds = <String>{}.obs;

  /// 多选模式下已选中的游戏 ID 集合
  final RxSet<String> selectedIds = <String>{}.obs;

  /// 是否处于多选模式
  bool get isSelecting => selectedIds.isNotEmpty;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    final GameLibrarySettings settings = await _service.getSettings();
    selectedSort.value = settings.defaultSort;
    await refresh();
    // 监听游玩会话保存事件，自动刷新列表（游戏进程退出后触发）
    ever(_processTracker.sessionSavedCount, (_) => refresh());
  }

  @override
  Future<void> refresh() async {
    final List<GameItem> all = await _service.getGames();
    games.assignAll(all);
    // 批量加载收藏状态
    final Set<String> favs = <String>{};
    for (final GameItem g in all) {
      if (await _service.isFavorite(g.id)) favs.add(g.id);
    }
    favoriteIds.assignAll(favs);
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

  /// 从本地缓存过滤指定分类的游戏（同步，避免UI层 await）
  Future<List<GameItem>> getGamesByCategory(String categoryId) {
    return _service.getGamesByCategory(categoryId);
  }

  /// 从本地 games 缓存中同步过滤，供 UI 层 Obx 使用
  List<GameItem> getGamesByCategorySync(String categoryId) {
    // 无法在 ViewModel 层知道分类关联，需异步；UI 层应改用 FutureBuilder 或预加载
    // 返回空列表作占位，调用方请用 getGamesByCategory 并预加载
    return games.toList(growable: false);
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

  /// 扫描 [parentDir]，调用 Rust 扫描逻辑获取候选游戏文件夹，
  /// 搜索元数据后批量导入。
  Future<int> _batchImportGameFolders(String parentDir) async {
    // Rust 负责文件系统扫描（含递归、exe 检测）
    final String scanJson = await rust_api.gameLibraryScanDirectoryJson(paths: <String>[parentDir]);
    final List<dynamic> rawList = jsonDecode(scanJson) as List<dynamic>;
    if (rawList.isEmpty) {
      _logger.info('批量导入：未在 $parentDir 的子目录中找到含可执行文件的文件夹');
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
    for (final dynamic raw in rawList) {
      final Map<String, dynamic> info = Map<String, dynamic>.from(raw as Map);
      final String folderPath = info['folderPath'] as String? ?? '';
      final String folderName = info['folderName'] as String? ?? '';
      final List<String> exePaths =
          (info['exePaths'] as List<dynamic>?)
              ?.map((dynamic e) => e.toString())
              .toList(growable: false) ??
          <String>[];

      if (folderPath.isEmpty || folderName.isEmpty) continue;

      if (existingDirs.contains(folderPath.toLowerCase())) {
        _logger.info('批量导入跳过（目录已存在）: $folderPath');
        continue;
      }

      _logger.info('批量导入：搜索游戏信息 "$folderName"');
      final dynamic metadata = await _service.searchMetadataByName(folderName);
      if (metadata == null) {
        _logger.info('批量导入：API 未找到匹配游戏，跳过 "$folderName"');
        continue;
      }

      final String finalName = (metadata.name as String).trim().isNotEmpty
          ? (metadata.name as String).trim()
          : folderName;

      if (existingNames.contains(finalName.toLowerCase())) {
        _logger.info('批量导入跳过（游戏名已存在）: $finalName');
        existingDirs.add(folderPath.toLowerCase());
        continue;
      }

      // Rust 负责选择默认 exe（取 exePaths 第一项）
      final String defaultExe = exePaths.isNotEmpty ? exePaths.first : '';

      await _service.addGame(
        name: finalName,
        company: (metadata.company as String).trim().isNotEmpty
            ? (metadata.company as String).trim()
            : '未知',
        summary: (metadata.summary as String).trim(),
        rating: metadata.rating as double,
        releaseDate: (metadata.releaseDate as String).trim(),
        path: defaultExe,
        status: GameStatus.notStarted,
        coverPath: (metadata.coverUrl as String).trim(),
        exePaths: exePaths,
        gameDir: folderPath,
      );

      imported++;
      existingDirs.add(folderPath.toLowerCase());
      existingNames.add(finalName.toLowerCase());
      _logger.info('批量导入成功: $finalName ($folderPath)');
    }

    await refresh();
    return imported;
  }

  /// 供 UI 层调用：根据可执行文件路径推导游戏名（委托给 Rust）
  String deriveGameName(String executablePath) {
    return rust_api.gameLibraryDeriveGameName(path: executablePath);
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
    final bool next = !favoriteIds.contains(game.id);
    await _service.toggleFavorite(game.id, next);
    if (next) {
      favoriteIds.add(game.id);
    } else {
      favoriteIds.remove(game.id);
    }
  }

  bool isFavorite(String gameId) {
    return favoriteIds.contains(gameId);
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
    selectedIds.assignAll(next);
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
