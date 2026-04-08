import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/src/rust/api/http_bridge.dart';

/// HTTP Bridge 测试页面 - 类似 Postman
class HttpBridgeTestPage extends StatefulWidget {
  const HttpBridgeTestPage({super.key});

  @override
  State<HttpBridgeTestPage> createState() => _HttpBridgeTestPageState();
}

class _HttpBridgeTestPageState extends State<HttpBridgeTestPage> {
  final _moduleController = TextEditingController(text: 'novel_reader');
  final _functionController = TextEditingController(text: 'get_all_novels');
  final _paramsController = TextEditingController(text: '{}');

  String _response = '';
  bool _isLoading = false;
  int? _responseTime;
  String? _errorMessage;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  // 已注册的接口列表（从后端获取）
  List<String> _registeredModules = ['novel_reader'];
  List<String> _registeredFunctions = [
    'get_all_novels',
    'get_novel_content',
    'get_chapter_content',
    'search_in_novel',
    'add_novel',
  ];

  @override
  void initState() {
    super.initState();
    _initHttpBridge();
  }

  /// 初始化HTTP Bridge
  Future<void> _initHttpBridge() async {
    try {
      // 初始化HTTP Bridge（注册所有接口）
      final success = initHttpBridge();
      if (success) {
        debugPrint('HTTP Bridge initialized successfully');
      }
    } catch (e) {
      debugPrint('Failed to initialize HTTP Bridge: $e');
    }
    _loadRegisteredHandlers();
  }

  /// 加载已注册的接口列表
  Future<void> _loadRegisteredHandlers() async {
    try {
      final handlers = getRegisteredHandlers();

      // 提取模块名和函数名
      final modules = <String>{};
      final functions = <String>{};

      for (final handler in handlers) {
        modules.add(handler.$1);
        functions.add(handler.$2);
      }

      setState(() {
        _registeredModules = modules.toList();
        _registeredFunctions = functions.toList();
      });

      debugPrint('Loaded ${handlers.length} registered handlers');
    } catch (e) {
      debugPrint('Failed to load registered handlers: $e');
    }
  }

  @override
  void dispose() {
    _moduleController.dispose();
    _functionController.dispose();
    _paramsController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _response = '';
      _responseTime = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      // 验证 JSON 格式
      final paramText = _paramsController.text.trim();
      if (paramText.isEmpty) {
        throw const FormatException('参数不能为空');
      }
      final params = json.decode(paramText);

      // 调用真实的HTTP Bridge API
      final resultJson = callHandler(
        module: _moduleController.text,
        function: _functionController.text,
        params: paramText,
      );

      stopwatch.stop();
      _responseTime = stopwatch.elapsedMilliseconds;

      // 解析结果
      final result = json.decode(resultJson);

      setState(() {
        _response = const JsonEncoder.withIndent('  ').convert(result);
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _responseTime = stopwatch.elapsedMilliseconds;
      });
    }
  }

  /// 根据函数更新参数模板
  void _updateParamsTemplate(String function) {
    String template = '{}';
    switch (function) {
      case 'get_all_novels':
        template = '{}';
        break;
      case 'get_novel_content':
        template = '{\n  "file_path": "path/to/novel.txt"\n}';
        break;
      case 'get_chapter_content':
        template = '{\n  "file_path": "path/to/novel.txt",\n  "chapter_index": 0\n}';
        break;
      case 'search_in_novel':
        template = '{\n  "file_path": "path/to/novel.txt",\n  "keyword": "搜索关键词"\n}';
        break;
      case 'add_novel':
        template = '{\n  "file_path": "path/to/novel.txt"\n}';
        break;
    }
    _paramsController.text = template;
  }

  void _clearResponse() {
    setState(() {
      _response = '';
      _errorMessage = null;
      _responseTime = null;
    });
  }

  void _formatJson() {
    try {
      final paramText = _paramsController.text.trim();
      if (paramText.isEmpty) {
        _showSnack('JSON 内容为空');
        return;
      }
      final params = json.decode(paramText);
      _paramsController.text = const JsonEncoder.withIndent('  ').convert(params);
    } catch (e) {
      _showSnack('JSON 格式无效: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 800;

    return ScreenChrome(
      data: ScreenChromeData(
        title: 'HTTP Bridge 测试工具',
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '帮助',
            onPressed: () => _showHelp(),
          ),
        ],
      ),
      child: Scaffold(body: isNarrow ? _buildNarrowLayout() : _buildWideLayout()),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // 左侧：请求配置
        Expanded(flex: 1, child: _buildRequestPanel()),

        const VerticalDivider(width: 1),

        // 右侧：响应显示
        Expanded(flex: 1, child: _buildResponsePanel()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [_buildRequestPanel(), const Divider(height: 1), _buildResponsePanel()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '请求配置',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 模块名（下拉选择）
          DropdownButtonFormField<String>(
            initialValue: _moduleController.text,
            decoration: const InputDecoration(
              labelText: '模块名称',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            items: _registeredModules.map((module) {
              return DropdownMenuItem(value: module, child: Text(module));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                _moduleController.text = value;
              }
            },
          ),
          const SizedBox(height: 16),

          // 函数名（下拉选择+编辑）
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _registeredFunctions.contains(_functionController.text)
                      ? _functionController.text
                      : null,
                  decoration: const InputDecoration(
                    labelText: '函数名称',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.functions),
                  ),
                  items: _registeredFunctions.map((func) {
                    return DropdownMenuItem(value: func, child: Text(func));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _functionController.text = value;
                        _updateParamsTemplate(value);
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 参数 (JSON)
          Row(
            children: [
              Expanded(child: Text('参数 (JSON)', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: _formatJson,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('格式化'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TextField(
              controller: _paramsController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: '输入 JSON 格式的参数',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 发送按钮
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _sendRequest,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_isLoading ? '发送中...' : '发送请求'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsePanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '响应结果',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (_response.isNotEmpty || _errorMessage != null)
                IconButton(icon: const Icon(Icons.clear), tooltip: '清除', onPressed: _clearResponse),
            ],
          ),
          const SizedBox(height: 16),

          // 响应时间
          if (_responseTime != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '响应时间: $_responseTime ms',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // 错误消息
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        '错误',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _errorMessage!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),

          // 响应内容
          if (_response.isNotEmpty)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _response,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ),
            ),

          // 空状态
          if (_response.isEmpty && _errorMessage == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.http, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('发送请求后，响应将显示在这里', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用说明'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '这个工具用于测试 HTTP Bridge 模块的请求和响应。\n',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('1. 模块名称: 从下拉列表选择已注册的模块'),
              const SizedBox(height: 8),
              const Text('2. 函数名称: 从下拉列表选择已注册的函数'),
              const SizedBox(height: 8),
              const Text('3. 参数: 以 JSON 格式输入函数参数（会自动填充模板）'),
              const SizedBox(height: 8),
              const Text('4. 点击"发送请求"按钮'),
              const SizedBox(height: 16),
              const Text('已注册的接口:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var module in _registeredModules)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '模块: $module',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            for (var func in _registeredFunctions)
                              Padding(
                                padding: const EdgeInsets.only(left: 16, top: 2),
                                child: Text(
                                  '- $func',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }
}
