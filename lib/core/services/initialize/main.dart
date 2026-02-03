import 'package:slime_works/core/services/initialize/ffmpeg.dart';

class RustModules {
  const RustModules();

  static Future<void> initializeLazy() async {
    await RustFFmpeg.initialize();
  }
}
