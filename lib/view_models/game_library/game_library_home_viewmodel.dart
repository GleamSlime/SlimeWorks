import 'dart:io';

import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryHomeViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final Rxn<GameLibraryHomeData> homeData = Rxn<GameLibraryHomeData>();

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    await refresh();
  }

  @override
  Future<void> refresh() async {
    homeData.value = _service.getHomeData();
  }

  Future<void> launchGame(GameItem game) async {
    final String path = game.path.trim();
    if (path.isEmpty) {
      setError('未配置启动路径');
      return;
    }
    try {
      await Process.start(path, <String>[]);
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
