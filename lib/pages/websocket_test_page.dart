/// WebSocket 测试页面
library;

/// PC 端：可以创建服务器和客户端
/// 移动端：只能创建客户端

import 'package:flutter/material.dart';
import 'package:slime_works/core/services/websocket_manager.dart';
import 'package:slime_works/src/rust/api/websocket.dart';

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

  // 客户端相关
  WsClient? _client;
  bool _isClientConnected = false;

  // UI 相关
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8765');
  final _messageController = TextEditingController();
  final List<String> _logs = [];

  @override
  void dispose() {
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
      _startClientCountTimer();
    } catch (e) {
      _addLog('启动服务器失败: $e');
    }
  }

  Future<void> _stopServer() async {
    if (_server == null) return;
    try {
      await _wsManager.stopServer(_server!);
      setState(() {
        _isServerRunning = false;
        _clientCount = 0;
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

  void _startClientCountTimer() {
    if (!_isServerRunning) return;
    Future.delayed(const Duration(seconds: 1), () async {
      if (_server != null && _isServerRunning) {
        try {
          final count = await _wsManager.getClientCount(_server!);
          if (mounted) {
            setState(() => _clientCount = count);
            _startClientCountTimer();
          }
        } catch (e) {
          // 忽略错误
        }
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
      setState(() => _isClientConnected = true);
      _addLog('客户端已连接');
      _startMessageReceiver();
    } catch (e) {
      _addLog('连接失败: $e');
    }
  }

  Future<void> _disconnectClient() async {
    if (_client == null) return;
    try {
      await _wsManager.disconnect(_client!);
      setState(() => _isClientConnected = false);
      _addLog('客户端已断开');
    } catch (e) {
      _addLog('断开连接失败: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_client == null || !_isClientConnected) return;
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
                      if (_isServerRunning)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('连接数: $_clientCount', style: Theme.of(context).textTheme.bodyMedium),
                        ),
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
