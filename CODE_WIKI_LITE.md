# SlimeWorks Code Wiki（精简版）

> 跨平台数字内容管理工坊 | Flutter 3.41 + Rust 1.92 | 桌面端 + 移动端

---

## 架构核心原则

- **Flutter 只负责 UI 显示和 UI 相关数据处理**，Rust 负责逻辑运算/数据存储/物理设备/扫描/文件处理，**禁止职责越界**
- 状态管理：UI/页面 → **GetX**，业务 Service/FFI/配置/数据库 → **GetIt**
- 路由：GoRouter + TypedGoRoute（类型安全）
- 动态加载模块（capture_proxy 等）**仅桌面端可用**
- 移动端兼容：Rust 功能无法在移动端实现时，通过 HTTP 请求节点服务器中转

---

## 技术栈速查

| 层 | 技术 |
|----|------|
| UI | Flutter/Dart, GetX, GoRouter, ScreenUtil |
| FFI | flutter_rust_bridge 2.11.1 |
| Rust | tokio, hyper, redb, rusqlite, serde, reqwest, libloading |
| 存储 | redb(KV), SQLite, SharedPreferences |

---

## 目录结构（核心）

```
lib/
├── main.dart                 # 入口（初始化链：AppInfo→GetIt→FRB→Services→Theme→runApp）
├── core/
│   ├── routes/               # GoRouter 路由（模块化 part 文件 + RoleManager 权限守卫）
│   ├── services/             # 业务 Service 层（GetIt 单例）
│   │   ├── node/             # 节点服务（本地/远程节点、熔断、流量统计）
│   │   └── ollama/           # AI 翻译服务
│   ├── theme/                # AppTheme.metrics / DarkColors / LightColors / AppTextStyles
│   ├── utils/                # size_utils(scaleW/isDesktop/isMobile), Loggers
│   ├── viewmodels/           # BaseViewModel + BasePage 基类
│   └── widgets/              # 通用 Widget
├── components/               # window/buttons/dialogs/dropdown/animations
├── pages/                    # 页面模块（_screen.dart 结尾，继承 BasePage）
├── view_models/              # ViewModel 层（继承 BaseViewModel）
└── src/rust/                 # FRB 自动生成（勿改）

rust/
├── src/                      # 主库（api/ 转发 17 子模块 + node_server/）
│   ├── api/                  # FRB 绑定入口
│   └── node_server/          # HTTP 服务器（mod.rs/router.rs/handlers.rs/media_handler.rs）
├── db_module/                # redb KV 数据库（基础层，无依赖）
├── media_collection/         # 媒体集合 → 依赖 db_module
├── novel_reader/             # 小说阅读器 → 依赖 db_module + http_bridge
├── game_library/             # 游戏库（自建 SQLite，无内部依赖）
├── picacg_module/            # PicACG 漫画 API（无内部依赖）
├── lan_transfer/             # 局域网传输 mDNS+TCP（无内部依赖）
├── extract_module/           # 解压工具 → 依赖 db_module
├── sentry_log/               # Sentry 日志（自建 redb，无内部依赖）
├── http_bridge/              # HTTP 桥接（移动端中转，无内部依赖）
├── ws_module/                # WebSocket（条件编译，无内部依赖）
├── module_manager/           # 模块管理/动态加载（无内部依赖）
└── capture_proxy/            # 抓包代理（cdylib 动态库，仅桌面端）
```

---

## Rust 模块依赖图

```
基础层（无内部依赖）: db_module, http_bridge, lan_transfer, ws_module,
                      picacg_module, sentry_log, game_library, module_manager, capture_proxy

业务层:  media_collection → db_module
         novel_reader → db_module + http_bridge
         extract_module → db_module

聚合层:  rust_lib_slime_works → 所有子模块
```

---

## 服务层速查

| 服务 | 职责 | 依赖 |
|------|------|------|
| `PicAcgService` | 漫画认证/浏览/搜索/收藏/7种分流 | Rust FFI |
| `PicAcgDownloadService` | 下载队列/进度/离线路径 | PicAcgService |
| `GameLibraryService` | 游戏 CRUD/分类/统计 | MetadataApi → Rust FFI |
| `GameProcessTracker` | 进程追踪/时长记录 | GameLibraryService |
| `GameLibraryMetadataApi` | Steam/VNDB/Bangumi 元数据聚合 | HTTP |
| `LanTransferService` | 设备发现/文件传输/信任管理 | Rust FFI |
| `NodeSettingsService` | 节点管理/熔断/流量统计 | Rust FFI |
| `ExtractService` | 解压/密码库/进度轮询 | Rust FFI |
| `OllamaService` | AI 翻译/多服务器轮询/流式生成 | HTTP |
| `SentrySettingsService` | Sentry 配置/远程日志查询 | Rust FFI / HTTP |
| `MediaPrefsService` | 缩略图质量/并发/缓存管理 | SharedPreferences |
| `SystemTrayService` | 系统托盘（桌面端） | tray_manager |
| `WindowPositionService` | 窗口位置持久化 | SharedPreferences |
| `WebSocketManager` | WS 服务器(桌面)/客户端(移动) | Rust FFI |

---

## ViewModel 速查

| 模块 | ViewModel | 核心职责 |
|------|-----------|----------|
| 媒体 | MediaLibraryViewModel + VmCollections + VmRemote + VmSmartFolders | 浏览/集合/远程/智能文件夹 |
| 小说 | NovelLibraryViewModel(+Actions+Novel) / NovelReaderViewModel | 列表/操作/数据/阅读 |
| 游戏 | Home / Library / Detail / Categories / Stats / Settings | 首页/CRUD/详情/分类/统计/设置 |
| PicACG | Home / ComicDetail / Search / Reader / Downloads / Favourites / History | 完整漫画业务 |
| 传输 | LanTransferViewModel | 设备发现/传输管理 |
| 抓包 | CaptureScreenViewModel | 代理控制/流量展示 |
| 日志 | SentryLogViewModel | 日志查询/过滤 |

---

## Node Server 路由

| 路由 | 功能 |
|------|------|
| `POST /node/call` | action 分发（media_collection/novel_reader 等） |
| `GET /node/media` | 媒体文件流（缩放/Range） |
| `POST /node/upload` | 文件上传 |
| `POST /picacg/api` | PicACG API 中转 |
| `GET /picacg/img` | PicACG 图片中转 |
| `POST /api/{id}/store\|envelope` | Sentry 兼容端点 |

---

## 开发规范速查

| 规范 | 规则 |
|------|------|
| 页面命名 | `_screen.dart` 结尾，class `Screen` 结尾，继承 `BasePage` |
| 响应式 | 桌面端窗口≤600 强制移动端模式，用 `SizeUtils.isMobile/isDesktop` |
| 尺寸 | 参考 `AppTheme.metrics`，禁止直接数字或 `int.w`，未定义用 `scaleW()` |
| 日志 | Dart: `Loggers` class，Rust: `logger::{log_error, log_info}`，关键流程中文 |
| 注释 | 必须中文 |
| 弹窗 | `showDialog` 而非 `Get.dialog` |
| 校验 | Flutter → `flutter analyze`，Rust → `cargo build` |
| 新模块 | 静态链接参考 `ws_module/`，动态载入参考 `capture_proxy/` |

---

## 构建命令

```bash
flutter_rust_bridge_codegen generate          # 生成 FRB 绑定
flutter pub run build_runner build             # 生成资源引用/JSON序列化
flutter run -d macos                           # 开发运行
flutter build macos --release                  # 发布构建
cd rust && cargo test --workspace              # Rust 测试
flutter test                                   # Flutter 测试
```
