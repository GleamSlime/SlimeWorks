import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibraryDetailViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final Rxn<GameItem> game = Rxn<GameItem>();
  final RxList<PlaySession> sessions = <PlaySession>[].obs;
  final Rxn<GameProgress> progress = Rxn<GameProgress>();
  final RxList<GameCategory> categories = <GameCategory>[].obs;
  final RxSet<String> selectedCategoryIds = <String>{}.obs;

  Future<void> load(String gameId) async {
    await _service.init();
    game.value = _service.getGameById(gameId);
    sessions.assignAll(_service.getPlaySessionsByGameId(gameId));
    progress.value = _service.getProgressByGameId(gameId);
    categories.assignAll(_service.categories);
    selectedCategoryIds
      ..clear()
      ..addAll(_service.getCategoryIdsByGameId(gameId));
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
    final GameItem? current = game.value;
    if (current == null) {
      return false;
    }
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
}
