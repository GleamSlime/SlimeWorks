# LAN Transfer Module

局域网文件/消息传输模块

## 功能

- 局域网设备发现（mDNS）
- 文件传输（TCP）
- 文本消息传输
- 图片/视频传输
- 设备信任管理
- 传输历史记录

## 支持平台

- Windows
- MacOS
- iOS
- Android

## 架构

### 设备发现
使用 mDNS (Multicast DNS) 协议进行局域网设备发现和广播。

### 传输协议
使用 TCP 进行可靠的文件和消息传输。

### 数据结构

- `DeviceInfo`: 设备信息
- `TransferItem`: 传输项
- `TransferType`: 传输类型（文件/文本/图片/视频）
- `TransferStatus`: 传输状态
- `TrustedDevice`: 信任设备

## 使用方法

```rust
// 初始化
lan_transfer_init()?;

// 启动服务
lan_transfer_start(8888).await?;

// 获取发现的设备
let devices = lan_transfer_get_devices().await?;

// 发送文本
let transfer_id = lan_transfer_send_text(
    "192.168.1.100".to_string(),
    8888,
    "device_id".to_string(),
    "Hello!".to_string()
).await?;

// 发送文件
let transfer_id = lan_transfer_send_file(
    "192.168.1.100".to_string(),
    8888,
    "device_id".to_string(),
    "/path/to/file.txt".to_string()
).await?;

// 停止服务
lan_transfer_stop().await?;
```
