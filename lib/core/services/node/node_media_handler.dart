part of 'node_settings_service.dart';

/// 媒体文件 HTTP 服务和图片缩放逻辑（服务端侧）。
/// 缩放由 Rust FFI (`ensure_cover_thumbnail`) 完成：
///   ① Rust 先查磁盘缓存；
///   ② 缓存未命中 → 调 ffmpeg 原生进程缩放（支持 HEIC/AVIF）；
///   ③ ffmpeg 不可用 → 回退纯 Rust `image` crate；
///   ④ 全失败 → Dart 回退原图。
/// Dart 侧额外维护一个 LRU 内存缓存（120 条），命中则完全跳过 Rust 调用。
extension _NodeMediaHandlerExt on NodeSettingsService {
  static const Set<String> _kImageExts = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
    'heic',
    'heif',
    'avif',
  };

  // 判断文件路径是否为图片格式
  bool _isImageFilePath(String path) {
    return _kImageExts.contains(path.split('.').last.toLowerCase());
  }

  static const Set<String> _kVideoExts = {
    'mp4',
    'mov',
    'm4v',
    'mkv',
    'avi',
    'webm',
    'wmv',
    'flv',
    'ts',
  };

  // 判断文件路径是否为视频格式
  bool _isVideoFilePath(String path) {
    return _kVideoExts.contains(path.split('.').last.toLowerCase());
  }

  static const Set<String> _kAudioExts = {
    'mp3',
    'flac',
    'aac',
    'm4a',
    'ogg',
    'opus',
    'wav',
    'wma',
    'ape',
    'aiff',
    'alac',
  };

  // 判断文件路径是否为音频格式
  bool _isAudioFilePath(String path) {
    return _kAudioExts.contains(path.split('.').last.toLowerCase());
  }

  // ── 媒体文件服务 ─────────────────────────────────────────────────────────

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

    // 若请求了缩略图宽度且文件为图片（非 Range 请求），则缩放后返回
    final widthStr = request.uri.queryParameters['width'];
    final requestedWidth = widthStr != null ? int.tryParse(widthStr) : null;
    final isRangeRequest = request.headers.value(HttpHeaders.rangeHeader) != null;
    final isCoverMode = request.uri.queryParameters['mode'] == 'cover';
    // 图片或视频封面请求：调用 Rust ensureCoverThumbnail 统一处理
    if (!isRangeRequest &&
        (_isImageFilePath(filePath) ||
            (isCoverMode && (_isVideoFilePath(filePath) || _isAudioFilePath(filePath))))) {
      // 双向带宽保护：取 min(客户端请求宽度, 服务端本地设置宽度)，0 表示原图
      // mode=cover 使用封面清晰度设置；mode=preview（或无 mode）使用图片预览清晰度设置
      final serverMaxWidth = GetIt.instance.isRegistered<MediaPrefsService>()
          ? (isCoverMode
                ? GetIt.instance.get<MediaPrefsService>().remoteCoverWidth.value
                : GetIt.instance.get<MediaPrefsService>().remoteImageWidth.value)
          : 0;
      final clientWidth = (requestedWidth != null && requestedWidth > 0) ? requestedWidth : 0;
      // 有效宽度：若两端均不为 0 取最小值；若仅一端为 0 则用另一端；两端均 0 则原图
      final effectiveWidth = serverMaxWidth > 0
          ? (clientWidth > 0
                ? (clientWidth < serverMaxWidth ? clientWidth : serverMaxWidth)
                : serverMaxWidth)
          : clientWidth;
      // 视频/音频封面：即使没指定宽度也强制用默认宽度 240 提取帧/封面，避免返回原始媒体文件
      final finalWidth = effectiveWidth > 0
          ? effectiveWidth
          : (isCoverMode && (_isVideoFilePath(filePath) || _isAudioFilePath(filePath)) ? 240 : 0);
      if (finalWidth > 0) {
        await _serveResizedCover(request, file, filePath, finalWidth);
        return;
      }
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final start = int.tryParse(match.group(1) ?? '') ?? 0;
        final end = int.tryParse(match.group(2) ?? '') ?? (totalLength - 1);
        final boundedEnd = end.clamp(start, totalLength - 1);
        final rangeLength = boundedEnd - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$boundedEnd/$totalLength',
        );
        request.response.contentLength = rangeLength;
        await request.response.addStream(file.openRead(start, boundedEnd + 1));
        _recordAppTraffic(txBytes: rangeLength, rxBytes: 0);
        await request.response.close();
        return;
      }
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = totalLength;
    await request.response.addStream(file.openRead());
    _recordAppTraffic(txBytes: totalLength, rxBytes: 0);
    await request.response.close();
  }

  // ── 图片缩放服务 ─────────────────────────────────────────────────────────

  /// Rust FFI 缩放：先查 Dart 内存缓存 (L1)，未命中则调 Rust (L2 = 磁盘缓存 + ffmpeg/image)。
  Future<void> _serveResizedCover(
    HttpRequest request,
    File original,
    String filePath,
    int width,
  ) async {
    final cacheKey = '${filePath.hashCode.toUnsigned(32).toRadixString(16)}_w$width';

    // ① Dart 内存缓存（L1）
    final cachedBytes = _resizedBytesCache[cacheKey];
    if (cachedBytes != null) {
      // 命中后将 key 移到 Map 末尾，维持真正的 LRU 访问顺序
      _resizedBytesCache.remove(cacheKey);
      _resizedBytesCache[cacheKey] = cachedBytes;
      _writeBytesResponse(request, cachedBytes, ContentType('image', 'jpeg'));
      return;
    }

    // ② Rust 处理（磁盘缓存 + ffmpeg/image）
    try {
      final thumbPath = await media_api.ensureCoverThumbnail(
        filePath: filePath,
        width: width,
      );
      if (thumbPath != null && thumbPath.isNotEmpty) {
        final thumbFile = File(thumbPath);
        if (thumbFile.existsSync() && thumbFile.lengthSync() > 0) {
          final bytes = await thumbFile.readAsBytes();
          _putToMemoryCache(cacheKey, bytes);
          _writeBytesResponse(request, bytes, ContentType('image', 'jpeg'));
          return;
        }
      }
    } catch (e) {
      _logger.log('Rust ensure_cover_thumbnail 失败: $e', name: 'WARN');
    }

    // ③ 全失败 → 音频/视频文件无封面时返回 404，避免客户端将媒体字节误当图片解码
    if (_isAudioFilePath(filePath) || _isVideoFilePath(filePath)) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('no cover available');
      await request.response.close();
      return;
    }

    // 图片缩放失败时才回退原图
    await _writeFileResponse(request, original, _guessMediaContentType(filePath));
  }

  /// LRU 淘汰：超过总字节上限时逐步移除最老的条目，防止内存持续增长。
  void _putToMemoryCache(String key, Uint8List bytes) {
    // 若该 key 已存在，先移除旧值
    final existing = _resizedBytesCache[key];
    if (existing != null) {
      _resizedBytesCacheSize -= existing.length;
      _resizedBytesCache.remove(key);
    }
    // 超过字节上限时按 LRU 顺序逐条淘汰
    while (_resizedBytesCacheSize + bytes.length > NodeSettingsService._kBytesCacheMaxBytes &&
        _resizedBytesCache.isNotEmpty) {
      final oldest = _resizedBytesCache.keys.first;
      _resizedBytesCacheSize -= _resizedBytesCache[oldest]!.length;
      _resizedBytesCache.remove(oldest);
    }
    _resizedBytesCache[key] = bytes;
    _resizedBytesCacheSize += bytes.length;
  }

  /// 清除所有内存缓存（节点断开时调用，释放内存）。
  // ignore: unused_element
  void clearMemoryCache() {
    _resizedBytesCache.clear();
    _resizedBytesCacheSize = 0;
  }

  void _writeBytesResponse(HttpRequest request, Uint8List bytes, ContentType contentType) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = contentType;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    // 记录向客户端发出的流量（上行）
    _recordAppTraffic(txBytes: bytes.length, rxBytes: 0);
    request.response.close().ignore();
  }

  Future<void> _writeFileResponse(HttpRequest request, File file, ContentType contentType) async {
    final fileLen = file.lengthSync();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = contentType;
    request.response.contentLength = fileLen;
    await request.response.addStream(file.openRead());
    // 记录向客户端发出的流量（上行）
    _recordAppTraffic(txBytes: fileLen, rxBytes: 0);
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
}
