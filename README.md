# `史莱姆工坊` SlimeWorks

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows|macOS|Linux|iOS|Android-blue?style=flat-square" alt="多平台支持">
  <img src="https://img.shields.io/badge/Status-开发中-yellow?style=flat-square" alt="开发状态">
  <img src="https://img.shields.io/badge/Version-v0.1.0_preview-orange?style=flat-square" alt="版本">
  <p align="center">
    <strong>✨ 工坊 ✨</strong>
  </p>
</p>

## 开发

- rustc 1.92.0 (ded5c06cf 2025-12-08)
- Flutter version 3.41.0-0.0.pre
- Dart version 3.11.0

- MacOS 26.2 25C56 darwin-arm64

## 约束

### 状态管理

- UI/页面状态 使用GetX
- 业务逻辑Service、Rust FFI桥接层（全局单例）、配置、数据库 使用GetIt

### 路由管理

- 使用 TypedGoRoute 类型安全路由 注册和管理

## 打包

### MacOS

```shell
flutter build macos --release
```

### IOS

```shell
flutter build ipa
cargo build --target aarch64-apple-ios-sim

open build/ios/archive/Runner.xcarchive
```
IOS打包：flutter build ipa --release --tree-shake-icons --obfuscate --split-debug-info=./symbols --dart-define=APP_ENV=production
IOS发蒲公英：python3 ./scripts/publish_ios.py --use-xcodebuild

### Android

```shell
cargo build --target aarch64-linux-android
```
安卓发布：python3 ./scripts/publish.py -desc="增加应用稳定性" 

### 可用指令

```shell
# 生成FRB
$ flutter_rust_bridge_codegen generate
 
# rust开发阶段：监听rs并启动ui，修改rs时杀死进程重启
$ cd rust && cargo watch -s "cargo build && flutter run -d macos"

# FlutterGen
$ flutter pub run build_runner build
$ flutter pub run build_runner watch
$ flutter pub run build_runner clean && flutter pub run build_runner build --delete-conflicting-outputs # 清理缓存并生成

# 序列化
$ flutter packages pub run build_runner build --delete-conflicting-outputs
```

## 自动化测试

### Flutter 单元测试

```shell
# 运行全部 Flutter 单元测试
flutter test

# 运行指定测试文件
flutter test test/smart_folder_test.dart
flutter test test/dashboard_test.dart

# 运行集成测试（需要连接设备或模拟器）
flutter test integration_test/simple_test.dart

# 生成覆盖率报告（需 lcov）
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

**测试文件说明：**

| 文件 | 覆盖范围 | 用例数 |
|------|----------|--------|
| `test/smart_folder_test.dart` | `SmartFolder` 序列化/反序列化、`copyWith`、`matchesFileNames`、枚举标签、迁移兼容性 | 21 |
| `test/dashboard_test.dart` | 媒体类型识别逻辑、速度格式化、历史缓冲区边界 | 13 |

### Rust 单元测试

```shell
# 运行 media_collection crate 全部测试
cd rust/media_collection && cargo test

# 运行 lan_transfer crate 全部测试
cd rust/lan_transfer && cargo test

# 运行所有 Rust crate 测试（推荐 CI 使用）
cd rust && cargo test --workspace

# 运行并显示详细输出
cd rust && cargo test --workspace -- --nocapture

# 仅运行某个测试函数（支持模糊匹配）
cd rust/media_collection && cargo test default_title
```

**测试文件说明：**

| 文件 | 覆盖范围 | 用例数 |
|------|----------|--------|
| `rust/media_collection/src/types.rs` | `MediaKind` 扩展名映射、大小写不敏感、serde 往返 | 7 |
| `rust/media_collection/src/scanner.rs` | 文件识别、隐藏路径过滤、目录扫描、媒体项收集 | 13 |
| `rust/media_collection/src/api.rs` | `default_collection_title`、`pick_cover_path`、`normalize_folder_path` 边界 | 8 |
| `rust/lan_transfer/src/types.rs` | `DeviceInfo`/`TransferType`/`TransferStatus` serde 往返 | 6 |

### CI 一键执行

```shell
# Flutter + Rust 全量测试（在项目根目录执行）
flutter test && cd rust && cargo test --workspace
```

## 发布

### 一键发布到蒲公英（Android）

```shell
# 默认构建并上传 Android APK
python3 auto.py -desc="1. 新增xxx功能\n2. 修复xxx问题"
```

### 一键发布到蒲公英（iOS）

使用 `publish_ios.py` 脚本，**首次使用前须填写脚本顶部的四个配置项**：

```
PGYER_USER_KEY  — 蒲公英 User Key（https://www.pgyer.com/account/api）
PGYER_API_KEY   — 蒲公英 API Key
TEAM_ID         — Apple Developer Team ID（留空则自动签名）
BUNDLE_ID       — Bundle Identifier（留空则使用项目默认值）
```

```shell
# 构建并上传（flutter build ipa，失败自动切换到 xcodebuild）
python3 publish_ios.py -desc="1. 新功能\n2. Bug 修复"

# 仅上传已有 IPA，不重新构建
python3 publish_ios.py --ipa-only -desc="热修复"

# 强制使用 xcodebuild archive 流程
python3 publish_ios.py --use-xcodebuild --team-id XXXXXXXXXX -desc="正式版"

# 仅构建不上传
python3 publish_ios.py --build-only

# 自定义 IPA 路径上传
python3 publish_ios.py --ipa-only --ipa-path build/ios/ipa/MyApp.ipa

# 打包 IPA 并使用 XCode 编译
python3 ./scripts/publish_ios.py --use-xcodebuild 
```

> 注意：iOS 构建需要 Mac 环境、有效开发者证书，且证书须信任当前机器。  
> Team ID 可在 [Apple Developer > Membership](https://developer.apple.com/account/) 页面查看。

