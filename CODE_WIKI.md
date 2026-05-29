# SlimeWorks（史莱姆工坊）— Code Wiki

> **版本**: v1.0.0+17 | **状态**: 开发中 | **平台**: Windows / macOS / Linux / iOS / Android

---

## 目录

- [1. 项目概览](#1-项目概览)
- [2. 技术栈](#2-技术栈)
- [3. 项目整体架构](#3-项目整体架构)
- [4. 目录结构](#4-目录结构)
- [5. Flutter 前端架构](#5-flutter-前端架构)
  - [5.1 入口与初始化](#51-入口与初始化)
  - [5.2 状态管理](#52-状态管理)
  - [5.3 路由系统](#53-路由系统)
  - [5.4 依赖注入](#54-依赖注入)
  - [5.5 主题系统](#55-主题系统)
  - [5.6 权限系统](#56-权限系统)
  - [5.7 工具模块](#57-工具模块)
  - [5.8 通用 Widget](#58-通用-widget)
- [6. Rust 后端架构](#6-rust-后端架构)
  - [6.1 主库与 FRB 桥接](#61-主库与-frb-桥接)
  - [6.2 子模块详解](#62-子模块详解)
  - [6.3 Node Server](#63-node-server)
- [7. 核心业务模块](#7-核心业务模块)
  - [7.1 媒体集合（Media Collection）](#71-媒体集合media-collection)
  - [7.2 小说阅读器（Novel Reader）](#72-小说阅读器novel-reader)
  - [7.3 游戏库（Game Library）](#73-游戏库game-library)
  - [7.4 Manga 漫画平台](#74-manga-漫画平台)
  - [7.5 局域网传输（LAN Transfer）](#75-局域网传输lan-transfer)
  - [7.6 解压工具（Extract）](#76-解压工具extract)
  - [7.7 Sentry 日志收集](#77-sentry-日志收集)
  - [7.8 抓包代理（Capture Proxy）](#78-抓包代理capture-proxy)
- [8. 服务层详解](#8-服务层详解)
- [9. ViewModel 层详解](#9-viewmodel-层详解)
- [10. 通用组件库](#10-通用组件库)
- [11. 依赖关系图](#11-依赖关系图)
- [12. 构建与运行](#12-构建与运行)
- [13. 测试](#13-测试)
- [14. 发布](#14-发布)
- [15. 开发规范](#15-开发规范)
- [附录：FRB 生成的 Dart API 速查](#附录frb-生成的-dart-api-速查)

---

## 1. 项目概览

**SlimeWorks（史莱姆工坊）** 是一款跨平台桌面/移动端应用，定位为个人数字内容管理工坊。它集成了媒体库管理、小说阅读、游戏库管理、漫画浏览与下载、局域网传输、压缩包解压、抓包代理、AI 翻译等多种功能，采用 **Flutter + Rust** 双语言架构，通过 Flutter Rust Bridge (FRB) 实现高性能原生能力与跨平台 UI 的结合。

### 核心特性

| 特性 | 说明 |
|------|------|
| 媒体集合管理 | 本地图片/视频/音频的目录扫描、缩略图生成、文件夹分组 |
| 小说阅读器 | 支持 TXT/EPUB 格式，章节解析、全文搜索、阅读进度、AI 翻译 |
| 游戏库 | 视觉小说/游戏管理，时长追踪，元数据抓取（萌娘百科/2DFan） |
| Manga 漫画 | 漫画浏览/搜索/下载/离线阅读，7 种分流模式 |
| 局域网传输 | mDNS 设备发现，文件/文本传输，信任设备管理 |
| 解压工具 | 多格式解压（7z/zip/tar.gz/bz2/xz/lzma/zstd），密码库管理 |
| 抓包代理 | HTTP/HTTPS MITM 代理，CA 证书管理 |
| Sentry 日志 | 兼容 Sentry SDK 协议的日志收集与查询 |
| AI 翻译 | Ollama 本地大模型翻译，多服务器轮询 |
| 分布式节点 | PC 作为节点服务器，移动端通过 HTTP/WS 中转访问 |
| 模块管理 | 动态库加载/卸载/热更新，版本管理与 MD5 校验 |
| 系统监控 | CPU/内存/网速实时采集 |

---

## 2. 技术栈

### 前端（Flutter/Dart）

| 类别 | 技术 | 版本 |
|------|------|------|
| 框架 | Flutter | 3.41.0-0.0.pre |
| 语言 | Dart | 3.11.0 |
| 状态管理 | GetX | ^4.7.3 |
| 依赖注入 | GetIt | ^9.2.0 |
| 路由 | GoRouter (TypedGoRoute) | ^17.0.1 |
| 网络请求 | Dio | ^5.9.0 |
| 本地存储 | SharedPreferences / FlutterSecureStorage | ^2.3.4 / ^10.0.0 |
| 视频播放 | media_kit | ^1.1.11 |
| 图片缓存 | cached_network_image | ^3.4.1 |
| 桌面窗口 | window_manager | ^0.5.1 |
| 系统托盘 | tray_manager | ^0.5.0 |
| 屏幕适配 | flutter_screenutil | ^5.9.3 |
| 代码生成 | build_runner + flutter_gen + json_serializable | — |
| FFI 桥接 | flutter_rust_bridge | 2.11.1 |
| HTML渲染 | flutter_widget_from_html | ^0.15.2 |
| SVG | flutter_svg | ^2.2.3 |
| 下拉刷新 | easy_refresh | ^3.4.0 |
| 骨架屏 | skeletonizer | ^2.1.2 |

### 后端（Rust）

| 类别 | 技术 | 版本 |
|------|------|------|
| 语言 | Rust | 1.92.0 |
| FFI 桥接 | flutter_rust_bridge | =2.11.1 |
| 数据库 | redb (KV) / rusqlite (SQLite) | 2.1 / 0.31 |
| HTTP 服务器 | hyper | 0.14.32 |
| 异步运行时 | tokio | 1.49.0 |
| 序列化 | serde / serde_json | 1.0 |
| 错误处理 | anyhow / thiserror | 1.0 |
| 动态加载 | libloading | 0.8 |
| 网络请求 | reqwest | 0.12 |
| TLS | hyper-rustls / rustls | 0.27 / 0.23 |
| 图片处理 | image | 0.25 |
| EPUB解析 | epub | 2.0 |
| 编码检测 | encoding_rs / chardetng | 0.8 / 0.1 |
| 并行处理 | rayon | 1.10 |
| 压缩 | sevenz-rust2 / zip / tar / flate2 / bzip2 / liblzma | — |
| HTML解析 | scraper | 0.22 |
| 加密 | hmac / sha2 / md5 | — |

---

## 3. 项目整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter 前端层                           │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │
│  │  Pages   │ │ViewModels│ │ Services │ │  Components    │  │
│  │ (UI页面) │ │(状态管理) │ │(业务服务) │ │  (通用组件)    │  │
│  └────┬─────┘ └─────┬────┘ └─────┬────┘ └────────────────┘  │
│       │             │            │                           │
│       └─────────────┼────────────┘                           │
│                     │ GetX / GetIt                           │
│  ┌──────────────────┼─────────────────────────────────────┐ │
│  │           Core (路由/主题/权限/工具)                     │ │
│  └──────────────────┬─────────────────────────────────────┘ │
└─────────────────────┼───────────────────────────────────────┘
                      │ Flutter Rust Bridge (FFI)
┌─────────────────────┼───────────────────────────────────────┐
│              Rust 后端层                                     │
│  ┌──────────────────┴─────────────────────────────────────┐ │
│  │              api/ (FRB 绑定入口)                        │ │
│  └──┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬───┘ │
│     ▼      ▼      ▼      ▼      ▼      ▼      ▼      ▼     │
│  ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐  │
│  │media ││novel ││game  ││manga││lan   ││extract││sentry│  │
│  │coll. ││reader││lib.  ││module││trans.││module ││log   │  │
│  └──┬───┘└──┬───┘└──────┘└──────┘└──────┘└──┬───┘└──────┘  │
│     ▼       ▼                               ▼              │
│  ┌──────┐┌──────┐                       ┌──────┐           │
│  │db    ││http  │                       │db    │           │
│  │module││bridge│                       │module│           │
│  └──────┘└──────┘                       └──────┘           │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │ws_module │ │module_mgr│ │capture   │ ← cdylib 动态加载   │
│  └──────────┘ └──────────┘ │proxy     │                    │
│                             └──────────┘                    │
│  ┌──────────────────────────────────────┐                   │
│  │         node_server (HTTP)           │                   │
│  │   PC 中转 / 媒体服务 / Sentry 端点    │                   │
│  └──────────────────────────────────────┘                   │
└──────────────────────────────────────────────────────────────┘
```

### 架构设计原则

1. **职责严格分离（禁止越界）**: Flutter **只负责 UI 显示和 UI 相关数据处理**，Rust 负责逻辑运算、数据存储、物理设备、扫描、文件处理等。**禁止 Flutter 越界承担业务逻辑！**
2. **状态管理双轨制**: UI/页面状态使用 GetX，业务 Service、Rust FFI 桥接层、配置、数据库使用 GetIt
3. **类型安全路由**: 使用 `TypedGoRoute` 编译期路由检查
4. **模块化 Rust**: 每个 Rust 功能独立为 crate，主库聚合转发
5. **动态加载（仅桌面端）**: capture_proxy 等编译为 cdylib 的模块通过 libloading 动态加载，**仅在桌面端可用**，移动端不可用
6. **移动端兼容**: 当 Rust 功能无法在移动端完全实现时，通过 HTTP 请求客户端方式让桌面端（节点服务器）执行逻辑后返回数据，设计和选择方案时必须考虑兼容移动端

---

## 4. 目录结构

```
slime_works/
├── lib/                          # Flutter 主代码
│   ├── main.dart                 # 应用入口
│   ├── demo_main.dart            # 演示入口
│   ├── core/                     # 核心框架层
│   │   ├── index.dart            # 统一导出 barrel file
│   │   ├── provider/             # 屏幕提供者
│   │   │   ├── main.dart         # GetIt 初始化 + 全局单例注册
│   │   │   ├── screen_provider.dart      # DesktopScreenProvider 抽象类
│   │   │   ├── screen_provider_impl.dart # DesktopScreenProvider 实现
│   │   │   └── screen_chrome.dart        # ScreenChromeData / ScreenChromeEntry
│   │   ├── routes/               # 路由定义（模块化拆分）
│   │   │   ├── app_routes.dart   # 主路由配置 + AppShellRouteData
│   │   │   ├── app_sidebars.dart # 侧边栏分组自动生成
│   │   │   ├── role_manager.dart # RBAC 权限管理
│   │   │   └── routes/           # 路由模块拆分
│   │   │       ├── core_routes.dart
│   │   │       ├── business_routes.dart
│   │   │       ├── capture_routers.dart
│   │   │       ├── collection_routes.dart
│   │   │       ├── demo_routes.dart
│   │   │       ├── game_library_routes.dart
│   │   │       ├── lan_transfer_routes.dart
│   │   │       ├── novel_routes.dart
│   │   │       ├── manga_routes.dart
│   │   │       ├── placeholder_routes.dart
│   │   │       ├── test_routes.dart
│   │   │       └── tools_routes.dart
│   │   ├── services/             # 业务服务层
│   │   │   ├── app_info_service.dart      # 应用版本信息
│   │   │   ├── extract_service.dart       # 解压服务
│   │   │   ├── game_library_service.dart  # 游戏库聚合服务
│   │   │   ├── game_library_metadata_api.dart # 元数据搜索(Steam/VNDB/Bangumi)
│   │   │   ├── game_process_tracker.dart  # 游戏进程追踪
│   │   │   ├── lan_transfer_service.dart  # 局域网传输服务
│   │   │   ├── media_prefs_service.dart   # 媒体偏好设置
│   │   │   ├── manga_service.dart        # Manga 业务服务
│   │   │   ├── manga_download_service.dart # Manga 下载管理
│   │   │   ├── sentry_settings_service.dart # Sentry 设置服务
│   │   │   ├── system_tray_service.dart   # 系统托盘服务
│   │   │   ├── time_consumption_test.dart # 启动耗时测试
│   │   │   ├── video_thumb_queue.dart     # 视频缩略图队列
│   │   │   ├── websocket_manager.dart     # WebSocket 管理
│   │   │   ├── window_position_service.dart # 窗口位置持久化
│   │   │   ├── initialize/       # 初始化服务
│   │   │   │   ├── main.dart     # 初始化入口
│   │   │   │   └── ffmpeg.dart   # FFmpeg 初始化
│   │   │   ├── node/             # 节点服务
│   │   │   │   ├── node_http_handler.dart  # 节点HTTP分发(历史参考)
│   │   │   │   ├── node_media_handler.dart # 节点媒体处理(历史参考)
│   │   │   │   ├── node_models.dart        # 节点数据模型
│   │   │   │   └── node_settings_service.dart # 节点设置服务
│   │   │   └── ollama/           # AI 翻译服务
│   │   │       ├── ollama_service.dart        # Ollama API 调用
│   │   │       ├── ollama_models.dart         # Ollama 数据模型
│   │   │       └── ollama_settings_service.dart # Ollama 配置持久化
│   │   ├── theme/                # 主题系统
│   │   │   ├── app_theme.dart    # AppTheme + ThemeMetrics
│   │   │   └── app_colors.dart   # LightColors / DarkColors
│   │   ├── utils/                # 工具函数
│   │   │   ├── format.dart       # formatFileSize 等格式化工具
│   │   │   ├── logger.dart       # Loggers 日志类(Loki上报)
│   │   │   └── size_utils.dart   # scaleW/scaleH/scaleS + 平台判断
│   │   ├── viewmodels/           # 基础 ViewModel
│   │   │   ├── base_viewmodel.dart # BaseViewModel (GetxController)
│   │   │   └── base_page.dart      # BasePage + BasePageState
│   │   └── widgets/              # 通用 Widget
│   │       ├── binding_widget.dart  # GetX 生命周期绑定
│   │       └── common_widget.dart   # appBarBackButton 等
│   ├── components/               # UI 组件库
│   │   ├── animations/           # 动画组件
│   │   │   └── state_transition_animation.dart
│   │   ├── buttons/              # 按钮组件
│   │   │   ├── animated_button.dart
│   │   │   ├── cue_pressable.dart
│   │   │   └── svg_button.dart
│   │   ├── dialogs/              # 对话框组件
│   │   │   ├── confirm_dialog.dart
│   │   │   └── node_directory_picker.dart
│   │   ├── dropdown/             # 下拉菜单组件
│   │   │   ├── gooey_dropdown.dart
│   │   │   └── gooey_dropdown_shader.dart
│   │   └── window/               # 桌面窗口组件
│   │       ├── collapsible_sidebar.dart
│   │       ├── desktop_head.dart
│   │       ├── desktop_layout.dart
│   │       ├── desktop_scaffold.dart
│   │       ├── screen_chrome.dart
│   │       └── screen_top_bar.dart
│   ├── pages/                    # 页面模块
│   │   ├── about/                # 关于页面
│   │   ├── backup/capture_screen/# 抓包录屏
│   │   ├── collection/           # 收藏夹（library + picture）
│   │   ├── demo/                 # 演示页面
│   │   ├── game_library/         # 游戏库
│   │   ├── lan_transfer/         # 局域网传输
│   │   ├── novel_library/        # 小说库
│   │   ├── novel_reader/         # 小说阅读器
│   │   ├── manga/               # Manga 漫画
│   │   ├── sentry_log/           # Sentry 日志
│   │   ├── settings/             # 设置页面
│   │   ├── tools/                # 工具页面
│   │   ├── dashboard_screen.dart # 仪表盘
│   │   ├── module_management_screen.dart # 模块管理
│   │   ├── theme_preview_screen.dart # 主题预览
│   │   ├── http_bridge_test_page.dart # HTTP桥接测试
│   │   └── websocket_test_page.dart   # WebSocket测试
│   ├── view_models/              # ViewModel 层
│   ├── src/rust/                 # FRB 自动生成的 Dart 绑定
│   │   ├── frb_generated.dart    # FRB 核心生成代码
│   │   ├── frb_generated.io.dart
│   │   ├── frb_generated.web.dart
│   │   ├── lib.dart              # 导出汇总
│   │   └── api/                  # 各模块 API 绑定
│   │       ├── capture.dart
│   │       ├── extract.dart
│   │       ├── ffmpeg.dart
│   │       ├── game_library.dart
│   │       ├── http_bridge.dart
│   │       ├── lan_transfer.dart
│   │       ├── logger.dart
│   │       ├── media_collection.dart
│   │       ├── module_downloader.dart
│   │       ├── module_loader.dart
│   │       ├── module_manager.dart
│   │       ├── novel_reader.dart
│   │       ├── manga.dart
│   │       ├── sentry_log.dart
│   │       ├── simple.dart
│   │       ├── system_metrics.dart
│   │       └── websocket.dart
│   └── gen/                      # FlutterGen 生成的资源引用
│       ├── assets.gen.dart
│       ├── colors.gen.dart
│       └── fonts.gen.dart
├── rust/                         # Rust 后端代码
│   ├── src/                      # 主库（FRB 入口 + node_server）
│   ├── build.rs                  # 构建脚本
│   ├── capture_proxy/            # 抓包代理（cdylib 动态库）
│   ├── db_module/                # 通用数据库模块 (redb)
│   ├── extract_module/           # 解压工具模块
│   ├── game_library/             # 游戏库模块 (rusqlite)
│   ├── http_bridge/              # HTTP 桥接模块
│   ├── lan_transfer/             # 局域网传输模块
│   ├── media_collection/         # 媒体集合模块
│   ├── module_manager/           # 模块管理系统
│   ├── novel_reader/             # 小说阅读器模块
│   ├── manga_module/            # Manga 漫画模块
│   ├── sentry_log/               # Sentry 日志模块 (redb)
│   ├── ws_module/                # WebSocket 模块
│   └── examples/                 # Rust 示例
├── assets/                       # 静态资源
│   ├── fonts/                    # 方正兰亭圆字体
│   ├── image/svg/                # SVG 图标
│   ├── image/tray/               # 系统托盘图标
│   └── colors.xml                # FlutterGen 颜色配置
├── shaders/                      # Fragment Shaders
│   └── gooey.frag                # Gooey 下拉菜单着色器
├── android/ / ios/ / linux/ / macos/ / web/  # 平台原生代码
├── docs/                         # 文档
├── installer/                    # Windows NSIS 安装包脚本
├── scripts/                      # 自动化脚本
│   ├── auto.py                   # Android 蒲公英发布
│   └── publish_ios.py            # iOS 蒲公英发布
├── integration_test/             # 集成测试
├── rust_builder/                 # Rust 构建插件
├── .env                          # 环境变量
├── .fvmrc                        # FVM 版本配置
├── pubspec.yaml                  # Flutter 项目配置
└── flutter_rust_bridge.yaml      # FRB 配置
```

---

## 5. Flutter 前端架构

### 5.1 入口与初始化

**文件**: [main.dart](file:///Users/shilaimu/research/Software/slime_works/lib/main.dart)

应用启动流程：

```
main()
 ├── WidgetsFlutterBinding.ensureInitialized()
 ├── AppInfoService.init()              # 初始化应用信息
 ├── dotenv.load()                      # 加载 .env 环境变量
 ├── getItInit()                        # 注册所有 GetIt 单例
 ├── DesktopScaffold.initManager()      # 桌面端窗口管理器 (macOS/Windows/Linux)
 ├── SystemTrayService.init()           # 系统托盘 (桌面端)
 ├── RustLib.init()                     # FRB 初始化（必须在所有 Rust 调用前）
 ├── MediaKit.ensureInitialized()       # 视频播放引擎
 ├── MangaService.init()               # 恢复漫画登录态
 ├── MangaDownloadService.init()       # 恢复下载元数据
 ├── PaintingBinding.imageCache.maximumSizeBytes = 80MB  # 限制图片缓存
 ├── NodeSettingsService.init()         # 节点服务初始化
 ├── SentrySettingsService.init()       # Sentry 配置
 ├── AppTheme.loadSavedTheme()          # 加载主题
 ├── runApp(MyApp())                    # 启动 Flutter 应用
 └── _postAppInit()                     # 异步后置初始化
      ├── initializeLogger()            # 日志初始化
      ├── sentryLogInit()               # Sentry 数据库初始化
      └── configLoading()               # EasyLoading 配置
```

**MyApp** 类使用 `Obx` 响应式监听主题变化（`themeModeObs`、`accentColorObs`、`fontScaleObs`、`metricsVersion`），通过 `ScreenUtilInit` 适配不同屏幕尺寸（桌面 1920×1080 / 移动 375×815），使用 `MaterialApp.router` + `GoRouter` 管理路由。

### 5.2 状态管理

项目采用 **双轨制** 状态管理：

| 管理方式 | 适用场景 | 生命周期 |
|----------|----------|----------|
| **GetX** | UI/页面状态、响应式数据绑定 | 随页面销毁或永久存在 |
| **GetIt** | 业务 Service、Rust FFI 桥接层、全局单例 | 应用级单例 |

#### BaseViewModel

**文件**: [base_viewmodel.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/viewmodels/base_viewmodel.dart)

所有 ViewModel 的基类，继承 `GetxController`：

```dart
abstract class BaseViewModel extends GetxController {
  bool _isInitialized = false;      // 初始化状态
  bool _isLoading = false;          // 加载状态
  String? _errorMessage;            // 错误信息

  Future<void> onInitAsync();       // 异步初始化
  void setLoading(bool loading);    // 设置加载状态
  void setError(String? error);     // 设置错误信息
  void clearError();                // 清除错误
}
```

使用方式：
- **随页面销毁**：在 `createViewModel()` 中直接返回实例
- **长期存在**：使用 `Get.put(viewModel, permanent: true)`

#### BasePage

**文件**: [base_page.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/viewmodels/base_page.dart)

所有页面的基类，提供统一的生命周期管理：

```dart
abstract class BasePageState<VM extends BaseViewModel, T extends BasePage<VM>> extends State<T> {
  PageInitState _pageInitState;     // loading / success / error
  VM createViewModel();             // 子类实现：创建 ViewModel
  Widget buildContent(BuildContext); // 子类实现：构建页面内容
  Future<void> onPageInit();        // 可选覆盖：页面初始化
  Future<void> fetchData();         // 可选覆盖：数据获取
  bool get enableNetworkMonitoring; // 是否启用网络监听自动重连
  bool get showErrorPageOnInitFailed; // 是否在初始化失败时显示错误页面
}
```

**生命周期**: `initState` → `createViewModel` → `_initializePage` → `onPageInit` → `buildContent`

**网络监听**: 当 `enableNetworkMonitoring = true` 时，BasePage 自动监听 `ConnectivityPlus` 网络状态变化，断网恢复后自动调用 `onNetworkReconnected()` → `fetchData()`。

**错误处理**: 初始化失败时显示错误页面（含重试按钮），ViewModel 错误通过 SnackBar 展示。

### 5.3 路由系统

**文件**: [app_routes.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/routes/app_routes.dart)

使用 **TypedGoRoute** 实现类型安全路由，路由定义模块化拆分：

| Part 文件 | 路由模块 |
|-----------|----------|
| `routes/core_routes.dart` | 核心路由（Dashboard、Settings、About） |
| `routes/collection_routes.dart` | 收藏夹路由 |
| `routes/game_library_routes.dart` | 游戏库路由 |
| `routes/manga_routes.dart` | Manga 路由 |
| `routes/novel_routes.dart` | 小说路由 |
| `routes/lan_transfer_routes.dart` | 局域网传输路由 |
| `routes/capture_routers.dart` | 抓包路由 |
| `routes/tools_routes.dart` | 工具路由 |
| `routes/business_routes.dart` | 业务路由 |
| `routes/demo_routes.dart` | 演示路由 |
| `routes/test_routes.dart` | 测试路由 |
| `routes/placeholder_routes.dart` | 占位路由 |

**ShellRoute 架构**: 使用 `AppShellRouteData` 作为 ShellRoute，所有侧边栏页面共享 `DesktopLayout` 布局（侧边栏 + 内容区）。

**完整路由表**:

| 路径 | 路由类 | 侧边栏分组 |
|------|--------|------------|
| `/dashboard` | `DashboardRoute` | core |
| `/capture` | `CaptureRoute` | core |
| `/collection/library` | `CollectionLibraryRoute` | collection |
| `/collection/picture` | `CollectionPictureRoute` | collection |
| `/game/home` | `GameHomeRoute` | game-library |
| `/game/library` | `GameLibraryRoute` | game-library |
| `/game/categories` | `GameCategoriesRoute` | game-library |
| `/game/stats` | `GameStatsRoute` | game-library |
| `/game/settings` | `GameSettingsRoute` | game-library |
| `/manga` | `MangaHomeRoute` | manga |
| `/manga/downloads` | `MangaDownloadsRoute` | manga |
| `/lan-transfer` | `LanTransferRoute` | tools |
| `/settings` | `SettingsRoute` | bottom |
| `/about` | `AboutRoute` | bottom |
| `/tools` | `ToolsRoute` | tools |
| `/sentry-log` | `SentryLogRoute` | tools |
| `/novel/reader` | `NovelReaderRoute` | — (非侧边栏) |
| `/manga/comic-detail` | `MangaComicDetailRoute` | — (非侧边栏) |
| `/manga/search` | `MangaSearchRoute` | — (非侧边栏) |
| `/manga/reader` | `MangaReaderRoute` | — (非侧边栏) |
| `/manga/history` | `MangaHistoryRoute` | — (非侧边栏) |
| `/game/detail` | `GameDetailRoute` | — (非侧边栏) |
| `/game/category-detail` | `GameCategoryDetailRoute` | — (非侧边栏) |
| `/lan-chat` | `LanChatRoute` | — (非侧边栏) |

**路由守卫**: 在 `redirect` 回调中通过 `RoleManager` 检查权限，无权限时重定向到 `/dashboard`。

**页面过渡动画**:
- `buildPage()` — 缩放 + 淡入（220ms / 180ms）
- `buildFadePage()` — 纯淡入（320ms / 260ms）
- iOS 使用 `CupertinoPage` 原生过渡

**AppRouteData 抽象类**: 每个路由数据类需实现 `title`、`sidebarIcon`、`sidebarLabel`、`sidebarOrder`、`sidebarGroupId`、`sidebarBadgeCount`、`permission` 等元数据，用于侧边栏自动生成和权限控制。

**侧边栏生成**: [app_sidebars.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/routes/app_sidebars.dart) 中 `buildSidebarGroupsFromRoutes()` 从路由元数据自动生成分组侧边栏，分组配置：

| 分组ID | 标题 | 排序 | 权限 |
|--------|------|------|------|
| core | — | 10 | viewDashboard |
| collection | 收藏夹 | 20 | accessCollection |
| game-library | 游戏 | 30 | accessGameLibrary |
| manga | — | 40 | accessManga |
| tools | 工具 | 45 | accessTools |
| bottom | — | 90 | accessSettings |

### 5.4 依赖注入

**文件**: [provider/main.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/provider/main.dart)

通过 `GetIt` 注册全局单例服务：

```dart
final getIt = GetIt.instance;

void getItInit() {
  getIt.registerLazySingleton<DesktopScreenProvider>(() => DesktopScreenProviderImpl());
  getIt.registerLazySingleton<OllamaService>(() => OllamaService());
  getIt.registerLazySingleton<OllamaSettingsService>(() => OllamaSettingsService(getIt.get<OllamaService>()));
  getIt.registerLazySingleton<LanTransferService>(() => LanTransferService());
  getIt.registerLazySingleton<NodeSettingsService>(() => NodeSettingsService());
  getIt.registerLazySingleton<MediaPrefsService>(() => MediaPrefsService());
  getIt.registerLazySingleton<MangaService>(() => MangaService());
  getIt.registerLazySingleton<MangaDownloadService>(() => MangaDownloadService());
  getIt.registerLazySingleton<GameLibraryMetadataApi>(() => GameLibraryMetadataApi());
  getIt.registerLazySingleton<GameLibraryService>(() => GameLibraryService(metadataApi: getIt<GameLibraryMetadataApi>()));
  getIt.registerLazySingleton<GameProcessTracker>(() => GameProcessTracker(service: getIt<GameLibraryService>()));
  getIt.registerLazySingleton<ExtractService>(() => ExtractService());
  getIt.registerLazySingleton<SentrySettingsService>(() => SentrySettingsService());
}
```

### 5.5 主题系统

**文件**: [app_theme.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/theme/app_theme.dart), [app_colors.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/theme/app_colors.dart)

#### AppTheme

静态工具类，核心功能：

| 功能 | 说明 |
|------|------|
| `buildCustomLight(accent, fontScale)` | 构建亮色主题 |
| `buildCustomDark(accent, fontScale)` | 构建暗色主题 |
| `loadSavedTheme()` | 从 SharedPreferences 加载主题配置 |
| `isLight(context)` | 判断当前是否亮色模式 |
| `sideBarTheme(context)` | 侧边栏渐变背景 |
| `resetMetrics()` | 重新计算所有 UI 尺寸 |

**响应式状态**:
- `themeModeObs` — 主题模式 (system/light/dark)
- `accentColorObs` — 强调色 (默认 `#A89FEE`)
- `fontScaleObs` — 字体缩放 (0.5~2.0)
- `metricsVersion` — 度量版本号，变化时触发全局重建

#### ThemeMetrics

集中管理所有 UI 尺寸度量，基于 ScreenUtil 响应式缩放：

| 类别 | 属性示例 |
|------|----------|
| 圆角 | `radius2` ~ `radius999` (2~999px) |
| 字体 | `fontSize9` ~ `fontSize72` |
| 间距 | `kSpace1` ~ `kSpace80` |
| 图标 | `iconSize12` ~ `iconSize96` |
| 阴影 | `boxShadow10` |
| 别名 | `paddingSmall/Medium/Large/XLarge`, `spacingSmall/Medium/Large/XLarge` |

#### 颜色体系

**LightColors** / **DarkColors** 完整颜色定义：

| 类别 | 亮色 | 暗色 |
|------|------|------|
| 主色 | `#A89FEE` (淡紫) | `#A89FEE` |
| 背景1 | `#FFFFFF` | `#1E1F1C` |
| 背景2 | `#F5F5F5` | `#383838` |
| 背景3 | `#F6F6F6` | `#2E2E2E` |
| 错误 | `#FF6C74` | `#FF6C74` |
| 成功 | `#4CAF50` | `#66BB6A` |
| 警告 | `#FF9800` | `#FFA726` |

### 5.6 权限系统

**文件**: [role_manager.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/routes/role_manager.dart)

基于角色的访问控制（RBAC）：

**角色枚举** (`UserRole`):

| 角色 | 权限范围 |
|------|----------|
| `creator` | 全部权限（16个） |
| `admin` | 除 accessCollection 外的全部权限 |
| `editor` | 仪表盘 + 内容编辑 + 小说/游戏/Manga |
| `guest` | 仅仪表盘 |
| `developer` | 全部权限 |

**权限枚举** (`Permission`):

| 权限 | 说明 |
|------|------|
| `viewDashboard` | 仪表盘 |
| `manageUsers` | 用户管理 |
| `editContent` | 内容编辑 |
| `accessSettings` | 设置 |
| `manageModules` | 模块管理 |
| `accessCapture` | 抓包代理 |
| `accessNovelLibrary` | 小说库 |
| `accessGameLibrary` | 游戏库 |
| `accessNovelReader` | 小说阅读器 |
| `accessThemePreview` | 主题预览 |
| `accessHttpBridgeTest` | HTTP桥接测试 |
| `accessWebSocketTest` | WebSocket测试 |
| `accessCollection` | 收藏夹 |
| `accessDemo` | 演示 |
| `accessManga` | Manga |
| `accessTools` | 工具 |
| `accessSentryLog` | Sentry日志 |

核心方法：`RoleManager.canAccess(permission)` / `RoleManager.setUserRole(role)`

### 5.7 工具模块

#### size_utils.dart

**文件**: [size_utils.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/utils/size_utils.dart)

响应式尺寸换算工具：

| 函数 | 说明 |
|------|------|
| `scaleW(w)` | 响应式宽度换算（基于 ScreenUtil + 自适应系数） |
| `scaleH(h)` | 响应式高度换算 |
| `scaleS(fontSize)` | 响应式字体换算（字体缩放系数与宽度不同） |
| `isPhone` | 屏幕宽度 < 600 |
| `isPad` | 非手机且屏幕 < 900 |
| `isFold` | 屏幕高宽比 < 1.2 |

**自适应缩放系数** (`_adaptiveScaleFactor`):
- 移动端: 0.94~1.0（根据屏幕宽度微调）
- 桌面端: 1.08~1.14（根据屏幕宽度微调）

**PlatformUtil**: `isDesktop` (macOS/Windows) / `isMobile` (iOS/Android)

#### logger.dart

**文件**: [logger.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/utils/logger.dart)

日志工具类 `Loggers`，支持：
- `info(message)` / `error(message, error, stackTrace)` / `d(message)` / `i(message)` / `e(message)`
- Loki 远程日志上报（5分钟退避机制）
- 日志保存到文件（Base64 编码可选）
- 设备唯一标识生成

#### format.dart

**文件**: [format.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/utils/format.dart)

- `formatFileSize(BigInt bytes)` — 文件大小格式化（B/KB/MB/GB/TB）

### 5.8 通用 Widget

#### BindingWidget

**文件**: [binding_widget.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/widgets/binding_widget.dart)

GetX 生命周期绑定 Widget，用于在使用 GoRouter 时保持 GetX 的依赖注入和生命周期管理。所有路由页面通过 `BindingWidget` 包裹。

#### common_widget.dart

**文件**: [common_widget.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/widgets/common_widget.dart)

- `appBarBackButton(context, onPressed, prevRoutePath)` — 返回按钮，优先 `context.pop()`，否则 `context.go(prevRoutePath)`

---

## 6. Rust 后端架构

### 6.1 主库与 FRB 桥接

**文件**: `rust/src/lib.rs` + `rust/src/api/`

主库通过 `flutter_rust_bridge` 将所有子模块 API 暴露给 Dart 层。`api/mod.rs` 转发 17 个子模块的 API：

| API 模块 | 对应子 crate | 功能 |
|----------|-------------|------|
| `capture` | capture_proxy | 抓包代理 |
| `extract` | extract_module | 解压工具 |
| `ffmpeg` | — | FFmpeg 封装 |
| `game_library` | game_library | 游戏库 |
| `http_bridge` | http_bridge | HTTP 桥接 |
| `lan_transfer` | lan_transfer | 局域网传输 |
| `logger` | — | 日志 |
| `media_collection` | media_collection | 媒体集合 |
| `module_downloader` | module_manager | 模块下载 |
| `module_loader` | module_manager | 模块加载 |
| `module_manager` | module_manager | 模块管理 |
| `novel_reader` | novel_reader | 小说阅读器 |
| `manga` | manga_module | Manga 漫画 |
| `sentry_log` | sentry_log | Sentry 日志 |
| `simple` | — | 简单工具 |
| `system_metrics` | — | 系统指标 |
| `websocket` | ws_module | WebSocket |

FRB 配置 (`flutter_rust_bridge.yaml`):
```yaml
rust_input: crate::api
rust_root: rust/
dart_output: lib/src/rust
```

### 6.2 子模块详解

#### db_module — 通用数据库模块

| 项目 | 说明 |
|------|------|
| 存储 | redb 嵌入式 KV 数据库 |
| 加密 | 可选 AES-GCM |
| 依赖 | 无（基础模块） |
| crate-type | staticlib + rlib |

核心 API：`db_init` / `db_register_table` / `db_set` / `db_get` / `db_delete` / `db_list_keys` / `db_list_all` / `db_batch_set` / `db_count` / `db_clear_table`

源文件结构：
- `lib.rs` — 模块导出
- `api.rs` — 公共 API
- `storage.rs` — 存储引擎实现
- `types.rs` — 数据类型定义

#### media_collection — 媒体集合管理

| 项目 | 说明 |
|------|------|
| 功能 | 图片/视频/音频集合管理、缩略图生成、目录扫描 |
| 缩略图引擎 | ffmpeg + image crate 双引擎（ffmpeg 优先，image 回退） |
| 缓存 | 内存缓存 + 空闲自动释放 |
| 依赖 | db_module |
| crate-type | staticlib + rlib |

核心 Dart 类型（FRB 生成）：
- `MediaCollection` — 媒体集合（id, title, folderPath, folderId, coverPath, itemCount, createdAt, updatedAt）
- `MediaItem` — 媒体项（id, collectionId, title, filePath, kind, fileSize, modifiedAt, width, height, durationMs, order）
- `MediaFolder` — 文件夹（id, name, createdAt, order, parentId）
- `CollectionStats` — 集合统计（collectionId, totalSize, filePaths）
- `MediaKind` — 媒体类型枚举（image, video, audio）

核心 API：`getAllMediaCollections` / `importMediaFolder` / `scanMediaFolders` / `ensureCoverThumbnail` / `getAllCollectionStats` / 文件夹CRUD / 集合重命名/移动/删除

#### novel_reader — 小说阅读器

| 项目 | 说明 |
|------|------|
| 格式 | TXT / EPUB |
| 功能 | 书籍 CRUD、文件夹管理、全文搜索、阅读进度、关键词自动打标签 |
| EPUB | 按需加载章节，封面提取与压缩 |
| 编码检测 | chardetng + encoding_rs 自动检测与转换 |
| 并行 | rayon 并行扫描与搜索 |
| 依赖 | db_module + http_bridge |
| crate-type | staticlib + rlib |

核心 Dart 类型：
- `NovelMetadata` — 书籍元数据（id, title, author, filePath, format, fileSize, progress, isFavorite, tags, notes, coverPath, folderId, customOrder）
- `NovelContent` — 书籍内容（novelId, chapters）
- `NovelChapter` — 章节（id, title, index, content）
- `NovelFolder` — 文件夹（id, name, createdAt, order, parentId）
- `SearchMatch` — 搜索匹配（chapterIndex, chapterTitle, position, snippet）
- `ScanBatchResult` — 批量扫描结果（novels, completed, total, isFinished）
- `SearchBatchResult` — 批量搜索结果
- `KeywordRuleInput` — 关键词规则（keyword, tag）
- `KeywordApplyBatchResult` — 关键词应用结果
- `NovelFormat` — 格式枚举（txt, epub）

核心 API：`scanNovelsFolder` / `addNovel` / `getNovelContent` / `getChapterContent` / `searchInNovel` / `searchInAllNovelsBatched` / `applyKeywordRulesToAllNovelsBatch` / `updateReadingProgress` / 文件夹CRUD / 书籍排序/重命名/收藏/标签/封面/作者

#### game_library — 游戏库管理

| 项目 | 说明 |
|------|------|
| 数据库 | rusqlite (SQLite, bundled) |
| 功能 | 游戏 CRUD、分类、时长追踪、统计、目录扫描、启动游戏 |
| 元数据 | 萌娘百科 / 2DFan 网页抓取 (reqwest + scraper) |
| 并发 | parking_lot 锁 |
| 依赖 | 无（自建数据库） |
| crate-type | staticlib + rlib |

核心 API：`gameLibraryInit` / `gameLibraryGetGamesJson` / `gameLibraryAddGameJson` / `gameLibraryUpdateGameJson` / `gameLibraryDeleteGame` / `gameLibraryGetCategoriesJson` / `gameLibraryAddGameToCategory` / `gameLibraryToggleFavorite` / `gameLibraryAddPlaySessionJson` / `gameLibraryGetStatsJson` / `gameLibraryLaunchGame` / `gameLibraryScanDirectoryJson` / `gameLibraryFetchMoegirl` / `gameLibrarySearch2DfanSubject` / `gameLibraryDownloadFile` / 设置CRUD

#### extract_module — 解压工具

| 项目 | 说明 |
|------|------|
| 格式 | 7z (sevenz-rust2) / zip / tar / gz (flate2) / bz2 / xz (liblzma) |
| 功能 | 批量解压、进度追踪、取消操作、密码管理 |
| 依赖 | db_module |
| crate-type | staticlib + rlib |

核心 API：`extractInitPasswordTable` / `extractListPasswordsJson` / `extractAddPassword` / `extractRemovePassword` / `extractUpdatePasswordRemark` / `extractScanArchivesJson` / `extractGetProgressJson` / `extractGetResultJson` / `extractStart` / `extractCancel` / `extractFormatFileSize`

#### http_bridge — HTTP 桥接

| 项目 | 说明 |
|------|------|
| 功能 | 为移动端提供 HTTP 接口，转发到 FRB 函数 |
| 机制 | 处理器注册（module + function → handler） |
| 服务器 | hyper HTTP 服务器 |
| 依赖 | 无 |
| crate-type | staticlib + rlib |

核心 API：`initHttpBridge` / `getRegisteredHandlers` / `callHandler` / `startNodeServer` / `stopNodeServer` / `isNodeServerRunning`

源文件结构：
- `lib.rs` — 模块导出 + 全局状态管理
- `server.rs` — HTTP 服务器实现
- `client.rs` — HTTP 客户端
- `types.rs` — 类型定义

#### lan_transfer — 局域网传输

| 项目 | 说明 |
|------|------|
| 发现 | mDNS |
| 传输 | TCP |
| 功能 | 文件/文本传输、信任设备管理、传输历史 |
| 依赖 | 无 |
| crate-type | staticlib + rlib |

核心 API：`lanTransferInit` / `lanTransferStart` / `lanTransferStop` / `lanTransferGetLocalDevice` / `lanTransferGetDevices` / `lanTransferSendText` / `lanTransferSendFile` / `lanTransferAccept` / `lanTransferReject` / `lanTransferCancel` / `lanTransferGetTransfers` / `lanTransferAddTrusted` / `lanTransferRemoveTrusted` / `lanTransferIsTrusted` / `lanTransferGetTrustedDevices`

源文件结构：
- `lib.rs` — 模块导出
- `api.rs` — 公共 API
- `discovery.rs` — mDNS 设备发现

#### manga_module — Manga 漫画平台

| 项目 | 说明 |
|------|------|
| 功能 | API 客户端、认证、浏览/搜索、收藏/点赞/评论、多分流模式 |
| TLS | hyper-rustls + rustls |
| 签名 | HMAC-SHA256 |
| 代理 | HTTP/SOCKS5/CDN 分流/反代/PC 中转 |
| 依赖 | 无 |
| crate-type | staticlib + rlib |

分流模式（`mangaSetChannel`）：
| mode | 说明 |
|------|------|
| 0 | 标准直连 |
| 2 | 分流2 (IP: 104.21.91.145) |
| 3 | 分流3 (IP: 188.114.98.153) |
| 4 | CDN分流 (自定义IP，默认 104.18.227.172) |
| 5 | JP反代 (https://bika-api.jpacg.cc) |
| 6 | US反代 (https://bika2-api.jpacg.cc) |

核心 API：`mangaInit` / `mangaLogin` / `mangaSetProxy` / `mangaSetToken` / `mangaSetChannel` / `mangaSetImageServer` / `mangaTestChannel` / `mangaGetCollections` / `mangaGetRandomComics` / `mangaGetCategories` / `mangaSearchComics` / `mangaGetComicDetail` / `mangaGetComicEps` / `mangaGetEpsPages` / `mangaGetFavourites` / `mangaToggleFavourite` / `mangaToggleLike` / `mangaGetComments` / `mangaSendComment` / `mangaBuildImageUrl` / `mangaFetchImage` / `mangaInitHistory` / `mangaLoadHistory` / `mangaSaveHistoryRaw` / `mangaClearHistory`

#### sentry_log — Sentry 日志收集

| 项目 | 说明 |
|------|------|
| 存储 | redb |
| 功能 | 兼容 Sentry SDK 协议、事件存储/查询/统计/导出 |
| 依赖 | 无（自建数据库） |
| crate-type | staticlib + rlib |

核心 API：`sentryLogInit` / `sentryLogQuery` / `sentryLogGetEvent` / `sentryLogDeleteEvent` / `sentryLogDeleteEvents` / `sentryLogGetProjects` / `sentryLogUpdateProjectName` / `sentryLogGetStats` / `sentryLogExportJson` / `sentryLogClearProjectEvents`

#### ws_module — WebSocket

| 项目 | 说明 |
|------|------|
| 桌面端 | WebSocket 服务器 |
| 移动端 | WebSocket 客户端 |
| 条件编译 | `#[cfg(desktop)]` / `#[cfg(mobile)]` |
| 依赖 | 无 |

核心 Dart 类型：
- `WsClient` / `WsServer` / `WsMessage` / `WsConnectionState` (均为 RustOpaque)

核心 API：`wsClientNew` / `wsClientConnect` / `wsClientDisconnect` / `wsClientSendText` / `wsClientSendBinary` / `wsClientIsConnected` / `wsClientGetState` / `wsClientReceiveMessage` / `wsServerNew` / `wsServerStart` / `wsServerStop` / `wsServerBroadcast` / `wsServerGetClientCount`

#### module_manager — 模块管理

| 项目 | 说明 |
|------|------|
| 功能 | 版本管理、MD5 校验、自动更新、动态库加载/卸载/重载 |
| 动态加载 | libloading |
| 依赖 | 无 |

核心 Dart 类型：
- `ModuleManager` / `ModuleLoader` (RustOpaque)
- `AvailableModuleInfo` — 可用模块（name, version, moduleType, description）
- `InstalledModule` — 已安装模块（moduleName, version, isLocked, filePath, moduleType, fileSize, installedAt）
- `ModuleType` — 模块类型枚举（dynamicLibrary, executable）

核心 API：`createModuleManager` / `moduleGetAvailable` / `moduleCheckUpdate` / `moduleInstall` / `moduleUninstall` / `moduleReinstall` / `moduleListVersions` / `moduleListAll` / `createModuleLoader` / `moduleLoad` / `moduleUnload` / `moduleReload` / `moduleIsLoaded` / `moduleListLoaded`

#### capture_proxy — 抓包代理

| 项目 | 说明 |
|------|------|
| 类型 | cdylib 动态库（运行时加载，不静态链接） |
| 功能 | HTTP/HTTPS MITM 代理、CA 证书管理、流量捕获 |
| 依赖 | 无 |
| crate-type | cdylib（独立 Cargo.lock） |

核心 Dart 类型：
- `CaptureStats` — 捕获统计（total, videos, images, json, javascript）

核心 API：`startCaptureProxy` / `stopCaptureProxy` / `isProxyRunning` / `getCapturedVideos` / `getCapturedImages` / `getCapturedJson` / `getCapturedJavascript` / `clearCapturedData` / `getCaptureStats` / `installCaCertificate` / `isCaCertificateInstalled` / `isRunningAsAdministrator` / `initializeLogger` / `getLoggerDirectory` / `cleanupLoggerOldFiles` / `writeLogInfo` / `writeLogError`

源文件结构：
- `lib.rs` — 模块导出
- `capture.rs` — 捕获逻辑
- `cert.rs` — CA 证书管理
- `ffi.rs` — FFI 接口
- `mitm.rs` — MITM 代理实现
- `server.rs` — 代理服务器
- `system_proxy.rs` — 系统代理设置

### 6.3 Node Server

**文件**: `rust/src/node_server/`

PC 端运行的 HTTP 服务器，为移动端提供中转服务：

**文件结构**:
| 文件 | 说明 |
|------|------|
| `mod.rs` | 入口，服务器生命周期管理 |
| `router.rs` | 路由注册与分发 |
| `media_handler.rs` | 媒体文件流式分发（图片缩放、Range 请求） |
| `handlers.rs` | action 分发（调用 media_collection / novel_reader 等 FFI 函数） |

**路由表**:

| 路由 | 功能 |
|------|------|
| `POST /node/call` | 动作分发（调用 media_collection / novel_reader 等 FFI 函数） |
| `GET /node/media` | 媒体文件服务（图片缩放、Range 请求流式分发） |
| `POST /node/upload` | 文件上传 |
| `GET /health` | 健康检查 |
| `GET /manga/ping` | Manga 中转连通性检测 |
| `POST /manga/api` | Manga API 中转 |
| `GET /manga/img` | Manga 图片中转 |
| `GET /manga/token` | Manga Token 中转 |
| `POST /api/{id}/store` | Sentry 兼容端点 |
| `POST /api/{id}/envelope` | Sentry Envelope 端点 |
| `GET /sentry/logs` | Sentry 日志查询 |

**FFI 入口**: `rust/src/api/http_bridge.rs` 暴露 `startNodeServer` / `stopNodeServer` / `isNodeServerRunning`

---

## 7. 核心业务模块

### 7.1 媒体集合（Media Collection）

**Flutter 页面**: `pages/collection/picture/` + `pages/collection/library/`

**数据流**:
```
用户操作 → MediaLibraryViewModel → Rust FFI → media_collection crate → redb
```

**ViewModel**: `MediaLibraryViewModel` + `MediaLibraryVmCollections` + `MediaLibraryVmRemote` + `MediaLibraryVmSmartFolders`

**关键功能**:
- 目录扫描导入媒体文件
- 缩略图生成（ffmpeg / image 双引擎，ffmpeg 优先支持 HEIC/AVIF）
- 文件夹分组与层级管理（支持嵌套文件夹）
- 智能文件夹（规则匹配）
- 远程节点媒体访问
- 图片/视频预览与查看器
- 集合统计（`getAllCollectionStats` 批量获取大小与文件列表）
- 瀑布流网格布局（`MasonryMediaGrid`）

**页面组件**:
| 组件 | 说明 |
|------|------|
| `MasonryMediaGrid` | 瀑布流网格 |
| `MediaBrowseGrid` | 浏览网格 |
| `MediaCollectionCard` | 集合卡片 |
| `MediaCollectionDetail` | 集合详情 |
| `MediaFolderCard` | 文件夹卡片 |
| `MediaItemTile` | 媒体项 |
| `MediaViewerPage` | 媒体查看器 |
| `SmartFolder` / `SmartFolderCard` | 智能文件夹 |
| `LibraryActionBar` | 操作栏 |

### 7.2 小说阅读器（Novel Reader）

**Flutter 页面**: `pages/novel_library/` + `pages/novel_reader/`

**数据流**:
```
用户操作 → NovelLibraryViewModel / NovelReaderViewModel → Rust FFI → novel_reader crate → redb
```

**关键功能**:
- TXT/EPUB 文件扫描与导入（支持批量扫描 `scanNovelsFolderBatched`）
- 章节自动解析（TXT 按正则分割，EPUB 按 spine 解析）
- 阅读进度持久化
- 全文搜索（支持批量搜索与取消 `searchInAllNovelsBatched`）
- 关键词自动打标签（`applyKeywordRulesToAllNovelsBatch`）
- AI 翻译（Ollama）
- 翻译高亮与配置面板
- 封面更新与压缩
- 书籍排序、收藏、标签、备注

**阅读器组件**:
| 组件 | 说明 |
|------|------|
| `ChapterList` | 章节列表 |
| `ReaderContent` | 阅读内容 |
| `ReaderHighlightUtils` | 高亮工具 |
| `ReaderToolbar` | 阅读工具栏 |
| `TranslationPanel` | 翻译面板 |
| `TranslationConfigPanel` | 翻译配置面板 |

### 7.3 游戏库（Game Library）

**Flutter 页面**: `pages/game_library/` (home / library / detail / categories / stats / settings)

**数据流**:
```
用户操作 → GameLibrary*ViewModel → GameLibraryService → Rust FFI → game_library crate → SQLite
```

**ViewModel 矩阵**:

| ViewModel | 职责 |
|-----------|------|
| `GameLibraryHomeViewModel` | 首页数据加载、游戏启动 |
| `GameLibraryLibraryViewModel` | 游戏列表 CRUD、搜索过滤、批量导入、元数据刷新 |
| `GameLibraryDetailViewModel` | 游戏详情、元数据编辑 |
| `GameLibraryCategoriesViewModel` | 分类管理 |
| `GameLibraryStatsViewModel` | 统计数据 |
| `GameLibrarySettingsViewModel` | 设置管理 |

**GameProcessTracker**: 追踪游戏进程生命周期，启动游戏 → 监听 PID 退出 → 记录游玩时长

**GameLibraryMetadataApi**: 聚合萌娘百科 / 2DFan 两个数据源，网页抓取

**核心 Rust API**:
- `gameLibraryLaunchGame` — 启动游戏（返回 PID）
- `gameLibraryScanDirectoryJson` — 目录扫描
- `gameLibraryFetchMoegirl` — 萌娘百科元数据
- `gameLibrarySearch2DfanSubject` / `gameLibraryFetch2DfanDownloadPath` / `gameLibraryFetch2DfanDownloadInfo` — 2DFan 数据
- `gameLibraryGetStatsJson` — 统计数据（按时间范围）
- `gameLibraryGetHomePageDataJson` — 首页数据

### 7.4 Manga 漫画平台

**Flutter 页面**: `pages/manga/` (home / comic_detail / search / reader / downloads / favourites / history)

**数据流**:
```
用户操作 → Manga*ViewModel → MangaService / MangaDownloadService → Rust FFI → manga_module
```

**ViewModel 矩阵**:

| ViewModel | 职责 |
|-----------|------|
| `MangaHomeViewModel` | 首页推荐/分类/排行榜 |
| `MangaComicDetailViewModel` | 漫画详情/章节 |
| `MangaSearchViewModel` | 搜索 |
| `MangaReaderViewModel` | 阅读器 |
| `MangaDownloadsViewModel` | 下载管理 |
| `MangaFavouritesViewModel` | 收藏管理 |
| `MangaHistoryViewModel` | 浏览历史 |

**分流模式** (7 种): 直连 / 分流2 / 分流3 / CDN / JP反代 / US反代 / PC中转

**下载服务**: 队列管理、进度追踪、离线阅读路径查询

**页面组件**:
| 组件 | 说明 |
|------|------|
| `MangaComicCard` | 漫画卡片 |
| `MangaImageView` | 图片查看 |
| `MangaLoginDialog` | 登录对话框 |
| `MangaBlockWordsDialog` | 屏蔽词对话框 |

### 7.5 局域网传输（LAN Transfer）

**Flutter 页面**: `pages/lan_transfer/` (lan_transfer_screen / lan_chat_screen)

**数据流**:
```
用户操作 → LanTransferViewModel → LanTransferService → Rust FFI → lan_transfer crate
```

**关键功能**:
- mDNS 设备发现
- 文件/文本传输
- 信任设备管理（预加载信任列表避免竞态）
- 传输历史
- 聊天功能

**页面组件**:
| 组件 | 说明 |
|------|------|
| `DeviceList` | 设备列表 |
| `PendingRequests` | 待处理请求 |
| `ScanningAnimation` | 扫描动画 |
| `TransferActions` | 传输操作 |
| `TransferChat` | 聊天界面 |
| `TransferHistory` | 传输历史 |

### 7.6 解压工具（Extract）

**Flutter 页面**: `pages/tools/`

**数据流**:
```
用户操作 → ExtractService → Rust FFI → extract_module crate → db_module (密码库)
```

**关键功能**:
- 多格式解压（7z/zip/tar.gz/bz2/xz/lzma/zstd）
- 批量解压与进度追踪
- 密码库管理（持久化到 redb）
- 4 种输出模式
- 200ms 进度轮询

**页面组件**:
| 组件 | 说明 |
|------|------|
| `ExtractCard` | 解压卡片 |
| `ExtractParamsDialog` | 参数对话框 |
| `ExtractProgressDialog` | 进度对话框 |
| `ExtractResultDialog` | 结果对话框 |
| `SentryLogCard` | Sentry 日志卡片 |

### 7.7 Sentry 日志收集

**Flutter 页面**: `pages/sentry_log/`

**数据流**:
```
Sentry SDK → Node Server / 本地 → sentry_log crate → redb
用户操作 → SentryLogViewModel → SentrySettingsService → Rust FFI / 远程 API
```

**关键功能**:
- 兼容 Sentry SDK 协议（store/envelope 端点）
- 事件查询/统计/导出
- 项目管理
- 本地/远程节点切换

**页面组件**:
| 组件 | 说明 |
|------|------|
| `SentryLogEventDetail` | 事件详情 |
| `SentryLogFilterBar` | 过滤栏 |
| `SentryLogList` | 日志列表 |
| `SentryLogStatsPanel` | 统计面板 |

### 7.8 抓包代理（Capture Proxy）

**Flutter 页面**: `pages/backup/capture_screen/`

**数据流**:
```
HTTP 流量 → capture_proxy (MITM) → CapturedItem
用户操作 → CaptureScreenViewModel → Rust FFI → capture_proxy (动态加载)
```

**关键功能**:
- HTTP/HTTPS 代理服务器
- MITM 拦截与流量捕获
- CA 证书动态生成与管理
- 系统代理设置
- 捕获统计（视频/图片/JSON/JS 分类计数）

**页面组件**:
| 组件 | 说明 |
|------|------|
| `AvailableVideoCard` | 可用视频卡片 |
| `ControlPanel` | 控制面板 |
| `RecordingTaskCard` | 录制任务卡片 |
| `StatWidgets` | 统计组件 |
| `StyledTabBar` | 样式化标签栏 |

---

## 8. 服务层详解

| 服务类 | 注册方式 | 职责 |
|--------|----------|------|
| `DesktopScreenProvider` / `DesktopScreenProviderImpl` | GetIt | 屏幕尺寸与布局信息提供、ScreenChrome 栈管理、移动端沉浸模式 |
| `OllamaService` | GetIt | Ollama AI 模型调用（多服务器轮询、流式生成、翻译） |
| `OllamaSettingsService` | GetIt | Ollama 配置持久化（依赖 OllamaService） |
| `LanTransferService` | GetIt | 局域网设备发现与文件传输 |
| `NodeSettingsService` | GetIt | 节点服务器管理、远程节点 CRUD、熔断机制、流量统计 |
| `MediaPrefsService` | GetIt | 媒体偏好设置（缩略图质量、并发量、缓存管理） |
| `MangaService` | GetIt | Manga 完整业务（认证、浏览、搜索、下载、收藏） |
| `MangaDownloadService` | GetIt | Manga 下载管理（队列、进度、离线路径） |
| `GameLibraryMetadataApi` | GetIt | 游戏元数据搜索（萌娘百科/2DFan 聚合） |
| `GameLibraryService` | GetIt | 游戏库数据管理（依赖 MetadataApi） |
| `GameProcessTracker` | GetIt | 游戏进程追踪（依赖 GameLibraryService） |
| `ExtractService` | GetIt | 压缩包解压管理 |
| `SentrySettingsService` | GetIt | Sentry 日志设置与远程 API |
| `SystemTrayService` | GetX (Get.putAsync) | 系统托盘管理（桌面端） |
| `WindowPositionService` | GetX | 窗口位置持久化 |
| `WebSocketManager` | GetIt | WebSocket 服务器/客户端管理 |
| `AppInfoService` | 静态 | 应用版本信息 |
| `VideoThumbQueue` | — | 视频缩略图生成队列 |

### 服务依赖关系

```
GameProcessTracker ──→ GameLibraryService ──→ GameLibraryMetadataApi
OllamaSettingsService ──→ OllamaService
NodeSettingsService ──→ Rust FFI (node_server)
MangaDownloadService ──→ MangaService ──→ Rust FFI (manga_module)
ExtractService ──→ Rust FFI (extract_module)
LanTransferService ──→ Rust FFI (lan_transfer)
```

### DesktopScreenProvider 详解

**抽象类**: `DesktopScreenProvider` (screen_provider.dart)
**实现类**: `DesktopScreenProviderImpl` (screen_provider_impl.dart)

核心功能：
- 窗口尺寸管理（`width`, `height`, `size`）
- 桌面/移动端模式判断（`isDesktop`, `isMobile`，基于窗口宽度 600px 阈值）
- ScreenChrome 栈管理（支持多页面叠加 Chrome 配置）
- 移动端沉浸模式（`mobileImmersiveMode`）
- 侧边栏展开比例（`sidebarExpandScale`）
- 全局背景图路径（`globalBackgroundPath`）

### ScreenChromeData 详解

**文件**: [screen_chrome.dart](file:///Users/shilaimu/research/Software/slime_works/lib/core/provider/screen_chrome.dart)

页面级顶部/底部栏的统一配置：

| 属性 | 类型 | 说明 |
|------|------|------|
| `title` | `String?` | 标题文本 |
| `titleWidget` | `Widget?` | 自定义标题 Widget |
| `leading` | `Widget?` | 前导 Widget |
| `actions` | `List<Widget>` | 操作按钮列表 |
| `toolbar` | `Widget?` | 工具栏 |
| `toolbarHeight` | `double?` | 工具栏高度 |
| `bottomBar` | `Widget?` | 底部栏 |
| `bottomBarHeight` | `double?` | 底部栏高度 |
| `enableMobileImmersiveMode` | `bool` | 启用移动端沉浸模式 |
| `mobileBodyHandlesInsets` | `bool` | 移动端 Body 处理 Insets |
| `mobileImmersivePadding` | `EdgeInsets` | 沉浸模式内边距 |
| `mobileAppBarColor` | `Color?` | 移动端 AppBar 背景色 |

---

## 9. ViewModel 层详解

| ViewModel | 对应页面 | 核心职责 |
|-----------|----------|----------|
| `MediaLibraryViewModel` | 收藏夹-图片 | 媒体库浏览、搜索、筛选 |
| `MediaLibraryVmCollections` | 收藏夹-图片 | 集合管理 |
| `MediaLibraryVmRemote` | 收藏夹-图片 | 远程节点媒体访问 |
| `MediaLibraryVmSmartFolders` | 收藏夹-图片 | 智能文件夹 |
| `NovelLibraryViewModel` | 小说库 | 小说列表、搜索、分类 |
| `NovelLibraryViewModelActions` | 小说库 | 小说操作（导入/删除/移动） |
| `NovelLibraryViewModelNovel` | 小说库 | 小说数据查询 |
| `NovelReaderViewModel` | 小说阅读器 | 阅读进度、章节导航、翻译 |
| `GameLibraryHomeViewModel` | 游戏库首页 | 首页数据、游戏启动 |
| `GameLibraryLibraryViewModel` | 游戏库列表 | 游戏 CRUD、搜索、批量导入 |
| `GameLibraryDetailViewModel` | 游戏详情 | 详情编辑、元数据 |
| `GameLibraryCategoriesViewModel` | 游戏分类 | 分类管理 |
| `GameLibraryStatsViewModel` | 游戏统计 | 统计数据 |
| `GameLibrarySettingsViewModel` | 游戏设置 | 设置管理 |
| `MangaHomeViewModel` | Manga 首页 | 推荐/分类/排行榜 |
| `MangaComicDetailViewModel` | Manga 详情 | 漫画详情/章节 |
| `MangaSearchViewModel` | Manga 搜索 | 搜索 |
| `MangaReaderViewModel` | Manga 阅读器 | 阅读器 |
| `MangaDownloadsViewModel` | Manga 下载 | 下载管理 |
| `MangaFavouritesViewModel` | Manga 收藏 | 收藏管理 |
| `MangaHistoryViewModel` | Manga 历史 | 浏览历史 |
| `LanTransferViewModel` | 局域网传输 | 设备发现、传输管理 |
| `CaptureScreenViewModel` | 抓包录屏 | 代理控制、流量展示 |
| `SentryLogViewModel` | Sentry 日志 | 日志查询、过滤、统计 |
| `DemoScreenViewModel` | 演示 | 演示功能 |

---

## 10. 通用组件库

### 窗口组件 (`components/window/`)

| 组件 | 职责 |
|------|------|
| `DesktopScaffold` | 桌面端主框架，集成窗口管理器初始化 |
| `DesktopLayout` | 桌面布局（侧边栏 + 内容区），ShellRoute 使用 |
| `DesktopHead` | 桌面端标题栏（macOS 红绿灯 / Windows 最小化最大化关闭） |
| `CollapsibleSidebar` | 可折叠侧边栏，支持分组、徽章、权限过滤、折叠/展开动画 |
| `ScreenChrome` | 屏幕装饰器，向 DesktopScreenProvider 注册当前页面的 Chrome |
| `ScreenTopBar` | 顶部栏 |

### 按钮组件 (`components/buttons/`)

| 组件 | 职责 |
|------|------|
| `AnimatedButton` | 动画按钮，点击反馈与过渡动画 |
| `SvgButton` | SVG 图标按钮 |
| `CuePressable` | 基于 cue 包的可按压组件 |

### 对话框组件 (`components/dialogs/`)

| 组件 | 职责 |
|------|------|
| `ConfirmDialog` | 确认对话框 |
| `NodeDirectoryPicker` | 节点目录选择器 |

### 下拉菜单组件 (`components/dropdown/`)

| 组件 | 职责 |
|------|------|
| `GooeyDropdown` | 自定义 Gooey 视觉效果下拉菜单 |
| `GooeyDropdownShader` | Gooey 着色器（使用 `shaders/gooey.frag`） |

### 动画组件 (`components/animations/`)

| 组件 | 职责 |
|------|------|
| `StateTransitionAnimation` | 状态过渡动画 |

### 设置页面标签 (`pages/settings/components/`)

| 组件 | 说明 |
|------|------|
| `ExtractSettingsTab` | 解压设置 |
| `GameSettingsTab` | 游戏库设置 |
| `MediaSettingsTab` | 媒体设置 |
| `NodeSettingsTab` | 节点设置 |
| `OllamaSettingsTab` | Ollama AI 设置 |
| `MangaSettingsTab` | Manga 设置 |
| `SentrySettingsTab` | Sentry 设置 |
| `ThemeSettingsTab` | 主题设置 |

---

## 11. 依赖关系图

### Rust 模块依赖

```
                    ┌──────────────────────┐
                    │  rust_lib_slime_works │ (主库)
                    │  + node_server        │
                    └──────────┬───────────┘
                               │
    ┌──────────┬───────────┬───┴───┬──────────┬──────────┬──────────┐
    ▼          ▼           ▼       ▼          ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│db_     │ │media_  │ │novel_  │ │game_   │ │extract_│ │sentry_ │ │manga_ │
│module  │ │collect.│ │reader  │ │library │ │module  │ │log     │ │module  │
└────────┘ └───┬────┘ └──┬─────┘ └────────┘ └───┬────┘ └────────┘ └────────┘
               │         │                      │
         依赖──┘    依赖──┤                依赖──┘
                         │
                   ┌─────┴──────┐
                   │http_bridge │
                   └────────────┘

┌──────────┐ ┌──────────────┐ ┌──────────────┐
│ws_module │ │module_manager│ │capture_proxy │ ← cdylib 动态加载
└──────────┘ └──────────────┘ └──────────────┘
```

**依赖层次**:

| 层级 | 模块 | 说明 |
|------|------|------|
| 基础层 | db_module, http_bridge, lan_transfer, module_manager, ws_module, manga_module, sentry_log, game_library, capture_proxy | 无内部依赖 |
| 业务层 | media_collection → db_module; novel_reader → db_module + http_bridge; extract_module → db_module | 依赖基础层 |
| 聚合层 | rust_lib_slime_works | 依赖所有子模块 |

**各模块关键外部依赖**:

| 模块 | 关键外部依赖 |
|------|-------------|
| db_module | redb |
| media_collection | db_module, walkdir, image |
| novel_reader | db_module, http_bridge, epub, zip, image, rayon, encoding_rs, chardetng |
| game_library | rusqlite (bundled), reqwest, scraper |
| extract_module | db_module, sevenz-rust2, zip, tar, flate2, bzip2, liblzma |
| http_bridge | hyper |
| lan_transfer | (内部实现 mDNS + TCP) |
| manga_module | reqwest, hyper-rustls, hmac, sha2 |
| sentry_log | redb |
| ws_module | (条件编译) |
| module_manager | libloading |
| capture_proxy | (独立 cdylib) |

### Flutter 层依赖

```
Pages → ViewModels → Services → Rust FFI
  │         │           │
  │         └── GetX (UI状态)
  │                     └── GetIt (全局单例)
  └── Components
  └── Core (路由/主题/权限/工具)
```

---

## 12. 构建与运行

### 环境要求

| 工具 | 版本 |
|------|------|
| Rust | 1.92.0+ |
| Flutter | 3.41.0-0.0.pre |
| Dart | 3.11.0 |
| macOS | 26.2+ (darwin-arm64) |

### 开发运行

```bash
# 1. 生成 FRB 绑定代码
flutter_rust_bridge_codegen generate

# 2. 生成 FlutterGen 资源引用
flutter pub run build_runner build

# 3. 运行应用（macOS）
flutter run -d macos

# 4. Rust 开发热重载（监听 rs 变更自动重启）
cd rust && cargo watch -s "cargo build && flutter run -d macos"
```

### 构建发布

```bash
# macOS
flutter build macos --release

# iOS
flutter build ipa
cargo build --target aarch64-apple-ios-sim

# Android
cargo build --target aarch64-linux-android
flutter build apk
```

### 代码生成

```bash
# FlutterGen（资源引用）
flutter pub run build_runner build
flutter pub run build_runner watch
flutter pub run build_runner clean && flutter pub run build_runner build --delete-conflicting-outputs

# JSON 序列化
flutter packages pub run build_runner build --delete-conflicting-outputs

# FRB 绑定
flutter_rust_bridge_codegen generate
```

---

## 13. 测试

### Flutter 单元测试

```bash
flutter test                                    # 全部
flutter test test/smart_folder_test.dart        # 智能文件夹 (21 用例)
flutter test test/dashboard_test.dart           # 仪表盘 (13 用例)
flutter test integration_test/simple_test.dart  # 集成测试
flutter test --coverage                         # 覆盖率
```

### Rust 单元测试

```bash
cd rust && cargo test --workspace               # 全部
cd rust/media_collection && cargo test          # 媒体集合 (28 用例)
cd rust/lan_transfer && cargo test              # 局域网传输 (6 用例)
```

### CI 一键执行

```bash
flutter test && cd rust && cargo test --workspace
```

---

## 14. 发布

### Android → 蒲公英

```bash
python3 scripts/auto.py -desc="1. 新增xxx功能\n2. 修复xxx问题"
```

### iOS → 蒲公英

```bash
python3 scripts/publish_ios.py -desc="1. 新功能\n2. Bug 修复"
python3 scripts/publish_ios.py --ipa-only -desc="热修复"
python3 scripts/publish_ios.py --use-xcodebuild --team-id XXXXXXXXXX -desc="正式版"
python3 scripts/publish_ios.py --build-only     # 仅构建不上传
```

### Windows → NSIS 安装包

```bash
# 见 installer/ 目录
# installer.nsi + build.bat
```

---

## 15. 开发规范

### 页面命名规范

- 页面文件以 `_screen.dart` 结尾，class 使用 `Screen` 结尾并继承 `BasePage` 类
- 页面目录位于 `lib/pages/` 下，如果一个页面包含多个子页面则创建主页面名的文件夹
- 页面组件位于 `lib/pages/{pageName}/components/` 中，页面需细致拆分为组件，而非全写在一个文件中

### 响应式设计规范

| 条件 | 模式 |
|------|------|
| `Platform.isMacOS \|\| Platform.isWindows` | 桌面端（侧边栏 + 顶部工具栏） |
| `Platform.isAndroid \|\| Platform.isIOS` | 移动端（底部导航 + 顶部 Chrome） |
| 桌面端但窗口宽度 ≤ 600 | 强制切换为移动端模式 |

判断方式：
```dart
import 'package:slime_works/core/utils/size_utils.dart';
bool mobile = SizeUtils.isMobile;   // Platform.isAndroid || Platform.isIOS
bool desktop = SizeUtils.isDesktop; // Platform.isMacOS  || Platform.isWindows
```

修改 Flutter 时必须考虑响应式，确保桌面端和移动端两种模式均正常显示。

### 尺寸规范

- 所有尺寸需参考 `AppTheme.metrics`（`ThemeMetrics` 类），禁止直接使用数字或 `int.w`
- 如果所需尺寸未在 `ThemeMetrics` 中定义，使用 `scaleW()` 进行响应式宽度换算
- 颜色需同时考虑亮色和暗色主题，使用 `LightColors` / `DarkColors` 或 `Theme.of(context)` 获取

```dart
// 正确
SizedBox(height: AppTheme.metrics.kSpace16)
Text('示例', style: TextStyle(fontSize: AppTheme.metrics.fontSize14))

// 错误
SizedBox(height: 16)           // 禁止直接数字
Text('示例', style: TextStyle(fontSize: 14.w))  // 禁止 int.w
```

### 日志规范

- Dart 中使用 `Loggers` class 打日志，关键流程使用**中文**打 info/debug/error/warn log 方便后续定位问题
- Rust 中使用 `log::{info, warn, error}` 打日志

```dart
// Dart 日志
final _logger = Loggers(name: 'ModuleName');
_logger.info('操作完成');
_logger.error('失败', error: e, stackTrace: st);
```

```rust
// Rust 日志
use log::{info, warn, error};
info!("操作完成: {}", detail);
```

### 注释规范

- **注释必须使用中文**

### 弹窗规范

- 使用 `showDialog(context: context, ...)` 而非 `Get.dialog`，以保持 GoRouter 兼容性

### 代码校验

- 完成 Flutter 代码调整后需执行 `flutter analyze` 确保没有报错
- 如果只有 Rust 调整应当执行 `cargo build` 校验编译
- 完成代码编写后需完善本次修改的测试用例代码

---

## 附录：FRB 生成的 Dart API 速查

所有 FRB 生成的 Dart 绑定位于 `lib/src/rust/api/`，**勿直接修改**，由 `flutter_rust_bridge_codegen generate` 自动生成。

### capture.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `startCaptureProxy(port, installDir)` | `String` | 启动代理服务器 |
| `stopCaptureProxy(installDir)` | `String` | 停止代理服务器 |
| `isProxyRunning(installDir)` | `bool` | 获取捕获状态 |
| `getCapturedVideos(installDir)` | `List<String>` | 获取捕获的视频链接 |
| `getCapturedImages(installDir)` | `List<String>` | 获取捕获的图片链接 |
| `getCapturedJson(installDir)` | `List<String>` | 获取捕获的JSON数据 |
| `getCapturedJavascript(installDir)` | `List<String>` | 获取捕获的JS文件 |
| `clearCapturedData(installDir)` | `void` | 清除所有捕获数据 |
| `getCaptureStats(installDir)` | `CaptureStats?` | 获取捕获统计 |
| `installCaCertificate(password, installDir)` | `String` | 安装CA证书 |
| `isCaCertificateInstalled(installDir)` | `bool` | 检查CA证书是否已安装 |
| `isRunningAsAdministrator()` | `bool` | 检查是否管理员运行(Windows) |

### media_collection.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `getAllMediaCollections()` | `List<MediaCollection>` | 获取所有集合 |
| `getAllMediaFolders()` | `List<MediaFolder>` | 获取所有文件夹 |
| `getChildMediaFolders(parentId)` | `List<MediaFolder>` | 获取子文件夹 |
| `getMediaCollectionItems(collectionId)` | `List<MediaItem>` | 获取集合内媒体项 |
| `importMediaFolder(folderPath)` | `Future<MediaCollection>` | 导入媒体文件夹 |
| `scanMediaFolders(folderPath)` | `Future<List<MediaCollection>>` | 扫描媒体文件夹 |
| `ensureCoverThumbnail(filePath, width)` | `String?` | 生成/获取缩略图 |
| `getAllCollectionStats()` | `List<CollectionStats>` | 批量获取集合统计 |

### novel_reader.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `scanNovelsFolder(folderPath)` | `List<NovelMetadata>` | 扫描文件夹 |
| `getAllNovels()` | `List<NovelMetadata>` | 获取所有书籍 |
| `addNovel(filePaths)` | `List<NovelMetadata>` | 添加书籍 |
| `getNovelContent(filePath)` | `Future<NovelContent>` | 获取书籍内容 |
| `getChapterContent(filePath, chapterIndex)` | `Future<String>` | 获取章节内容 |
| `searchInNovel(filePath, keyword)` | `Future<List<SearchMatch>>` | 书内搜索 |
| `searchInAllNovelsBatched(keyword, batchSize)` | `Future<List<SearchBatchResult>>` | 全库批量搜索 |
| `applyKeywordRulesToAllNovelsBatch(rules, start, batchSize)` | `Future<KeywordApplyBatchResult>` | 批量应用关键词规则 |
| `updateReadingProgress(novelId, progress)` | `void` | 更新阅读进度 |

### game_library.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `gameLibraryInit(dbPath)` | `void` | 初始化数据库 |
| `gameLibraryGetGamesJson()` | `Future<String>` | 获取所有游戏 |
| `gameLibraryAddGameJson(gameJson)` | `Future<String>` | 添加游戏 |
| `gameLibraryDeleteGame(gameId)` | `Future<void>` | 删除游戏 |
| `gameLibraryLaunchGame(exePath, workingDir, useOpen)` | `Future<PlatformInt64>` | 启动游戏 |
| `gameLibraryScanDirectoryJson(paths)` | `Future<String>` | 扫描目录 |
| `gameLibraryFetchMoegirl(gameName)` | `Future<String>` | 萌娘百科元数据 |
| `gameLibraryGetStatsJson(startTsSec, endTsSec)` | `Future<String>` | 统计数据 |

### manga.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `mangaInit()` | `void` | 初始化客户端 |
| `mangaLogin(email, password)` | `Future<String>` | 登录 |
| `mangaSetChannel(mode, custom)` | `void` | 设置分流模式 |
| `mangaTestChannel(mode, custom)` | `Future<BigInt>` | 测试分流延迟(ms) |
| `mangaGetCollections()` | `Future<String>` | 首页推荐 |
| `mangaSearchComics(keyword, categories, page, sort)` | `Future<String>` | 搜索漫画 |
| `mangaGetComicDetail(comicId)` | `Future<String>` | 漫画详情 |
| `mangaGetEpsPages(comicId, epsOrder, page)` | `Future<String>` | 章节图片 |
| `mangaFetchImage(fileServer, path)` | `Future<Uint8List>` | 获取图片 |

### lan_transfer.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `lanTransferInit()` | `void` | 初始化 |
| `lanTransferStart(port, saveDir, preTrustedJson)` | `Future<void>` | 启动传输管理器 |
| `lanTransferGetDevices()` | `Future<List<String>>` | 获取设备列表 |
| `lanTransferSendText(targetIp, targetPort, targetDeviceId, text)` | `Future<String>` | 发送文本 |
| `lanTransferSendFile(targetIp, targetPort, targetDeviceId, filePath)` | `Future<String>` | 发送文件 |
| `lanTransferAccept(transferId)` | `Future<void>` | 接受传输 |
| `lanTransferReject(transferId)` | `Future<void>` | 拒绝传输 |

### sentry_log.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `sentryLogInit(dbPath)` | `String` | 初始化日志存储 |
| `sentryLogQuery(...)` | `Future<String>` | 查询日志事件 |
| `sentryLogGetEvent(eventId)` | `Future<String>` | 获取单个事件 |
| `sentryLogGetProjects()` | `Future<String>` | 获取项目列表 |
| `sentryLogGetStats()` | `Future<String>` | 获取统计 |
| `sentryLogExportJson(...)` | `Future<String>` | 导出为JSON |

### module_manager.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `createModuleManager(installDir)` | `ModuleManager` | 创建模块管理器 |
| `moduleGetAvailable(manager)` | `Future<List<AvailableModuleInfo>>` | 获取可用模块 |
| `moduleInstall(manager, moduleName, version, lockVersion, autoLoad)` | `Future<String>` | 安装模块 |
| `createModuleLoader(installDir)` | `ModuleLoader` | 创建模块加载器 |
| `moduleLoad(loader, moduleName, version)` | `Future<void>` | 加载动态库 |
| `moduleUnload(loader, moduleName)` | `Future<void>` | 卸载动态库 |

### http_bridge.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `initHttpBridge()` | `bool` | 初始化HTTP Bridge |
| `getRegisteredHandlers()` | `List<(String, String)>` | 获取已注册处理器 |
| `callHandler(module, function, params)` | `String` | 调用处理器 |
| `startNodeServer(host, port, name)` | `void` | 启动节点服务器 |
| `stopNodeServer()` | `void` | 停止节点服务器 |
| `isNodeServerRunning()` | `bool` | 检查服务器状态 |

### websocket.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `wsClientNew(url)` | `WsClient` | 创建客户端 |
| `wsClientConnect(client)` | `Future<void>` | 连接 |
| `wsClientSendText(client, message)` | `Future<void>` | 发送文本 |
| `wsServerNew(host, port)` | `WsServer` | 创建服务器 |
| `wsServerStart(server)` | `Future<void>` | 启动服务器 |
| `wsServerBroadcast(server, message)` | `Future<void>` | 广播消息 |

### system_metrics.dart

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `getSystemResourceSnapshot()` | `SystemResourceSnapshot` | 获取系统资源快照 |

`SystemResourceSnapshot` 字段：`cpuUsagePercent`, `memoryUsedMb`, `memoryTotalMb`, `rxKbps`, `txKbps`

---

> 本文档由代码分析自动生成，最后更新时间：2026年5月

---

## 附录：README.AI.md 规则与实际项目差异说明

`README.AI.md` 中列出的部分 Flutter 规则为通用模板，与项目实际实现存在差异，开发时以实际项目为准：

| README.AI.md 规则 | 实际项目实现 | 说明 |
|-------------------|-------------|------|
| 使用 ConsumerWidget + Riverpod | 使用 GetX（GetxController + Obx） | 项目统一使用 GetX 做状态管理 |
| 或 BlocBuilder + flutter_bloc | 未使用 | 项目不使用 Bloc |
| 使用 Either\<Failure, Success\> 模式 | 使用 Result 类型 / try-catch | Rust FFI 层返回 Result，Dart 侧用 try-catch 处理 |
| 使用 AsyncValue 处理异步状态 | 使用 BasePageState 的 PageInitState | 项目自建页面初始化状态管理 |
| 使用 SelectableText.rich 显示错误 | 使用 SnackBar + buildErrorPage | 项目使用 BasePage 内置错误展示 |
