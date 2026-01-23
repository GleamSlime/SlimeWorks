# `史莱姆工坊` SlimeWorks

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows|macOS|Linux|iOS|Android-blue?style=flat-square" alt="多平台支持">
  <img src="https://img.shields.io/badge/Status-开发中-yellow?style=flat-square" alt="开发状态">
  <img src="https://img.shields.io/badge/Version-v0.1.0_preview-orange?style=flat-square" alt="版本">
  <p align="center"> 
    <img src="https://raw.githubusercontent.com/shi-lai-mu/SlimeWorks/refs/heads/main/assets/logo.svg?token=GHSAT0AAAAAADTQ2T3TNXRA2L5NMYJFSU442LS3VBA" alt="icon">
    <strong>✨ 工坊 ✨</strong>
  </p>
</p>

## 开发

## 打包

### MacOS

```shell
flutter build macos --release
```

### 可用指令

```shell
# 生成FRB
$ flutter_rust_bridge_codegen generate
 
# rust开发阶段：监听rs并启动ui，修改rs时杀死进程重启
$ cd rust && cargo watch -s "cargo build && flutter run -d macos"
```
