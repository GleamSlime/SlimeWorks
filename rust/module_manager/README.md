# 模块管理系统

## 概述

这是一个完整的模块下载、安装、加载管理系统，支持：

1. ✅ 版本管理和锁定版本
2. ✅ 远程 JSON 配置
3. ✅ MD5 文件校验
4. ✅ 动态库和可执行文件
5. ✅ 模糊文件名匹配（兼容开发环境）
6. ✅ Flutter Rust Bridge API 暴露

## 目录结构

```
{install_dir}/
├── dll/                                    # 动态库目录
│   ├── capture_proxy_1-2-0-23.dll         # 动态库（可更新）
│   ├── libcapture_proxy_1-2-0-23_lock.dylib  # 锁定版本的动态库
│   └── capture_proxy.so                   # 开发环境文件（模糊匹配兼容）
└── bin/                                   # 可执行文件目录
    └── ffmpeg/                            # 按模块名分组
        ├── ffmpeg_6-0-1-5.exe
        └── ffmpeg_6-0-1-5_lock
```

## 文件命名规则

### 版本化文件名

格式：`{lib前缀}{module_name}_{version}{_lock后缀}.{扩展名}`

示例：
- Windows DLL: `capture_proxy_1-2-0-23.dll`
- macOS dylib: `libcapture_proxy_1-2-0-23.dylib`
- Linux so: `libcapture_proxy_1-2-0-23.so`
- 可执行文件: `ffmpeg_6-0-1-5.exe`

### 锁定版本

在文件名末尾添加 `_lock` 表示锁定版本，不会自动更新：

- `libcapture_proxy_1-2-0-23_lock.dylib`
- `ffmpeg_6-0-1-5_lock.exe`

### 版本格式转换

标准版本 `1.2.0+23` 会被转换为文件名版本 `1-2-0-23`

## JSON 配置格式

```json
{
  "modules": {
    "capture_proxy": {
      "latest_version": "1.2.0+23",
      "description": "Capture Proxy Dynamic Library",
      "module_type": "DynamicLibrary",
      "platforms": {
        "windows-x64": {
          "url": "https://example.com/capture_proxy_1.2.0_23_windows_x64.dll",
          "md5": "abc123...",
          "file_size": 1048576
        },
        "darwin-aarch64": {
          "url": "https://example.com/capture_proxy_1.2.0_23_darwin_aarch64.dylib",
          "md5": "def456...",
          "file_size": 1048576
        },
        "linux-x64": {
          "url": "https://example.com/capture_proxy_1.2.0_23_linux_x64.so",
          "md5": "ghi789...",
          "file_size": 1048576
        }
      }
    },
    "ffmpeg": {
      "latest_version": "6.0.1+5",
      "description": "FFmpeg Executable",
      "module_type": "Executable",
      "platforms": {
        "windows-x64": {
          "url": "https://example.com/ffmpeg_6.0.1_5_windows_x64.exe",
          "md5": "jkl012...",
          "file_size": 52428800
        }
      }
    }
  }
}
```

## Rust API 使用

### 1. 创建模块管理器

```rust
use crate::api::module_manager::{ModuleManager, ModuleLoader};
use std::path::PathBuf;

// 创建管理器
let install_dir = PathBuf::from("/path/to/modules");
let config_url = "https://example.com/modules.json".to_string();
let manager = ModuleManager::new(install_dir.clone(), config_url);

// 创建加载器
let loader = ModuleLoader::new(install_dir);
```

### 2. 安装模块

```rust
// 安装最新版本
manager.install_module("capture_proxy", None, false, true).await?;

// 安装指定版本
manager.install_module("capture_proxy", Some("1.2.0+23".to_string()), false, false).await?;

// 安装并锁定版本
manager.install_module("ffmpeg", Some("6.0.1+5".to_string()), true, true).await?;
```

### 3. 加载模块

```rust
// 加载动态库（支持模糊匹配）
loader.load_module("capture_proxy", None)?;

// 加载特定版本
loader.load_module("capture_proxy", Some("1.2.0+23".to_string()))?;

// 检查是否已加载
if loader.is_loaded("capture_proxy")? {
    println!("Module is loaded");
}

// 卸载模块
loader.unload_module("capture_proxy")?;

// 重新加载
loader.reload_module("capture_proxy", None)?;
```

### 4. 版本管理

```rust
// 列出已安装版本
let versions = manager.list_installed_versions("capture_proxy")?;
for version_info in versions {
    println!("{} - {} - locked: {}", 
        version_info.module_name,
        version_info.version,
        version_info.is_locked
    );
}

// 检查更新
if let Some(new_version) = manager.check_for_update("capture_proxy").await? {
    println!("New version available: {}", new_version);
}

// 卸载模块
manager.uninstall_module("capture_proxy", Some("1.2.0+23"))?;

// 重新安装
manager.reinstall_module("capture_proxy", None, false).await?;
```

### 5. 列出所有模块

```rust
let all_modules = manager.list_all_modules().await?;
for (name, config) in all_modules {
    println!("Module: {}", name);
    println!("  Latest: {}", config.latest_version);
    println!("  Type: {:?}", config.module_type);
}
```

## Flutter (Dart) API 使用

所有 API 都已通过 FRB 暴露，可在 Flutter 中使用：

### 1. 创建管理器

```dart
// 创建模块管理器
final manager = await createModuleManager(
  installDir: '/path/to/modules',
  configUrl: 'https://example.com/modules.json',
);

// 创建模块加载器
final loader = await createModuleLoader(
  installDir: '/path/to/modules',
);
```

### 2. 安装模块

```dart
// 安装最新版本并自动加载
await moduleInstall(
  manager: manager,
  moduleName: 'capture_proxy',
  version: null,  // null = 最新版本
  lockVersion: false,
  autoLoad: true,
);

// 安装指定版本并锁定
await moduleInstall(
  manager: manager,
  moduleName: 'ffmpeg',
  version: '6.0.1+5',
  lockVersion: true,
  autoLoad: false,
);
```

### 3. 加载模块

```dart
// 加载模块
await moduleLoad(
  loader: loader,
  moduleName: 'capture_proxy',
  version: null,  // null = 自动选择最新
);

// 检查是否已加载
final isLoaded = await moduleIsLoaded(
  loader: loader,
  moduleName: 'capture_proxy',
);

// 卸载模块
await moduleUnload(
  loader: loader,
  moduleName: 'capture_proxy',
);

// 列出已加载模块
final loadedModules = await moduleListLoaded(loader: loader);
for (final name in loadedModules) {
  print('Loaded: $name');
}
```

### 4. 版本管理

```dart
// 列出已安装版本
final versions = await moduleListVersions(
  manager: manager,
  moduleName: 'capture_proxy',
);

for (final version in versions) {
  print('${version.moduleName} - ${version.version}');
  print('  Locked: ${version.isLocked}');
  print('  Path: ${version.filePath}');
  print('  Size: ${version.fileSize} bytes');
}

// 检查更新
final newVersion = await moduleCheckUpdate(
  manager: manager,
  moduleName: 'capture_proxy',
);
if (newVersion != null) {
  print('New version available: $newVersion');
}

// 卸载
await moduleUninstall(
  manager: manager,
  moduleName: 'capture_proxy',
  version: '1.2.0+23',
);

// 重新安装
await moduleReinstall(
  manager: manager,
  moduleName: 'capture_proxy',
  version: null,
  lockVersion: false,
);
```

### 5. 列出所有可用模块

```dart
final allModules = await moduleListAll(manager: manager);
for (final entry in allModules.entries) {
  print('Module: ${entry.key}');
  print('  Latest: ${entry.value.latestVersion}');
  print('  Type: ${entry.value.moduleType}');
  print('  Description: ${entry.value.description}');
}
```

## 模糊文件匹配规则

加载模块时会按以下顺序尝试匹配文件名：

1. **精确版本匹配**: `{lib}module_name_{version}{_lock}.ext`
2. **任意版本匹配**: `{lib}module_name_*{_lock}.ext`（选择最新版本）
3. **开发环境匹配**: `{lib}module_name.ext`（无版本号）

示例：`load_module("capture_proxy", None)` 会尝试：
- macOS: `libcapture_proxy_*.dylib` → `libcapture_proxy.dylib`
- Windows: `capture_proxy_*.dll` → `capture_proxy.dll`
- Linux: `libcapture_proxy_*.so` → `libcapture_proxy.so`

这样可以兼容开发环境中没有版本号的文件。

## 注意事项

1. **锁定版本**: 带 `_lock` 后缀的模块不会被自动更新
2. **MD5 校验**: 下载后会自动验证文件完整性
3. **平台识别**: 自动根据当前平台选择正确的下载链接
4. **并发安全**: 所有操作都是线程安全的
5. **错误处理**: 所有操作都返回 Result，需要适当处理错误

## 平台支持

- ✅ Windows (x64, x86)
- ✅ macOS (x64, aarch64)
- ✅ Linux (x64, aarch64)
- ✅ iOS (aarch64)
- ✅ Android (arm64-v8a, armeabi-v7a, x86_64)

## 迁移指南

如果你正在使用旧的 `module_api.rs`，请迁移到新的 API：

```dart
// 旧 API (已废弃)
await downloadModule(
  installDir: dir,
  moduleName: 'capture_proxy',
  moduleType: ModuleType.library,
  version: '1.2.0+23',
  windowsUrl: 'https://...',
  macosUrl: 'https://...',
  fileName: 'capture_proxy',
);

// 新 API (推荐)
final manager = await createModuleManager(
  installDir: dir,
  configUrl: 'https://example.com/modules.json',
);
await moduleInstall(
  manager: manager,
  moduleName: 'capture_proxy',
  version: '1.2.0+23',
  lockVersion: false,
  autoLoad: true,
);
```
