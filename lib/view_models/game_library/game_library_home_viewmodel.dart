import 'dart:async';

import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryHomeViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();
  final GameProcessTracker _processTracker = getIt<GameProcessTracker>();

  final Rxn<GameLibraryHomeData> homeData = Rxn<GameLibraryHomeData>();

  /// 游玩会话保存事件订阅（onClose 时必须销毁，否则页面销毁后仍持续刷新）
  Worker? _sessionWorker;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    await refresh();
    _sessionWorker ??= ever(_processTracker.sessionSavedCount, (_) {
      if (!isClosed) refresh();
    });
  }

  @override
  void onClose() {
    _sessionWorker?.dispose();
    _sessionWorker = null;
    super.onClose();
  }

  @override
  Future<void> refresh() async {
    homeData.value = await _service.getHomeData();
  }

  Future<void> launchGame(GameItem game) async {
    final String path = game.path.trim();
    if (path.isEmpty) {
      setError('未配置启动路径');
      return;
    }
    final String workDir = game.gameDir.trim().isNotEmpty ? game.gameDir.trim() : game.path.trim();
    final bool ok = await _processTracker.launchAndTrack(
      gameId: game.id,
      exePath: path,
      workingDirectory: workDir,
    );
    if (!ok) {
      setError('启动失败，请确认可执行文件是否有效');
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
