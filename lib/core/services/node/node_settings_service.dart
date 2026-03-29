import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

import 'node_models.dart';

class NodeSettingsService extends GetxService {
  static const String _keyRemoteNodes = 'node_remote_nodes';
  static const String _keyLocalEnabled = 'node_local_enabled';
  static const String _keyLocalName = 'node_local_name';
  static const String _keyLocalPort = 'node_local_port';
  static const int _defaultRemoteNodePort = 17888;

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
  bool get isInitialized => _isInitialized;
  DateTime? _trafficWindowStartAt;
  DateTime? _lastTrafficAt;
  int _trafficWindowRxBytes = 0;
  int _trafficWindowTxBytes = 0;
  final Map<String, Future<Map<String, dynamic>>> _inFlightNodeCalls =
      <String, Future<Map<String, dynamic>>>{};

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
      await _callNode(node: node, action: 'list_novels', params: const <String, dynamic>{});
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
      _server!.listen(
        _handleRequest,
        onError: (Object e, StackTrace st) {
          _logger.error('节点服务监听出错', error: e, stackTrace: st);
        },
      );
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

  Future<List<Map<String, dynamic>>> fetchNodeMediaCollections(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_media_collections',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchNodeMediaFolders(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_media_folders',
      params: const <String, dynamic>{},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchNodeMediaCollectionItems({
    required String nodeId,
    required String collectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'get_media_collection_items',
      params: <String, dynamic>{'collection_id': collectionId},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> scanNodeMediaFolders({
    required String nodeId,
    required String folderPath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'scan_media_folders',
      params: <String, dynamic>{'folder_path': folderPath},
    );

    final data = response['data'];
    if (data is! List) {
      return <Map<String, dynamic>>[];
    }
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> importNodeMediaFolder({
    required String nodeId,
    required String folderPath,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'import_media_folder',
      params: <String, dynamic>{'folder_path': folderPath},
    );

    final data = response['data'];
    if (data is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> renameNodeMediaCollection({
    required String nodeId,
    required String collectionId,
    required String title,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'rename_media_collection',
      params: <String, dynamic>{'collection_id': collectionId, 'title': title},
    );
  }

  Future<void> deleteNodeMediaCollection({
    required String nodeId,
    required String collectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_media_collection',
      params: <String, dynamic>{'collection_id': collectionId},
    );
  }

  Future<void> moveNodeMediaCollectionToFolder({
    required String nodeId,
    required String collectionId,
    String? folderId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'move_media_collection_to_folder',
      params: <String, dynamic>{'collection_id': collectionId, 'folder_id': folderId},
    );
  }

  Future<Map<String, dynamic>> createNodeMediaFolder({
    required String nodeId,
    required String name,
    String? parentId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: parentId == null ? 'create_media_folder' : 'create_child_media_folder',
      params: <String, dynamic>{'name': name, if (parentId != null) 'parent_id': parentId},
    );
    return Map<String, dynamic>.from(response['data'] as Map<dynamic, dynamic>);
  }

  Future<void> renameNodeMediaFolder({
    required String nodeId,
    required String folderId,
    required String name,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'rename_media_folder',
      params: <String, dynamic>{'folder_id': folderId, 'name': name},
    );
  }

  Future<void> deleteNodeMediaFolder({required String nodeId, required String folderId}) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    await _callNode(
      node: node,
      action: 'delete_media_folder',
      params: <String, dynamic>{'folder_id': folderId},
    );
  }

  String buildNodeMediaUrl({required String nodeId, required String filePath}) {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    final normalized = _normalizeBaseUrl(node.apiBaseUrl);
    final uri = Uri.parse(
      '$normalized/node/media',
    ).replace(queryParameters: <String, String>{'path': filePath});
    return uri.toString();
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
    return chapters.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String> fetchNodeChapterContent({
    required String nodeId,
    required String filePath,
    required int chapterIndex,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final response = await _callNode(
      node: node,
      action: 'get_chapter_content',
      params: <String, dynamic>{'file_path': filePath, 'chapter_index': chapterIndex},
    );

    final data = response['data'];
    return (data ?? '').toString();
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
      params: <String, dynamic>{'novel_id': novelId, 'image_base64': encoded, 'image_ext': ext},
    );
  }

  Future<Map<String, dynamic>> _callNode({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> params,
  }) async {
    final sanitizedParams = _sanitizeJsonMap(params);
    final requestPayload = <String, dynamic>{'action': action, 'params': sanitizedParams};
    final callKey = _buildNodeCallKey(node.id, action, sanitizedParams);
    final inFlight = _inFlightNodeCalls[callKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performNodeCall(node: node, action: action, requestPayload: requestPayload);
    _inFlightNodeCalls[callKey] = future;
    future.whenComplete(() {
      if (identical(_inFlightNodeCalls[callKey], future)) {
        _inFlightNodeCalls.remove(callKey);
      }
    });
    return future;
  }

  Future<Map<String, dynamic>> _performNodeCall({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> requestPayload,
  }) async {
    final candidateUrls = _candidateNodeCallUrls(node.apiBaseUrl);
    final txBytes = _estimatePayloadBytes(requestPayload);
    Object? lastError;
    StackTrace? lastStackTrace;

    for (int index = 0; index < candidateUrls.length; index++) {
      final url = candidateUrls[index];
      try {
        final response = await _dio.post<Map<String, dynamic>>(url, data: requestPayload);
        final body = response.data ?? <String, dynamic>{};
        _recordAppTraffic(txBytes: txBytes, rxBytes: _estimatePayloadBytes(body));
        if (body['success'] == true) {
          nodeConnectivity[node.id] = true;
          nodeConnectivityError[node.id] = '';
          await _persistResolvedNodeBaseUrl(node, _baseUrlFromNodeCallUrl(url));
          return body;
        }
        throw Exception((body['error'] ?? '节点返回失败').toString());
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        if (index >= candidateUrls.length - 1 || !_shouldTryFallbackUrl(e)) {
          break;
        }
      }
    }

    final error = lastError ?? Exception('节点请求失败');
    nodeConnectivity[node.id] = false;
    nodeConnectivityError[node.id] = error.toString();
    _logger.error(
      '节点请求失败: ${node.name} $action | URLs=${candidateUrls.join(' , ')}',
      error: error,
      stackTrace: lastStackTrace,
    );
    throw error;
  }

  String _buildNodeCallKey(String nodeId, String action, Map<String, dynamic> params) {
    return '$nodeId|$action|${jsonEncode(params)}';
  }

  List<String> _candidateNodeCallUrls(String baseUrl) {
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return <String>[_nodeCallUrl(normalized)];
    }

    final candidates = <String>{_nodeCallUrl(uri.toString())};
    if (!uri.hasPort) {
      candidates.add(_nodeCallUrl(uri.replace(port: _defaultRemoteNodePort).toString()));
    }
    return candidates.toList(growable: false);
  }

  bool _shouldTryFallbackUrl(Object error) {
    if (error is! DioException) {
      return false;
    }
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  String _baseUrlFromNodeCallUrl(String url) {
    return url.endsWith('/node/call') ? url.substring(0, url.length - '/node/call'.length) : url;
  }

  Future<void> _persistResolvedNodeBaseUrl(NodeEndpoint node, String resolvedBaseUrl) async {
    final normalizedResolved = _normalizeBaseUrl(resolvedBaseUrl);
    if (normalizedResolved.isEmpty || normalizedResolved == _normalizeBaseUrl(node.apiBaseUrl)) {
      return;
    }

    final index = remoteNodes.indexWhere((item) => item.id == node.id);
    if (index == -1) {
      return;
    }

    remoteNodes[index] = remoteNodes[index].copyWith(apiBaseUrl: normalizedResolved);
    remoteNodes.refresh();
    await _save();
    _logger.info('节点地址已自动修正: ${node.name} -> $normalizedResolved');
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
    await prefs.setString(_keyRemoteNodes, jsonEncode(remoteNodes.map((n) => n.toJson()).toList()));
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
    if (withScheme.endsWith('/node')) {
      withScheme = withScheme.substring(0, withScheme.length - '/node'.length);
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

    if (request.method == 'GET' && request.uri.path == '/node/media') {
      await _serveMediaFile(request);
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
      writeJsonResponse(<String, dynamic>{'success': false, 'error': e.toString()});
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
            .map(
              (n) =>
                  _novelToJson(n, chapterCountMap: chapterCountMap, folderNameMap: folderNameMap),
            )
            .toList();
      case 'list_media_collections':
        final collections = media_api.getAllMediaCollections();
        return collections.map(_mediaCollectionToJson).toList();
      case 'list_media_folders':
        final folders = media_api.getAllMediaFolders();
        return folders.map(_mediaFolderToJson).toList();
      case 'get_media_collection_items':
        final collectionId = (params['collection_id'] ?? '').toString();
        final items = media_api.getMediaCollectionItems(collectionId: collectionId);
        return items.map(_mediaItemToJson).toList();
      case 'create_media_folder':
        final name = (params['name'] ?? '').toString();
        final folder = media_api.createMediaFolder(name: name);
        _emitLibraryMutation();
        return _mediaFolderToJson(folder);
      case 'create_child_media_folder':
        final name = (params['name'] ?? '').toString();
        final parentId = (params['parent_id'] ?? '').toString();
        final folder = media_api.createChildMediaFolder(name: name, parentId: parentId);
        _emitLibraryMutation();
        return _mediaFolderToJson(folder);
      case 'rename_media_folder':
        final folderId = (params['folder_id'] ?? '').toString();
        final name = (params['name'] ?? '').toString();
        media_api.renameMediaFolder(folderId: folderId, name: name);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'delete_media_folder':
        final folderId = (params['folder_id'] ?? '').toString();
        media_api.deleteMediaFolder(folderId: folderId);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'scan_media_folders':
        final folderPath = (params['folder_path'] ?? '').toString();
        final collections = await media_api.scanMediaFolders(folderPath: folderPath);
        _emitLibraryMutation();
        return collections.map(_mediaCollectionToJson).toList();
      case 'import_media_folder':
        final folderPath = (params['folder_path'] ?? '').toString();
        final collection = await media_api.importMediaFolder(folderPath: folderPath);
        _emitLibraryMutation();
        return _mediaCollectionToJson(collection);
      case 'rename_media_collection':
        final collectionId = (params['collection_id'] ?? '').toString();
        final title = (params['title'] ?? '').toString();
        media_api.renameMediaCollection(collectionId: collectionId, title: title);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'delete_media_collection':
        final collectionId = (params['collection_id'] ?? '').toString();
        media_api.deleteMediaCollection(collectionId: collectionId);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'move_media_collection_to_folder':
        final collectionId = (params['collection_id'] ?? '').toString();
        final folderIdValue = params['folder_id'];
        final folderId = folderIdValue == null ? null : folderIdValue.toString();
        media_api.moveMediaCollectionToFolder(collectionId: collectionId, folderId: folderId);
        _emitLibraryMutation();
        return <String, dynamic>{'ok': true};
      case 'search_all_novels':
        final keyword = (params['keyword'] ?? '').toString();
        if (keyword.isEmpty) {
          return <Map<String, dynamic>>[];
        }
        final chapterCountMap = await _loadLocalChapterCountMap();
        final folderNameMap = await _loadFolderNameMap();
        final result = await rust_api.searchInAllNovels(keyword: keyword);
        return result
            .map(
              (r) => _novelToJson(
                r.novel,
                chapterCountMap: chapterCountMap,
                folderNameMap: folderNameMap,
              ),
            )
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
      case 'get_chapter_content':
        final filePath = (params['file_path'] ?? '').toString();
        final chapterIndex = (params['chapter_index'] as num?)?.toInt() ?? 0;
        return await rust_api.getChapterContent(
          filePath: filePath,
          chapterIndex: BigInt.from(chapterIndex),
        );
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

  Map<String, dynamic> _mediaCollectionToJson(media_api.MediaCollection collection) {
    return <String, dynamic>{
      'id': collection.id,
      'title': collection.title,
      'folder_path': collection.folderPath,
      'folder_id': collection.folderId,
      'cover_path': collection.coverPath,
      'item_count': collection.itemCount.toString(),
      'created_at': collection.createdAt,
      'updated_at': collection.updatedAt,
    };
  }

  Map<String, dynamic> _mediaFolderToJson(media_api.MediaFolder folder) {
    return <String, dynamic>{
      'id': folder.id,
      'name': folder.name,
      'created_at': folder.createdAt,
      'order': folder.order,
      'parent_id': folder.parentId,
    };
  }

  Map<String, dynamic> _mediaItemToJson(media_api.MediaItem item) {
    return <String, dynamic>{
      'id': item.id,
      'collection_id': item.collectionId,
      'title': item.title,
      'file_path': item.filePath,
      'kind': item.kind.name,
      'file_size': item.fileSize.toString(),
      'modified_at': item.modifiedAt,
      'width': item.width,
      'height': item.height,
      'duration_ms': item.durationMs?.toString(),
      'order': item.order,
    };
  }

  Future<void> _serveMediaFile(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    if (filePath == null || filePath.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('missing path');
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('file not found');
      await request.response.close();
      return;
    }

    final stat = await file.stat();
    final totalLength = stat.size;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType = _guessMediaContentType(filePath);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final start = int.tryParse(match.group(1) ?? '') ?? 0;
        final end = int.tryParse(match.group(2) ?? '') ?? (totalLength - 1);
        final boundedEnd = end.clamp(start, totalLength - 1);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$boundedEnd/$totalLength',
        );
        request.response.contentLength = boundedEnd - start + 1;
        await request.response.addStream(file.openRead(start, boundedEnd + 1));
        await request.response.close();
        return;
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = totalLength;
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  ContentType _guessMediaContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return ContentType('image', 'png');
    if (lower.endsWith('.webp')) return ContentType('image', 'webp');
    if (lower.endsWith('.gif')) return ContentType('image', 'gif');
    if (lower.endsWith('.bmp')) return ContentType('image', 'bmp');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return ContentType('image', 'jpeg');
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return ContentType('video', 'mp4');
    if (lower.endsWith('.mov')) return ContentType('video', 'quicktime');
    if (lower.endsWith('.webm')) return ContentType('video', 'webm');
    if (lower.endsWith('.mkv')) return ContentType('video', 'x-matroska');
    if (lower.endsWith('.avi')) return ContentType('video', 'x-msvideo');
    return ContentType.binary;
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
