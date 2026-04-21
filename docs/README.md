# SlimeWorks 文档导航索引（AI 快速定位指南）

> 本文件供 AI 助手快速了解项目结构，在接到新需求时快速定位相关文件和文档，**减少不必要的代码搜索，节省 Token**。

---

## 项目技术栈

| 技术 | 用途 |
|------|------|
| Flutter 3.41 + Dart 3.11 | UI、路由、基础业务逻辑 |
| Rust 1.92（flutter_rust_bridge） | 复杂逻辑、数据库、HTTP 服务、媒体处理 |
| GetX | UI 状态管理（`RxBool`, `RxList`…）|
| GetIt | 业务服务（Service/Repository）的依赖注入 |
| GoRouter + TypedGoRoute | 路由跳转 |
| SharedPreferences | 用户偏好持久化 |
| SQLite（Rust 侧） | 媒体库、书库数据存储 |

---

## 模块文档索引

| 模块 | 文档文件 | 主要修改入口 |
|------|---------|------------|
| 概览 Dashboard | [docs/overview.md](overview.md) | `lib/pages/dashboard_screen.dart` |
| 局域网互传 | [docs/lan_transfer.md](lan_transfer.md) | `lib/pages/lan_transfer/` · `rust/lan_transfer/` |
| 媒体库 | [docs/media_library.md](media_library.md) | `lib/pages/collection/picture/` · `rust/media_collection/` |
| 书库 | [docs/novel_library.md](novel_library.md) | `lib/pages/collection/library/` · `rust/novel_reader/` |
| 游戏库（LunaBox迁移） | `待补充` | `lib/pages/game_library/` · `lib/core/services/game_library_service.dart` · `rust/game_library/` |
| 设置 | [docs/settings.md](settings.md) | `lib/pages/settings/` · `lib/core/services/node/` |
| PicACG 漫画 | [docs/picacg.md](picacg.md) | `lib/pages/picacg/` · `rust/picacg_module/` |

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

### Rust 层

| 文件/目录 | 说明 |
|-----------|------|
| `rust/src/node_server/` | 本地节点 HTTP 服务（`mod.rs` 入口，`router.rs` 路由，`media_handler.rs` 媒体流，`handlers.rs` action 分发） |
| `rust/src/api/http_bridge.rs` | FFI 入口（`start_node_server`, `stop_node_server`, `is_node_server_running`） |
| `rust/lan_transfer/src/` | 局域网互传核心（`api.rs` FFI, `manager.rs` 总控, `discovery.rs` mDNS, `transfer.rs` TCP 帧传输） |
| `rust/media_collection/` | 媒体库（扫描、FFI、缩略图生成） |
| `rust/novel_reader/` | 书库（TXT/EPUB 解析、搜索、进度管理） |
| `rust/game_library/` | 游戏库核心（SQLite、分类、游玩会话、统计） |
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
