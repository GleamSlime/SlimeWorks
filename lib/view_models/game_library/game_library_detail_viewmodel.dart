import 'dart:io';

import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

final Loggers _logger = Loggers(name: '游戏详情ViewModel');

class GameLibraryDetailViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();
  final GameProcessTracker processTracker = getIt<GameProcessTracker>();

  final Rxn<GameItem> game = Rxn<GameItem>();
  final RxList<PlaySession> sessions = <PlaySession>[].obs;
  final Rxn<GameProgress> progress = Rxn<GameProgress>();
  final RxList<GameCategory> categories = <GameCategory>[].obs;
  final RxSet<String> selectedCategoryIds = <String>{}.obs;
  // 自动检测到的存档目录（相对于 game.gameDir 或可识别的子目录）
  final RxString detectedSaveFolder = ''.obs;

  Future<void> load(String gameId) async {
    await _service.init();
    game.value = await _service.getGameById(gameId);
    sessions.assignAll(await _service.getPlaySessionsByGameId(gameId));
    progress.value = await _service.getProgressByGameId(gameId);
    categories.assignAll(await _service.getCategories());
    selectedCategoryIds
      ..clear()
      ..addAll(await _service.getCategoryIdsByGameId(gameId));
    // 监听游玩会话保存（游戏退出后）自动刷新
    ever(processTracker.sessionSavedCount, (_) {
      final String? id = game.value?.id;
      if (id != null) {
        load(id);
      }
    });
    // 尝试检测存档目录
    await detectSaveFolder();
  }

  /// 简单启发式检测游戏存档目录：检查游戏目录下常见的存档文件夹名
  Future<String?> detectSaveFolder() async {
    final GameItem? current = game.value;
    if (current == null) return null;
    final String dir = current.gameDir.trim();
    if (dir.isEmpty) {
      detectedSaveFolder.value = '';
      return null;
    }
    try {
      final Directory base = Directory(dir);
      if (!base.existsSync()) {
        detectedSaveFolder.value = '';
        return null;
      }
      final List<String> candidates = <String>[
        'save',
        'saves',
        'savegames',
        'savedata',
        'Save',
        'Saves',
        'Saved Games',
        'UserData',
        'userdata',
      ];
      for (final String name in candidates) {
        final Directory d = Directory('${base.path}${Platform.pathSeparator}$name');
        if (d.existsSync()) {
          detectedSaveFolder.value = d.path;
          return d.path;
        }
      }

      // 若没有标准名字，尝试查找体积较小的子目录（heuristic）
      final List<FileSystemEntity> children = base.listSync();
      for (final FileSystemEntity ent in children) {
        if (ent is Directory) {
          final String lower = ent.path.split(Platform.pathSeparator).last.toLowerCase();
          if (lower.contains('save') || lower.contains('userdata') || lower.contains('saves')) {
            detectedSaveFolder.value = ent.path;
            return ent.path;
          }
        }
      }
    } catch (_) {}
    detectedSaveFolder.value = '';
    return null;
  }

  Future<void> updateGame(GameItem next) async {
    await _service.updateGame(next);
    await load(next.id);
  }

  /// 从远程元数据源刷新当前游戏数据
  Future<void> refreshMetadata() async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    final GameSearchMetadata? meta = await _service.searchMetadataByName(current.name);
    if (meta == null) {
      return;
    }
    await _service.updateGame(
      current.copyWith(
        name: meta.name.trim().isNotEmpty ? meta.name.trim() : current.name,
        company: meta.company.trim().isNotEmpty ? meta.company.trim() : current.company,
        summary: meta.summary.trim().isNotEmpty ? meta.summary.trim() : current.summary,
        rating: meta.rating > 0 ? meta.rating : current.rating,
        releaseDate: meta.releaseDate.trim().isNotEmpty
            ? meta.releaseDate.trim()
            : current.releaseDate,
        coverPath: meta.coverUrl.trim().isNotEmpty ? meta.coverUrl.trim() : current.coverPath,
      ),
    );
    await load(current.id);
  }

  Future<void> toggleCategory(String categoryId, bool checked) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    final Set<String> next = Set<String>.from(selectedCategoryIds);
    if (checked) {
      next.add(categoryId);
    } else {
      next.remove(categoryId);
    }
    await _service.setGameCategories(current.id, next);
    await load(current.id);
  }

  Future<void> saveProgress({
    required String chapter,
    required String route,
    required String note,
  }) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    await _service.upsertProgress(gameId: current.id, chapter: chapter, route: route, note: note);
    await load(current.id);
  }

  Future<void> addManualSession({required DateTime start, required DateTime end}) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    await _service.addPlaySession(gameId: current.id, startTime: start, endTime: end);
    await load(current.id);
  }

  Future<void> toggleFavorite(bool favorite) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    await _service.toggleFavorite(current.id, favorite);
    await load(current.id);
  }

  bool get isFavorite {
    // 使用本地缓存值（load 时已加载），如需实时可改为 Future<bool>
    return false; // placeholder — see isFavoriteAsync
  }

  Future<bool> isFavoriteAsync() async {
    final GameItem? current = game.value;
    if (current == null) return false;
    return _service.isFavorite(current.id);
  }

  String formatDuration(int seconds) {
    final int hour = seconds ~/ 3600;
    final int minute = (seconds % 3600) ~/ 60;
    if (hour == 0) {
      return '$minute 分钟';
    }
    return '$hour 小时 $minute 分钟';
  }

  /// 当前游戏是否正在运行
  bool get isRunning {
    final String? id = game.value?.id;
    if (id == null) {
      return false;
    }
    return processTracker.isRunning(id);
  }

  /// 获取游戏所有可用 exe 路径（供 UI 展示多 exe 选择）
  List<String> get gameExePaths {
    final GameItem? g = game.value;
    if (g == null) {
      return <String>[];
    }
    if (g.exePaths.isNotEmpty) {
      return g.exePaths;
    }
    if (g.path.trim().isNotEmpty) {
      return <String>[g.path.trim()];
    }
    return <String>[];
  }

  /// 启动游戏。[overrideExePath] 非空时跳过默认 exe 逻辑直接启动指定 exe。
  Future<bool> launchGame({String? overrideExePath}) async {
    final GameItem? current = game.value;
    if (current == null) {
      return false;
    }

    final String exePath = (overrideExePath?.trim().isNotEmpty == true)
        ? overrideExePath!.trim()
        : _resolveDefaultExe(current);

    if (exePath.isEmpty) {
      setError('未配置启动路径，请在「编辑」标签中填写');
      return false;
    }
    if (!File(exePath).existsSync()) {
      setError('启动文件不存在: $exePath');
      return false;
    }

    final String workDir = _resolveWorkingDirectory(current, exePath);
    _logger.info('详情页启动游戏: ${current.name}, exe=$exePath, workDir=$workDir');

    final bool ok = await processTracker.launchAndTrack(
      gameId: current.id,
      exePath: exePath,
      workingDirectory: workDir,
    );
    if (!ok) {
      setError('启动失败，请确认可执行文件是否有效');
    }
    return ok;
  }

  /// 设置默认启动 exe
  Future<void> setDefaultExe(String exePath) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    await _service.updateGame(current.copyWith(path: exePath));
    await load(current.id);
  }

  /// 从 exePaths 列表中移除指定 exe
  Future<void> removeExePath(String exePath) async {
    final GameItem? current = game.value;
    if (current == null) {
      return;
    }
    final List<String> updated = List<String>.from(current.exePaths)..remove(exePath);
    String newDefault = current.path;
    if (newDefault == exePath) {
      newDefault = updated.isNotEmpty ? updated.first : '';
    }
    await _service.updateGame(current.copyWith(exePaths: updated, path: newDefault));
    await load(current.id);
  }

  String _resolveDefaultExe(GameItem g) {
    final String primary = g.path.trim();
    if (primary.isNotEmpty && File(primary).existsSync()) {
      return primary;
    }
    for (final String p in g.exePaths) {
      if (File(p).existsSync()) {
        return p;
      }
    }
    return primary;
  }

  String _resolveWorkingDirectory(GameItem g, String exePath) {
    final String dir = g.gameDir.trim();
    if (dir.isNotEmpty && Directory(dir).existsSync()) {
      return dir;
    }
    return File(exePath).parent.path;
  }
}
