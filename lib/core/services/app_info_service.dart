import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  AppInfoService._();

  static String appName = '史莱姆工坊';
  static String version = '1.0.0';
  static String buildNumber = '1';
  static String versionWithBuild = 'v1.0.0+1';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      appName = info.appName.isNotEmpty ? info.appName : '史莱姆工坊';
      version = info.version;
      buildNumber = info.buildNumber;
      versionWithBuild = 'v$version+$buildNumber';
    } catch (_) {}
    _initialized = true;
  }
}
