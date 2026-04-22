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
    settings.value = await _service.getSettings();
  }

  Future<void> saveSettings(GameLibrarySettings next) async {
    await _service.updateSettings(next);
    settings.value = next;
  }

  /// 导出备份（暂未实现，数据已迁移至 SQLite，可通过复制数据库文件备份）
  String exportBackupJson() {
    return '{"note": "请直接复制数据库文件进行备份"}';
  }

  /// 导入备份（暂未实现）
  Future<void> importBackupJson(String jsonText) async {
    // TODO: 实现从 JSON 导入数据到 SQLite 的迁移逻辑
  }
}
