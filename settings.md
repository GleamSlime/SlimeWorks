# 设置模块（Settings）

## 简介

设置页面集中管理应用主题、节点连接、媒体质量、AI 集成等全局配置。关键数据通过 `SharedPreferences` 持久化，状态变更实时通过 GetX/GetIt 响应式传播到各界面。

## 文件位置

| 文件 | 说明 |
|------|------|
| `lib/pages/settings/settings_page.dart` | 主页面（`SettingsPage`，`TabController`） |
| `lib/pages/settings/components/theme_settings_tab.dart` | 主题设置 Tab |
| `lib/pages/settings/components/node_settings_tab.dart` | 节点设置 Tab |
| `lib/pages/settings/components/media_settings_tab.dart` | 媒体库设置 Tab |
| `lib/pages/settings/components/ollama_settings_tab.dart` | Ollama AI 设置 Tab |
| `lib/pages/settings/components/settings_tab_placeholder.dart` | 占位 Tab（账户、通知、书籍） |
| `lib/core/services/node/node_settings_service.dart` | 节点配置 Service（`GetxService`） |
| `lib/core/services/media_prefs_service.dart` | 媒体偏好 Service（`GetIt` 单例） |

## 页面结构

```
SettingsPage（TabController，6 个 Tab）
├── 主题设置     → ThemeSettingsTab
├── 节点设置     → NodeSettingsTab
├── 资源库       → _ResourcesSettingsTab（嵌套 TabController）
│   ├── 媒体设置 → MediaSettingsTab
│   └── 书籍设置 → SettingsTabPlaceholder（待实现）
├── Ollama 设置  → OllamaSettingsTab
├── 账户设置     → SettingsTabPlaceholder（待实现）
└── 通知设置     → SettingsTabPlaceholder（待实现）
```

---

## 主题设置（`ThemeSettingsTab`）

### 持久化字段（`SharedPreferences`）

| 设置项 | Key | 默认值 |
|--------|-----|--------|
| 主题模式 | `theme_mode` | `ThemeMode.system` |
| 强调色 | `accent_color` | 主色（蓝色） |
| 字体缩放 | `font_scale` | `1.0` |

### 实时生效机制

修改后直接更新 `AppTheme` 响应式变量，`MaterialApp` 内部 `Obx` 监听后立即重建：

```dart
AppTheme.themeModeObs.value = ThemeMode.dark;
AppTheme.accentColorObs.value = Colors.purple;
AppTheme.fontScaleObs.value = 1.2;
```

### 预设主题色（10 种）

| 颜色名 | 对应常量 |
|--------|---------|
| 默认蓝 | `LightColors.primary` |
| 紫 | `LightColors.purple` |
| 靛蓝 | `LightColors.indigo` |
| 天蓝 | `LightColors.blue` |
| 青 | `LightColors.cyan` |
| 薄荷 | `LightColors.mint` |
| 绿 | `LightColors.green` |
| 黄 | `LightColors.yellow` |
| 橙 | `LightColors.orange` |
| 红 | `LightColors.red` |

---

## 节点设置（`NodeSettingsTab` + `NodeSettingsService`）

### 本地节点

| 设置项 | SharedPreferences Key | 默认值 |
|--------|----------------------|--------|
| 启用本地节点 | `node_local_enabled` | `false` |
| 节点名称 | `node_local_name` | `'本机节点'` |
| 监听端口 | `node_local_port` | `17888` |

启动/停止流程：
```dart
// 启动本地 Rust HTTP 服务器
await http_bridge_api.startNodeServer(
  host: '0.0.0.0',
  port: localNodePort.value,
  name: localNodeName.value,
);
// → Rust crate::node_server::start_node_server(host, port, name)
```

本地节点 HTTP 服务提供以下路由（由 Rust `node_server` 模块实现）：

| 路由 | 方法 | 说明 |
|------|------|------|
| `/health` | GET | 健康检查，返回节点名称和端口 |
| `/node/call` | POST | 功能调用分发（`{ action, params }` JSON Body） |
| `/node/media` | GET | 媒体文件服务（支持 Range 请求） |
| `/node/upload` | POST | 文件上传（`multipart/form-data`） |

### 远程节点

```dart
// 节点配置
class NodeEndpoint {
  String id;           // 节点唯一 ID（格式：node_<timestamp>_<rand>）
  String name;         // 显示名称
  String apiBaseUrl;   // 基础 URL（如 http://192.168.1.100:17888）
  bool enabled;        // 是否启用
  bool supportsMove;   // 是否支持集合移动
  bool supportsCoverUpdate;  // 是否支持封面更新
}
```

持久化：`SharedPreferences` key `node_remote_nodes`（JSON 数组）。

#### 熔断机制

当节点连续超时/断开时，会被加入熔断集合（`_circuitBreakedNodes`）：

- **自动触发**：连接超时/断开 → 快速探测（`_quickProbeNode`）失败 → 加入熔断集合
- **熔断后效果**：跳过该节点的所有自动请求，防止界面卡顿
- **手动恢复**：设置页面点击「重试」→ `resetNodeCircuitBreaker(nodeId)` + 重新连通性检测

#### 连通性检测

```dart
// 检测单个节点（手动操作）
await nodeSettingsService.checkNodeConnectivity(nodeId);

// 检测全部节点（定期自动执行）
await nodeSettingsService.refreshNodeConnectivity();
```

结果存储：
- `nodeConnectivity[nodeId]`：`true` = 在线
- `nodeConnectivityError[nodeId]`：错误信息文本

#### 智能 URL 修正

节点首次成功响应后，若实际生效的 URL 与配置不同（例如补全了端口号 `17888`），会自动将修正后的地址写回配置，下次直接使用正确地址。

### 流量统计

| 状态变量 | 说明 |
|----------|------|
| `appRxKbps` | 应用下行速率（kB/s） |
| `appTxKbps` | 应用上行速率（kB/s） |
| `nodeRequestCount` | 本地节点累计请求数 |

流量数据由节点请求/响应时通过 `_recordAppTraffic(txBytes, rxBytes)` 实时累积，`Dashboard` 页面每秒调用 `syncTrafficDisplayNow()` 刷新展示值，1.5 秒无新流量后自动归零。

### 去重并发控制（In-Flight 请求缓存）

相同 `nodeId + action + params` 的并发请求会复用同一个 `Future`（`_inFlightNodeCalls`），避免在快速刷新时向同一节点重复发起相同请求。

---

## 媒体库设置（`MediaSettingsTab` + `MediaPrefsService`）

| 设置项 | SharedPreferences Key | 默认值 | 说明 |
|--------|----------------------|--------|------|
| 缩略图质量（1-5） | `media_thumb_quality` | 3 | 控制 ffmpeg 缩放分辨率和质量参数 |
| 缩略图并发量（1-20） | `media_thumb_concurrency` | 2 | 同时生成缩略图的最大任务数 |
| 远程封面宽度（px） | `media_remote_cover_width` | 240 | 节点返回封面图的最大宽度 |
| 远程图片预览宽度（px） | `media_remote_image_width` | 0 | 0 = 原图 |
| 本地图片预览宽度（px） | `media_local_preview_width` | 480 | 本地加载时的最大宽度 |
| 缓存大小上限（字节） | `media_cache_limit_bytes` | 1 GB | 超出后清理最旧缓存 |

缩略图质量等级对照：

| 等级 | 分辨率（宽） | qscale | 帧采样数 |
|------|------------|--------|---------|
| 1（最低） | 120 px | 10 | 3 帧 |
| 2 | 180 px | 8 | 5 帧 |
| **3（默认）** | **240 px** | **6** | **6 帧** |
| 4 | 360 px | 4 | 8 帧 |
| 5（最高） | 480 px | 2 | 10 帧 |

---

## Ollama 设置（`OllamaSettingsTab`）

配置本地或远程 Ollama 服务，用于 AI 辅助功能（书籍摘要、智能搜索等，未来功能）。

| 设置项 | Key | 默认值 |
|--------|-----|--------|
| Ollama 地址 | `ollama_base_url` | `http://localhost:11434` |
| 默认模型 | `ollama_model` | — |

---

## 数据持久化总览

所有设置均通过 `SharedPreferences` 持久化，Service 在应用启动时通过 `init()` 方法同步加载，无 Server 端依赖：

```dart
// 应用启动流程
GetIt.instance.registerSingletonAsync<NodeSettingsService>(() async {
  final service = NodeSettingsService();
  await service.init();  // 加载 SharedPreferences + 启动本地节点（若已启用）
  return service;
});
```
