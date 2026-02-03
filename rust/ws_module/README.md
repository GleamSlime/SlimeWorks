# WebSocket 模块

WebSocket 模块提供了 PC 端服务器和移动端客户端功能，用于实现 PC 和移动设备之间的实时通信。

## 功能特性

### PC 端（Windows / macOS / Linux）

- ✅ 创建 WebSocket 服务器
- ✅ 支持多客户端连接
- ✅ 广播消息到所有客户端
- ✅ 实时监控客户端连接数

### 移动端（iOS / Android）

- ✅ 连接到 WebSocket 服务器
- ✅ 发送文本消息
- ✅ 发送二进制消息
- ✅ 自动重连（可配置）
- ✅ 连接状态监控

## 技术栈

### Rust 端

- `tokio` - 异步运行时
- `tokio-tungstenite` - WebSocket 实现
- `flutter_rust_bridge` - Rust-Flutter 桥接

### Flutter 端

- 自动生成的绑定代码
- 类型安全的 API
- 平台感知（自动区分 PC/移动端）

## 项目结构

```
rust/
  └── ws_module/                # WebSocket 模块（独立 crate）
      ├── Cargo.toml
      └── src/
          ├── lib.rs            # 模块入口
          ├── types.rs          # 类型定义
          ├── api.rs            # 导出 API
          ├── server.rs         # PC 端服务器（条件编译）
          └── client.rs         # 移动端客户端

lib/
  ├── core/
  │   └── services/
  │       └── websocket_manager.dart  # WebSocket 管理器
  └── pages/
      └── websocket_test_page.dart    # 测试页面
```

## 快速开始

### 1. Rust 端已集成

WebSocket 模块已作为独立 crate 集成到主项目中：

```toml
# rust/Cargo.toml
[dependencies]
ws_module = { path = "ws_module" }
```

### 2. 生成 Flutter 绑定

```bash
cd /Users/shilaimu/research/Software/slime_works
flutter_rust_bridge_codegen generate
```

### 3. PC 端使用示例

```dart
import 'package:slime_works/core/services/websocket_manager.dart';

final wsManager = WebSocketManager();

// 启动服务器
await wsManager.startServer(host: '127.0.0.1', port: 8765);

// 广播消息
await wsManager.broadcastMessage('Hello from PC!');

// 获取客户端数量
final count = await wsManager.getClientCount();
print('Connected clients: $count');

// 停止服务器
await wsManager.stopServer();
```

### 4. 移动端使用示例

```dart
import 'package:slime_works/core/services/websocket_manager.dart';

final wsManager = WebSocketManager();

// 连接到服务器（替换为实际 PC IP）
await wsManager.connectToServer(url: 'ws://192.168.1.100:8765');

// 发送消息
await wsManager.sendText('Hello from mobile!');

// 检查连接状态
final isConnected = await wsManager.isConnected();

// 断开连接
await wsManager.disconnect();
```

### 5. 测试页面

项目已包含一个完整的测试页面 `WebSocketTestPage`，可以直接使用：

```dart
import 'package:slime_works/pages/websocket_test_page.dart';

// 导航到测试页面
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const WebSocketTestPage()),
);
```

## API 文档

### WebSocketManager

#### PC 端方法

| 方法 | 描述 | 参数 | 返回值 |
|------|------|------|--------|
| `startServer()` | 启动服务器 | `host`, `port` | `Future<void>` |
| `stopServer()` | 停止服务器 | - | `Future<void>` |
| `broadcastMessage()` | 广播消息 | `message` | `Future<void>` |
| `getClientCount()` | 获取客户端数 | - | `Future<int>` |

#### 移动端方法

| 方法 | 描述 | 参数 | 返回值 |
|------|------|------|--------|
| `connectToServer()` | 连接服务器 | `url` | `Future<void>` |
| `disconnect()` | 断开连接 | - | `Future<void>` |
| `sendText()` | 发送文本 | `message` | `Future<void>` |
| `sendBinary()` | 发送二进制 | `data` | `Future<void>` |
| `isConnected()` | 检查连接 | - | `Future<bool>` |
| `getConnectionState()` | 获取状态 | - | `Future<WsConnectionState>` |

### WsConnectionState

连接状态枚举：

- `connected` - 已连接
- `connecting` - 连接中
- `disconnected` - 已断开
- `error` - 错误

## 网络配置

### PC 端

默认监听 `127.0.0.1:8765`。若要允许外部设备连接，改为：

```dart
await wsManager.startServer(host: '0.0.0.0', port: 8765);
```

### 移动端

连接时使用 PC 的实际 IP 地址：

```dart
// 获取 PC IP（例如在同一局域网）
await wsManager.connectToServer(url: 'ws://192.168.1.100:8765');
```

### 防火墙设置

确保防火墙允许 8765 端口（或您使用的端口）的入站连接。

## 调试

### 启用日志

Rust 端使用 `log` crate，可通过 `RUST_LOG` 环境变量控制：

```bash
# macOS/Linux
export RUST_LOG=ws_module=debug

# Windows
set RUST_LOG=ws_module=debug
```

### 常见问题

#### 1. 连接被拒绝

- 检查 PC 端服务器是否已启动
- 确认 IP 地址和端口正确
- 检查防火墙设置

#### 2. 无法广播消息

- 确认服务器正在运行
- 检查是否有客户端连接

#### 3. 编译错误

- 确保已运行 `flutter_rust_bridge_codegen generate`
- 检查 Rust 工具链是否安装

## 扩展功能

### 添加消息回调

当前实现是基础版本，可以扩展添加：

1. **消息接收回调**：在客户端接收到消息时触发
2. **连接状态回调**：监听连接状态变化
3. **错误处理**：更详细的错误信息

### 自定义消息格式

可以定义自己的消息格式（JSON、Protobuf 等）：

```dart
// 发送 JSON 消息
final jsonMessage = jsonEncode({'type': 'chat', 'content': 'Hello'});
await wsManager.sendText(jsonMessage);
```

## 性能优化

- 服务器默认最大连接数：100（可在 `WsServerConfig` 中配置）
- 客户端自动重连间隔：3 秒（可在 `WsClientConfig` 中配置）
- 消息缓冲区：100 条（可调整 channel 大小）

## 许可证

遵循项目主许可证。
