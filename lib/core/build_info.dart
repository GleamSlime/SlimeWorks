/// CI 打包信息：由 .github/workflows/release.yml 的"写入 CI 构建信息"步骤
/// 在打包前用 sed 替换下面两个常量，随二进制一起编进 App。
///
/// 本地开发构建这两个值保持空串，关于页回退显示 package_info_plus
/// 读到的 pubspec 构建号。
class CiBuildInfo {
  CiBuildInfo._();

  /// CI 构建号，格式 YYYYMMDD.commit短hash（与 GitHub Release tag 一致）
  static const String buildNumber = '';

  /// CI 打包时间（北京时间 UTC+8）
  static const String buildTime = '';
}
