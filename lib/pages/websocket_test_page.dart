/// WebSocket 测试页面
library;

/// PC 端：可以创建服务器和客户端
/// 移动端：只能创建客户端

import 'package:flutter/material.dart';
import 'package:slime_works/core/services/websocket_manager.dart';
import 'package:slime_works/src/rust/api/websocket.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:convert';

class WebSocketTestPage extends StatefulWidget {
  const WebSocketTestPage({super.key});

  @override
  State<WebSocketTestPage> createState() => _WebSocketTestPageState();
}

class _WebSocketTestPageState extends State<WebSocketTestPage> {
  final _wsManager = WebSocketManager.instance;

  // 服务器相关
  WsServer? _server;
  bool _isServerRunning = false;
  int _clientCount = 0;
  List<ClientInfo> _clients = [];
  Timer? _clientUpdateTimer;
  WsClient? _serverMonitorClient; // 用于接收服务器的广播响应

  // 客户端相关
  WsClient? _client;
  bool _isClientConnected = false;
  Timer? _heartbeatTimer;

  // UI 相关
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8765');
  final _messageController = TextEditingController();
  final List<String> _logs = [];
  String? _selectedClientId;

  @override
  void dispose() {
    _clientUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _hostController.dispose();
    _portController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  // =============== 服务器操作 ===============

  Future<void> _createServer() async {
    try {
      final host = _hostController.text;
      final port = int.parse(_portController.text);
      _server = _wsManager.createServer(host: host, port: port);
      _addLog('服务器已创建: $host:$port');
      setState(() {});
    } catch (e) {
      _addLog('创建服务器失败: $e');
    }
  }

  Future<void> _startServer() async {
    if (_server == null) return;
    try {
      await _wsManager.startServer(_server!);
      setState(() => _isServerRunning = true);
      _addLog('服务器已启动');

      // 创建监听客户端来接收服务器广播的响应
      final url = 'ws://${_hostController.text}:${_portController.text}';
      _serverMonitorClient = _wsManager.createClient(url: url);
      await _wsManager.connect(_serverMonitorClient!);
      // 发送鉴权消息
      await _wsManager.sendText(_serverMonitorClient!, 'AUTH:monitor');
      _addLog('[监听客户端] 已连接并鉴权');
      _startServerMonitorReceiver();

      _startClientUpdateTimer();
    } catch (e) {
      _addLog('启动服务器失败: $e');
    }
  }

  Future<void> _stopServer() async {
    if (_server == null) return;
    try {
      _clientUpdateTimer?.cancel();
      if (_serverMonitorClient != null) {
        await _wsManager.disconnect(_serverMonitorClient!);
        _serverMonitorClient = null;
      }
      await _wsManager.stopServer(_server!);
      setState(() {
        _isServerRunning = false;
        _clientCount = 0;
        _clients = [];
      });
      _addLog('服务器已停止');
    } catch (e) {
      _addLog('停止服务器失败: $e');
    }
  }

  Future<void> _broadcastMessage() async {
    if (_server == null || !_isServerRunning) return;
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await _wsManager.broadcast(_server!, message);
      _addLog('[服务器广播] $message');
      _messageController.clear();
    } catch (e) {
      _addLog('广播失败: $e');
    }
  }

  Future<void> _sendToClient() async {
    if (_server == null || !_isServerRunning || _selectedClientId == null) return;
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await _wsManager.sendToClient(_server!, _selectedClientId!, message);
      _addLog('[发送给 $_selectedClientId] $message');
      _messageController.clear();
    } catch (e) {
      _addLog('发送失败: $e');
    }
  }

  Future<void> _disconnectClientById(String clientId) async {
    if (_server == null || !_isServerRunning) return;
    try {
      await _wsManager.disconnectClient(_server!, clientId);
      _addLog('已断开客户端: $clientId');
      _updateClients();
    } catch (e) {
      _addLog('断开失败: $e');
    }
  }

  void _startClientUpdateTimer() {
    _clientUpdateTimer?.cancel();
    _clientUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_server != null && _isServerRunning && mounted) {
        _updateClients();
      }
    });
  }

  Future<void> _updateClients() async {
    if (_server == null || !_isServerRunning) return;
    try {
      final count = await _wsManager.getClientCount(_server!);
      // 请求客户端列表（实际数据通过 _startServerMonitorReceiver 接收）
      _addLog('[请求] GET_CLIENTS');
      await _wsManager.getClients(_server!);
      if (mounted) {
        setState(() {
          _clientCount = count;
          // _clients 会在接收到 CLIENTS_LIST 响应时更新
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  // 监听服务器广播的响应消息
  void _startServerMonitorReceiver() {
    if (!_isServerRunning || _serverMonitorClient == null) return;

    Future.delayed(const Duration(milliseconds: 50), () async {
      if (_serverMonitorClient != null && _isServerRunning && mounted) {
        try {
          final message = await _wsManager.receiveMessage(_serverMonitorClient!);
          if (message != null) {
            final data = wsMessageGetData(message: message);
            if (data.startsWith('CLIENTS_LIST:')) {
              final jsonStr = data.substring('CLIENTS_LIST:'.length);
              try {
                final List<dynamic> jsonList = json.decode(jsonStr);
                final clients = jsonList.map((item) => ClientInfo.fromJson(item as Map<String, dynamic>)).toList();
                if (mounted) {
                  setState(() {
                    _clients = clients;
                  });
                  _addLog('[客户端列表更新] ${clients.length} 个客户端');
                }
              } catch (e) {
                _addLog('[解析客户端列表失败] $e');
              }
            }
          }
        } catch (e) {
          // 忽略错误
        }
        _startServerMonitorReceiver();
      }
    });
  }

  // =============== 客户端操作 ===============

  void _createClient() {
    try {
      final url = 'ws://${_hostController.text}:${_portController.text}';
      _client = _wsManager.createClient(url: url);
      _addLog('客户端已创建: $url');
      setState(() {});
    } catch (e) {
      _addLog('创建客户端失败: $e');
    }
  }

  Future<void> _connectClient() async {
    if (_client == null) return;
    try {
      await _wsManager.connect(_client!);

      // 发送鉴权消息
      await _wsManager.sendText(_client!, 'AUTH:test_token');

      setState(() => _isClientConnected = true);
      _addLog('客户端已连接并发送鉴权');
      _startMessageReceiver();
      _startHeartbeat();
    } catch (e) {
      _addLog('连接失败: $e');
    }
  }

  Future<void> _disconnectClient() async {
    if (_client == null) return;
    try {
      _heartbeatTimer?.cancel();
      await _wsManager.disconnect(_client!);
      setState(() => _isClientConnected = false);
      _addLog('客户端已断开');
    } catch (e) {
      _addLog('断开连接失败: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_client == null) {
      _addLog('[错误] 客户端未创建');
      return;
    }

    if (!_isClientConnected) {
      _addLog('[错误] 客户端未连接，无法发送消息');
      return;
    }

    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await _wsManager.sendText(_client!, message);
      _addLog('[客户端发送] $message');
      _messageController.clear();
    } catch (e) {
      _addLog('发送失败: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_client != null && _isClientConnected && mounted) {
        try {
          await _wsManager.sendText(_client!, 'PING');
          _addLog('[心跳] PING');
        } catch (e) {
          _addLog('[心跳失败] $e');
        }
      }
    });
  }

  // =============== 消息接收 ===============

  void _startMessageReceiver() {
    if (!_isClientConnected || _client == null) return;

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (_client != null && _isClientConnected && mounted) {
        try {
          final message = await _wsManager.receiveMessage(_client!);
          if (message != null) {
            final data = wsMessageGetData(message: message);
            _addLog('[收到消息] $data');
          }
        } catch (e) {
          // 忽略错误
        }
        _startMessageReceiver();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebSocket 测试')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 服务器配置
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(labelText: '主机', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 服务器控制（仅 PC 端）
            if (_wsManager.isServerSupported) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('服务器控制', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ElevatedButton(onPressed: _server == null ? _createServer : null, child: const Text('创建服务器')),
                          ElevatedButton(onPressed: _server != null && !_isServerRunning ? _startServer : null, child: const Text('启动')),
                          ElevatedButton(onPressed: _server != null && _isServerRunning ? _stopServer : null, child: const Text('停止')),
                        ],
                      ),
                      if (_isServerRunning) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              Text('在线客户端: $_clientCount', style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(width: 8),
                              IconButton(icon: const Icon(Icons.refresh, size: 16), onPressed: _updateClients, tooltip: '刷新列表'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('客户端列表:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: _clients.isEmpty
                              ? const Center(
                                  child: Text('暂无客户端连接', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                )
                              : ListView.builder(
                                  itemCount: _clients.length,
                                  itemBuilder: (context, index) {
                                    final client = _clients[index];
                                    final connectedTime = DateTime.fromMillisecondsSinceEpoch(client.connectedAt * 1000);
                                    final duration = DateTime.now().difference(connectedTime);
                                    final isSelected = _selectedClientId == client.id;

                                    return ListTile(
                                      dense: true,
                                      selected: isSelected,
                                      title: Text('${client.address} ${client.authenticated ? "✓" : "✗"}', style: const TextStyle(fontSize: 12)),
                                      subtitle: Text('连接时长: ${duration.inMinutes}分${duration.inSeconds % 60}秒', style: const TextStyle(fontSize: 10)),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        onPressed: () => _disconnectClientById(client.id),
                                        tooltip: '断开连接',
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedClientId = isSelected ? null : client.id;
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 客户端控制
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('客户端控制', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(onPressed: _client == null ? _createClient : null, child: const Text('创建客户端')),
                        ElevatedButton(onPressed: _client != null && !_isClientConnected ? _connectClient : null, child: const Text('连接')),
                        ElevatedButton(onPressed: _client != null && _isClientConnected ? _disconnectClient : null, child: const Text('断开')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 消息发送
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(labelText: '消息', border: OutlineInputBorder()),
                    onSubmitted: (_) {
                      if (_wsManager.isServerSupported && _isServerRunning) {
                        _broadcastMessage();
                      } else if (_isClientConnected) {
                        _sendMessage();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (_wsManager.isServerSupported && _isServerRunning) ElevatedButton(onPressed: _broadcastMessage, child: const Text('广播')),
                if (_isClientConnected) ElevatedButton(onPressed: _sendMessage, child: const Text('发送')),
              ],
            ),
            const SizedBox(height: 16),

            // 日志
            Text('日志', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text(_logs[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
