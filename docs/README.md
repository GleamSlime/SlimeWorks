# SlimeWorks 文档导航索引（AI 快速定位指南）

> 本文件供 AI 助手快速了解项目结构，在接到新需求时快速定位相关文件和文档，**减少不必要的代码搜索，节省 Token**。

---

## 项目技术栈

| 技术 | 用途 |
|------|------|
| Flutter/Dart（版本以 CI `FLUTTER_VERSION` 与 `.dart_tool/version` 为准） | UI、路由、基础业务逻辑 |
| Rust（flutter_rust_bridge） | 复杂逻辑、数据库、HTTP 服务、媒体处理 |
| GetX | UI 状态管理（`RxBool`, `RxList`…）|
| GetIt | 业务服务（Service/Repository）的依赖注入 |
| GoRouter + TypedGoRoute | 路由跳转 |
| SharedPreferences | 用户偏好持久化 |
| SQLite（Rust 侧） | 媒体库、书库、游戏库、流水账数据存储 |

---

## 模块文档索引

| 模块 | 文档文件 | 主要修改入口 |
|------|---------|------------|
| 概览 Dashboard | [docs/overview.md](overview.md) | `lib/pages/dashboard_screen.dart` |
| 局域网互传 | [docs/lan_transfer.md](lan_transfer.md) | `lib/pages/lan_transfer/` · `rust/lan_transfer/` |
| 媒体库 | [docs/media_library.md](media_library.md) | `lib/pages/collection/picture/` · `rust/media_collection/` |
| 书库 | [docs/novel_library.md](novel_library.md) | `lib/pages/collection/library/` · `rust/novel_reader/` |
| 游戏库（LunaBox迁移） | [docs/game_library.md](game_library.md) | `lib/pages/game_library/` · `lib/core/services/game_library_service.dart` · `lib/core/services/game_process_tracker.dart` |
| 设置 | [docs/settings.md](settings.md) | `lib/pages/settings/` · `lib/core/services/node/` |
| Manga 漫画 | [docs/manga.md](manga.md) | `lib/pages/manga/` · `rust/manga_module/` |
| 音乐播放器 | [docs/music_player.md](music_player.md) | `lib/pages/music_player/` · `rust/music_player/` |
| 流水账 | [docs/ledger.md](ledger.md) | `lib/pages/ledger/` · `lib/core/services/ledger_service.dart` · `rust/ledger_module/` · `rust/email_module/` |
| 节点服务安全（**仅方案文档，未实施**） | [docs/node_server_security.md](node_server_security.md) | `rust/src/node_server/` · `lib/core/services/node/` |
| 性能/隐藏 Bug/UI 修复台账（含待办） | [docs/ui_perf_fix_todo.md](ui_perf_fix_todo.md) | `lib/core/theme/` · `rust/src/node_server/` · `rust/novel_reader/` |

---

## 关键文件速查表

### UI 层

| 文件 | 说明 |
|------|------|
| `lib/core/provider/screen_chrome.dart` | `ScreenChromeData` / `ScreenChromeEntry` 定义——**所有页面顶部/底部栏的统一配置** |
| `lib/core/provider/screen_provider.dart` | `DesktopScreenProvider` 抽象类——管理全局 Chrome 状态 |
| `lib/components/window/desktop_layout.dart` | 桌面/移动端双模式布局根组件，`_DesktopTopBar` 渲染顶部，`_MobileLayout` 渲染移动端 Chrome |
| `lib/components/window/screen_chrome.dart` | `ScreenChrome` Widget——向 DesktopScreenProvider 注册当前页面的 Chrome |
| `lib/core/viewmodels/base_page.dart` | `BasePage` / `BasePageState` 基类，所有页面继承此类 |
| `lib/core/theme/app_theme.dart` | `AppTheme.metrics`——全局尺寸定义（禁止直接使用数字） |
| `lib/core/theme/app_colors.dart` | `DarkColors` / `LightColors`——所有颜色常量 |
| `lib/core/theme/app_text_styles.dart` | `AppTextStyles`——所有文字样式 |
| `lib/core/utils/size_utils.dart` | `scaleW()`——响应式宽度换算；`isDesktop` / `isMobile` 判断 |

### 服务层（GetIt 单例）

| 文件 | 说明 |
|------|------|
| `lib/core/services/node/node_settings_service.dart` | 本地/远程节点管理、流量统计、熔断机制 |
| `lib/core/services/node/node_media_handler.dart` | Range 请求、缩略图服务（Dart 侧，**已被 Rust Superseded，历史参考**） |
| `lib/core/services/node/node_http_handler.dart` | 节点 action 分发（**已迁移到 Rust，历史参考**） |
| `lib/core/services/lan_transfer_service.dart` | 互传 Dart Service，含端口重试逻辑 |
| `lib/core/services/media_prefs_service.dart` | 媒体质量偏好设置 |
| `lib/core/services/game_library_service.dart` | 游戏库聚合服务（游戏、分类、统计、备份） |
| `lib/core/services/ledger_service.dart` | 流水账：FFI JSON 包装 + 邮箱口令（`flutter_secure_storage`）+ 移动端节点中转 |

### Rust 层

| 文件/目录 | 说明 |
|-----------|------|
| `rust/src/node_server/` | 本地节点 HTTP 服务（`mod.rs` 入口，`router.rs` 路由，`media_handler.rs` 媒体流，`handlers.rs` action 分发） |
| `rust/src/api/http_bridge.rs` | FFI 入口（`start_node_server`, `stop_node_server`, `is_node_server_running`） |
| `rust/lan_transfer/src/` | 局域网互传核心（`api.rs` FFI, `manager.rs` 总控, `discovery.rs` mDNS, `transfer.rs` TCP 帧传输） |
| `rust/media_collection/` | 媒体库（扫描、FFI、缩略图生成） |
| `rust/novel_reader/` | 书库（TXT/EPUB 解析、搜索、进度管理） |
| `rust/game_library/` | 游戏库核心（SQLite、分类、游玩会话、统计） |
| `rust/music_player/` | 音乐播放器（播放列表、扫描、CUE 解析、封面提取、均衡器） |
| `rust/ledger_module/` | 流水账（`storage.rs` SQLite、`parser.rs` 账单模板、`scheduler.rs` 收信调度、`api.rs` FFI 面） |
| `rust/email_module/` | 邮件协议层（`imap.rs`/`pop3.rs`/`smtp.rs`、`mime.rs` 解码、`types.rs` TLS 准入策略） |
| `rust/src/frb_generated.rs` | FRB 自动生成，**勿直接修改** |
| `lib/src/rust/` | Dart FFI 自动生成，**勿直接修改** |

---


## 响应式设计规范

| 条件 | 模式 |
|------|------|
| `Platform.isMacOS \|\| Platform.isWindows` | 桌面端（侧边栏 + 顶部工具栏） |
| `Platform.isAndroid \|\| Platform.isIOS` | 移动端（底部导航 + 顶部 Chrome） |
| 桌面端但窗口宽度 ≤ 600 | 强制切换为移动端模式（`DesktopScreenProvider.isMobile`） |

判断方式：
```dart
import 'package:slime_works/core/utils/size_utils.dart';
bool mobile = SizeUtils.isMobile;   // Platform.isAndroid || Platform.isIOS
bool desktop = SizeUtils.isDesktop; // Platform.isMacOS  || Platform.isWindows
```

---

## 状态管理规范

| 场景 | 用法 |
|------|------|
| UI 响应式状态 | `GetX`（`RxBool`, `RxList`, `Obx(() => ...)`） |
| 全局单例 Service | `GetIt.instance.get<MyService>()` 或 `getIt<MyService>()` |
| 路由导航 | `context.go('/path')` 或 `context.push('/path')`（GoRouter） |
| 弹窗/对话框 | `showDialog(context: context, ...)` 而非 `Get.dialog`（GoRouter 兼容） |

---

## 日志规范

```dart
// Dart
final _logger = Loggers(name: 'ModuleName');
_logger.info('操作完成');
_logger.error('失败', error: e, stackTrace: st);
```

```rust
// Rust
use log::{info, warn, error};
info!("操作完成: {}", detail);
```

---

## 常用命令

```bash
# Dart 静态分析（必须无报错）
flutter analyze

# Rust 编译检查
cd rust && cargo build

# 运行 iOS 模拟器
flutter run -d <simulator_id>
```

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
├── src/                      # 主 crate（api/ 转发各子模块 + node_server/）
├── slime_logger/             # 文件日志（按天滚动保留 30 天，多数 crate 依赖）
├── db_module/                # redb KV 数据库（基础层）
├── http_bridge/              # HTTP 桥接（移动端中转）
├── email_module/             # 邮件协议层 IMAP/POP3/SMTP+MIME，TLS 强制
├── media_collection/         # 媒体集合 → db_module
├── novel_reader/             # 小说阅读器 → db_module + http_bridge
├── game_library/             # 游戏库（自建 SQLite）
├── manga_module/             # Manga 漫画 API
├── lan_transfer/             # 局域网传输 mDNS+TCP
├── extract_module/           # 解压工具 → db_module
├── music_player/             # 音乐播放器 → db_module
├── ncm_decrypt/              # NCM 格式解密
├── power_stats/              # 电量统计
├── aliyun_module/            # 阿里云 DDNS
├── asr_module/               # 语音识别
├── whisper_module/           # Whisper 本地识别 → db_module
├── sentry_log/               # Sentry 日志（自建 redb）
├── ws_module/                # WebSocket（条件编译）
├── module_manager/           # 模块管理/动态加载
├── ledger_module/            # 流水账（SQLite + 账单模板 + 收信调度）→ email_module
└── capture_proxy/            # 抓包代理（cdylib 动态库，仅桌面端）
```

## Rust 模块依赖图

```
基础层（无业务依赖）: slime_logger, db_module, http_bridge, email_module,
                      lan_transfer, ws_module, manga_module, sentry_log,
                      game_library, module_manager, capture_proxy,
                      aliyun_module, power_stats, ncm_decrypt, asr_module
                      （除 module_manager / capture_proxy 外均依赖 slime_logger）

业务层:  media_collection → db_module
         novel_reader → db_module + http_bridge
         extract_module → db_module
         music_player → db_module
         whisper_module → db_module
         ledger_module → email_module

聚合层:  rust_lib_slime_works（rust/src）→ 所有子模块
```

## 服务层速查

> 速查快照，新增服务以代码为准。

| 服务 | 职责 | 依赖 |
|------|------|------|
| `MangaService` | 漫画认证/浏览/搜索/收藏/7种分流 | Rust FFI |
| `MangaDownloadService` | 下载队列/进度/离线路径 | MangaService |
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
| `LedgerService` | 流水账 FFI 包装/邮箱口令安全存储/移动端节点中转 | Rust FFI / NodeSettingsService |
| `LedgerStubStore` | 记账增强桩仓库（标签/分组/模板/定时/附件/备份/CSV，进程级单例，后端未接入） | SharedPreferences |

## ViewModel 速查

| 模块 | ViewModel | 核心职责 |
|------|-----------|----------|
| 媒体 | MediaLibraryViewModel + VmCollections + VmRemote + VmSmartFolders | 浏览/集合/远程/智能文件夹 |
| 小说 | NovelLibraryViewModel(+Actions+Novel) / NovelReaderViewModel | 列表/操作/数据/阅读 |
| 游戏 | Home / Library / Detail / Categories / Stats / Settings | 首页/CRUD/详情/分类/统计/设置 |
| Manga | Home / ComicDetail / Search / Reader / Downloads / Favourites / History | 完整漫画业务 |
| 传输 | LanTransferViewModel | 设备发现/传输管理 |
| 抓包 | CaptureScreenViewModel | 代理控制/流量展示 |
| 日志 | SentryLogViewModel | 日志查询/过滤 |
| 流水账 | Home / Records / Stats / Pending / Settings / Accounts / Organize / Templates / Data | 概览/明细/统计/待确认入账/邮箱规则/账户/分类与标签/模板与定时/导入导出 |

## Node Server 路由

| 路由 | 功能 |
|------|------|
| `POST /node/call` | action 分发（media_collection/novel_reader 等） |
| `GET /node/media` | 媒体文件流（缩放/Range） |
| `POST /node/upload` | 文件上传 |
| `POST /manga/api` | Manga API 中转 |
| `GET /manga/img` | Manga 图片中转 |
| `POST /api/{id}/store\|envelope` | Sentry 兼容端点 |

`POST /node/call` 的 `action` 用扁平命名（`list_media_collections` / `get_novel_content` / …）；流水账统一带 `ledger_` 前缀，分发前先 `ensure_ledger_ready` 让节点自己建库。`init/is_ready/version/set_rule_password/rule_detail` 五个不转发（本机专属）。详见 [ledger.md](ledger.md)。

## 日志文件位置

- macOS：`~/Library/Logs/史莱姆工坊/logs/slime_works_<日期>.log`
- Windows：`%APPDATA%\SlimeWorks\logs\`
- 由 `slime_logger` 按天滚动并保留 30 天。
