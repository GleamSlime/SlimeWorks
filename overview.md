# 概览模块（Dashboard）

## 简介

概览页面（`DashboardScreen`）是应用的首页，以实时折线图展示系统资源与网络状态，并提供各主要功能模块的快速入口。

## 文件位置

| 文件 | 说明 |
|------|------|
| `lib/pages/dashboard_screen.dart` | 主页面（`DashboardScreen`，`BasePage` 子类） |

## 核心功能

### 1. 实时性能监控

页面启动后以 **1 秒**为周期（`Timer.periodic(1s)`）轮询系统资源：

| 指标卡 | 数据来源 | 说明 |
|--------|----------|------|
| CPU 占用率 | `rust_sys.getSystemResourceSnapshot().cpuPercent` | Rust FFI（`SystemResourceSnapshot`） |
| 内存占用 | `rust_sys.getSystemResourceSnapshot().memoryMb` | Rust FFI |
| 应用下行速率 | `NodeSettingsService.appRxKbps` | 节点请求流量统计 |
| 应用上行速率 | `NodeSettingsService.appTxKbps` | 节点请求流量统计 |
| 节点请求数 | `NodeSettingsService.nodeRequestCount` | 仅本地节点启用时显示 |

每项指标保留最近 **60 个**采样点（`_kHistoryLength = 60`），绘制滚动折线图。网络流量由 `NodeSettingsService.syncTrafficDisplayNow()` 在 1.5 秒空闲后自动归零，避免历史流量持续显示。

### 2. 状态字段

```dart
rust_sys.SystemResourceSnapshot? _snapshot      // CPU + 内存快照
double _appRxKbps, _appTxKbps                  // 实时网速 kB/s
int _lastNodeRequestCount                       // 上次请求数（用于求增量）
List<double> _cpuHistory, _memHistory           // 折线图历史数组
List<double> _rxHistory, _txHistory, _reqHistory
```

### 3. 功能入口

概览页下方提供卡片式功能导航（静态展示，通过路由跳转）：

- 媒体库 → 多媒体集合管理
- 书库 → 小说/电子书管理
- 互传 → 局域网文件传输
- 设置 → 应用配置

## 响应式布局

- **桌面端（宽屏）**：MetricCard 以 3 列网格排列，折线图宽度自适应
- **移动端（窄屏）**：MetricCard 以单列纵向排列，折线图适度缩减高度

## 数据流向

```
Rust FFI (getSystemResourceSnapshot)
        │
        ▼ Timer.periodic(1s)
 DashboardScreen
        │
        ├── _cpuHistory / _memHistory  →  折线图（CPU/内存）
        │
        └── NodeSettingsService
              │  appRxKbps / appTxKbps
              └── 折线图（网络流量）
```

## 依赖服务

- `NodeSettingsService`（GetIt 单例）：网络流量数据与节点请求计数
- `rust_sys`：系统资源 FFI（`lib/src/rust/api/system_info.dart`）
