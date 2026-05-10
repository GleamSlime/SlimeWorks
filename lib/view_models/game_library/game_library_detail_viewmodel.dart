import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/src/rust/api/game_library.dart' as rust_api;

const Loggers _logger = Loggers(name: '游戏详情ViewModel');

class GameLibraryDetailViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();
  final GameProcessTracker processTracker = getIt<GameProcessTracker>();

  final Rxn<GameItem> game = Rxn<GameItem>();
  final RxList<PlaySession> sessions = <PlaySession>[].obs;
  final Rxn<GameProgress> progress = Rxn<GameProgress>();
  final RxList<GameCategory> categories = <GameCategory>[].obs;
  final RxSet<String> selectedCategoryIds = <String>{}.obs;
  final RxString detectedSaveFolder = ''.obs;

  // ── 萌娘百科 ────────────────────────────────────────────
  final RxString moegirlHtml = ''.obs;
  final RxBool moegirlLoading = false.obs;
  final RxString moegirlError = ''.obs;

  // ── 2DFan ────────────────────────────────────────────────
  final RxString twodfanDesc = ''.obs;
  final RxString twodfanStatus = ''.obs;
  final RxBool twodfanProcessing = false.obs;

  // ── 启动设置 ─────────────────────────────────────────────
  final RxBool useOpenOnMacos = false.obs;

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
    // 加载全局设置（useOpenOnMacos）
    try {
      final GameLibrarySettings settings = await _service.getSettings();
      useOpenOnMacos.value = settings.useOpenOnMacos;
    } catch (_) {}
    // 尝试检测存档目录
    await detectSaveFolder();
    // 后台加载萌娘百科内容（不阻塞主界面）
    _fetchMoegirlInBackground();
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
  bool _launching = false;

  Future<bool> launchGame({String? overrideExePath}) async {
    if (_launching) return false;
    _launching = true;
    try {
      return await _doLaunchGame(overrideExePath: overrideExePath);
    } finally {
      _launching = false;
    }
  }

  Future<bool> _doLaunchGame({String? overrideExePath}) async {
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
      useOpen: useOpenOnMacos.value,
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

  // ── 萌娘百科 ─────────────────────────────────────────────

  void _fetchMoegirlInBackground() {
    final String? name = game.value?.name;
    if (name == null || name.trim().isEmpty) return;
    moegirlLoading.value = true;
    moegirlHtml.value = '';
    moegirlError.value = '';
    rust_api
        .gameLibraryFetchMoegirl(gameName: name)
        .then((String html) {
          moegirlHtml.value = html;
          moegirlLoading.value = false;
        })
        .catchError((Object e) {
          _logger.info('萌娘百科加载失败: $e');
          moegirlError.value = e.toString();
          moegirlLoading.value = false;
        });
  }

  void retryMoegirl() => _fetchMoegirlInBackground();

  // ── 2DFan ─────────────────────────────────────────────────

  /// 执行完整的「搜索→获取存档列表→获取下载链接→下载文件」流程。
  /// [downloadItemPath]：若提供则跳过搜索/列表步骤，直接使用该路径进行下载。
  Future<void> downloadTwodfanSave({String? downloadItemPath}) async {
    final String? name = game.value?.name;
    if (name == null || name.trim().isEmpty) return;
    if (twodfanProcessing.value) return;

    twodfanProcessing.value = true;
    twodfanDesc.value = '';

    try {
      String actualDownloadPath;

      if (downloadItemPath != null) {
        // 直接使用外部传入的路径（来自选择器）
        actualDownloadPath = downloadItemPath;
        twodfanStatus.value = '正在获取下载链接...';
      } else {
        // Step 1: 搜索
        twodfanStatus.value = '正在搜索游戏...';
        final String subjectPath = await rust_api.gameLibrarySearch2DfanSubject(gameName: name);
        if (subjectPath.isEmpty) {
          twodfanStatus.value = '未在 2DFan 找到该游戏';
          return;
        }

        // Step 2: 获取存档下载列表（JSON 数组）
        twodfanStatus.value = '正在获取存档列表...';
        final String itemsJson = await rust_api.gameLibraryFetch2DfanDownloadPath(
          subjectPath: subjectPath,
        );
        final dynamic parsed = _parseJson(itemsJson);
        final List<dynamic> items = parsed is List ? parsed : <dynamic>[];
        if (items.isEmpty) {
          twodfanStatus.value = '未找到存档资源';
          return;
        }
        actualDownloadPath = (items.first as Map?)?['path'] as String? ?? '';
        if (actualDownloadPath.isEmpty) {
          twodfanStatus.value = '未找到存档资源';
          return;
        }
        twodfanStatus.value = '正在获取下载链接...';
      }

      // Step 3: 获取下载链接与简介
      final String infoJson = await rust_api.gameLibraryFetch2DfanDownloadInfo(
        downloadPath: actualDownloadPath,
      );
      final Map<String, dynamic> info = Map<String, dynamic>.from((_parseJson(infoJson)) as Map);
      final String desc = (info['description'] as String?) ?? '';
      if (desc.isNotEmpty) twodfanDesc.value = desc;
      final String fileUrl = (info['fileUrl'] as String?) ?? '';
      if (fileUrl.isEmpty) {
        twodfanStatus.value = '未找到下载文件';
        return;
      }

      // Step 4: 下载到 ~/Downloads
      twodfanStatus.value = '正在下载...';
      final String home = Platform.environment['HOME'] ?? '';
      final String downloadsDir = home.isNotEmpty ? '$home/Downloads' : '.';
      final String filename = fileUrl
          .split('/')
          .last
          .split('?')
          .first
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      final String destPath = '$downloadsDir/$filename';

      // Rust 直接下载（内部已处理代理）
      await rust_api.gameLibraryDownloadFile(url: fileUrl, savePath: destPath);
      twodfanStatus.value = '下载完成: $destPath';
    } catch (e) {
      twodfanStatus.value = '下载失败: $e';
      _logger.info('2DFan下载失败: $e');
    } finally {
      twodfanProcessing.value = false;
    }
  }

  /// 获取 2DFan 存档条目列表（用于 UI 选择器）。返回 [{path, title}, ...]
  Future<List<Map<String, String>>> fetchTwodfanDownloadItems() async {
    final String? name = game.value?.name;
    if (name == null || name.trim().isEmpty) return const <Map<String, String>>[];
    final String subjectPath = await rust_api.gameLibrarySearch2DfanSubject(gameName: name);
    if (subjectPath.isEmpty) return const <Map<String, String>>[];
    final String itemsJson = await rust_api.gameLibraryFetch2DfanDownloadPath(
      subjectPath: subjectPath,
    );
    final dynamic parsed = _parseJson(itemsJson);
    if (parsed is! List) return const <Map<String, String>>[];
    return parsed
        .whereType<Map>()
        .map(
          (dynamic e) => Map<String, String>.from(
            (e as Map).map<String, String>(
              (dynamic k, dynamic v) => MapEntry(k.toString(), v.toString()),
            ),
          ),
        )
        .toList();
  }

  dynamic _parseJson(String s) {
    if (s.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(s);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<GameLibrarySettings> getSettings() => _service.getSettings();

  Future<void> saveSettings(GameLibrarySettings settings) => _service.updateSettings(settings);
}
