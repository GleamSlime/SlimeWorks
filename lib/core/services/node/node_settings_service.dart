import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

import 'node_models.dart';

class NodeSettingsService extends GetxService {
  static const String _keyRemoteNodes = 'node_remote_nodes';
  static const String _keyLocalEnabled = 'node_local_enabled';
  static const String _keyLocalName = 'node_local_name';
  static const String _keyLocalPort = 'node_local_port';

  final Loggers _logger = Loggers(name: 'NodeSettings');

  final RxList<NodeEndpoint> remoteNodes = <NodeEndpoint>[].obs;
  final RxMap<String, bool> nodeConnectivity = <String, bool>{}.obs;
  final RxMap<String, String> nodeConnectivityError = <String, String>{}.obs;
  final RxDouble appRxKbps = 0.0.obs;
  final RxDouble appTxKbps = 0.0.obs;
  final RxInt libraryMutationTick = 0.obs;
  final RxBool localNodeEnabled = false.obs;
  final RxString localNodeName = '本机节点'.obs;
  final RxInt localNodePort = 17888.obs;
  final RxList<String> localNodeApiList = <String>[].obs;

  SharedPreferences? _prefs;
  HttpServer? _server;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
    ),
  );

  bool _isInitialized = false;
  DateTime? _trafficWindowStartAt;
  DateTime? _lastTrafficAt;
  int _trafficWindowRxBytes = 0;
  int _trafficWindowTxBytes = 0;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    _prefs = await SharedPreferences.getInstance();
    await _load();
    await _refreshLocalApiList();

    if (localNodeEnabled.value) {
      await startLocalNodeServer();
    }

    _isInitialized = true;
  }

  List<NodeEndpoint> get enabledRemoteNodes {
    return remoteNodes.where((n) => n.enabled).toList();
  }

  NodeEndpoint? getNodeById(String nodeId) {
    return remoteNodes.firstWhereOrNull((n) => n.id == nodeId);
  }

  Future<void> addRemoteNode({required String name, required String apiBaseUrl}) async {
    final normalized = _normalizeBaseUrl(apiBaseUrl);
    final endpoint = NodeEndpoint(
      id: _createNodeId(),
      name: name.trim().isEmpty ? '未命名节点' : name.trim(),
      apiBaseUrl: normalized,
      enabled: true,
      supportsMove: true,
      supportsCoverUpdate: true,
    );
    remoteNodes.add(endpoint);
    await _save();
    await checkNodeConnectivity(endpoint.id);
  }

  Future<void> updateRemoteNode(NodeEndpoint endpoint) async {
    final index = remoteNodes.indexWhere((n) => n.id == endpoint.id);
    if (index == -1) {
      return;
    }

    remoteNodes[index] = endpoint.copyWith(apiBaseUrl: _normalizeBaseUrl(endpoint.apiBaseUrl));
    remoteNodes.refresh();
    await _save();
    await checkNodeConnectivity(endpoint.id);
  }

  Future<void> removeRemoteNode(String nodeId) async {
    remoteNodes.removeWhere((n) => n.id == nodeId);
    nodeConnectivity.remove(nodeId);
    nodeConnectivityError.remove(nodeId);
    await _save();
  }

  Future<void> setRemoteNodeEnabled(String nodeId, bool enabled) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      return;
    }

    await updateRemoteNode(node.copyWith(enabled: enabled));
    if (!enabled) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '节点已禁用';
    }
  }

  Future<void> refreshNodeConnectivity() async {
    for (final node in remoteNodes) {
      if (!node.enabled) {
        nodeConnectivity[node.id] = false;
        nodeConnectivityError[node.id] = '节点已禁用';
        continue;
      }
      await checkNodeConnectivity(node.id);
    }
  }

  Future<void> checkNodeConnectivity(String nodeId) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      return;
    }
    if (!node.enabled) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = '节点已禁用';
      return;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _nodeCallUrl(node.apiBaseUrl),
        data: const <String, dynamic>{
          'action': 'list_novels',
          'params': <String, dynamic>{},
        },
      );
      final ok = response.statusCode == 200 && (response.data?['success'] == true);
      nodeConnectivity[nodeId] = ok;
      nodeConnectivityError[nodeId] = ok ? '' : '响应异常';
    } catch (e) {
      nodeConnectivity[nodeId] = false;
      nodeConnectivityError[nodeId] = e.toString();
    }
  }

  Future<void> updateLocalSettings({
    required bool enabled,
    required String nodeName,
    required int port,
  }) async {
    localNodeEnabled.value = enabled;
    localNodeName.value = nodeName.trim().isEmpty ? '本机节点' : nodeName.trim();
    localNodePort.value = port;

    await _save();

    if (enabled) {
      await startLocalNodeServer();
    } else {
      await stopLocalNodeServer();
    }

    await _refreshLocalApiList();
  }

  Future<void> startLocalNodeServer() async {
    if (_server != null) {
      return;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, localNodePort.value);
      _server!.listen(_handleRequest, onError: (Object e, StackTrace st) {
        _logger.error('节点服务监听出错', error: e, stackTrace: st);
      });
      _logger.info('节点服务已启动: ${localNodePort.value}');
    } catch (e, st) {
      _logger.error('启动节点服务失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> stopLocalNodeServer() async {
    final server = _server;
    _server = null;
    if (server == null) {
      return;
    }

    await server.close(force: true);
    _logger.info('节点服务已停止');
  }

  bool get isLocalServerRunning {
    return _server != null;
  }

  Future<List<Map<String, dynamic>>> fetchNodeNovels(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_novels',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }

    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> searchNodeNovels(NodeEndpoint node, String keyword) async {
    final response = await _callNode(
      node: node,
      action: 'search_all_novels',
      params: <String, dynamic>{'keyword': keyword},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }

    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> deleteNodeNovel({required String nodeId, required String novelId}) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_novel',
      params: <String, dynamic>{'novel_id': novelId},
    );
  }

  Future<void> updateNodeNovelInfo({
    required String nodeId,
    required String novelId,
    String? title,
    String? author,
    String? notes,
    List<String>? tags,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'update_novel_info',
      params: <String, dynamic>{
        'novel_id': novelId,
        if (title != null) 'title': title,
        if (author != null) 'author': author,
        if (notes != null) 'notes': notes,
        if (tags != null) 'tags': tags,
      },
    );
  }

  Future<void> setNodeNovelFavorite({
    required String nodeId,
    required String novelId,
    required bool isFavorite,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    try {
      await _callNode(
        node: node,
        action: 'set_novel_favorite',
        params: <String, dynamic>{'novel_id': novelId, 'is_favorite': isFavorite},
      );
    } catch (_) {
      await _callNode(
        node: node,
        action: 'update_novel_info',
        params: <String, dynamic>{'novel_id': novelId, 'is_favorite': isFavorite},
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchNodeNovelContent({
    required String nodeId,
    required String filePath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'get_novel_content',
      params: <String, dynamic>{'file_path': filePath},
    );

    final data = response['data'];
    if (data is! Map) {
      return <Map<String, dynamic>>[];
    }

    final mapData = Map<String, dynamic>.from(data);
    final chapters = mapData['chapters'];
    if (chapters is! List) {
      return <Map<String, dynamic>>[];
    }
    return chapters
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> moveNodeNovelToFolder({
    required String nodeId,
    required String novelId,
    String? folderId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'move_novel_to_folder',
      params: <String, dynamic>{'novel_id': novelId, 'folder_id': folderId},
    );
  }

  Future<void> updateNodeNovelCover({
    required String nodeId,
    required String novelId,
    required String imagePath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final bytes = await File(imagePath).readAsBytes();
    final ext = _extractImageExt(imagePath);
    final encoded = base64Encode(bytes);

    await _callNode(
      node: node,
      action: 'update_novel_cover_base64',
      params: <String, dynamic>{
        'novel_id': novelId,
        'image_base64': encoded,
        'image_ext': ext,
      },
    );
  }

  Future<Map<String, dynamic>> _callNode({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> params,
  }) async {
    final url = _nodeCallUrl(node.apiBaseUrl);
    final requestPayload = <String, dynamic>{
      'action': action,
      'params': _sanitizeJsonMap(params),
    };
    final txBytes = _estimatePayloadBytes(requestPayload);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: requestPayload,
      );
      final body = response.data ?? <String, dynamic>{};
      _recordAppTraffic(txBytes: txBytes, rxBytes: _estimatePayloadBytes(body));
      if (body['success'] == true) {
        nodeConnectivity[node.id] = true;
        nodeConnectivityError[node.id] = '';
        return body;
      }
      throw Exception((body['error'] ?? '节点返回失败').toString());
    } catch (e, st) {
      nodeConnectivity[node.id] = false;
      nodeConnectivityError[node.id] = e.toString();
      _logger.error('节点请求失败: ${node.name} $action', error: e, stackTrace: st);
      rethrow;
    }
  }

  Map<String, dynamic> _sanitizeJsonMap(Map<String, dynamic> source) {
    final output = <String, dynamic>{};
    source.forEach((key, value) {
      output[key] = _sanitizeJsonValue(value);
    });
    return output;
  }

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null) return null;
    if (value is BigInt) return value.toString();
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      final map = <String, dynamic>{};
      value.forEach((key, innerValue) {
        map[key.toString()] = _sanitizeJsonValue(innerValue);
      });
      return map;
    }
    if (value is Iterable) {
      return value.map(_sanitizeJsonValue).toList(growable: false);
    }
    if (value is num || value is bool || value is String) return value;
    return value.toString();
  }

  int _estimatePayloadBytes(dynamic payload) {
    try {
      final encoded = jsonEncode(_sanitizeJsonValue(payload));
      return utf8.encode(encoded).length;
    } catch (_) {
      return 0;
    }
  }

  void _recordAppTraffic({required int txBytes, required int rxBytes}) {
    final now = DateTime.now();
    _lastTrafficAt = now;
    final windowStart = _trafficWindowStartAt;
    if (windowStart == null) {
      _trafficWindowStartAt = now;
      _trafficWindowTxBytes = txBytes;
      _trafficWindowRxBytes = rxBytes;
      appTxKbps.value = txBytes / 1024.0;
      appRxKbps.value = rxBytes / 1024.0;
      return;
    }

    _trafficWindowTxBytes += txBytes;
    _trafficWindowRxBytes += rxBytes;

    final elapsedSeconds = now.difference(windowStart).inMilliseconds / 1000.0;
    if (elapsedSeconds < 0.5) {
      final safeElapsed = elapsedSeconds <= 0 ? 0.1 : elapsedSeconds;
      appTxKbps.value = (_trafficWindowTxBytes / 1024.0) / safeElapsed;
      appRxKbps.value = (_trafficWindowRxBytes / 1024.0) / safeElapsed;
      return;
    }

    appTxKbps.value = (_trafficWindowTxBytes / 1024.0) / elapsedSeconds;
    appRxKbps.value = (_trafficWindowRxBytes / 1024.0) / elapsedSeconds;

    _trafficWindowStartAt = now;
    _trafficWindowTxBytes = 0;
    _trafficWindowRxBytes = 0;
  }

  void syncTrafficDisplayNow() {
    final lastTrafficAt = _lastTrafficAt;
    if (lastTrafficAt == null) {
      appTxKbps.value = 0;
      appRxKbps.value = 0;
      return;
    }

    final idleSeconds = DateTime.now().difference(lastTrafficAt).inMilliseconds / 1000.0;
    if (idleSeconds >= 1.5) {
      appTxKbps.value = 0;
      appRxKbps.value = 0;
      _lastTrafficAt = null;
      _trafficWindowStartAt = DateTime.now();
      _trafficWindowTxBytes = 0;
      _trafficWindowRxBytes = 0;
    }
  }

  void _emitLibraryMutation() {
    libraryMutationTick.value++;
  }

  Future<void> _load() async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    localNodeEnabled.value = prefs.getBool(_keyLocalEnabled) ?? false;
    localNodeName.value = prefs.getString(_keyLocalName) ?? '本机节点';
    localNodePort.value = prefs.getInt(_keyLocalPort) ?? 17888;

    final raw = prefs.getString(_keyRemoteNodes);
    if (raw == null || raw.isEmpty) {
      remoteNodes.clear();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        remoteNodes.clear();
        return;
      }

      final nodes = decoded
          .whereType<Map>()
          .map((e) => NodeEndpoint.fromJson(Map<String, dynamic>.from(e)))
          .map((n) => n.copyWith(apiBaseUrl: _normalizeBaseUrl(n.apiBaseUrl)))
          .where((n) => n.id.isNotEmpty && n.apiBaseUrl.isNotEmpty)
          .toList();
      remoteNodes.assignAll(nodes);
    } catch (e, st) {
      _logger.error('读取节点设置失败', error: e, stackTrace: st);
      remoteNodes.clear();
    }
  }

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    await prefs.setBool(_keyLocalEnabled, localNodeEnabled.value);
    await prefs.setString(_keyLocalName, localNodeName.value);
    await prefs.setInt(_keyLocalPort, localNodePort.value);
    await prefs.setString(
      _keyRemoteNodes,
      jsonEncode(remoteNodes.map((n) => n.toJson()).toList()),
    );
  }

  String _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    String withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    if (withScheme.endsWith('/node/call')) {
      withScheme = withScheme.substring(0, withScheme.length - '/node/call'.length);
    }
    if (withScheme.endsWith('/health')) {
      withScheme = withScheme.substring(0, withScheme.length - '/health'.length);
    }
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
  }

  String _nodeCallUrl(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    return '$normalized/node/call';
  }

  String _createNodeId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = now % 1000000;
    return 'node_${now}_$rand';
  }

  Future<void> _refreshLocalApiList() async {
    final values = <String>[];

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }
          values.add('http://$ip:${localNodePort.value}/node/call');
        }
      }
    } catch (e) {
      _logger.log('读取本机网卡地址失败: $e', name: 'NodeSettings');
    }

    values.add('http://127.0.0.1:${localNodePort.value}/node/call');
    localNodeApiList.assignAll(values.toSet().toList()..sort());
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    int requestBytes = 0;

    void writeJsonResponse(Map<String, dynamic> data) {
      final body = jsonEncode(_sanitizeJsonValue(data));
      _recordAppTraffic(txBytes: utf8.encode(body).length, rxBytes: requestBytes);
      request.response.write(body);
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      writeJsonResponse(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'name': localNodeName.value, 'port': localNodePort.value},
      });
      await request.response.close();
      return;
    }

    if (request.method != 'POST' || request.uri.path != '/node/call') {
      request.response.statusCode = HttpStatus.notFound;
      writeJsonResponse(<String, dynamic>{'success': false, 'error': 'Not Found'});
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      requestBytes = utf8.encode(body).length;
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid payload');
      }

      final action = (payload['action'] ?? '').toString();
      final params = payload['params'];
      final mapParams = params is Map ? Map<String, dynamic>.from(params) : <String, dynamic>{};

      final data = await _dispatchAction(action, mapParams);
      request.response.statusCode = HttpStatus.ok;
      writeJsonResponse(<String, dynamic>{'success': true, 'data': data});
    } catch (e, st) {
      _logger.error('节点请求处理失败', error: e, stackTrace: st);
      request.response.statusCode = HttpStatus.ok;
      writeJsonResponse(<String, dynamic>{
        'success': false,
        'error': e.toString(),
      });
    }

    await request.response.close();
  }

  Future<dynamic> _dispatchAction(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'list_novels':
        final chapterCountMap = await _loadLocalChapterCountMap();
        final folderNameMap = await _loadFolderNameMap();
        final novels = rust_api.getAllNovels();
        return novels
            .map((n) => _novelToJson(n, chapterCountMap: chapterCountMap, folderNameMap: folderNameMap))
            .toList();
      case 'search_all_novels':
        final keyword = (params['keyword'] ?? '').toString();
        if (keyword.isEmpty) {
          return <Map<String, dynamic>>[];
        }
        final chapterCountMap = await _loadLocalChapterCountMap();
        final folderNameMap = await _loadFolderNameMap();
        final result = await rust_api.searchInAllNovels(keyword: keyword);
        return result
            .map((r) => _novelToJson(r.novel, chapterCountMap: chapterCountMap, folderNameMap: folderNameMap))
            .toList();
      case 'search_in_novel':
        final filePath = (params['file_path'] ?? '').toString();
        final keyword = (params['keyword'] ?? '').toString();
        final matches = await rust_api.searchInNovel(filePath: filePath, keyword: keyword);
        return matches
            .map(
              (m) => <String, dynamic>{
                'chapter_index': m.chapterIndex,
                'chapter_title': m.chapterTitle,
                'position': m.position,
                'snippet': m.snippet,
              },
            )
            .toList();
      case 'get_novel_content':
        final filePath = (params['file_path'] ?? '').toString();
        final content = await rust_api.getNovelContent(filePath: filePath);
        return <String, dynamic>{
          'novel_id': content.novelId,
          'chapters': content.chapters
              .map(
                (c) => <String, dynamic>{
                  'id': c.id,
                  'title': c.title,
                  'content': c.content,
                  'index': c.index.toString(),
                },
              )
              .toList(),
        };
      case 'delete_novel':
        final novelId = (params['novel_id'] ?? '').toString();
        rust_api.removeNovel(novelId: novelId);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'update_novel_tags':
        final novelId = (params['novel_id'] ?? '').toString();
        final tags = (params['tags'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        rust_api.updateNovelTags(novelId: novelId, tags: tags);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'set_novel_favorite':
        final novelId = (params['novel_id'] ?? '').toString();
        final isFavorite = params['is_favorite'] == true;
        rust_api.setNovelFavorite(novelId: novelId, isFavorite: isFavorite);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'update_novel_info':
        final novelId = (params['novel_id'] ?? '').toString();
        final tags = (params['tags'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        final hasFavorite = params.containsKey('is_favorite');
        final isFavorite = params['is_favorite'] == true;
        if (hasFavorite) {
          rust_api.setNovelFavorite(novelId: novelId, isFavorite: isFavorite);
        }
        rust_api.updateNovelInfo(
          novelId: novelId,
          title: params['title']?.toString(),
          author: params['author']?.toString(),
          notes: params['notes']?.toString(),
          tags: params.containsKey('tags') ? tags : null,
        );
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'move_novel_to_folder':
        final novelId = (params['novel_id'] ?? '').toString();
        final dynamic folderIdValue = params['folder_id'];
        final folderId = folderIdValue == null ? null : folderIdValue.toString();
        rust_api.moveNovelToFolder(novelId: novelId, folderId: folderId);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'update_novel_cover_base64':
        final novelId = (params['novel_id'] ?? '').toString();
        final imageBase64 = (params['image_base64'] ?? '').toString();
        final ext = (params['image_ext'] ?? 'png').toString();
        if (novelId.isEmpty || imageBase64.isEmpty) {
          throw ArgumentError('novel_id or image_base64 is empty');
        }
        final bytes = base64Decode(imageBase64);
        final tempPath = await _writeTempImage(bytes, ext);
        await rust_api.updateNovelCover(novelId: novelId, imagePath: tempPath);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      default:
        throw UnsupportedError('Unsupported action: $action');
    }
  }

  String _extractImageExt(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.webp')) return 'webp';
    return 'png';
  }

  Future<String> _writeTempImage(Uint8List bytes, String ext) async {
    final dir = await Directory.systemTemp.createTemp('slime_node_cover_');
    final file = File('${dir.path}${Platform.pathSeparator}cover.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Map<String, int>> _loadLocalChapterCountMap() async {
    try {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['HOME'];
      final base = appData != null
          ? '$appData${Platform.pathSeparator}slimeworks'
          : Directory.systemTemp.path;
      final path = '$base${Platform.pathSeparator}chapter_counts.json';
      final file = File(path);
      if (!file.existsSync()) {
        return <String, int>{};
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, int>{};
      }

      final map = <String, int>{};
      decoded.forEach((key, value) {
        if (value is int) {
          map[key] = value;
        } else if (value is num) {
          map[key] = value.toInt();
        }
      });
      return map;
    } catch (e) {
      _logger.log('读取章节缓存失败: $e', name: 'NodeSettings');
      return <String, int>{};
    }
  }

  Future<Map<String, String>> _loadFolderNameMap() async {
    try {
      final list = rust_api.getAllFolders();
      return {for (final f in list) f.id: f.name};
    } catch (e) {
      _logger.log('读取目录映射失败: $e', name: 'NodeSettings');
      return <String, String>{};
    }
  }

  String? _encodeCoverBase64(String? coverPath) {
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    try {
      final file = File(coverPath);
      if (!file.existsSync()) {
        return null;
      }
      final size = file.lengthSync();
      if (size > 256 * 1024) {
        return null;
      }
      return base64Encode(file.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _novelToJson(
    rust_api.NovelMetadata novel, {
    required Map<String, int> chapterCountMap,
    required Map<String, String> folderNameMap,
  }) {
    final coverBase64 = _encodeCoverBase64(novel.coverPath);
    final coverExt = _extractImageExt(novel.coverPath ?? '');
    return <String, dynamic>{
      'id': novel.id,
      'title': novel.title,
      'author': novel.author,
      'file_path': novel.filePath,
      'format': novel.format.name,
      'file_size': novel.fileSize.toString(),
      'modified_at': novel.modifiedAt.toString(),
      'added_at': novel.addedAt.toString(),
      'progress': novel.progress,
      'last_read_at': novel.lastReadAt?.toString(),
      'cover_path': novel.coverPath,
      'cover_base64': coverBase64,
      'cover_ext': coverExt,
      'folder_id': novel.folderId,
      'folder_name': novel.folderId == null ? null : folderNameMap[novel.folderId],
      'chapter_count': chapterCountMap[novel.id],
      'custom_order': novel.customOrder,
      'is_favorite': novel.isFavorite,
      'tags': novel.tags,
      'notes': novel.notes,
    };
  }
}
