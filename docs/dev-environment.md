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
  **装了完整 Xcode 之后不要再设 `CXXFLAGS` / `CFLAGS`**：那套
  `-I.../CommandLineTools/SDKs/MacOSX.sdk/usr/include/c++/v1` 是「只有 CLT」时的变通，
  现在会让 CLT 与 Xcode 26 的 libc++ 混用，炸 `cstdint using_if_exists` /
  `unknown type name 'uint64_t'` 满屏 error。正确姿势：
  ```bash
  export LIBCLANG_PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib
  # CXXFLAGS / CFLAGS 都不设
  ```
- **镜像源 pub cache 有两个残缺包**（本机「macOS 打不出来」的另一半原因）：
  `~/.pub-cache/hosted/pub.flutter-io.cn/` 下
  `media_kit_video-2.0.1/macos/Headers/mpv/`（缺 4 个头）与
  `media_kit_libs_macos_video-1.1.4/macos/Frameworks/`（缺 18 个 mpv xcframework）
  相对 pub.dev 原版是空的。症状是 Swift 报 `cannot find type 'mpv_node_list' in scope`。
  修法：`rm -rf` 镜像那份 + `cp -R ~/.pub-cache/hosted/pub.dev/<同名>` 覆盖，diff 确认一致。
  ★ 别把 4 个头直接摊到 `Headers/` 顶层——会和 `Headers/mpv/` 重名，报
  `Multiple commands produce ... client.h`，必须保持原版 `Headers/mpv/*.h` 结构。
- `pod install` 需要 UTF-8 locale，否则崩在 `Unicode Normalization`，且会被 flutter 静默吞掉。
- **`flutter test -d macos` 每次都会重跑 pod install**：`macos/Pods/Manifest.lock`
  与 `Podfile.lock` 不同步时直接 `error: The sandbox is not in sync with the Podfile.lock`。
  所以**别随手 `git checkout -- macos/Podfile.lock`**（它会弄坏同步）；需要还原时
  先 `pod install` 补回 `Manifest.lock`。网络不通时 pod install 会失败
  （`CDN: trunk URL couldn't be downloaded`），出包/跑测一律走上面那条代理。
- 海外下载慢时可走用户代理：`export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897`。

## Xcode 与 macOS 打包

- 本机已装完整 **Xcode 26.3（17C529）**，`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer` → macOS 打包本机可验（旧文档「本机无 Xcode.app、打包不可验证」的说法已作废）。
- **本机版本天花板是 26.3**：macOS 15.6.1 上 Xcode 26.4+ / 27.x 全部要求 macOS 26.2+，装不上；App Store 只给最新版，同样装不了（必须走 developer.apple.com 手动下 xip）。Apple Silicon 单架构 xip 约 **2.1 GB**（不是老版本的 10GB+，别按体积误判下载不完整），校验 sha1 才对。
- iOS 模拟器 runtime 是独立包（`xcodebuild -downloadPlatform iOS`，约 8.4 GB），Xcode 本体装完仍为空，需单独拉。
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

## 全量模拟回归测试（`scripts/full_regression.sh`）

无头节点/远程模式的**行为回归**。与 `precommit_gate.sh` 分工不同：那个验「能不能编、
测试过不过」，这个验「用户在远程模式下点按钮，节点数据到底变没变」。

```bash
bash scripts/full_regression.sh                  # 核心 11 个小节，约 11s
bash scripts/full_regression.sh --with-app       # 追加真 macOS App 集成测试（+10min）
bash scripts/full_regression.sh --with-full-test # 追加全量 flutter test + 基线对照（+15min）
bash scripts/full_regression.sh --all            # 两个都加
bash scripts/full_regression.sh --only C,E,F     # 只跑指定小节
bash scripts/full_regression.sh --keep           # 保留临时目录便于排查
```

小节：A 环境自检 / B Rust 构建 / C 冷启动模块 / D 假成功契约 / E 条目 ID 稳定 /
F 幽灵体积 / G 重新扫描 / H 文件上传 / I 账本口令 / J Sentry 清空 / M 真实测试数据 /
K 真 App（可选）/ L 全量测试（可选）。

**关键设计**（都是踩过坑才这么写的，别随手改）：

1. **用全新空 `--data-dir` 起节点**。用热进程测，「模块未初始化」这类缺陷会被
   完全掩盖——上一轮就是这么漏掉阿里云/电力统计/Sentry 全部挂掉的。
2. **真实数据只读**。M 小节把 `$DATA_ROOT`（默认 `/Volumes/T22/测试数据`）里的
   素材**复制**到临时目录再导入，并断言源目录没被写入 `.SlimeWorks`。
3. **输出只有结论表**，细节进 `$TMPDIR/slime_works_regress/<时间戳>/` 的日志。
   排查时只读对应文件，别把整份日志贴进上下文。
4. **Sentry 走独立 HTTP 路由**（`/sentry/*`、`/api/*/store|envelope`），
   不经过 `dispatch_action`，所以惰性初始化兜底必须在路由分发前单独做一次——
   否则全新节点上 `/sentry/stats` 回「未初始化」，脚本的 C 小节会立刻抓到。
5. `--list` 只列小节；`--only` 支持逗号分隔多选。

**验证脚本本身有效**：把 `reuse_existing_item_ids` 的调用注释掉（复现条目 ID 抖动的
历史 bug），E 小节会报 `FAIL 删掉 1 条后其余条目 id 变了` 并打印删前/删后 id 与
「用快照 id 删除失败」——修复后恢复全绿。改动脚本后建议这样自证一次。

★ bash 3.2/5.x 通用坑：`"$VAR（"` 这种变量紧邻全角字符的写法会把多字节字符的
首字节并进变量名，报 `unbound variable`。脚本里一律写 `"${VAR}（"`。

## ★ `flutter test` 会拦截真实 HTTP（排查时最容易误判的坑）

**`flutter test`（只要调了 `TestWidgetsFlutterBinding.ensureInitialized()`）
会注入 HTTP mock，把所有真实网络请求返回 `400`，且响应体为空。**

症状极具迷惑性：
- 同一个节点，`curl` 打返回 200；
- 同一个 Dio 配置，在纯 `dart:io`（不加 Flutter binding）里返回 200；
- 唯独在带 binding 的测试里 400，而且**连 `ServerSocket` 都收不到请求**
  （因为根本没建立连接，Dio 拿到的是 mock 的伪造响应）。

所以任何「用 flutter test / integration_test 打真实节点」的验证，
都必须在 `setUpAll` 里清掉注入：

```dart
setUpAll(() => HttpOverrides.global = null);
```

本仓库 `test/ledger_service_test.dart`、`test/node_auth_code_test.dart`、
`test/novel_library_remote_fetch_test.dart` 都是这么做的。

★ 这条曾经让人误判成「节点侧协议坏了」，实际节点一直是好的。
遇到「curl 通、测试里 400」先查这个，不要急着改业务代码。
（真 App 集成测试 `-d macos` 跑在真引擎上，不受这个 mock 影响。）

## 真 App 集成测试（`flutter test -d macos`）

在**真 macOS App**里跑测试（真 Cocoa 窗口、真插件、真 Rust framework），
用来复现只在真机出现的缺陷——widget test 里平台通道是测试实现，测不到这一层。

```bash
mkdir -p /tmp/sw_real_app_home
HOME=/tmp/sw_real_app_home \
CFFIXED_USER_HOME=/tmp/sw_real_app_home \
SLIME_E2E_HOME=/tmp/sw_real_app_home \
CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
FLUTTER_SWIFT_PACKAGE_MANAGER=false \
/private/tmp/fl/flutter/bin/flutter test integration_test/<文件>.dart -d macos --no-pub
```

- **`CFFIXED_USER_HOME` 才是 macOS 的真隔离开关**。只设 `HOME` 时 `NSHomeDirectory()`
  仍是 `/Users/<你>`，`path_provider` 的 `getApplicationSupportDirectory()` 与
  `UserDefaults`（shared_preferences）照样写开发者真实目录（ledger.db 会落到
  `~/Library/Application Support/com.gleamslime.works/`）。
  → `shared_preferences` **连 CFFIXED_USER_HOME 也拦不住**，测试里要用
  `SharedPreferences.setMockInitialValues({})` 隔离，否则会读到上一次跑留下的陈旧节点。
- **`HOME` 一改会打死 cargokit**：`flutter test -d macos` 会先尝试重建 Rust，
  cargokit 用 `$HOME/.cargo` 找 rustup，报 `rustup is not installed at '/tmp/...'`
  构建直接失败 → 必须显式透传 `CARGO_HOME` / `RUSTUP_HOME`。
- **必须逐文件跑**：`flutter test integration_test/`（整个目录）会把多个文件放**同一进程**
  串跑，而 `RustLib.init()` / `getItInit()` / `runApp()` 都不可重入，加载阶段就崩
  （症状是 `build/test/listener_N.dart` not found 或一堆 loading error）。
- ★★ **写任何临时探针/一次性真 App 测试，第一行必须
  `SharedPreferences.setMockInitialValues(<String, Object>{})`**。
  `HOME` + `CFFIXED_USER_HOME` 拦不住 `shared_preferences`——它走 CFPreferences
  的**真实用户域**，会直接写 `~/Library/Preferences/com.gleamslime.works.plist`。
  2026-11-21 就因为探针没加这一行，把 **36 个假节点**（`真机测试`/`移动测试`，
  指向已关闭的临时端口）写进了开发者真实配置：
  - 真 App 一启动就加载这些死节点 → 全都连接被拒；
  - 书库/媒体库读到的是**上一次测试遗留的陈旧节点**，而不是刚注入的那个；
  - 表现成「明明选了节点却没数据」，排查方向被带偏了好几轮。
  清理办法（先备份！`cp ~/Library/Preferences/com.gleamslime.works.plist /tmp/`）：
  ```bash
  killall cfprefsd          # 必须，否则内存缓存会把旧值写回去
  # 用 plutil -p 看清 flutter.node_remote_nodes，确认全是测试残留后再改
  ```
  记忆里那条「`flutter test` 会拦截真实 HTTP」是另一回事（那个是 400 空 body）。
- `testWidgets` 默认跑在 **fake-async 区**：真实 socket / FFI 的完成回调永远不会被推进，
  直接 `await` 真实网络会挂到超时且**没有任何日志**。真 I/O 一律放进 `tester.runAsync()`，
  再与 `tester.pump` 交替推进。
- 排障：报 `Failed to foreground app; open returned 1` 通常是已有同名 .app 实例在跑，
  先 `pkill -f 史莱姆工坊`；报 `build.db is locked` 是有并发构建，等另一路结束再跑。

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