/// WebSocket 管理器服务
library;

/// PC 端：提供服务器和客户端功能
/// 移动端：仅提供客户端功能

import 'package:flutter/foundation.dart';
import 'package:slime_works/src/rust/api/websocket.dart';

/// Dart-side representation of `ClientInfo` from Rust (via JSON)
class ClientInfo {
  final String id;
  final int connectedAt;
  final int lastHeartbeat;
  final bool authenticated;
  final String address;

  ClientInfo({required this.id, required this.connectedAt, required this.lastHeartbeat, required this.authenticated, required this.address});

  factory ClientInfo.fromJson(Map<String, dynamic> json) {
    return ClientInfo(
      id: json['id'] as String,
      connectedAt: (json['connected_at'] as num).toInt(),
      lastHeartbeat: (json['last_heartbeat'] as num).toInt(),
      authenticated: json['authenticated'] as bool,
      address: json['address'] as String,
    );
  }
}

class WebSocketManager {
  WebSocketManager._();
  static final WebSocketManager instance = WebSocketManager._();

  // =============== 服务器 API (仅 PC 端) ===============

  /// 检查当前平台是否支持服务器
  bool get isServerSupported {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
  }

  /// 创建 WebSocket 服务器（仅 PC 端）
  WsServer? createServer({required String host, required int port}) {
    if (!isServerSupported) {
      throw UnsupportedError('Server is only supported on desktop platforms');
    }
    return wsServerNew(host: host, port: port);
  }

  /// 启动服务器
  Future<void> startServer(WsServer server) async {
    await wsServerStart(server: server);
  }

  /// 停止服务器
  Future<void> stopServer(WsServer server) async {
    await wsServerStop(server: server);
  }

  /// 广播消息到所有连接的客户端
  Future<void> broadcast(WsServer server, String message) async {
    await wsServerBroadcast(server: server, message: message);
  }

  /// 发送消息到指定客户端
  Future<void> sendToClient(WsServer server, String clientId, String message) async {
    // Use broadcast with a routing prefix so server can route to single client
    final routed = 'TO:$clientId:$message';
    await wsServerBroadcast(server: server, message: routed);
  }

  /// 断开指定客户端连接
  Future<void> disconnectClient(WsServer server, String clientId) async {
    // Send a control broadcast instructing server to disconnect a specific client
    final cmd = 'DISCONNECT:$clientId';
    await wsServerBroadcast(server: server, message: cmd);
  }

  /// 获取当前连接的客户端数量
  Future<int> getClientCount(WsServer server) async {
    final count = await wsServerGetClientCount(server: server);
    return count.toInt();
  }

  /// 获取所有连接的客户端信息列表
  /// 注意：这会发送 GET_CLIENTS 请求，真实数据需要通过 WebSocket 消息接收
  Future<List<ClientInfo>> getClients(WsServer server) async {
    // 发送 GET_CLIENTS 请求，服务器会广播 CLIENTS_LIST:json 响应
    try {
      await wsServerBroadcast(server: server, message: 'GET_CLIENTS');
      // 返回空列表，实际数据由 UI 通过接收消息更新
      return <ClientInfo>[];
    } catch (_) {
      return <ClientInfo>[];
    }
  }

  // =============== 客户端 API (所有平台) ===============

  /// 创建 WebSocket 客户端
  WsClient createClient({required String url}) {
    return wsClientNew(url: url);
  }

  /// 连接到服务器
  Future<void> connect(WsClient client) async {
    await wsClientConnect(client: client);
  }

  /// 断开连接
  Future<void> disconnect(WsClient client) async {
    await wsClientDisconnect(client: client);
  }

  /// 发送文本消息
  Future<void> sendText(WsClient client, String message) async {
    await wsClientSendText(client: client, message: message);
  }

  /// 发送二进制消息
  Future<void> sendBinary(WsClient client, List<int> data) async {
    await wsClientSendBinary(client: client, data: data);
  }

  /// 检查是否已连接
  Future<bool> isConnected(WsClient client) async {
    return await wsClientIsConnected(client: client);
  }

  /// 获取连接状态
  Future<WsConnectionState> getState(WsClient client) async {
    return await wsClientGetState(client: client);
  }

  /// 接收消息（非阻塞，如果没有消息返回 null）
  Future<WsMessage?> receiveMessage(WsClient client) async {
    return await wsClientReceiveMessage(client: client);
  }
}
