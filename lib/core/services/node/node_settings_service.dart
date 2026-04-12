import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/http_bridge.dart' as http_bridge_api;
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust_api;

import 'node_models.dart';

part 'node_http_handler.dart';
part 'node_media_handler.dart';

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
  final RxInt nodeRequestCount = 0.obs;
  final RxInt libraryMutationTick = 0.obs;
  final RxBool localNodeEnabled = false.obs;
  final RxString localNodeName = '本机节点'.obs;
  final RxInt localNodePort = 17888.obs;
  final RxList<String> localNodeApiList = <String>[].obs;

  SharedPreferences? _prefs;
  // 服务器实例已迁移到 Rust 管理，不再需要 Dart 端的 HttpServer
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

  /// 熔断节点集合：本次运行期间验证失败的节点，不再自动请求。
  final Set<String> _circuitBreakedNodes = <String>{};

  /// 已缩放图片的内存缓存（key = cacheKey，LRU 淘汰，总字节上限 80MB）。
  final Map<String, Uint8List> _resizedBytesCache = {};

  /// 当前缓存总字节数，用于 LRU 淘汰判断。
  int _resizedBytesCacheSize = 0;

  /// 缓存总字节上限：80MB，防止大量远程封面导致内存飙升。
  static const int _kBytesCacheMaxBytes = 80 * 1024 * 1024;

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
    // 启动后台节点连通性检测，不阻塞应用启动
    Future.delayed(const Duration(milliseconds: 200), refreshNodeConnectivity).ignore();
  }

  /// 是否已熔断（本次运行期间不再自动请求）
  bool isNodeCircuitBreaked(String nodeId) => _circuitBreakedNodes.contains(nodeId);

  /// 重置熔断状态，供用户在设置页面手动重试。
  void resetNodeCircuitBreaker(String nodeId) {
    _circuitBreakedNodes.remove(nodeId);
    nodeConnectivityError[nodeId] = '';
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
    // 手动检测时先清除熔断状态，允许重新连接
    _circuitBreakedNodes.remove(nodeId);

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
    if (Platform.isAndroid || Platform.isIOS) {
      _logger.info('移动端不支持启动本地节点服务，已跳过');
      return;
    }

    // 检查 Rust 服务器是否已在运行
    if (http_bridge_api.isNodeServerRunning()) {
      _logger.info('节点服务已在运行');
      return;
    }

    try {
      // 调用 Rust 启动节点服务器
      http_bridge_api.startNodeServer(
        host: '0.0.0.0',
        port: localNodePort.value,
        name: localNodeName.value,
      );
      _logger.info('节点服务已启动 (Rust): ${localNodePort.value}');
    } catch (e, st) {
      _logger.error('启动节点服务失败', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> stopLocalNodeServer() async {
    if (!http_bridge_api.isNodeServerRunning()) {
      return;
    }

    try {
      http_bridge_api.stopNodeServer();
      _logger.info('节点服务已停止');
    } catch (e, st) {
      _logger.error('停止节点服务失败', error: e, stackTrace: st);
    }
  }

  bool get isLocalServerRunning {
    return http_bridge_api.isNodeServerRunning();
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

  Future<List<Map<String, dynamic>>> fetchNodeSmartFolders(NodeEndpoint node) async {
    final response = await _callNode(
      node: node,
      action: 'list_smart_folders',
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
    ProgressCallback? onReceiveProgress,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }

    final Map<String, dynamic> response;
    if (onReceiveProgress != null) {
      // 需要报告进度时直接走 _performNodeCall，绕过去重缓存
      final payload = <String, dynamic>{
        'action': 'get_media_collection_items',
        'params': _sanitizeJsonMap(<String, dynamic>{'collection_id': collectionId}),
      };
      response = await _performNodeCall(
        node: node,
        action: 'get_media_collection_items',
        requestPayload: payload,
        onReceiveProgress: onReceiveProgress,
      );
    } else {
      response = await _callNode(
        node: node,
        action: 'get_media_collection_items',
        params: <String, dynamic>{'collection_id': collectionId},
      );
    }

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

  /// 列举节点上 [path] 目录下的一级子目录路径列表。
  Future<List<String>> listNodeDirectories({required String nodeId, required String path}) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'list_directories',
      params: <String, dynamic>{'path': path},
    );
    final data = response['data'];
    if (data is! List) return <String>[];
    return data.whereType<String>().toList();
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

  String buildNodeMediaUrl({
    required String nodeId,
    required String filePath,
    int? thumbnailWidth,
    bool isCover = false,
  }) {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    final normalized = _normalizeBaseUrl(node.apiBaseUrl);
    final params = <String, String>{'path': filePath};
    if (thumbnailWidth != null && thumbnailWidth > 0) {
      params['width'] = thumbnailWidth.toString();
    }
    if (isCover) {
      params['mode'] = 'cover';
    }
    final uri = Uri.parse('$normalized/node/media').replace(queryParameters: params);
    return uri.toString();
  }

  String buildNodeUploadUrl(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final normalized = _normalizeBaseUrl(node.apiBaseUrl);
    return '$normalized/node/upload';
  }

  /// 上传本地文件到远程节点的媒体库。
  /// [localPath] 本地文件路径，[collectionId] 可选目标集合（null 则扫描创建）。
  Future<Map<String, dynamic>> uploadMediaToNode({
    required String nodeId,
    required String localPath,
    String? collectionId,
  }) async {
    if (_circuitBreakedNodes.contains(nodeId)) {
      throw StateError('节点已熔断: $nodeId，请在设置中手动重试');
    }
    final uploadUrl = buildNodeUploadUrl(nodeId);
    final file = File(localPath);
    final filename = localPath.split('/').last;
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(localPath, filename: filename),
      'filename': filename,
      if (collectionId != null && collectionId.isNotEmpty) 'collection_id': collectionId,
    });
    final txBytes = await file.length();
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        uploadUrl,
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final body = resp.data ?? <String, dynamic>{};
      _recordAppTraffic(txBytes: txBytes, rxBytes: 256);
      if (body['success'] == true) {
        return Map<String, dynamic>.from(body['data'] as Map? ?? <String, dynamic>{});
      }
      throw Exception((body['error'] ?? '上传失败').toString());
    } on DioException catch (e) {
      _logger.error('媒体上传失败: $nodeId | $filename', error: e);
      rethrow;
    }
  }

  /// 删除节点上某个集合的本地物理文件（不删除数据库记录）。
  Future<int> deleteNodeCollectionLocalFiles({
    required String nodeId,
    required String rawCollectionId,
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) throw StateError('节点不存在: $nodeId');
    final response = await _callNode(
      node: node,
      action: 'delete_collection_local_files',
      params: <String, dynamic>{'collection_id': rawCollectionId},
    );
    final data = response['data'];
    if (data is Map) {
      return (data['deleted'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// 从节点下载单个文件到本地指定路径。
  Future<void> downloadNodeFileTo({
    required String nodeId,
    required String filePath,
    required String savePath,
  }) async {
    final url = buildNodeMediaUrl(nodeId: nodeId, filePath: filePath);
    await _dio.download(
      url,
      savePath,
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
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

  // ── 通用节点调用（供 ViewModel 直接使用） ────────────────────────────────

  /// 向指定节点发起任意 action 调用，返回 response data。
  Future<Map<String, dynamic>> callNodeAction({
    required String nodeId,
    required String action,
    Map<String, dynamic> params = const {},
  }) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      throw StateError('节点不存在: $nodeId');
    }
    return _callNode(node: node, action: action, params: params);
  }

  Future<Map<String, dynamic>> _callNode({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> params,
  }) async {
    // 熔断检查：本次运行期间不再自动请求已熔断节点
    if (_circuitBreakedNodes.contains(node.id)) {
      throw StateError('节点已熔断: ${node.name}，请在设置中手动重试');
    }
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
    }).ignore();
    return future;
  }

  Future<Map<String, dynamic>> _performNodeCall({
    required NodeEndpoint node,
    required String action,
    required Map<String, dynamic> requestPayload,
    ProgressCallback? onReceiveProgress,
  }) async {
    final candidateUrls = _candidateNodeCallUrls(node.apiBaseUrl);
    final txBytes = _estimatePayloadBytes(requestPayload);
    Object? lastError;
    StackTrace? lastStackTrace;

    for (int index = 0; index < candidateUrls.length; index++) {
      final url = candidateUrls[index];
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: requestPayload,
          options: _nodeCallOptionsForAction(action),
          onReceiveProgress: onReceiveProgress,
        );
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

    // 如果是网络超时/断开，做一次快速探测；探测也失败则熔断
    final isNetworkTimeout =
        error is DioException &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout);
    if (isNetworkTimeout && !_circuitBreakedNodes.contains(node.id)) {
      final probeOk = await _quickProbeNode(node);
      if (!probeOk) {
        _circuitBreakedNodes.add(node.id);
        nodeConnectivityError[node.id] = '节点已熔断（多次超时），请在设置中手动重试';
        _logger.info('节点已熔断: ${node.name}');
      }
    }

    throw error;
  }

  /// 快速探测节点是否可达（bypass 熔断检查，用于验证重试）。
  /// 返回 true 表示节点有响应（无论业务是否成功）。
  Future<bool> _quickProbeNode(NodeEndpoint node) async {
    final url = _candidateNodeCallUrls(node.apiBaseUrl).firstOrNull;
    if (url == null) return false;
    try {
      await _dio.post<dynamic>(
        url,
        data: <String, dynamic>{'action': 'ping', 'params': <String, dynamic>{}},
        options: Options(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      return true;
    } on DioException catch (e) {
      // 只有连接层失败才判定为不可达
      return e.type != DioExceptionType.connectionTimeout &&
          e.type != DioExceptionType.connectionError &&
          e.type != DioExceptionType.receiveTimeout &&
          e.type != DioExceptionType.sendTimeout;
    } catch (_) {
      return false;
    }
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

  Options? _nodeCallOptionsForAction(String action) {
    if (action == 'list_novels') {
      return Options(
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
      );
    }
    if (action.startsWith('picacg_')) {
      return Options(
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      );
    }
    return null;
  }
}
