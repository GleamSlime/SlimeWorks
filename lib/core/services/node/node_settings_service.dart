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
  }

  Future<void> updateRemoteNode(NodeEndpoint endpoint) async {
    final index = remoteNodes.indexWhere((n) => n.id == endpoint.id);
    if (index == -1) {
      return;
    }

    remoteNodes[index] = endpoint.copyWith(apiBaseUrl: _normalizeBaseUrl(endpoint.apiBaseUrl));
    remoteNodes.refresh();
    await _save();
  }

  Future<void> removeRemoteNode(String nodeId) async {
    remoteNodes.removeWhere((n) => n.id == nodeId);
    await _save();
  }

  Future<void> setRemoteNodeEnabled(String nodeId, bool enabled) async {
    final node = getNodeById(nodeId);
    if (node == null) {
      return;
    }

    await updateRemoteNode(node.copyWith(enabled: enabled));
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
      _server = await HttpServer.bind(InternetAddress.anyIPv4, localNodePort.value, shared: true);
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

    await _callNode(
      node: node,
      action: 'set_novel_favorite',
      params: <String, dynamic>{'novel_id': novelId, 'is_favorite': isFavorite},
    );
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
    if (!node.supportsMove) {
      throw StateError('节点未开启移动能力');
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
    if (!node.supportsCoverUpdate) {
      throw StateError('节点未开启封面能力');
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
    final url = '${_normalizeBaseUrl(node.apiBaseUrl)}/node/call';
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: <String, dynamic>{
          'action': action,
          'params': params,
        },
      );
      final body = response.data ?? <String, dynamic>{};
      if (body['success'] == true) {
        return body;
      }
      throw Exception((body['error'] ?? '节点返回失败').toString());
    } catch (e, st) {
      _logger.error('节点请求失败: ${node.name} $action', error: e, stackTrace: st);
      rethrow;
    }
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

    final withScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
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

    if (request.method == 'GET' && request.uri.path == '/health') {
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'name': localNodeName.value, 'port': localNodePort.value},
      }));
      await request.response.close();
      return;
    }

    if (request.method != 'POST' || request.uri.path != '/node/call') {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(jsonEncode(<String, dynamic>{'success': false, 'error': 'Not Found'}));
      await request.response.close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid payload');
      }

      final action = (payload['action'] ?? '').toString();
      final params = payload['params'];
      final mapParams = params is Map ? Map<String, dynamic>.from(params) : <String, dynamic>{};

      final data = await _dispatchAction(action, mapParams);
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode(<String, dynamic>{'success': true, 'data': data}));
    } catch (e, st) {
      _logger.error('节点请求处理失败', error: e, stackTrace: st);
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode(<String, dynamic>{
        'success': false,
        'error': e.toString(),
      }));
    }

    await request.response.close();
  }

  Future<dynamic> _dispatchAction(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'list_novels':
        final novels = rust_api.getAllNovels();
        return novels.map(_novelToJson).toList();
      case 'search_all_novels':
        final keyword = (params['keyword'] ?? '').toString();
        if (keyword.isEmpty) {
          return <Map<String, dynamic>>[];
        }
        final result = await rust_api.searchInAllNovels(keyword: keyword);
        return result.map((r) => _novelToJson(r.novel)).toList();
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
                  'index': c.index,
                },
              )
              .toList(),
        };
      case 'delete_novel':
        final novelId = (params['novel_id'] ?? '').toString();
        rust_api.removeNovel(novelId: novelId);
        return <String, dynamic>{'ok': true};
      case 'update_novel_tags':
        final novelId = (params['novel_id'] ?? '').toString();
        final tags = (params['tags'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        rust_api.updateNovelTags(novelId: novelId, tags: tags);
        return <String, dynamic>{'ok': true};
      case 'set_novel_favorite':
        final novelId = (params['novel_id'] ?? '').toString();
        final isFavorite = params['is_favorite'] == true;
        rust_api.setNovelFavorite(novelId: novelId, isFavorite: isFavorite);
        return <String, dynamic>{'ok': true};
      case 'update_novel_info':
        final novelId = (params['novel_id'] ?? '').toString();
        final tags = (params['tags'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        rust_api.updateNovelInfo(
          novelId: novelId,
          title: params['title']?.toString(),
          author: params['author']?.toString(),
          notes: params['notes']?.toString(),
          tags: params.containsKey('tags') ? tags : null,
        );
        return <String, dynamic>{'ok': true};
      case 'move_novel_to_folder':
        final novelId = (params['novel_id'] ?? '').toString();
        final dynamic folderIdValue = params['folder_id'];
        final folderId = folderIdValue == null ? null : folderIdValue.toString();
        rust_api.moveNovelToFolder(novelId: novelId, folderId: folderId);
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

  Map<String, dynamic> _novelToJson(rust_api.NovelMetadata novel) {
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
      'folder_id': novel.folderId,
      'custom_order': novel.customOrder,
      'is_favorite': novel.isFavorite,
      'tags': novel.tags,
      'notes': novel.notes,
    };
  }
}
