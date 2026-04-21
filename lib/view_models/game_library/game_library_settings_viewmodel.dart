import 'package:get/get.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';

class GameLibrarySettingsViewModel extends BaseViewModel {
  final GameLibraryService _service = getIt<GameLibraryService>();

  final Rxn<GameLibrarySettings> settings = Rxn<GameLibrarySettings>();

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await _service.init();
    settings.value = _service.settings;
  }

  Future<void> saveSettings(GameLibrarySettings next) async {
    await _service.updateSettings(next);
    settings.value = next;
  }

  String exportBackupJson() {
    return _service.exportBackupJson();
  }

  Future<void> importBackupJson(String jsonText) async {
    await _service.importBackupJson(jsonText);
    settings.value = _service.settings;
  }
}
