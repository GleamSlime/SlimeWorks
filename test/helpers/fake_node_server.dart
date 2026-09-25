import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 集成测试夹具：本机环回端口上的"假节点服务器"。
///
/// 用途：给 [NodeSettingsService] 的节点调用链路（`/node/call`、`/node/upload`、
/// `/node/upload/archive`、`/node/media`）提供一个可控的对端，记录每个请求的
/// method / path / query / headers / body 原始字节，并按用例编排响应状态码、
/// JSON、字节与延迟。flutter test 在本机 VM 允许 socket，无需 mock Dio。
class FakeNodeServer {
  FakeNodeServer._(this._server) {
    _subscription = _server.listen(
      _handle,
      onError: (Object error, StackTrace stack) {
        // 连接被客户端中断（例如测试提前结束）属预期，记录后继续服务
        _serverErrors.add('$error');
      },
    );
  }

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;

  /// 已到达的请求（按 body 读取完成顺序）。
  final List<FakeNodeRequest> _requests = <FakeNodeRequest>[];

  /// 服务端异常信息（目前仅用于排障断言）。
  final List<String> _serverErrors = <String>[];

  /// 已捕获的服务端异常（如客户端提前断开），便于用例排障。
  List<String> get serverErrors => List<String>.unmodifiable(_serverErrors);

  /// 响应编排回调：按请求返回一个 [FakeNodeReply]。
  /// 默认对所有请求回 `{success: true, data: {}}`，保证 ping 探测可通过。
  FakeNodeReply Function(FakeNodeRequest request) responder = _defaultResponder;

  static FakeNodeReply _defaultResponder(FakeNodeRequest request) =>
      FakeNodeReply(json: <String, dynamic>{'success': true, 'data': <String, dynamic>{}});

  /// 启动夹具（绑定 127.0.0.1 的随机可用端口）。
  static Future<FakeNodeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeNodeServer._(server);
  }

  /// 客户端配置节点用的基地址，形如 `http://127.0.0.1:54321`（无尾斜杠）。
  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  /// 已记录的请求快照。
  List<FakeNodeRequest> get requests => List<FakeNodeRequest>.unmodifiable(_requests);

  /// 最后一个请求。
  FakeNodeRequest get lastRequest {
    if (_requests.isEmpty) {
      throw StateError('假节点服务器尚未收到任何请求');
    }
    return _requests.last;
  }

  /// 按 path / action 过滤计数，用于并发去重与"请求是否发出"的断言。
  int requestCount({String? path, String? action}) {
    return _requests
        .where((r) => (path == null || r.path == path))
        .where((r) => action == null || r.action == action)
        .length;
  }

  /// 等待请求总数达到 [count]（超时即抛，避免用例挂死）。
  Future<void> waitForRequestCount(
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_requests.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('假节点服务器只收到 ${_requests.length} 个请求，期望 $count', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyBytes = await _readBody(request);
    final headers = <String, String>{};
    request.headers.forEach((String name, List<String> values) {
      headers[name.toLowerCase()] = values.join(', ');
    });
    final recorded = FakeNodeRequest(
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: headers,
      bodyBytes: bodyBytes,
    );
    // 先入队再延迟响应，测试可以在请求进行中就观察到它已经到达
    _requests.add(recorded);

    final reply = responder(recorded);
    if (reply.delay > Duration.zero) {
      await Future<void>.delayed(reply.delay);
    }

    final response = request.response;
    try {
      if (reply.statusCode != HttpStatus.ok) {
        response.statusCode = reply.statusCode;
      }
      final bytes = reply.resolvedBytes;
      // 未显式指定时：给了 json 就按 application/json 回（与 Rust node_server 一致，
      // 也是 Dio 自动把响应解码成 Map 的前提），否则按二进制流回。
      response.headers.contentType =
          reply.contentType ?? (reply.json != null ? ContentType.json : ContentType.binary);
      // 显式 Content-Length：客户端才能可靠上报下载进度
      response.contentLength = bytes.length;
      response.add(bytes);
      await response.flush();
    } catch (_) {
      // 客户端可能已断开（熔断/超时用例），忽略写入失败
    }
    try {
      await response.close();
    } catch (_) {}
  }

  static Future<Uint8List> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

/// 夹具记录下来的单个请求。
class FakeNodeRequest {
  FakeNodeRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.bodyBytes,
  });

  final String method;
  final String path;

  /// 已解码的查询参数（`Uri.queryParameters` 语义）。
  final Map<String, String> query;

  /// 全部请求头，key 已转小写。
  final Map<String, String> headers;

  /// 原始请求体字节，用于校验上传的 zip 字节完全一致。
  final Uint8List bodyBytes;

  int get bodyLength => bodyBytes.length;

  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);

  /// JSON 请求体；非 JSON 时返回 null。
  Map<String, dynamic>? get jsonBody {
    if (bodyBytes.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(bodyText);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// `/node/call` 请求里的 action 字段。
  String? get action => jsonBody?['action']?.toString();

  /// `/node/call` 请求里的 params 字段（清洗后的 JSON 形态）。
  Map<String, dynamic> get params {
    final raw = jsonBody?['params'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// 忽略大小写读取请求头。
  String? header(String name) => headers[name.toLowerCase()];
}

/// 夹具的响应编排对象。
class FakeNodeReply {
  FakeNodeReply({
    this.statusCode = HttpStatus.ok,
    this.json,
    this.bodyBytes,
    this.contentType,
    this.delay = Duration.zero,
  });

  /// 业务成功：`{success: true, data: ...}`
  factory FakeNodeReply.successData(Object? data) =>
      FakeNodeReply(json: <String, dynamic>{'success': true, 'data': data});

  /// 业务失败（HTTP 200 + success:false），走节点的错误文案分支。
  factory FakeNodeReply.businessError(String error) =>
      FakeNodeReply(json: <String, dynamic>{'success': false, 'error': error});

  /// 授权码错误：节点侧 `is_authorized` 不通过时回 401。
  factory FakeNodeReply.unauthorized({String error = '未授权：缺少或错误的 X-SW-Auth 请求头'}) =>
      FakeNodeReply(
        statusCode: HttpStatus.unauthorized,
        json: <String, dynamic>{'success': false, 'error': error},
      );

  /// 二进制响应（`/node/media` 文件流）。
  factory FakeNodeReply.fileBytes(List<int> bytes) => FakeNodeReply(
        bodyBytes: bytes,
        contentType: ContentType.parse('application/octet-stream'),
      );

  final int statusCode;
  final Object? json;
  final List<int>? bodyBytes;
  final ContentType? contentType;

  /// 响应前挂起的时长，用于并发去重用例。
  final Duration delay;

  Uint8List get resolvedBytes {
    if (bodyBytes != null) {
      return Uint8List.fromList(bodyBytes!);
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(json ?? <String, dynamic>{})));
  }
}

/// 占用再释放一个环回端口，得到一个"确定无人监听"的端口（用于熔断用例）。
Future<int> freeLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}
