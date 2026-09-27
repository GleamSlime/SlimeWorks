import 'package:package_info_plus/package_info_plus.dart';

import 'package:slime_works/core/build_info.dart';

class AppInfoService {
  AppInfoService._();

  static String appName = '史莱姆工坊';
  static String version = '1.0.0';
  static String buildNumber = '1';
  static String versionWithBuild = 'v1.0.0+1';

  /// CI 打包时间（UTC），仅 GitHub Actions 分发的构建非空
  static String buildTime = '';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      appName = info.appName.isNotEmpty ? info.appName : '史莱姆工坊';
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}
    // CI 注入的构建号优先：pubspec 里的 +N 是手动档，和 GitHub Release
    // tag（日期.commit短hash）对不上，关于页要显示用户实际装的那个版本
    if (CiBuildInfo.buildNumber.isNotEmpty) {
      buildNumber = CiBuildInfo.buildNumber;
      buildTime = CiBuildInfo.buildTime;
    }
    versionWithBuild = 'v$version+$buildNumber';
    _initialized = true;
  }
}
