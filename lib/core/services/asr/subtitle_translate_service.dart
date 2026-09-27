import 'package:dio/dio.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/utils/logger.dart';

const _logger = Loggers(name: '字幕翻译');

/// 字幕翻译客户端（LibreTranslate 兼容 `POST {url}/translate`）
///
/// 输入是已经解析好的字幕逐行文本，输出严格等长的译文列表：
/// 任何一批翻译失败都保留原文并计入 [TranslateResult.untranslatedCount]，
/// 绝不因为翻译服务抖动而丢掉整条字幕的时间轴。
class SubtitleTranslateService {
  /// 单次请求的字符上限：自建 LibreTranslate 默认有 5000 字符限制，留足余量
  static const int _maxCharsPerRequest = 1500;

  /// 单次请求的条目上限：部分服务端对 q 数组长度另有限制
  static const int _maxSegmentsPerRequest = 60;

  final Dio _dio;
  final List<TranslateServer> _servers = [];

  SubtitleTranslateService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          // 长字幕要跑很多批，单批响应放宽到 5 分钟
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 2),
        ),
      );

  List<TranslateServer> get servers => List.unmodifiable(_servers);

  void setServers(List<TranslateServer> servers) {
    _servers
      ..clear()
      ..addAll(servers);
  }

  TranslateServer? get firstAvailable {
    for (final server in _servers) {
      if (server.enabled && server.isAvailable) return server;
    }
    return null;
  }

  /// 探测服务是否在线：直接发一条最小翻译请求，顺带验证 api_key 是否被接受
  Future<bool> testServer(TranslateServer server) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        server.translateUrl,
        data: _body(server, q: ['hello'], source: 'auto', target: 'zh'),
      );
      final ok = response.statusCode == 200 && response.data != null;
      _markChecked(server, ok);
      return ok;
    } catch (e) {
      _logger.info('[字幕翻译] 服务不可用: ${server.url} ($e)');
      _markChecked(server, false);
      return false;
    }
  }

  /// 依次探测所有启用的服务，返回第一个可用的（列表顺序即优先级）
  Future<TranslateServer?> probeAvailableServer() async {
    for (final server in _servers.where((s) => s.enabled)) {
      if (await testServer(server)) {
        _logger.info('[字幕翻译] 命中可用内网服务: ${server.name}(${server.url})');
        return server;
      }
    }
    return null;
  }

  /// 逐段翻译字幕文本
  ///
  /// * [source] 识别时用的语言代码，auto 时交给服务端自检
  /// * [target] 目标语言，审核流程固定中文 `zh`
  Future<TranslateResult> translate(
    TranslateServer server, {
    required List<String> texts,
    required String source,
    String target = 'zh',
    CancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    final src = _nmtSourceCode(source);
    final batches = _splitBatches(texts);
    final out = List<String>.filled(texts.length, '');
    var untranslated = 0;
    var done = 0;

    for (final batch in batches) {
      try {
        final translated = await _translateBatch(
          server,
          batch.texts,
          source: src,
          target: target,
          cancelToken: cancelToken,
        );
        for (int i = 0; i < batch.texts.length; i++) {
          out[batch.start + i] = translated[i];
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        untranslated += batch.texts.length;
        _copyThrough(out, batch, reason: '$e');
      } catch (e) {
        untranslated += batch.texts.length;
        _copyThrough(out, batch, reason: '$e');
      }
      done += batch.texts.length;
      onProgress?.call(done, texts.length);
    }

    return TranslateResult(texts: out, untranslatedCount: untranslated);
  }

  /// 把一批文本交给服务端，返回与 [chunk] 等长的译文
  Future<List<String>> _translateBatch(
    TranslateServer server,
    List<String> chunk, {
    required String source,
    required String target,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      server.translateUrl,
      data: _body(server, q: chunk, source: source, target: target),
      cancelToken: cancelToken,
      options: Options(
        headers: server.apiKey != null && server.apiKey!.isNotEmpty
            ? {'Authorization': 'Bearer ${server.apiKey}'}
            : null,
        receiveDataWhenStatusError: true,
        responseType: ResponseType.json,
      ),
    );

    final raw = response.data?['translatedText'];
    return normalizeTranslated(raw, chunk.length);
  }

  /// 归一化服务端返回的译文
  ///
  /// 服务端可能把 q 数组当成单条文本处理（返回 String），此时退化成按换行切分；
  /// 条数对不上就抛错，由调用方保留原文——宁可少译几段，也不能让译文串到别的时间轴上。
  static List<String> normalizeTranslated(Object? raw, int expected) {
    if (raw is List) {
      final items = raw.map((e) => (e as Object?)?.toString().trim() ?? '').toList();
      if (items.length != expected) {
        throw Exception('译文条数(${items.length})与请求条数($expected)不一致');
      }
      return items;
    }
    if (raw is String) {
      final lines = raw.split('\n').map((l) => l.trim()).toList();
      if (lines.length != expected) {
        throw Exception('服务端未按条目返回译文');
      }
      return lines;
    }
    throw Exception('翻译响应缺少 translatedText 字段');
  }

  Map<String, dynamic> _body(
    TranslateServer server, {
    required List<String> q,
    required String source,
    required String target,
  }) => {
    'q': q,
    'source': source,
    'target': target,
    'format': 'text',
    if (server.apiKey != null && server.apiKey!.isNotEmpty) 'api_key': server.apiKey,
  };

  /// 识别语言代码 → NMT 语言代码
  ///
  /// 纯 NMT 服务（NLLB/OPUS-MT 系）普遍没有粤语 `yue` 这一档，粤语字幕直接让服务端自检
  static String _nmtSourceCode(String code) => switch (code) {
    'ko' || 'ja' || 'zh' || 'en' => code,
    _ => 'auto',
  };

  List<_Batch> _splitBatches(List<String> texts) {
    final batches = <_Batch>[];
    var start = 0;
    var chars = 0;
    for (int i = 0; i < texts.length; i++) {
      final len = texts[i].length;
      // 单条超长时允许单独成批，否则会死循环
      if (i > start && (chars + len > _maxCharsPerRequest || i - start >= _maxSegmentsPerRequest)) {
        batches.add(_Batch(start: start, texts: texts.sublist(start, i)));
        start = i;
        chars = 0;
      }
      chars += len;
    }
    if (start < texts.length) {
      batches.add(_Batch(start: start, texts: texts.sublist(start)));
    }
    return batches;
  }

  void _copyThrough(List<String> out, _Batch batch, {required String reason}) {
    for (int i = 0; i < batch.texts.length; i++) {
      out[batch.start + i] = batch.texts[i];
    }
    _logger.info('[字幕翻译] 第 ${batch.start + 1} 段起的 ${batch.texts.length} 段翻译失败，保留原文: $reason');
  }

  void _markChecked(TranslateServer server, bool ok) {
    final index = _servers.indexWhere((s) => s.url == server.url);
    if (index != -1) {
      _servers[index] = server.copyWith(
        isAvailable: ok,
        lastChecked: DateTime.now(),
      );
    }
  }
}

class _Batch {
  final int start;
  final List<String> texts;

  const _Batch({required this.start, required this.texts});
}
