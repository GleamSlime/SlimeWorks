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

## 打包

### MacOS

```shell
flutter build macos --release
```

### IOS

```shell
flutter build ipa
cargo build --target aarch64-apple-ios-sim
```

### Android

```shell
cargo build --target aarch64-linux-android
```

### 可用指令

```shell
# 生成FRB
$ flutter_rust_bridge_codegen generate
 
# rust开发阶段：监听rs并启动ui，修改rs时杀死进程重启
$ cd rust && cargo watch -s "cargo build && flutter run -d macos"
```
