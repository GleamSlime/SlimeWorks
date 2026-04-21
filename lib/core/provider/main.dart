import 'package:get_it/get_it.dart';

import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/core/services/game_library_metadata_api.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/game_library_service.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/services/picacg_download_service.dart';

final getIt = GetIt.instance;

bool isInitialized = false;

void getItInit() {
  if (isInitialized) {
    return;
  }

  getIt.registerLazySingleton<DesktopScreenProvider>(() => DesktopScreenProviderImpl());

  // Ollama 服务
  getIt.registerLazySingleton<OllamaService>(() => OllamaService());
  getIt.registerLazySingleton<OllamaSettingsService>(
    () => OllamaSettingsService(getIt.get<OllamaService>()),
  );

  // 局域网传输服务
  getIt.registerLazySingleton<LanTransferService>(() => LanTransferService());

  // 节点设置服务
  getIt.registerLazySingleton<NodeSettingsService>(() => NodeSettingsService());

  // 媒体偏好设置服务
  getIt.registerLazySingleton<MediaPrefsService>(() => MediaPrefsService());

  // PicACG 漫画平台服务
  getIt.registerLazySingleton<PicAcgService>(() => PicAcgService());

  // PicACG 下载服务
  getIt.registerLazySingleton<PicAcgDownloadService>(() => PicAcgDownloadService());

  // 游戏库服务
  getIt.registerLazySingleton<GameLibraryMetadataApi>(() => GameLibraryMetadataApi());
  getIt.registerLazySingleton<GameLibraryService>(
    () => GameLibraryService(metadataApi: getIt<GameLibraryMetadataApi>()),
  );

  isInitialized = true;
}
