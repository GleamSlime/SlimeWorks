part of 'node_settings_service.dart';

/// HTTP 请求处理和 API 动作分发逻辑（服务端侧）已迁移到 Rust node_server 模块。
/// 保留此文件中的代码作为历史参考，HTTP 服务现在由 Rust 的 start_node_server 负责。
extension _NodeHttpHandlerExt on NodeSettingsService {
  // ── 请求入口 ─────────────────────────────────────────────────────────────

  // ignore: unused_element
  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    int requestBytes = 0;

    void writeJsonResponse(Map<String, dynamic> data) {
      final bodyStr = jsonEncode(_sanitizeJsonValue(data));
      final bodyBytes = utf8.encode(bodyStr);
      _recordAppTraffic(txBytes: bodyBytes.length, rxBytes: requestBytes);
      // 明确设置 Content-Length，客户端 Dio 才能正确上报接收进度百分比
      request.response.contentLength = bodyBytes.length;
      request.response.add(bodyBytes);
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

    // ── 媒体文件上传接口（multipart/form-data POST） ──────────────────────
    if (request.method == 'POST' && request.uri.path == '/node/upload') {
      await _handleMediaUpload(request);
      return;
    }

    if (request.method != 'POST' || request.uri.path != '/node/call') {
      request.response.statusCode = HttpStatus.notFound;
      writeJsonResponse(<String, dynamic>{'success': false, 'error': 'Not Found'});
      await request.response.close();
      return;
    }

    nodeRequestCount.value++;

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

  // ── 动作分发 ─────────────────────────────────────────────────────────────

  Future<dynamic> _dispatchAction(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'get_status':
        return <String, dynamic>{
          'name': localNodeName.value,
          'port': localNodePort.value,
          'version': '1.0',
        };
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
        // 批量获取所有集合大小，一次 FFI 调用，避免 N+1 查询
        final statsList = media_api.getAllCollectionStats();
        final statsMap = {for (final s in statsList) s.collectionId: s};
        return collections.map((c) {
          final map = _mediaCollectionToJson(c);
          map['total_size'] = (statsMap[c.id]?.totalSize ?? BigInt.zero).toString();
          return map;
        }).toList();
      case 'list_media_folders':
        final folders = media_api.getAllMediaFolders();
        return folders.map(_mediaFolderToJson).toList();
      case 'list_directories':
        // 列举指定路径下的一级子目录，供客户端展示树状目录选择器
        try {
          final dirPath = (params['path'] ?? '/').toString();
          final dir = Directory(dirPath);
          if (!dir.existsSync()) return <String>[];
          final entries = dir.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
          return entries;
        } catch (_) {
          return <String>[];
        }
      case 'list_smart_folders':
        // 将本机的智能文件夹列表暴露给远程节点客户端
        try {
          final dir = await getApplicationSupportDirectory();
          final file = File('${dir.path}/smart_folders_data.json');
          if (await file.exists()) {
            final raw = await file.readAsString();
            if (raw.isNotEmpty) {
              return jsonDecode(raw) as List<dynamic>;
            }
          }
        } catch (_) {}
        return <dynamic>[];
      case 'create_smart_folder':
        // 在节点本机创建智能文件夹，返回创建后的完整智能文件夹列表
        try {
          final dir = await getApplicationSupportDirectory();
          final sfFile = File('${dir.path}/smart_folders_data.json');
          final List<dynamic> existingList;
          if (await sfFile.exists()) {
            final raw = await sfFile.readAsString();
            existingList = raw.isNotEmpty ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
          } else {
            existingList = <dynamic>[];
          }
          final newSf = {
            'id': 'sf_${DateTime.now().millisecondsSinceEpoch}',
            'name': (params['name'] ?? '').toString(),
            'regexPattern': (params['regex_pattern'] ?? '').toString(),
            'targetFolderIds': (params['target_folder_ids'] is List)
                ? params['target_folder_ids']
                : <dynamic>[],
            'regexTarget': (params['regex_target'] ?? 'collectionName').toString(),
            'fileTypeFilter': (params['file_type_filter'] ?? 'all').toString(),
          };
          existingList.add(newSf);
          await sfFile.parent.create(recursive: true);
          await sfFile.writeAsString(jsonEncode(existingList));
          _emitLibraryMutation();
          return existingList;
        } catch (e) {
          throw StateError('创建智能文件夹失败: $e');
        }
      case 'update_smart_folder':
        // 更新节点本机指定智能文件夹，通过 id 定位后更新字段
        try {
          final dir = await getApplicationSupportDirectory();
          final sfFile = File('${dir.path}/smart_folders_data.json');
          final List<dynamic> existingList;
          if (await sfFile.exists()) {
            final raw = await sfFile.readAsString();
            existingList = raw.isNotEmpty ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
          } else {
            existingList = <dynamic>[];
          }
          final targetId = (params['id'] ?? '').toString();
          final idx = existingList.indexWhere((e) => (e as Map<String, dynamic>)['id'] == targetId);
          if (idx == -1) throw StateError('智能文件夹不存在: $targetId');
          existingList[idx] = {
            'id': targetId,
            'name': (params['name'] ?? '').toString(),
            'regexPattern': (params['regex_pattern'] ?? '').toString(),
            'targetFolderIds': (params['target_folder_ids'] is List)
                ? params['target_folder_ids']
                : <dynamic>[],
            'regexTarget': (params['regex_target'] ?? 'collectionName').toString(),
            'fileTypeFilter': (params['file_type_filter'] ?? 'all').toString(),
          };
          await sfFile.writeAsString(jsonEncode(existingList));
          _emitLibraryMutation();
          return existingList;
        } catch (e) {
          throw StateError('更新智能文件夹失败: $e');
        }
      case 'delete_smart_folder':
        // 删除节点本机指定智能文件夹
        try {
          final dir = await getApplicationSupportDirectory();
          final sfFile = File('${dir.path}/smart_folders_data.json');
          final List<dynamic> existingList;
          if (await sfFile.exists()) {
            final raw = await sfFile.readAsString();
            existingList = raw.isNotEmpty ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
          } else {
            existingList = <dynamic>[];
          }
          final targetId = (params['id'] ?? '').toString();
          existingList.removeWhere((e) => (e as Map<String, dynamic>)['id'] == targetId);
          await sfFile.writeAsString(jsonEncode(existingList));
          _emitLibraryMutation();
          return <String, dynamic>{'ok': true};
        } catch (e) {
          throw StateError('删除智能文件夹失败: $e');
        }
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
      case 'delete_collection_local_files':
        final deleteCollectionId = (params['collection_id'] ?? '').toString();
        try {
          final deletedCount = media_api.deleteCollectionLocalFiles(
            collectionId: deleteCollectionId,
          );
          return <String, dynamic>{'deleted': deletedCount};
        } catch (_) {
          return <String, dynamic>{'deleted': 0};
        }
      case 'delete_media_item_local_file':
        final deleteItemId = (params['item_id'] ?? '').toString();
        final deleteCollId = (params['collection_id'] ?? '').toString();
        final itemsForDelete = media_api.getMediaCollectionItems(collectionId: deleteCollId);
        final targetItem = itemsForDelete.where((i) => i.id == deleteItemId).firstOrNull;
        if (targetItem != null) {
          try {
            media_api.deleteMediaItemFile(itemFilePath: targetItem.filePath);
          } catch (_) {}
          _emitLibraryMutation();
        }
        return <String, dynamic>{'ok': targetItem != null};
      case 'move_media_collection_to_folder':
        final collectionId = (params['collection_id'] ?? '').toString();
        final folderIdValue = params['folder_id'];
        final folderId = folderIdValue?.toString();
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
        final folderId = folderIdValue?.toString();
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

  // ── 序列化工具 ───────────────────────────────────────────────────────────

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

  // ── 媒体上传处理 ──────────────────────────────────────────────────────────

  /// 接受客户端发来的媒体文件上传（multipart/form-data）。
  /// 期望字段：file（文件数据）、filename（原始文件名）、collection_id（可选，目标集合 ID）。
  Future<void> _handleMediaUpload(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    void writeJson(Map<String, dynamic> data) {
      request.response.write(jsonEncode(_sanitizeJsonValue(data)));
    }

    try {
      final contentType = request.headers.contentType;
      final boundary = contentType?.parameters['boundary'];
      if (boundary == null) {
        request.response.statusCode = HttpStatus.badRequest;
        writeJson(<String, dynamic>{'success': false, 'error': 'Missing multipart boundary'});
        await request.response.close();
        return;
      }

      // 手动解析 multipart body
      final bodyBytes = await request.fold<List<int>>(
        <int>[],
        (prev, element) => prev..addAll(element),
      );
      _recordAppTraffic(txBytes: 0, rxBytes: bodyBytes.length);

      final parsed = _parseMultipart(bodyBytes, boundary);
      final fileBytes = parsed['file'] as Uint8List?;
      final filename =
          (parsed['filename'] as String?) ?? 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
      // ignore: unused_local_variable
      final collectionId = parsed['collection_id'] as String?;

      if (fileBytes == null || fileBytes.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        writeJson(<String, dynamic>{'success': false, 'error': 'No file data'});
        await request.response.close();
        return;
      }

      // 保存到节点本地上传目录
      final uploadRoot = await _getUploadDir();
      final destFile = File('${uploadRoot.path}/$filename');
      await destFile.writeAsBytes(fileBytes);

      // 将文件导入到媒体集合
      // 扫描上传目录，自动将文件加入集合（或创建新集合）
      final importPath = destFile.parent.path;
      await media_api.scanMediaFolders(folderPath: importPath);
      _emitLibraryMutation();

      request.response.statusCode = HttpStatus.ok;
      writeJson(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'saved_path': destFile.path, 'size': fileBytes.length},
      });
    } catch (e, st) {
      _logger.error('媒体上传处理失败', error: e, stackTrace: st);
      request.response.statusCode = HttpStatus.internalServerError;
      writeJson(<String, dynamic>{'success': false, 'error': e.toString()});
    }
    await request.response.close();
  }

  Future<Directory> _getUploadDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/node_uploads');
    await dir.create(recursive: true);
    return dir;
  }

  /// 极简 multipart 解析器：仅读取 file 字段的字节和 filename/collection_id 文本字段。
  Map<String, Object> _parseMultipart(List<int> body, String boundary) {
    final result = <String, Object>{};
    final sep = utf8.encode('--$boundary');
    int pos = 0;
    // 找到第一个 boundary
    while (pos < body.length) {
      final idx = _indexOfSeq(body, sep, pos);
      if (idx < 0) break;
      pos = idx + sep.length;
      // skip CRLF after boundary
      if (pos < body.length - 1 && body[pos] == 13 && body[pos + 1] == 10) {
        pos += 2;
      } else if (pos < body.length &&
          body[pos] == 45 &&
          pos + 1 < body.length &&
          body[pos + 1] == 45) {
        break; // -- (end boundary)
      }

      // read headers until blank line (\r\n\r\n)
      final headerEnd = _indexOfSeq(body, [13, 10, 13, 10], pos);
      if (headerEnd < 0) break;
      final headerStr = utf8.decode(body.sublist(pos, headerEnd), allowMalformed: true);
      pos = headerEnd + 4;

      // parse Content-Disposition
      String? fieldName;
      String? fileFilename;
      for (final line in headerStr.split('\r\n')) {
        final lower = line.toLowerCase();
        if (lower.startsWith('content-disposition:')) {
          final re = RegExp(r'name="([^"]*)"');
          final fnRe = RegExp(r'filename="([^"]*)"');
          final m = re.firstMatch(line);
          final fm = fnRe.firstMatch(line);
          fieldName = m?.group(1);
          fileFilename = fm?.group(1);
        }
      }
      if (fieldName == null) continue;

      // find the next boundary to delimit the value
      final nextBound = _indexOfSeq(body, [13, 10, ...sep], pos);
      final valueEnd = nextBound >= 0 ? nextBound : body.length;
      final valueBytes = body.sublist(pos, valueEnd);

      if (fileFilename != null || fieldName == 'file') {
        result['file'] = Uint8List.fromList(valueBytes);
        if (fileFilename != null && fileFilename.isNotEmpty) {
          result['filename'] = fileFilename;
        }
      } else {
        result[fieldName] = utf8.decode(valueBytes, allowMalformed: true).trim();
      }
      pos = valueEnd;
    }
    return result;
  }

  int _indexOfSeq(List<int> haystack, List<int> needle, int start) {
    outer:
    for (int i = start; i <= haystack.length - needle.length; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
