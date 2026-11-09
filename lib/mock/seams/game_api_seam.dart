import 'package:slime_works/mock/data/game_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/game_library.dart' as rust;

MockGameData get _m => MockGameData.instance;

void gameLibraryInit({required String dbPath}) {
  if (MockMode.enabled) return;
  rust.gameLibraryInit(dbPath: dbPath);
}

bool gameLibraryIsReady() {
  if (MockMode.enabled) return true;
  return rust.gameLibraryIsReady();
}

void gameLibraryClose() {
  if (MockMode.enabled) return;
  rust.gameLibraryClose();
}

Future<String> gameLibraryGetGamesJson() async {
  if (MockMode.enabled) return _m.getGamesJson();
  return rust.gameLibraryGetGamesJson();
}

Future<String> gameLibraryGetGameByIdJson({required String gameId}) async {
  if (MockMode.enabled) return _m.getGameByIdJson(gameId);
  return rust.gameLibraryGetGameByIdJson(gameId: gameId);
}

Future<String> gameLibraryAddGameJson({required String gameJson}) async {
  if (MockMode.enabled) return _m.addGameJson(gameJson);
  return rust.gameLibraryAddGameJson(gameJson: gameJson);
}

Future<void> gameLibraryUpdateGameJson({required String gameJson}) async {
  if (MockMode.enabled) {
    _m.updateGameJson(gameJson);
    return;
  }
  await rust.gameLibraryUpdateGameJson(gameJson: gameJson);
}

Future<void> gameLibraryDeleteGame({required String gameId}) async {
  if (MockMode.enabled) {
    _m.deleteGame(gameId);
    return;
  }
  await rust.gameLibraryDeleteGame(gameId: gameId);
}

Future<String> gameLibraryGetCategoriesJson() async {
  if (MockMode.enabled) return _m.getCategoriesJson();
  return rust.gameLibraryGetCategoriesJson();
}

Future<String> gameLibraryUpsertCategoryJson({
  required String categoryJson,
}) async {
  if (MockMode.enabled) return _m.upsertCategoryJson(categoryJson);
  return rust.gameLibraryUpsertCategoryJson(categoryJson: categoryJson);
}

Future<void> gameLibraryDeleteCategory({required String categoryId}) async {
  if (MockMode.enabled) {
    _m.deleteCategory(categoryId);
    return;
  }
  await rust.gameLibraryDeleteCategory(categoryId: categoryId);
}

Future<void> gameLibraryAddGameToCategory({
  required String gameId,
  required String categoryId,
}) async {
  if (MockMode.enabled) {
    _m.addGameToCategory(gameId, categoryId);
    return;
  }
  await rust.gameLibraryAddGameToCategory(
    gameId: gameId,
    categoryId: categoryId,
  );
}

Future<void> gameLibraryRemoveGameFromCategory({
  required String gameId,
  required String categoryId,
}) async {
  if (MockMode.enabled) {
    _m.removeGameFromCategory(gameId, categoryId);
    return;
  }
  await rust.gameLibraryRemoveGameFromCategory(
    gameId: gameId,
    categoryId: categoryId,
  );
}

Future<List<String>> gameLibraryGetGameCategoryIds({
  required String gameId,
}) async {
  if (MockMode.enabled) return _m.categoryIdsOf(gameId);
  return rust.gameLibraryGetGameCategoryIds(gameId: gameId);
}

Future<void> gameLibraryToggleFavorite({
  required String gameId,
  required bool favorite,
}) async {
  if (MockMode.enabled) {
    _m.toggleFavorite(gameId, favorite);
    return;
  }
  await rust.gameLibraryToggleFavorite(gameId: gameId, favorite: favorite);
}

Future<bool> gameLibraryIsFavorite({required String gameId}) async {
  if (MockMode.enabled) return _m.isFavorite(gameId);
  return rust.gameLibraryIsFavorite(gameId: gameId);
}

Future<List<String>> gameLibraryGetFavoriteIds() async {
  if (MockMode.enabled) return _m.favouriteIds();
  return rust.gameLibraryGetFavoriteIds();
}

Future<String> gameLibraryGetGamesByCategoryJson({
  required String categoryId,
}) async {
  if (MockMode.enabled) return _m.getGamesByCategoryJson(categoryId);
  return rust.gameLibraryGetGamesByCategoryJson(categoryId: categoryId);
}

Future<void> gameLibraryAddPlaySessionJson({
  required String sessionJson,
}) async {
  if (MockMode.enabled) {
    _m.addSession(sessionJson);
    return;
  }
  await rust.gameLibraryAddPlaySessionJson(sessionJson: sessionJson);
}

Future<String> gameLibraryGetPlaySessionsJson({
  required String gameId,
}) async {
  if (MockMode.enabled) return _m.getSessionsJson(gameId);
  return rust.gameLibraryGetPlaySessionsJson(gameId: gameId);
}

Future<void> gameLibraryUpsertProgressJson({
  required String progressJson,
}) async {
  if (MockMode.enabled) {
    _m.upsertProgress(progressJson);
    return;
  }
  await rust.gameLibraryUpsertProgressJson(progressJson: progressJson);
}

Future<String> gameLibraryGetProgressJson({required String gameId}) async {
  if (MockMode.enabled) return _m.getProgressJson(gameId);
  return rust.gameLibraryGetProgressJson(gameId: gameId);
}

Future<String> gameLibraryGetStatsJson({
  required int startTsSec,
  required int endTsSec,
}) async {
  if (MockMode.enabled) return _m.getStatsJson(startTsSec, endTsSec);
  return rust.gameLibraryGetStatsJson(
    startTsSec: startTsSec,
    endTsSec: endTsSec,
  );
}

Future<String> gameLibraryGetHomePageDataJson() async {
  if (MockMode.enabled) return _m.getHomePageDataJson();
  return rust.gameLibraryGetHomePageDataJson();
}

Future<int> gameLibraryLaunchGame({
  required String exePath,
  required String workingDir,
  required bool useOpen,
}) async {
  if (MockMode.enabled) return 0;
  return rust.gameLibraryLaunchGame(
    exePath: exePath,
    workingDir: workingDir,
    useOpen: useOpen,
  );
}

String gameLibraryDeriveGameName({required String path}) {
  if (MockMode.enabled) return _m.deriveName(path);
  return rust.gameLibraryDeriveGameName(path: path);
}

Future<String> gameLibraryScanDirectoryJson({
  required List<String> paths,
}) async {
  if (MockMode.enabled) return _m.scanDirectoryJson(paths);
  return rust.gameLibraryScanDirectoryJson(paths: paths);
}

Future<List<String>> gameLibraryCheckPathsExist({
  required List<String> paths,
}) async {
  if (MockMode.enabled) return List<String>.of(paths);
  return rust.gameLibraryCheckPathsExist(paths: paths);
}

Future<String> gameLibraryGetSettingsJson() async {
  if (MockMode.enabled) return _m.getSettingsJson();
  return rust.gameLibraryGetSettingsJson();
}

Future<void> gameLibrarySaveSettingsJson({
  required String settingsJson,
}) async {
  if (MockMode.enabled) {
    _m.saveSettingsJson(settingsJson);
    return;
  }
  await rust.gameLibrarySaveSettingsJson(settingsJson: settingsJson);
}

Future<String> gameLibraryFetchMoegirl({required String gameName}) async {
  if (MockMode.enabled) return '{"name":"$gameName","summary":"演示条目"}';
  return rust.gameLibraryFetchMoegirl(gameName: gameName);
}

Future<String> gameLibrarySearch2DfanSubject({required String gameName}) async {
  if (MockMode.enabled) return '{"subjects":[]}';
  return rust.gameLibrarySearch2DfanSubject(gameName: gameName);
}

Future<String> gameLibraryFetch2DfanDownloadPath({
  required String subjectPath,
}) async {
  if (MockMode.enabled) return '{"paths":[]}';
  return rust.gameLibraryFetch2DfanDownloadPath(subjectPath: subjectPath);
}

Future<String> gameLibraryFetch2DfanDownloadInfo({
  required String downloadPath,
}) async {
  if (MockMode.enabled) return '{"files":[]}';
  return rust.gameLibraryFetch2DfanDownloadInfo(downloadPath: downloadPath);
}

Future<void> gameLibraryDownloadFile({
  required String url,
  required String savePath,
}) async {
  if (MockMode.enabled) return;
  await rust.gameLibraryDownloadFile(url: url, savePath: savePath);
}
