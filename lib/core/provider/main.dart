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
import 'package:slime_works/core/services/game_process_tracker.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/services/manga_download_service.dart';
import 'package:slime_works/core/services/extract_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';

final getIt = GetIt.instance;

bool isInitialized = false;

void getItInit() {
  if (isInitialized) {
    return;
  }

  getIt.registerLazySingleton<DesktopScreenProvider>(
    () => DesktopScreenProviderImpl(),
  );

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

  // Manga 漫画平台服务
  getIt.registerLazySingleton<MangaService>(() => MangaService());

  // Manga 下载服务
  getIt.registerLazySingleton<MangaDownloadService>(() => MangaDownloadService());

  // 游戏库服务
  getIt.registerLazySingleton<GameLibraryMetadataApi>(
    () => GameLibraryMetadataApi(),
  );
  getIt.registerLazySingleton<GameLibraryService>(
    () => GameLibraryService(metadataApi: getIt<GameLibraryMetadataApi>()),
  );
  // 游戏进程追踪器（依赖 GameLibraryService，务必在其后注册）
  getIt.registerLazySingleton<GameProcessTracker>(
    () => GameProcessTracker(service: getIt<GameLibraryService>()),
  );

  // 解压服务
  getIt.registerLazySingleton<ExtractService>(() => ExtractService());

  // Sentry 设置服务
  getIt.registerLazySingleton<SentrySettingsService>(
    () => SentrySettingsService(),
  );

  // 系统资源监控服务
  getIt.registerLazySingleton<SystemMetricsService>(
    () => SystemMetricsService(),
  );

  // 阿里云DDNS服务
  getIt.registerLazySingleton<AliyunDdnsService>(() => AliyunDdnsService());

  // 应用更新服务
  getIt.registerLazySingleton<AppUpdateService>(() => AppUpdateService());

  isInitialized = true;
}
