# 局域网互传模块（LAN Transfer）

## 简介

互传模块允许同一局域网内的设备（Android、iOS、macOS、Windows）之间直接传输文件、图片、视频及文本消息，无需服务器中转，核心逻辑由 Rust 实现。

## 文件位置

| 层 | 文件 |
|----|------|
| Flutter 页面 | `lib/pages/lan_transfer/lan_transfer_screen.dart` |
| 组件 | `lib/pages/lan_transfer/components/device_list.dart` |
| | `lib/pages/lan_transfer/components/transfer_chat.dart` |
| | `lib/pages/lan_transfer/components/transfer_actions.dart` |
| | `lib/pages/lan_transfer/components/pending_requests.dart` |
| | `lib/pages/lan_transfer/components/scanning_animation.dart` |
| | `lib/pages/lan_transfer/components/transfer_history.dart` |
| ViewModel | `lib/view_models/lan_transfer_viewmodel.dart` |
| Dart Service | `lib/core/services/lan_transfer_service.dart` |
| Rust 核心 | `rust/lan_transfer/src/api.rs` |
| | `rust/lan_transfer/src/manager.rs` |
| | `rust/lan_transfer/src/transfer.rs` |
| | `rust/lan_transfer/src/discovery.rs` |
| | `rust/lan_transfer/src/types.rs` |

## 架构设计

```
Flutter UI
    │
    ▼
LanTransferViewModel（GetX）
    │  Dart FFI via flutter_rust_bridge
    ▼
LanTransferService（Dart）
    │  rust_api.lanTransferStart / lanTransferStop / …
    ▼
LanTransferManager（Rust）
    ├── DiscoveryService  ──── mDNS 广播 + 监听
    └── TransferService   ──── TCP 文件传输
```

## 核心流程

### 1. 服务启动

```
App 启动 / 互传页面初始化
    │
    ▼
LanTransferService.startService(port: 8889)
    │
    ├── rust_api.lanTransferInit()          // 初始化 env_logger
    ├── rust_api.lanTransferStart(port, saveDir)
    │       │
    │       ├── LanTransferManager::new(port)
    │       │       ├── DiscoveryService::new(port) // 创建 mDNS 服务
    │       │       └── TransferService::new(port)  // TCP bind(0.0.0.0:8889)
    │       └── manager.start()
    │               ├── DiscoveryService::start_broadcast()
    │               ├── DiscoveryService::start_browse()
    │               └── TransferService::start_listening()
    └── 定期刷新设备列表（Timer）
```

默认端口：`8889`（`LanTransferService.kDefaultPort`）。

#### 端口占用恢复策略

| 平台 | 策略 |
|------|------|
| macOS / Linux | `lsof -ti :<port>` 找到占用进程 → `kill -9` → 延迟 250ms 重试绑定 |
| Windows | `netstat -ano` 解析 PID → `taskkill /F /PID` → 延迟 250ms 重试 |
| iOS / Android | 应用层多次重试（400ms → 800ms → 1500ms），等待 OS 释放 TIME_WAIT 端口 |

Dart 层额外提供三次递增延迟重试（400 / 800 / 1500 ms），每次失败若不是端口占用错误则立即停止重试并上抛。

### 2. 设备发现

使用 [`mdns_sd`](https://crates.io/crates/mdns-sd) crate 实现零配置服务发现：

- **服务类型**：`_slimeworks-lan._tcp.local.`
- **服务名格式**：`SlimeWorks-<UUID>`（UUID = 设备唯一 ID）
- **TXT 记录**：携带 `device_id`、`device_name`、`device_type`

定期兜底：设备列表为空时，后台触发 `refresh_devices_fallback_scan()`（TCP 心跳子网扫描），以应对 mDNS 在部分网络环境下失效的情况。

### 3. 文件传输协议

底层使用 **TCP 自定义帧**：

```
┌─────────────────────────────┐
│  4 字节大端 uint32：length  │  length=0 表示传输结束（EOF）
│  length 字节：JSON payload  │
└─────────────────────────────┘
```

**消息类型（`MessageType`）**：

| 类型 | 说明 |
|------|------|
| `DeviceAnnouncement` | 设备信息交换（握手） |
| `TransferRequest` | 发起传输请求 |
| `TransferResponse` | 接受 / 拒绝响应 |
| `TransferData` | 文件数据块（256 KB/块） |
| `TransferComplete` | 传输完成确认 |
| `TransferCancel` | 取消传输 |
| `Heartbeat` | 心跳保活 |

帧大小上限：
- JSON 消息：32 MB（`MAX_JSON_MSG`）
- 文件数据块：256 KB（`CHUNK_SIZE`）
- 用户接受/拒绝超时：120 秒（`USER_ACCEPT_TIMEOUT_SECS`）

### 4. 接收确认流程

发送方发起 `TransferRequest` → 接收方展示 `PendingRequests` 弹窗 → 用户点击接受/拒绝 → 接收方回复 `TransferResponse` → 文件数据流传输 → `TransferComplete`。

**已信任设备**（`TrustedDevice`）可跳过确认弹窗，自动接收。

## 数据模型

### `DeviceInfo`

```dart
class DeviceInfo {
  String deviceId;      // 设备唯一 UUID
  String deviceName;    // 用户可读设备名
  String deviceType;    // Windows / MacOS / iOS / Android
  String ipAddress;     // 当前 IP
  int port;             // 监听端口（默认 8889）
  String discoveredAt;  // mDNS 发现时间
  bool isOnline;        // 在线状态
}
```

### `TransferItem`

| 字段 | 说明 |
|------|------|
| `transferId` | UUID（Rust 生成）或本地临时 ID（`local-<ts>-<rand>`） |
| `senderDeviceId / receiverDeviceId` | 收发两端设备 ID |
| `senderDeviceName` | 发送方设备名称 |
| `receiverDeviceName` | 接收方设备名称（仅本地离线排队项有值） |
| `transferType` | `File / Text / Image / Video` |
| `fileName / fileSize` | 文件名与大小（字节） |
| `textContent` | 文本消息内容 |
| `filePath` | 本地保存路径（接收端有值） |
| `status` | `Pending / Accepted / Rejected / Transferring / Completed / Failed / Cancelled / Queued` |
| `progress` | `0.0 ~ 100.0`，传输进度 |

## ViewModel 关键状态

```dart
RxBool isServiceRunning;                     // 服务是否运行中
RxBool isScanning;                           // 是否正在扫描设备
RxList<DeviceInfo> discoveredDevices;        // 已发现设备
Rx<DeviceInfo?> localDevice;                 // 本机设备信息
RxList<TransferItem> transferHistory;        // 完整传输历史（持久化）
RxList<TransferItem> pendingRequests;        // 待确认的收入请求
Rx<DeviceInfo?> selectedDevice;              // 当前聊天对端
RxList<TrustedDevice> trustedDevices;        // 已信任设备列表
Map<String, String> _deviceNames;           // 设备 ID → 名称持久化缓存（离线时保留名称）
Set<String> _pinnedPeers;                    // 已置顶的会话对端 ID
Map<String, _OfflineSendJob> _offlineJobs;  // 离线发送任务队列
```

传输历史持久化至 `SharedPreferences`：
- 键：`'lan_transfer_history'`（JSON 数组）
- 已删除 ID 保护键：`'lan_transfer_deleted_ids'`
- 设备名称缓存键：`'lan_transfer_device_names'`
- 置顶会话键：`'lan_transfer_pinned_peers'`
- 接收文件保存路径：`<ApplicationDocumentsDirectory>/LanTransfer/`

## UI 说明

### 主页面（`LanTransferScreen`）

- **工具栏**：本机 IP + 在线状态指示灯 + 附近设备数量徽章 + 服务开关
- **会话列表**：已传输过的对端设备列表（支持长按/右键菜单）
  - 置顶：将会话固定在列表顶部，有图钉图标标识
  - 删除历史：删除该对端的所有传输记录（保留文件）
  - 删除会话及文件：删除传输记录 + 本地已保存的文件
- **底部弹层**（`_DeviceSheetContent`）：打开时**自动开始搜索**附近设备，点击设备直接进入会话

### 会话页面（`_LanChatPage`）

- **顶部工具栏**：返回按钮 + 设备名称 + 在线状态点（兼容桌面端 DesktopTopBar）
- **消息列表**（`TransferChatView`）：文本/图片/视频以气泡形式展示，视频支持内嵌播放
  - 智能滚动：收到或发出消息时自动滚动到最新条目；若用户手动向上滚动则暂停自动滚动，触底后恢复
  - 返回底部按钮：用户向上滚动时右下角显示「返回底部」悬浮按钮
  - 失败重试：自己发出的失败消息气泡前显示 🔄 重试图标，点击重新发送
- **底部操作栏**（`TransferActions`）：**始终显示**（即使对端离线）
  - 对端在线：绿色状态点 + 「已连接」
  - 对端离线：灰色状态点 + 「不在线·发送后排队」
  - 发送文本、发送文件、发送图片、发送视频
  - 离线排队：发送时立即入库持久化（`queued` 状态），后台每 5 秒搜索对端设备，找到后自动发送；3 分钟未找到则变为 `failed` 状态，可重试

### 视频内嵌播放

聊天列表中的视频消息（本地文件）通过 `VideoPlayerController.file()` 内嵌播放，支持暂停/播放控制。

## 平台支持

| 功能 | macOS | Windows | iOS | Android |
|------|-------|---------|-----|---------|
| 发送文件 | ✅ | ✅ | ✅ | ✅ |
| 接收文件 | ✅ | ✅ | ✅ | ✅ |
| mDNS 发现 | ✅ | ✅ | ✅ | ✅ |
| 视频播放 | ✅ | ✅ | ✅ | ✅ |
| 端口强杀恢复 | ✅ | ✅ | ⏳ 等待 OS 释放 | ⏳ 等待 OS 释放 |
