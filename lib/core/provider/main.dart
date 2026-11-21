import 'package:get_it/get_it.dart';

import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/services/video_waveform_service.dart';
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
import 'package:slime_works/core/services/ncm_decrypt_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/power_stats_service.dart';
import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/services/asr/asr_service.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/services/asr/subtitle_translate_service.dart';
import 'package:slime_works/core/services/transcription_task_queue.dart';

final getIt = GetIt.instance;

/// 依赖注入是否已注册过（`getItInit` 的幂等守卫）。
///
/// ★ 这个名字必须区别于 `BaseViewModel.isInitialized`！
/// 之前它叫顶层变量 `isInitialized`，而 ViewModel 文件普遍
/// `import 'package:slime_works/core/provider/main.dart'`。Dart 的作用域规则下，
/// 子类方法体里裸写 `isInitialized` 会解析到这个**顶层变量**而不是基类 getter，
/// 于是：
///   - `NovelLibraryViewModel.onInitAsync()` 打开那个 `if (isInitialized) return;`
///     永远是 true（main 里 getItInit 后即置 true）→ **初始化整段从不执行**
///     → `refreshRemoteNovels()` 一次都没跑 → 远程书库永远空；
///   - 本机模式靠别处直接读 FFI 照样有数据，把这个坑完全盖住；
///   - `MediaLibraryViewModel` 同款写法，也受影响。
/// 这是个不报错、只静默跑错分支的隐式遮蔽，改名是最省事的根治办法。
bool diRegistryInitialized = false;

void getItInit() {
  if (diRegistryInitialized) {
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

  // 视频预览振幅进度条的波形服务：本地交给本机 Rust，远程交给节点算
  // （客户端只取 JSON，移动端因此也能用），故需注入节点服务
  getIt.registerLazySingleton<VideoWaveformService>(
    () => VideoWaveformService(nodeService: getIt<NodeSettingsService>()),
  );

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

  // NCM 解密服务
  getIt.registerLazySingleton<NcmDecryptService>(() => NcmDecryptService());

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

  // 电力定时统计服务
  getIt.registerLazySingleton<PowerStatsService>(() => PowerStatsService());

  // 流水账服务（手工记账 + 邮件账单自动入账）
  getIt.registerLazySingleton<LedgerService>(() => LedgerService());

  // 应用更新服务
  getIt.registerLazySingleton<AppUpdateService>(() => AppUpdateService());

  // 语音识别任务队列
  getIt.registerLazySingleton<TranscriptionTaskQueue>(() => TranscriptionTaskQueue());

  // 语音识别（字幕）：内网大模型列表 + 本地 SenseVoice 引擎部署
  getIt.registerLazySingleton<AsrService>(() => AsrService());
  // 字幕翻译：内网 NMT（LibreTranslate 兼容）服务，把日韩文字幕转中文供审核
  getIt.registerLazySingleton<SubtitleTranslateService>(() => SubtitleTranslateService());
  getIt.registerLazySingleton<AsrSettingsService>(
    () => AsrSettingsService(getIt<AsrService>(), getIt<SubtitleTranslateService>()),
  );

  diRegistryInitialized = true;
}
