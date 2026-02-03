import 'package:get_it/get_it.dart';

import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';

final getIt = GetIt.instance;

bool isInitialized = false;

void getItInit() {
  if (isInitialized) {
    return;
  }

  getIt.registerLazySingleton<DesktopScreenProvider>(() => DesktopScreenProviderImpl());

  isInitialized = true;
}
