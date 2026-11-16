# SlimeWorks Agent 指南

> 跨平台数字内容管理工坊 | Flutter（UI）+ Rust（逻辑）| 桌面端 + 移动端
> 本文件只放**不随环境/版本变化的稳定约定**，保持精简以减少上下文缓存失效。
> 环境与构建细节见 [docs/dev-environment.md](docs/dev-environment.md)；模块导航与架构速查见 [docs/README.md](docs/README.md)。

---

## 架构核心原则

- **Flutter 只负责 UI 显示和 UI 相关数据处理**，Rust 负责逻辑运算/数据存储/物理设备/扫描/文件处理，**禁止职责越界**
- 状态管理：UI/页面 → **GetX**，业务 Service/FFI/配置/数据库 → **GetIt**
- 路由：GoRouter + TypedGoRoute（类型安全）
- 动态加载模块（capture_proxy 等）**仅桌面端可用**
- 移动端兼容：Rust 功能无法在移动端实现时，通过 HTTP 请求节点服务器中转

## 节点与无头模式（硬性）

NAS/服务器上以 `slime_node` 无头进程常驻，客户端可把全部数据功能切到远程节点（侧栏「节点」下拉）。因此：

- **新功能必须同时有节点侧实现**：数据读写落在 `rust/src/node_server/handlers.rs` 的 action 上，客户端经 `NodeSettingsService` 调用；不允许只写本机 FFI 分支就收工。
- **节点 action 不得依赖 Flutter 初始化**：日志、ffmpeg、数据目录由 `slime_node` 自行初始化，Rust 侧不得假设已有 Flutter 传入的运行时状态。
- **无法远程实现的功能要隐藏入口**：依赖本机设备/动态库/临时文件等的功能（如互传、捕获、工具箱）在远程节点模式下必须隐藏侧栏入口与首页卡片，登记到 `kRemoteUnsupportedPathPrefixes`，**绝不静默回退本机**。
- **改动后要保证无头包仍可构建**：`cargo build --release --bin slime_node` 能过，CI 的 `build-headless-*`（macOS/Windows/Linux）不被破坏。
- 页面级节点选择统一走 `NodeSettingsService.resolveNodeSelection`：远程模式强制跟随全局节点，页面自己的记忆值只在「本机」模式下生效。

## 技术栈

UI：Flutter/Dart、GetX、GoRouter、ScreenUtil ｜ FFI：flutter_rust_bridge ｜ Rust：tokio、hyper、redb、rusqlite、serde、reqwest、libloading ｜ 存储：redb(KV)、SQLite、SharedPreferences

具体版本号以 `pubspec.yaml` 与 CI 的 `FLUTTER_VERSION` 为准，不在本文件硬编码。

## 目录速览

- `lib/`：`pages/`（页面模块）、`view_models/`、`core/`（routes/services/theme/utils/viewmodels/widgets）、`components/`、`src/rust/`（FRB 自动生成，**勿改**）
- `rust/`：`src/`（主库 api/ + node_server/）+ 各业务子模块 crate
- 完整目录树、Rust 模块依赖图、服务层/ViewModel 速查、Node Server 路由：见 [docs/README.md](docs/README.md)

---

## 开发规范

| 项 | 规则 |
|------|------|
| 页面命名 | `_screen.dart` 结尾，class `Screen` 结尾，继承 `BasePage` |
| 响应式 | 桌面端窗口≤600 强制移动端模式，用 `SizeUtils.isMobile/isDesktop` |
| 尺寸 | 参考 `AppTheme.metrics`，禁止直接数字或 `int.w`，未定义用 `scaleW()` |
| 日志 | Dart: `Loggers` class，Rust: `logger::{log_error, log_info}`，关键流程中文；文件日志由 `slime_logger` 按天滚动保留 30 天 |
| 注释 | 必须中文，不要删除已有注释 |
| 弹窗 | `showDialog` 而非 `Get.dialog` |
| 新模块 | 静态链接参考 `ws_module/`，动态载入参考 `capture_proxy/` |

---

## 校验与提交（硬性门槛）

任何一次 `git commit` 之前，三道校验缺一不可：

1. **`flutter analyze` 干净** —— 不许有 error，warning/info 也尽量清零。
2. **全量 `flutter test`** —— 必须是全量，不是只跑改动相关的文件。golden 基线失败属既有环境问题，判定标准是**对比基线失败集合**：用 `git worktree` 起基线 commit，两边用同一 SDK 跑全量，head 侧不得新增任何失败。
3. **打包能过** —— `fastforge`，命令与本机姿势见 [docs/dev-environment.md](docs/dev-environment.md)。

三道校验通过后，直接 `git commit` 并 `git push`，无需再询问。

**分支规则**：新功能/修复必须从 `main` 单独拉分支开发，发版时才合并回 `main`；禁止直接在 `main` 上提交功能/修复改动。

---

## 开工前必读

- 跑 flutter/cargo/打包命令前，先读 [docs/dev-environment.md](docs/dev-environment.md)：SDK 选择（现读 `.dart_tool/version`）、镜像 env、Xcode/签名、打包门。
- 定位模块代码前，先读 [docs/README.md](docs/README.md)：导航索引，减少盲目搜索。

## AI 开发工具

仓库提供 `.mcp.json`（Dart/Flutter 官方 MCP Server，`dart mcp-server` 统一入口，含分析/测试/hot reload 等工具）。本地 `dart` 命令必须解析到与 `.dart_tool/version` 一致的 SDK，详见 [docs/dev-environment.md](docs/dev-environment.md)。
