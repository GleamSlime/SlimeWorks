import 'package:get_it/get_it.dart';

import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';

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

  isInitialized = true;
}
