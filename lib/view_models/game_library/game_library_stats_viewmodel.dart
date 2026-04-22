import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryStatsViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final Rx<DateTime> startDate = DateTime.now().subtract(const Duration(days: 29)).obs;
  final Rx<DateTime> endDate = DateTime.now().obs;
  final Rxn<GameStatsData> statsData = Rxn<GameStatsData>();

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    await refresh();
  }

  @override
  Future<void> refresh() async {
    statsData.value = await _service.getStats(start: startDate.value, end: endDate.value);
  }

  Future<void> setRange(DateTime start, DateTime end) async {
    startDate.value = start;
    endDate.value = end;
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
