# 开发环境与构建姿势（本机）

> 本文件记录随机器/SDK 版本变化的环境事实，**按需读取**，不常驻注入上下文。
> 最近核实：2026-11-13。

---

## SDK 布局与选择

- 本机多套 SDK：`~/development/flutter`（官方 git 检出，旧版 Dart 3.13.4，**PATH 默认的 `dart`/`flutter` 指它**）与 `~/fvm/versions/`（fvm 管理，含 3.41.5 / 3.50.0）。
- **项目当前解析到哪个 SDK，唯一权威来源是 `.dart_tool/version`**（谁最后跑 pub get 就写谁的版本，`package_config.json` 同步跟着换）。`.fvm/` 配置与 `flutter_sdk` 软链已对齐 3.50.0（供 `.mcp.json` 取项目内 dart），但仍非权威来源——升级后先现读 `.dart_tool/version`。
- 命令必须用与 `.dart_tool/version` 一致的 SDK 二进制。混用时 framework 源码与引擎 platform dill 分属两套 SDK，报 `HitTestResponse not found` / `displayCornerRadii` 一类类型错误。
- CI 钉的版本见 `.github/workflows/release.yml` 的 `FLUTTER_VERSION`。
- Flutter 3.50.0 = Dart 3.14.0（2026-11-11 发布）。

## 命令姿势

Bash 工具不加载 `.zshrc`，环境变量要显式补：

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
  LIBCLANG_PATH="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"
```

- `flutter test` 一律加 `--no-pub`；任何不带 `--no-pub` 的 flutter 命令都会按当前 `PUB_HOSTED_URL` 重写 `pubspec.lock`。`pubspec.yaml` 未改时 HEAD 那份 lock 就是对的，`git checkout -- pubspec.lock` 可回退。
- 缺镜像 env 时 `flutter build` / `precache` **不报错，静默卡在下载引擎产物**，出包命令同样要带两个镜像变量。
- cargo 需要 `LIBCLANG_PATH`（bindgen），否则 `Unable to find libclang`。
- `pod install` 需要 UTF-8 locale，否则崩在 `Unicode Normalization`，且会被 flutter 静默吞掉。
- 海外下载慢时可走用户代理：`export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897`。

## Xcode 与 macOS 打包

- 本机已装完整 **Xcode 27.0（27A266a）**，`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer` → macOS 打包本机可验（旧文档「本机无 Xcode.app、打包不可验证」的说法已作废）。
- 打包门：`fastforge package --platform macos --target dmg`；`PATH` 补 `~/.pub-cache/bin` 与 flutter bin。
- **SDK 升级后全局 fastforge 会失效**（报 cannot resolve to the same set of dependencies），先 `dart pub global activate fastforge` 重新激活再跑。
- **`FLUTTER_SWIFT_PACKAGE_MANAGER=false`**：iOS/macOS 钉死 CocoaPods 路线（部分插件无 SPM 支持，iOS 工程不做 SPM 迁移）。Flutter 3.50 起关闭 SPM 每次命令会告警；CocoaPods Trunk 2026-12 进入只读，SPM 迁移是后续专项。
- Windows 打包只能在 Windows 上做；Linux/Android/iOS 同理。
- 后台跑打包别信完成通知的 exit 0：grep 日志里自己埋的退出标记，并核对 `dist/` 真出了新包。
- 重跑打包前先把 `dist/<版本>/` 里的旧 DMG 挪走：appdmg 见目标文件已存在直接报 `Target already exists`，前面整个 flutter build 白跑。
- **cargo/make 0% CPU 挂起时查 sccache**：构建中途冷启动的 sccache 守护进程会继承 make/cargo 的 jobserver 管道并吞掉令牌——make 阻塞在 `read`（0% CPU、无子进程），cargo 停在 `exec_with_streaming/read2/poll` 等管道 EOF。实证 make 阻塞的管道地址与 sccache 持有的完全一致，sccache 退出后构建立即自愈。macOS 默认 universal 包，cargokit 先后跑 arm64/x86_64 两遍 cargo，whisper.cpp 的 cmake/make 阶段两遍都可能挂。
- **根治 sccache 挂起**：普通 `sccache --start-server` 预热不够——服务器默认空闲 600s 退出，构建间隙退出后又会中途冷启动。出包前用 `SCCACHE_IDLE_TIMEOUT=0 sccache --start-server`（永不空闲退出，且从干净 shell 启动不带 jobserver fd）；已挂起时杀掉该 sccache 进程即自愈，再按此式重启。
- fastforge 启动的版本检查用裸 Dio 直连 `PUB_HOSTED_URL`（**不走 https_proxy**），网络抖动时 `HandshakeException` 直接退出、打包根本没开始；出包命令加 `--no-version-check` 跳过。

## macOS 签名身份（决定更新后要不要重授权限）

- 仓库必须配置 `MAC_SIGN_IDENTITY_P12` / `MAC_SIGN_IDENTITY_PASSWORD` / `MAC_SIGN_IDENTITY_NAME` 三项 Secrets，否则 CI 回退 ad-hoc 签名：CDHash 每次构建都不同 → macOS TCC（完全磁盘访问、外置卷等）把每次更新后的 App 当成另一个程序，权限清零，用户每次自动更新后都要重新授权。
- 自签证书身份跨版本不变，授权一次后续更新不再掉权限。
- 生成（一次性）：`bash scripts/make_mac_signing_cert.sh`，产出 p12 的 base64 单行、导出口令、证书通用名分别填进上述三项 Secrets。
- **证书一旦投入使用不要重新生成**——换证书等于换身份，用户机器上的 TCC 授权全部重来。CI 未配置 Secrets 时以 `::error` 报出。

## 构建命令

```bash
flutter_rust_bridge_codegen generate          # 生成 FRB 绑定（codegen 版本须与 pubspec 的 flutter_rust_bridge 一致）
flutter pub run build_runner build             # 生成资源引用/JSON序列化
dart run tool/stroke_icons/generate.dart       # 生成描边图标常量（*.g.dart 不入库，CI 同样先跑这步）
flutter run -d macos                           # 开发运行
flutter build macos --release                  # 发布构建
cd rust && cargo test --workspace              # Rust 测试
flutter test                                   # Flutter 测试
```

- FRB codegen 不在全局激活列表时用 `dart pub global activate flutter_rust_bridge_codegen <与 pubspec 一致的版本>`。
- Rust 格式化只碰自己改过的文件；主 crate `rust/src` 在 HEAD 上不是 fmt-clean，不要全仓 `cargo fmt`。

## golden 基线与 worktree 对照

- 全量 `flutter test` 存在一批因 Flutter 版本/字体差异失败的 golden 用例，属既有环境问题，不是回归。
- 判定方法：`git worktree add /tmp/sw_baseline <基线commit>`，两边用**同一 SDK** 跑全量，逐条对比失败集合，head 侧不得新增。基线失败数量随 SDK 漂移，**不要硬编码数字**。
- 干净 worktree 缺三样，补上才跑得起来：`cp .env`（pubspec 当资源声明）、`dart run tool/stroke_icons/generate.dart`、从主目录 `cp lib/core/routes/app_routes.g.dart`。
- golden 逐帧比对看差值数字：改动前后差值完全相同就是环境漂移而不是回归。

## AI 开发工具（MCP）

- 仓库根 `.mcp.json` 声明官方 Dart/Flutter MCP Server：`dart mcp-server` 是统一入口，覆盖 analyze_files / run_tests / hot_reload / hot_restart / pub 等工具，自动从 Dart SDK 向上定位 Flutter SDK。
- 命令里的 `dart` 必须解析到与项目 `.dart_tool/version` 一致的 SDK（PATH/fvm），否则分析与引擎混用。
- `.mcp.json` 用项目相对路径 `.fvm/flutter_sdk/bin/dart`（软链跟随项目 SDK，跨机器可移植，不依赖 PATH 上的旧 dart）。Qoder App 的 `manage_app_mcp` 注册目前拒绝自定义 stdio 配置（MCP_AGENT_INPUT_INVALID），`.mcp.json` 即 MCP 客户端的可移植入口。
- Flutter 3.50 起官方提供 Agent Plugins（Agent Skills、MCP 配置、hot reload 自动化规则）；本仓库接入 MCP 部分。