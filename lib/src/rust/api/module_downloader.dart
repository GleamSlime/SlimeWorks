// ignore_for_file: invalid_use_of_internal_member, unused_import, unnecessary_import

import 'package:slime_works/src/rust/lib.dart';

import '../frb_generated.dart';
import 'ffmpeg.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

abstract class ModuleDownloader implements RustOpaqueInterface {
  /// 下载并安装模块
  Future<PathBuf> downloadModule({required ModuleConfig config});

  /// 获取可执行文件路径
  Future<PathBuf> getExecutablePath({
    required String moduleName,
    required String executableName,
  });

  /// 获取模块安装路径
  Future<PathBuf> getModulePath({required String moduleName});

  /// 获取模块版本（通过执行 --version 命令）
  Future<String> getModuleVersion({
    required String moduleName,
    required String executableName,
  });

  /// 检查模块是否已安装
  Future<bool> isModuleInstalled({
    required String moduleName,
    required String executableName,
  });

  /// 创建模块下载器
  static Future<ModuleDownloader> newInstance({
    required PathBuf installDir,
  }) async {
    throw UnimplementedError(
      'ModuleDownloader.newInstance is not available. Regenerate FRB bindings after exposing the constructor in Rust.',
    );
  }

  /// 删除模块
  Future<void> removeModule({required String moduleName});
}

/// 模块下载配置
class ModuleConfig {
  final String name;
  final String windowsUrl;
  final String macosUrl;
  final String executableName;

  const ModuleConfig({
    required this.name,
    required this.windowsUrl,
    required this.macosUrl,
    required this.executableName,
  });

  @override
  int get hashCode =>
      name.hashCode ^
      windowsUrl.hashCode ^
      macosUrl.hashCode ^
      executableName.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleConfig &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          windowsUrl == other.windowsUrl &&
          macosUrl == other.macosUrl &&
          executableName == other.executableName;
}
