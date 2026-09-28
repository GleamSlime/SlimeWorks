import 'dart:io';

import 'package:dio/dio.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/utils/logger.dart';

const _logger = Loggers(name: 'ASR');

/// 内网语音识别服务客户端
///
/// 走 OpenAI 兼容的 `POST {url}/v1/audio/transcriptions`，要求服务端返回
/// `verbose_json`（带 segments 时间轴）；服务端不支持时自动降级为整段文本。
class AsrService {
  final Dio _dio;
  final List<AsrServer> _servers = [];

  AsrService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          // 长音频转写是慢操作：整部电影可能十几分钟，收流超时放宽到 40 分钟
          receiveTimeout: const Duration(minutes: 40),
          sendTimeout: const Duration(minutes: 20),
        ),
      );

  List<AsrServer> get servers => List.unmodifiable(_servers);

  void setServers(List<AsrServer> servers) {
    _servers
      ..clear()
      ..addAll(servers);
  }

  AsrServer? get firstAvailable {
    for (final server in _servers) {
      if (server.enabled && server.isAvailable) return server;
    }
    return null;
  }

  /// 探测服务是否在线（模型列表接口最轻量）
  Future<bool> testServer(AsrServer server) async {
    try {
      final response = await _dio.get(
        server.modelsUrl,
        options: _authOptions(server),
      );
      final ok = response.statusCode == 200;
      _markChecked(server, ok);
      return ok;
    } catch (e) {
      _logger.info('[ASR] 服务不可用: ${server.url} ($e)');
      _markChecked(server, false);
      return false;
    }
  }

  /// 依次探测所有启用的服务，返回第一个可用的（保持列表顺序即优先级顺序）
  Future<AsrServer?> probeAvailableServer() async {
    for (final server in _servers.where((s) => s.enabled)) {
      if (await testServer(server)) {
        _logger.info('[ASR] 命中可用内网服务: ${server.name}(${server.url})');
        return server;
      }
    }
    return null;
  }

  /// 上传媒体文件做转写
  ///
  /// 直接把原始媒体（mp4/mp3/wav…）交给服务端，多数 whisper 系服务内部会用
  /// ffmpeg 解容器；个别只吃音频的服务端会在 [DioException] 里报格式错误。
  Future<RemoteTranscription> transcribe(
    AsrServer server, {
    required String filePath,
    String? language,
    CancelToken? cancelToken,
    void Function(double status)? onSendProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }
    final stat = await file.stat();

    // 用文件流而不是 MultipartFile.fromFile：后者会把整个文件读进内存，
    // 几十 GB 的视频在局域网上传时会直接把应用撑爆
    final form = FormData.fromMap({
      'file': MultipartFile.fromStream(
        // provider 形式而不是直接传流：Dio 重定向重试时可以重新开一次流
        () => file.openRead(),
        stat.size,
        filename: file.uri.pathSegments.last,
      ),
      'model': server.model,
      'response_format': 'verbose_json',
      if (language != null && language.isNotEmpty && language != 'auto')
        'language': language,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      server.transcribeUrl,
      data: form,
      options: _authOptions(server),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (total > 0 && onSendProgress != null) {
          // 上传只占整体耗时的一小段，这里最多映射到 30%
          onSendProgress((sent / total) * 0.3);
        }
      },
    );

    final data = response.data;
    if (data == null) {
      throw Exception('转写响应为空');
    }
    return parseTranscriptionResponse(data);
  }

  /// 解析 verbose_json：{ text, language, segments: [{start, end, text}] }
  /// start/end 为秒（浮点）
  static RemoteTranscription parseTranscriptionResponse(Map<String, dynamic> data) {
    final rawSegments = data['segments'];
    final segments = <AsrSegmentData>[];
    if (rawSegments is List) {
      for (final item in rawSegments) {
        if (item is! Map) continue;
        final start = _asDouble(item['start']);
        final end = _asDouble(item['end']);
        final text = (item['text'] as String?)?.trim() ?? '';
        if (text.isEmpty || end == null || start == null || end <= start) continue;
        segments.add(AsrSegmentData(
          startMs: (start * 1000).round(),
          endMs: (end * 1000).round(),
          text: text,
        ));
      }
    }

    final fullText = (data['text'] as String?)?.trim() ?? '';
    if (segments.isEmpty && fullText.isNotEmpty) {
      _logger.info('[ASR] 服务未返回时间轴，整段文本降级为单条字幕');
      segments.add(AsrSegmentData(startMs: 0, endMs: 0, text: fullText));
    }

    return RemoteTranscription(
      segments: segments,
      language: data['language'] as String?,
      text: fullText,
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Options _authOptions(AsrServer server) => Options(
    headers: server.apiKey != null && server.apiKey!.isNotEmpty
        ? {'Authorization': 'Bearer ${server.apiKey}'}
        : null,
    receiveDataWhenStatusError: true,
    responseType: ResponseType.json,
  );

  void _markChecked(AsrServer server, bool ok) {
    final index = _servers.indexWhere((s) => s.url == server.url);
    if (index != -1) {
      _servers[index] = server.copyWith(
        isAvailable: ok,
        lastChecked: DateTime.now(),
      );
    }
  }
}
