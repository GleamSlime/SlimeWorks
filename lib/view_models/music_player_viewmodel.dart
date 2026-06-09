import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;

part 'music_player_vm_remote.dart';

/// 播放模式
enum PlayerPlayMode {
  sequential('顺序播放', Icons.repeat_rounded),
  loop('列表循环', Icons.repeat_rounded),
  singleLoop('单曲循环', Icons.repeat_one_rounded),
  shuffle('随机播放', Icons.shuffle_rounded);

  final String label;
  final IconData icon;
  const PlayerPlayMode(this.label, this.icon);
}

/// 音乐播放器 ViewModel
class MusicPlayerViewModel extends BaseViewModel {
  final NodeSettingsService _nodeService = getIt<NodeSettingsService>();
  final Loggers _logger = Loggers(name: '播放器');

  // ── 播放列表 ─────────────────────────────────────────────────────────────
  final playlists = <music_api.Playlist>[].obs;
  final currentPlaylistId = Rxn<String>();

  // ── 目录 ─────────────────────────────────────────────────────────────────
  final folders = <music_api.FolderInfo>[].obs;

  /// 当前浏览的目录 ID，null 表示根级
  final currentFolderId = Rxn<String>();

  /// 面包屑导航路径
  final breadcrumbFolders = <music_api.FolderInfo>[].obs;

  // ── 音乐列表 ─────────────────────────────────────────────────────────────
  final currentItems = <music_api.MusicItem>[].obs;

  // ── 播放状态 ─────────────────────────────────────────────────────────────
  final isPlaying = false.obs;
  final currentIndex = (-1).obs;
  final currentPositionMs = 0.obs;
  final durationMs = 0.obs;
  final playMode = PlayerPlayMode.sequential.obs;

  // ── 当前播放歌曲信息 ──────────────────────────────────────────────────────
  final currentTitle = ''.obs;
  final currentArtist = Rxn<String>();
  final currentAlbum = Rxn<String>();
  final currentCoverPath = Rxn<String>();

  // ── 收藏 ─────────────────────────────────────────────────────────────────
  final favoriteItems = <music_api.MusicItem>[].obs;

  // ── 最近播放 ─────────────────────────────────────────────────────────────
  final recentRecords = <music_api.PlayRecordInfo>[].obs;

  // ── 均衡器 ───────────────────────────────────────────────────────────────
  final eqPresets = <music_api.EqualizerPresetInfo>[].obs;
  final currentEqPresetId = Rxn<String>();

  // ── 搜索 ─────────────────────────────────────────────────────────────────
  final searchQuery = ''.obs;

  /// 是否正在从远程节点加载
  final isRemoteLoading = false.obs;

  /// 是否正在导入音乐
  final isImporting = false.obs;

  /// 导入状态文本
  final importingStatus = ''.obs;

  // ── 音频播放器（media_kit） ───────────────────────────────────────────────
  final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
  );
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  bool _playerReady = false;

  @override
  void onInit() {
    super.onInit();
    _initPlayer();
    _loadFolders();
    _loadPlaylists();
  }

  void _initPlayer() {
    // 监听播放位置
    _positionSub = _player.stream.position.listen((pos) {
      currentPositionMs.value = pos.inMilliseconds;
    });

    // 监听时长变化
    _durationSub = _player.stream.duration.listen((dur) {
      if (dur.inMilliseconds > 0) {
        durationMs.value = dur.inMilliseconds;
      }
    });

    // 监听播放状态
    _playingSub = _player.stream.playing.listen((playing) {
      isPlaying.value = playing;
    });

    // 监听播放完毕，自动切歌
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        _onPlaybackCompleted();
      }
    });
  }

  /// 播放完毕回调
  void _onPlaybackCompleted() {
    switch (playMode.value) {
      case PlayerPlayMode.singleLoop:
        _player.seek(Duration.zero);
        _player.play();
        break;
      case PlayerPlayMode.loop:
        playNext();
        break;
      case PlayerPlayMode.sequential:
        final next = currentIndex.value + 1;
        if (next < currentItems.length) {
          playItem(next);
        } else {
          isPlaying.value = false;
        }
        break;
      case PlayerPlayMode.shuffle:
        playNext();
        break;
    }
  }

  @override
  void onClose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.onClose();
  }

  // ── 目录操作 ─────────────────────────────────────────────────────────────

  Future<void> _loadFolders() async {
    try {
      folders.value = music_api.getAllFolders();
    } catch (e) {
      _logger.info('[播放器] 加载目录失败: $e');
    }
  }

  /// 进入指定目录
  Future<void> navigateToFolder(String? folderId) async {
    currentFolderId.value = folderId;
    await _loadPlaylists();
    _updateBreadcrumb(folderId);
  }

  /// 返回上级目录
  Future<void> navigateUp() async {
    final current = currentFolderId.value;
    if (current == null) return;
    final folder = folders.firstWhereOrNull((f) => f.id == current);
    await navigateToFolder(folder?.parentId);
  }

  /// 更新面包屑导航
  void _updateBreadcrumb(String? folderId) {
    breadcrumbFolders.clear();
    if (folderId == null) return;
    // 从当前目录向上回溯构建路径
    final path = <music_api.FolderInfo>[];
    var current = folders.firstWhereOrNull((f) => f.id == folderId);
    while (current != null) {
      path.insert(0, current);
      current = current.parentId != null
          ? folders.firstWhereOrNull((f) => f.id == current!.parentId)
          : null;
    }
    breadcrumbFolders.value = path;
  }

  /// 获取当前目录下的子目录
  List<music_api.FolderInfo> get currentSubFolders {
    return folders.where((f) => f.parentId == currentFolderId.value).toList();
  }

  /// 获取当前目录下的播放列表
  List<music_api.Playlist> get currentFolderPlaylists {
    return playlists.where((p) => p.folderId == currentFolderId.value).toList();
  }

  /// 创建子目录
  Future<void> createSubFolder(String name) async {
    try {
      final folder = music_api.createFolder(
        name: name,
        parentId: currentFolderId.value,
      );
      folders.add(folder);
    } catch (e) {
      _logger.info('[播放器] 创建目录失败: $e');
    }
  }

  /// 重命名目录
  Future<void> renameFolder(String folderId, String name) async {
    try {
      music_api.renameFolder(folderId: folderId, name: name);
      await _loadFolders();
    } catch (e) {
      _logger.info('[播放器] 重命名目录失败: $e');
    }
  }

  /// 删除目录
  Future<void> deleteFolder(String folderId) async {
    try {
      music_api.deleteFolder(folderId: folderId);
      await _loadFolders();
      await _loadPlaylists();
    } catch (e) {
      _logger.info('[播放器] 删除目录失败: $e');
    }
  }

  // ── 播放列表操作 ─────────────────────────────────────────────────────────

  Future<void> _loadPlaylists() async {
    try {
      // 初始化数据库
      music_api.musicInitializeDb();
      // 确保默认播放列表存在
      final allPlaylists = music_api.getAllPlaylists();
      if (allPlaylists.isEmpty) {
        music_api.ensureDefaultPlaylist();
      }
      final list = music_api.getPlaylistsByFolder(
        folderId: currentFolderId.value,
      );
      playlists.value = list;
      if (currentPlaylistId.value == null && playlists.isNotEmpty) {
        await selectPlaylist(playlists.first.id);
      }
    } catch (e) {
      _logger.info('[播放器] 加载播放列表失败: $e');
    }
  }

  Future<void> selectPlaylist(String playlistId) async {
    currentPlaylistId.value = playlistId;
    await _loadPlaylistItems(playlistId);
  }

  Future<void> _loadPlaylistItems(String playlistId) async {
    try {
      currentItems.value = music_api.getPlaylistItems(playlistId: playlistId);
      // 后台修复缺失的元数据（时长等）
      _repairMetadataInBackground(playlistId);
    } catch (e) {
      _logger.info('[播放器] 加载音乐列表失败: $e');
    }
  }

  /// 后台修复缺失的元数据
  void _repairMetadataInBackground(String playlistId) {
    // 检查是否有时长缺失的条目
    final hasMissing = currentItems.any((i) => i.durationMs == null);
    if (!hasMissing) return;
    Future(() async {
      try {
        final count = await music_api.repairMissingMetadata(
          playlistId: playlistId,
        );
        if (count > BigInt.zero) {
          _logger.info('[播放器] 修复了 ${count.toInt()} 条元数据');
          currentItems.value = music_api.getPlaylistItems(
            playlistId: playlistId,
          );
        }
      } catch (e) {
        _logger.info('[播放器] 修复元数据失败: $e');
      }
    });
  }

  Future<void> createPlaylist(String name) async {
    try {
      music_api.createPlaylistInFolder(
        name: name,
        folderId: currentFolderId.value,
      );
      await _loadPlaylists();
      // 选中新创建的列表
      final newList = music_api.getPlaylistsByFolder(
        folderId: currentFolderId.value,
      );
      if (newList.isNotEmpty) {
        await selectPlaylist(newList.last.id);
      }
    } catch (e) {
      _logger.info('[播放器] 创建播放列表失败: $e');
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    try {
      music_api.renamePlaylist(playlistId: playlistId, name: name);
      await _loadPlaylists();
    } catch (e) {
      _logger.info('[播放器] 重命名播放列表失败: $e');
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      music_api.deletePlaylist(playlistId: playlistId);
      await _loadPlaylists();
      if (currentPlaylistId.value == playlistId) {
        currentPlaylistId.value = playlists.isNotEmpty
            ? playlists.first.id
            : null;
        if (currentPlaylistId.value != null) {
          await selectPlaylist(currentPlaylistId.value!);
        } else {
          currentItems.clear();
        }
      }
    } catch (e) {
      _logger.info('[播放器] 删除播放列表失败: $e');
    }
  }

  // ── 音乐导入 ─────────────────────────────────────────────────────────────

  Future<void> importMusicFolder(String folderPath) async {
    final pid = currentPlaylistId.value;
    if (pid == null) return;
    isImporting.value = true;
    importingStatus.value = '正在扫描音乐文件...';
    try {
      await music_api.importMusicFolder(
        playlistId: pid,
        folderPath: folderPath,
      );
      importingStatus.value = '导入完成，正在刷新列表...';
      await _loadPlaylistItems(pid);
      await _loadPlaylists();
      importingStatus.value = '正在提取封面...';
      // 后台提取封面
      _extractCoversInBackground(pid);
    } catch (e) {
      _logger.info('[播放器] 导入音乐文件夹失败: $e');
      importingStatus.value = '导入失败: $e';
    } finally {
      // 封面提取是后台的，不阻塞 finally
      Future.delayed(const Duration(seconds: 2), () {
        if (importingStatus.value.contains('提取封面')) {
          isImporting.value = false;
          importingStatus.value = '';
        }
      });
    }
  }

  Future<void> importMusicPaths(List<String> paths) async {
    final pid = currentPlaylistId.value;
    if (pid == null) return;
    isImporting.value = true;
    importingStatus.value = '正在导入音乐...';
    try {
      await music_api.importMusicPaths(playlistId: pid, paths: paths);
      await _loadPlaylistItems(pid);
      await _loadPlaylists();
      _extractCoversInBackground(pid);
    } catch (e) {
      _logger.info('[播放器] 导入音乐失败: $e');
      importingStatus.value = '导入失败: $e';
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        isImporting.value = false;
        importingStatus.value = '';
      });
    }
  }

  /// 后台提取封面
  void _extractCoversInBackground(String playlistId) {
    Future(() async {
      try {
        final count = await music_api.batchExtractCovers(
          playlistId: playlistId,
        );
        if (count > BigInt.zero) {
          importingStatus.value = '已提取 ${count.toInt()} 个封面';
          await _loadPlaylistItems(playlistId);
        }
      } catch (e) {
        _logger.info('[播放器] 后台提取封面失败: $e');
      } finally {
        isImporting.value = false;
        importingStatus.value = '';
      }
    });
  }

  /// 打开文件选择器导入音乐
  Future<void> pickAndImportFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3',
        'flac',
        'aac',
        'm4a',
        'ogg',
        'opus',
        'wav',
        'wma',
        'ape',
        'aiff',
        'alac',
      ],
      allowMultiple: true,
    );
    if (result != null && result.paths.isNotEmpty) {
      final paths = result.paths.whereType<String>().toList();
      await importMusicPaths(paths);
    }
  }

  /// 打开文件夹选择器导入音乐
  Future<void> pickAndImportFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await importMusicFolder(result);
    }
  }

  /// 拖拽导入
  /// 文件夹→自动以文件夹名创建子目录并在其中新建播放列表
  /// 多个音频文件→导入到当前目录的当前播放列表
  Future<void> importDroppedPaths(List<String> paths) async {
    final pid = currentPlaylistId.value;
    final folders = <String>[];
    final files = <String>[];
    for (final p in paths) {
      final entity = FileSystemEntity.typeSync(p);
      if (entity == FileSystemEntityType.directory) {
        folders.add(p);
      } else if (entity == FileSystemEntityType.file) {
        files.add(p);
      }
    }
    // 文件夹：每个文件夹创建子目录 + 播放列表
    for (final folder in folders) {
      final dirName = Directory(folder).path.split(Platform.pathSeparator).last;
      try {
        // 在当前目录下创建子目录
        final newFolder = music_api.createFolder(
          name: dirName,
          parentId: currentFolderId.value,
        );
        // 在子目录下创建播放列表并导入
        final pl = music_api.createPlaylistInFolder(
          name: dirName,
          folderId: newFolder.id,
        );
        await music_api.importMusicFolder(
          playlistId: pl.id,
          folderPath: folder,
        );
      } catch (e) {
        _logger.info('[播放器] 拖拽导入文件夹失败: $e');
      }
    }
    // 多个音频文件：导入到当前播放列表
    if (files.isNotEmpty) {
      if (pid != null) {
        await importMusicPaths(files);
      } else {
        // 当前目录没有播放列表，自动创建一个
        await createPlaylist('导入的音乐');
        final newPid = currentPlaylistId.value;
        if (newPid != null) {
          await importMusicPaths(files);
        }
      }
    }
    // 刷新
    await _loadFolders();
    await _loadPlaylists();
  }

  // ── 音乐操作 ─────────────────────────────────────────────────────────────

  Future<void> deleteMusicItem(String itemId) async {
    try {
      music_api.deleteMusicItem(itemId: itemId);
      currentItems.removeWhere((i) => i.id == itemId);
    } catch (e) {
      _logger.info('[播放器] 删除音乐失败: $e');
    }
  }

  Future<void> updateMusicItem({
    required String itemId,
    String? title,
    String? artist,
    String? album,
    bool? isFavorite,
  }) async {
    try {
      music_api.updateMusicItem(
        itemId: itemId,
        title: title,
        artist: artist,
        album: album,
        isFavorite: isFavorite,
      );
      final pid = currentPlaylistId.value;
      if (pid != null) {
        await _loadPlaylistItems(pid);
      }
    } catch (e) {
      _logger.info('[播放器] 更新音乐信息失败: $e');
    }
  }

  // ── 播放控制 ─────────────────────────────────────────────────────────────

  Future<void> playItem(int index) async {
    if (index < 0 || index >= currentItems.length) return;
    currentIndex.value = index;
    final item = currentItems[index];
    currentTitle.value = item.title;
    currentArtist.value = item.artist;
    currentAlbum.value = item.album;
    currentCoverPath.value = item.coverPath;
    currentPositionMs.value = 0;
    durationMs.value = item.durationMs != null ? item.durationMs!.toInt() : 0;
    _recordPlay(item.id);

    try {
      // 设置音频源为本地文件
      final uri = item.filePath.startsWith('http')
          ? item.filePath
          : Uri.file(item.filePath).toString();
      await _player.open(Media(uri));
      _playerReady = true;
      await _player.play();
    } catch (e) {
      _logger.info('[播放器] 播放失败: $e');
      isPlaying.value = false;
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.state.playing) {
      await _player.pause();
    } else {
      // 如果还没有加载音频源，播放当前选中项
      if (!_playerReady && currentIndex.value >= 0) {
        await playItem(currentIndex.value);
      } else {
        await _player.play();
      }
    }
  }

  void playNext() {
    if (currentItems.isEmpty) return;
    int next;
    switch (playMode.value) {
      case PlayerPlayMode.singleLoop:
        next = currentIndex.value;
        break;
      case PlayerPlayMode.shuffle:
        next = (currentIndex.value + 1) % currentItems.length;
        break;
      case PlayerPlayMode.loop:
        next = (currentIndex.value + 1) % currentItems.length;
        break;
      case PlayerPlayMode.sequential:
        next = currentIndex.value + 1;
        if (next >= currentItems.length) {
          isPlaying.value = false;
          return;
        }
    }
    playItem(next);
  }

  void playPrevious() {
    if (currentItems.isEmpty) return;
    // 如果播放超过3秒，回到开头而不是上一曲
    if (_player.state.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prev = currentIndex.value - 1;
    if (prev < 0) {
      prev = playMode.value == PlayerPlayMode.loop
          ? currentItems.length - 1
          : 0;
    }
    playItem(prev);
  }

  Future<void> seekTo(int positionMs) async {
    await _player.seek(Duration(milliseconds: positionMs));
  }

  void cyclePlayMode() {
    final modes = PlayerPlayMode.values;
    final idx = modes.indexOf(playMode.value);
    playMode.value = modes[(idx + 1) % modes.length];
  }

  // ── 收藏 ─────────────────────────────────────────────────────────────────

  Future<void> toggleFavorite(String itemId) async {
    try {
      music_api.toggleFavorite(itemId: itemId);
      final pid = currentPlaylistId.value;
      if (pid != null) {
        await _loadPlaylistItems(pid);
      }
      await loadFavorites();
    } catch (e) {
      _logger.info('[播放器] 切换收藏失败: $e');
    }
  }

  Future<void> loadFavorites() async {
    try {
      favoriteItems.value = music_api.getFavoriteItems();
    } catch (e) {
      _logger.info('[播放器] 加载收藏失败: $e');
    }
  }

  // ── 最近播放 ─────────────────────────────────────────────────────────────

  Future<void> loadRecentPlayed({int limit = 50}) async {
    try {
      recentRecords.value = music_api.getRecentPlayed(limit: limit);
    } catch (e) {
      _logger.info('[播放器] 加载最近播放失败: $e');
    }
  }

  Future<void> _recordPlay(String musicId) async {
    try {
      music_api.recordPlay(musicId: musicId);
    } catch (_) {}
  }

  // ── 均衡器 ───────────────────────────────────────────────────────────────

  Future<void> loadEqPresets() async {
    try {
      eqPresets.value = music_api.getEqPresets();
    } catch (e) {
      _logger.info('[播放器] 加载均衡器预设失败: $e');
    }
  }

  Future<void> saveEqPreset(String name, List<double> bands) async {
    try {
      music_api.saveEqPreset(name: name, bands: bands);
      await loadEqPresets();
    } catch (e) {
      _logger.info('[播放器] 保存均衡器预设失败: $e');
    }
  }

  // ── 搜索 ─────────────────────────────────────────────────────────────────

  List<music_api.MusicItem> get filteredItems {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return currentItems;
    return currentItems.where((item) {
      return item.title.toLowerCase().contains(query) ||
          (item.artist?.toLowerCase().contains(query) ?? false) ||
          (item.album?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  // ── 刷新 ─────────────────────────────────────────────────────────────────

  Future<void> refreshAll() async {
    await _loadFolders();
    await _loadPlaylists();
    if (currentPlaylistId.value != null) {
      await _loadPlaylistItems(currentPlaylistId.value!);
    }
    await loadFavorites();
    await loadRecentPlayed();
    await loadEqPresets();
  }

  /// 当前播放的歌曲
  music_api.MusicItem? get currentItem {
    if (currentIndex.value < 0 || currentIndex.value >= currentItems.length) {
      return null;
    }
    return currentItems[currentIndex.value];
  }

  /// 格式化时长 mm:ss
  String formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
