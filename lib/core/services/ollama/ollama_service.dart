import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/utils/logger.dart';

/// Ollama API 服务
/// 负责与 Ollama 服务器交互，支持多服务器轮询
class OllamaService {
  final Dio _dio;
  OllamaServer? _currentServer;
  final List<OllamaServer> _servers = [];

  OllamaService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

  /// 当前可用的服务器
  OllamaServer? get currentServer => _currentServer;

  /// 所有服务器列表
  List<OllamaServer> get servers => List.unmodifiable(_servers);

  /// 设置服务器列表
  void setServers(List<OllamaServer> servers) {
    _servers.clear();
    _servers.addAll(servers);
    _currentServer = null;
  }

  /// 添加服务器
  void addServer(OllamaServer server) {
    _servers.add(server);
  }

  /// 移除服务器
  void removeServer(String url) {
    _servers.removeWhere((s) => s.url == url);
    if (_currentServer?.url == url) {
      _currentServer = null;
    }
  }

  /// 测试服务器连接
  Future<bool> testServer(OllamaServer server) async {
    try {
      final response = await _dio.get(
        '${server.url}/api/tags',
        options: Options(
          headers: server.apiKey != null ? {'Authorization': 'Bearer ${server.apiKey}'} : null,
        ),
      );
      return response.statusCode == 200;
    } catch (e) {
      const Loggers(name: 'Ollama').error('测试 Ollama 服务器失败: ${server.url}', error: e);
      return false;
    }
  }

  /// 轮询查找可用服务器
  Future<OllamaServer?> findAvailableServer() async {
    if (_servers.isEmpty) {
      const Loggers(name: 'Ollama').info('没有配置 Ollama 服务器');
      return null;
    }

    // 先尝试当前服务器
    if (_currentServer != null && await testServer(_currentServer!)) {
      _currentServer = _currentServer!.copyWith(isAvailable: true, lastChecked: DateTime.now());
      _updateServerInList(_currentServer!);
      return _currentServer;
    }

    // 轮询所有服务器
    for (final server in _servers) {
      if (await testServer(server)) {
        _currentServer = server.copyWith(isAvailable: true, lastChecked: DateTime.now());
        _updateServerInList(_currentServer!);
        const Loggers(name: 'Ollama').info('找到可用 Ollama 服务器: ${_currentServer!.url}');
        return _currentServer;
      }
    }

    const Loggers(name: 'Ollama').info('未找到可用的 Ollama 服务器');
    return null;
  }

  /// 更新服务器列表中的服务器状态
  void _updateServerInList(OllamaServer server) {
    final index = _servers.indexWhere((s) => s.url == server.url);
    if (index != -1) {
      _servers[index] = server;
    }
  }

  /// 获取可用模型列表
  Future<List<OllamaModel>> getModels() async {
    final server = _currentServer ?? await findAvailableServer();
    if (server == null) {
      throw Exception('没有可用的 Ollama 服务器');
    }

    try {
      final response = await _dio.get(
        '${server.url}/api/tags',
        options: Options(
          headers: server.apiKey != null ? {'Authorization': 'Bearer ${server.apiKey}'} : null,
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final models =
          (data['models'] as List?)
              ?.map((m) => OllamaModel.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [];

      return models;
    } catch (e) {
      const Loggers(name: 'Ollama').error('获取 Ollama 模型列表失败', error: e);
      _currentServer = null; // 标记当前服务器不可用
      rethrow;
    }
  }

  /// 调用 Ollama 生成内容
  /// [model] 模型名称
  /// [prompt] 提示词
  /// [onChunk] 流式响应回调（可选）
  /// [cancelToken] 取消令牌（可选）
  Future<String> generate({
    required String model,
    required String prompt,
    void Function(String chunk)? onChunk,
    CancelToken? cancelToken,
  }) async {
    final server = _currentServer ?? await findAvailableServer();
    if (server == null) {
      throw Exception('没有可用的 Ollama 服务器');
    }

    try {
      final response = await _dio.post(
        '${server.url}/api/chat',
        data: {
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': '你是一个专业的翻译工具。你的任务是将用户提供的文本翻译成目标语言。只输出翻译结果一次，立即结束。禁止重复输出、禁止添加任何解释或注释。',
            },
            {'role': 'user', 'content': prompt},
          ],
          'stream': onChunk != null,
          // 添加停止标记防止模型重复输出
          'stop': [
            '<|im_end|>',
            '<|im_start|>',
            '<|endoftext|>',
            '<|system|>',
            '<|user|>',
            '<|assistant|>',
            "</note>",
            "<note>",
          ],
          // 推理控制参数（使用推荐值以降低重复和幻觉）
          'options': {'top_k': 20, 'top_p': 0.6, 'repetition_penalty': 1.05, 'temperature': 0},
        },
        options: Options(
          headers: server.apiKey != null ? {'Authorization': 'Bearer ${server.apiKey}'} : null,
          responseType: onChunk != null ? ResponseType.stream : ResponseType.json,
        ),
        cancelToken: cancelToken,
      );

      if (onChunk != null) {
        // 流式响应
        final stream = response.data as ResponseBody;
        final buffer = StringBuffer();

        const Loggers(name: 'Ollama').info('开始流式生成, url=${server.url}/api/chat');
        var finished = false;

        await for (final chunk in stream.stream) {
          final text = utf8.decode(chunk);
          const Loggers(name: 'Ollama').info('收到原始流 chunk: ${text.replaceAll('\n', '\\n')}');

          final lines = text.split('\n').where((line) => line.trim().isNotEmpty);

          for (final rawLine in lines) {
            var line = rawLine.trim();
            // 支持可能的 SSE 风格 'data: {...}' 前缀
            if (line.startsWith('data:')) {
              line = line.substring(5).trim();
            }
            if (line == '[DONE]') {
              finished = true;
              break;
            }

            try {
              final json = jsonDecode(line);
              final ollamaResponse = OllamaResponse.fromJson(json);
              if (ollamaResponse.content.isNotEmpty) {
                buffer.write(ollamaResponse.content);
                onChunk(ollamaResponse.content);
              } else {
                const Loggers(name: 'Ollama').info('流响应 content 为空, done=${ollamaResponse.done}');
              }

              if (ollamaResponse.done) {
                finished = true;
                break;
              }
            } catch (e, st) {
              const Loggers(name: 'Ollama').info('解析流式响应失败', error: e, stackTrace: st);
            }
          }

          if (finished) break;
        }

        const Loggers(name: 'Ollama').info('流式生成结束, total length=${buffer.length}');
        return _cleanupResponse(buffer.toString());
      } else {
        // 非流式响应
        const Loggers(name: 'Ollama').info('非流式响应: status=${response.statusCode} data=${response.data}');
        final ollamaResponse = OllamaResponse.fromJson(response.data);
        return _cleanupResponse(ollamaResponse.content);
      }
    } catch (e) {
      const Loggers(name: 'Ollama').error('Ollama 生成内容失败', error: e);
      _currentServer = null; // 标记当前服务器不可用
      rethrow;
    }
  }

  /// 清理响应中的特殊标记
  String _cleanupResponse(String content) {
    // 移除训练时的特殊标记
    String cleaned = content;
    final specialTokens = [
      '<|im_start|>',
      '<|im_end|>',
      '<|endoftext|>',
      '<|system|>',
      '<|user|>',
      '<|assistant|>',
    ];
    for (final token in specialTokens) {
      cleaned = cleaned.replaceAll(token, '');
    }
    // 移除多余的空行
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  /// 翻译文本段落（单段）
  /// [model] 模型名称
  /// [text] 要翻译的文本
  /// [languagePair] 语言对
  /// [onChunk] 流式响应回调（可选）
  /// [cancelToken] 取消令牌（可选）
  Future<String> translate({
    required String model,
    required String text,
    required TranslationLanguagePair languagePair,
    void Function(String chunk)? onChunk,
    CancelToken? cancelToken,
  }) async {
    final prompt = text.trim();

    const Loggers(name: 'Ollama').info(
      '开始翻译, model=$model, languagePair=${languagePair.displayName}, prompt=${prompt.replaceAll('\n', '\\n')}',
    );
    return generate(model: model, prompt: prompt, onChunk: onChunk, cancelToken: cancelToken);
  }

  /// 批量翻译多个段落
  /// [model] 模型名称
  /// [paragraphs] 要翻译的段落列表
  /// [languagePair] 语言对
  /// [onProgress] 进度回调（当前完成数/总数）
  /// [cancelToken] 取消令牌（可选）
  Future<List<String>> translateBatch({
    required String model,
    required List<String> paragraphs,
    required TranslationLanguagePair languagePair,
    void Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final results = <String>[];
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      if (paragraph.isEmpty) {
        results.add('');
        continue;
      }
      try {
        const Loggers(name: 'Ollama').info('正在翻译段落 ${i + 1}/${paragraphs.length}');
        // 使用非流式响应，避免结构重复
        final translated = await translate(
          model: model,
          text: paragraph,
          languagePair: languagePair,
          cancelToken: cancelToken,
        );
        results.add(translated.trim());
        onProgress?.call(i + 1, paragraphs.length);
        const Loggers(name: 'Ollama').info('段落 ${i + 1} 翻译完成, length=${translated.length}');
      } catch (e) {
        const Loggers(name: 'Ollama').error('翻译段落 ${i + 1} 失败', error: e);
        results.add(paragraph); // 失败时保留原文
        onProgress?.call(i + 1, paragraphs.length);
      }
    }
    return results;
  }

  /// 清理资源
  void dispose() {
    _dio.close();
  }
}
