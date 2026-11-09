part of 'media_library_viewmodel.dart';

/// 资源来源构建与封面/缩略图/scrub 帧生成。
/// 通过 extension 挂载到 [MediaLibraryViewModel]，共享同一库私有成员。
extension MediaLibrarySourceBuildersExt on MediaLibraryViewModel {
  /// [isCover] = true 时使用「远程封面清晰度」（列表缩略图），false 时用「远程图片清晰度」（预览全图）。
  String? buildMediaSource(
    media_api.MediaItem item, {
    String? collectionId,
    bool isCover = false,
  }) {
    final targetCollectionId = collectionId ?? currentCollectionId.value;
    if (targetCollectionId == null) {
      return item.filePath;
    }
    if (!isRemoteCollection(targetCollectionId)) {
      // 本地图片：网格缩略图（isCover=true）走缩略图管线，生成后缓存到资源旁的 .SlimeWorks/tmp；
      // 预览大图（isCover=false）仍用原图。
      if (isCover && item.kind == media_api.MediaKind.image) {
        // 读取异步版本号，注册响应式依赖（缩略图生成完成后触发重建）
        _asyncCoverVersion.value;
        final cached = _itemThumbnails[item.filePath];
        if (cached != null) return cached;
        // 缩略图还没就绪时返回 null，让卡片显示加载态：
        // 原图动辄数千万像素，拿去当封面解码慢、占内存，解码失败还会闪一下「无图片」图标。
        // 只有缩略图生成失败或用户暂停生成时才退回原图，否则这张图会一直空着。
        if (_itemThumbFailed.contains(item.filePath) ||
            thumbGenerationPaused.value) {
          return item.filePath;
        }
        _enqueueItemThumbnail(item.filePath);
        return null;
      }
      return item.filePath;
    }
    final nodeId = getRemoteNodeId(targetCollectionId);
    if (nodeId == null) {
      return null;
    }
    if (isCover) {
      // 「随本地」档在此解析为本地缩略图质量；0=原图时不带 width 参数，节点直传原图
      final width = mediaPrefs.effectiveRemoteCoverWidth;
      return nodeSettingsService.buildNodeMediaUrl(
        nodeId: nodeId,
        filePath: item.filePath,
        thumbnailWidth: width > 0 ? width : null,
        isCover: true,
      );
    }
    final width = mediaPrefs.remoteImageWidth.value;
    return nodeSettingsService.buildNodeMediaUrl(
      nodeId: nodeId,
      filePath: item.filePath,
      thumbnailWidth: width > 0 ? width : null,
    );
  }

  /// 远程图片兜底原图 URL：不带缩放参数，节点直接传输原始文件。
  /// 供缩略图 2s 超时临时充当封面使用。
  String? buildRemoteOriginalMediaSource(
    media_api.MediaItem item, {
    String? collectionId,
  }) {
    final targetCollectionId = collectionId ?? currentCollectionId.value;
    if (targetCollectionId == null || !isRemoteCollection(targetCollectionId)) {
      return null;
    }
    if (item.kind != media_api.MediaKind.image) {
      return null;
    }
    final nodeId = getRemoteNodeId(targetCollectionId);
    if (nodeId == null) {
      return null;
    }
    return nodeSettingsService.buildNodeMediaUrl(
      nodeId: nodeId,
      filePath: item.filePath,
    );
  }

  String? buildCollectionCoverSource(media_api.MediaCollection collection) {
    // 读取异步封面版本，在 Obx 上下文中注册响应式依赖
    _asyncCoverVersion.value;
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }
    if (isRemoteCollection(collection.id)) {
      // 远程集合：视频/音频封面路径均通过节点 URL 返回（服务端节点内存缩略图提取帧/封面，不落盘）
      final nodeId = getRemoteNodeId(collection.id);
      if (nodeId == null) return null;
      // 应用节点可用图片清晰度（含「随本地」档），节省上行带宽；isCover=true 使服务端用对应保护策略
      final width = mediaPrefs.effectiveRemoteCoverWidth;
      return nodeSettingsService.buildNodeMediaUrl(
        nodeId: nodeId,
        filePath: coverPath,
        thumbnailWidth: width > 0 ? width : null,
        isCover: true,
      );
    }
    // 本地视频封面 — 异步生成缩略图（暂停期间不入队）
    if (MediaLibraryViewModel._isVideoPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!thumbGenerationPaused.value &&
          !_collectionCoverFailed.contains(collection.id) &&
          !_coverQueue.contains(collection.id) &&
          !_inFlightCoverKeys.contains(collection.id)) {
        _generateCollectionVideoThumbnailAsync(collection.id, coverPath);
      }
      return null;
    }
    // 本地音频封面 — 异步提取嵌入专辑封面（暂停期间不入队）
    if (MediaLibraryViewModel._isAudioPath(coverPath)) {
      if (_collectionVideoThumbnails.containsKey(collection.id)) {
        return _collectionVideoThumbnails[collection.id];
      }
      if (!thumbGenerationPaused.value &&
          !_audioCoverEmptyCollections.contains(collection.id) &&
          !_collectionCoverFailed.contains(collection.id) &&
          !_coverQueue.contains(collection.id) &&
          !_inFlightCoverKeys.contains(collection.id)) {
        _generateCollectionAudioCoverAsync(collection.id, coverPath);
      }
      return null;
    }
    return coverPath;
  }

  /// 封面异步版本号（读取即注册响应式依赖）。
  ///
  /// 详情页的 Obx 需要在 build 期间读一次：GridView 的 itemBuilder 在布局阶段执行，
  /// 那时已不在 Rx 的依赖收集窗口内，卡片里读版本号不会真正建立订阅。
  int get coverVersionTick => _asyncCoverVersion.value;

  /// 该图片条目的网格缩略图是否仍在生成（供卡片显示加载态而不是占位图标）。
  ///
  /// 远程图片由节点按需生成，交给图片自身的首帧加载态，这里一律返回 false。
  bool isItemCoverGenerating(
    media_api.MediaItem item, {
    String? collectionId,
  }) {
    // 注册响应式依赖：缩略图落地后卡片能重建
    _asyncCoverVersion.value;
    if (item.kind != media_api.MediaKind.image) return false;
    final targetCollectionId = collectionId ?? currentCollectionId.value;
    if (targetCollectionId != null && isRemoteCollection(targetCollectionId)) {
      return false;
    }
    if (_itemThumbnails.containsKey(item.filePath)) return false;
    if (_itemThumbFailed.contains(item.filePath)) return false;
    if (thumbGenerationPaused.value) return false;
    return true;
  }

  /// 该集合的封面是否正在生成（本地视频抽帧 / 音频提取，且尚无结果）。
  /// 卡片据此在 source 为空时显示加载态，而不是「图片错误」图标。
  bool isCollectionCoverGenerating(media_api.MediaCollection collection) {
    // 注册响应式依赖：生成完成后卡片能重建
    _asyncCoverVersion.value;
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) return false;
    // 远程封面有 URL，由节点按需生成；图区用图片首帧加载态即可
    if (isRemoteCollection(collection.id)) return false;
    if (thumbGenerationPaused.value) return false;
    final isVideo = MediaLibraryViewModel._isVideoPath(coverPath);
    final isAudio = MediaLibraryViewModel._isAudioPath(coverPath);
    if (!isVideo && !isAudio) return false;
    if (_collectionVideoThumbnails.containsKey(collection.id)) return false;
    if (_collectionCoverFailed.contains(collection.id)) return false;
    if (isAudio && _audioCoverEmptyCollections.contains(collection.id)) {
      return false;
    }
    return true;
  }

  /// 文件夹封面取第一个集合；与 [buildFolderCoverSource] 的选中规则同源。
  media_api.MediaCollection? _firstCoverCollectionForFolder(
    media_api.MediaFolder folder,
  ) {
    if (isDupGroup(folder.id)) {
      final grouped = dupGroupCollections(folder.id);
      if (grouped.isEmpty) return null;
      final sorted = _applySortOrder(List.of(grouped), folder.id);
      return sorted.isEmpty ? null : sorted.first;
    }
    return _findFirstCollectionForFolder(folder.id);
  }

  /// 文件夹封面是否正在生成（封面来自该文件夹下的首个集合）。
  bool isFolderCoverGenerating(media_api.MediaFolder folder) {
    final collection = _firstCoverCollectionForFolder(folder);
    return collection == null ? false : isCollectionCoverGenerating(collection);
  }

  /// 智能文件夹封面是否正在生成（封面来自命中的首个集合）。
  bool isSmartFolderCoverGenerating(SmartFolder sf) {
    final sorted = _applySortOrder(
      List.of(collectionsMatchingSmartFolder(sf)),
      sf.id,
    );
    if (sorted.isEmpty) return false;
    return isCollectionCoverGenerating(sorted.first);
  }

  /// 为本地集合入队封面生成（导入时勾选「全文件生成缩略图」与启动预热共用）。
  /// [trackFolder] = false 时任务不进入当前文件夹取消组，离开文件夹不会中断。
  ///
  /// 入队前先查磁盘缓存是否已就绪：内存缓存只活在本次进程里，重新导入 /
  /// 重新扫描时它多半是空的。不查磁盘就会把早已生成好的封面全部重排一遍，
  /// 用户看到的是「文件没动却又冒出一批任务」。命中时直接写内存缓存，不入队。
  void enqueueLocalCollectionCover(
    media_api.MediaCollection collection, {
    bool trackFolder = true,
    bool force = false,
  }) {
    if (thumbGenerationPaused.value) return;
    if (isRemoteCollection(collection.id)) return;
    final coverPath = collection.coverPath;
    if (coverPath == null || coverPath.isEmpty) return;
    if (MediaLibraryViewModel._isVideoPath(coverPath)) {
      _generateCollectionVideoThumbnailAsync(
        collection.id,
        coverPath,
        trackFolder: trackFolder,
        force: force,
      );
    } else if (MediaLibraryViewModel._isAudioPath(coverPath)) {
      _generateCollectionAudioCoverAsync(
        collection.id,
        coverPath,
        trackFolder: trackFolder,
        force: force,
      );
    }
  }

  /// 集合封面在磁盘上是否已就绪；就绪则直接写内存缓存并返回 true。
  ///
  /// 视频按「预览清晰度」宽度、音频按音频封面固定宽度（300）各查一次，
  /// 与真实生成路径用的宽度保持一致，否则会永远查不到而每轮都重排。
  Future<bool> _adoptReadyCoverCover(String collectionId, String coverPath) async {
    final isVideo = MediaLibraryViewModel._isVideoPath(coverPath);
    final isAudio = MediaLibraryViewModel._isAudioPath(coverPath);
    if (!isVideo && !isAudio) return false;
    try {
      final width = isAudio ? 300 : mediaPrefs.localPreviewWidth.value;
      final ready = await media_api.readyCoverThumbnailPath(
        filePath: coverPath,
        width: width > 0 ? width : 480,
      );
      if (ready == null || ready.isEmpty) return false;
      _collectionVideoThumbnails[collectionId] = ready;
      return true;
    } catch (e) {
      // 查询失败就当作未就绪，交给正常生成路径兜底
      _logger.error('[CoverReady] 磁盘就绪查询失败: $collectionId err=$e');
      return false;
    }
  }

  /// 应用启动后预热本地集合封面：不再等用户点进文件夹才由卡片惰性触发。
  void prewarmLocalCollectionCovers() {
    if (thumbGenerationPaused.value) return;
    int count = 0;
    for (final collection in collections) {
      if (isRemoteCollection(collection.id)) continue;
      final coverPath = collection.coverPath;
      if (coverPath == null || coverPath.isEmpty) continue;
      if (!MediaLibraryViewModel._isVideoPath(coverPath) &&
          !MediaLibraryViewModel._isAudioPath(coverPath)) {
        continue;
      }
      if (_collectionVideoThumbnails.containsKey(collection.id) ||
          _collectionCoverFailed.contains(collection.id) ||
          _audioCoverEmptyCollections.contains(collection.id)) {
        continue;
      }
      enqueueLocalCollectionCover(collection, trackFolder: false);
      count++;
    }
    if (count > 0) {
      _logger.info('[CoverPrewarm] 启动预热 $count 个本地集合封面');
    }
  }

  /// 从帧列表中挑选封面帧：优先选第一个文件体积大于 1KB 的帧，
  /// 避免选中纯黑帧（部分视频开头/中间为黑屏，生成的封面看起来像没有封面）。
  String _pickCoverFrame(List<String> frames) {
    for (final path in frames) {
      try {
        if (File(path).lengthSync() > 1024) return path;
      } catch (_) {}
    }
    return frames[frames.length ~/ 2];
  }

  void _generateCollectionVideoThumbnailAsync(
    String collectionId,
    String videoPath, {
    bool trackFolder = true,
    bool force = false,
  }) {
    if (_collectionVideoThumbnails.containsKey(collectionId) ||
        _collectionCoverFailed.contains(collectionId) ||
        _coverQueue.contains(collectionId) ||
        _inFlightCoverKeys.contains(collectionId)) {
      return;
    }
    // 覆盖模式：磁盘预检一律跳过，直接重新生成
    if (force) {
      _enqueueCollectionVideoCover(collectionId, videoPath, trackFolder: trackFolder);
      return;
    }
    // 先占位再异步查磁盘：查询期间同一集合不会被重复入队
    _inFlightCoverKeys.add(collectionId);
    _adoptReadyCoverCover(collectionId, videoPath).then((ready) {
      _inFlightCoverKeys.remove(collectionId);
      if (ready) {
        // 磁盘命中：只通知卡片刷新，不产生任何生成任务
        _logger.info('[VideoThumb] 磁盘已就绪，跳过入队: collectionId=$collectionId');
        _notifyCoverChanged();
        return;
      }
      _enqueueCollectionVideoCover(collectionId, videoPath, trackFolder: trackFolder);
    });
  }

  void _enqueueCollectionVideoCover(
    String collectionId,
    String videoPath, {
    bool trackFolder = true,
  }) {
    if (_collectionVideoThumbnails.containsKey(collectionId) ||
        _collectionCoverFailed.contains(collectionId) ||
        _coverQueue.contains(collectionId) ||
        _inFlightCoverKeys.contains(collectionId)) {
      return;
    }
    _logger.info('[VideoThumb] 入队封面: collectionId=$collectionId');
    // 仅卡片惰性触发的任务跟随文件夹取消；导入/启动预热任务必须跑完
    if (trackFolder) _currentFolderCoverKeys.add(collectionId);
    _inFlightCoverKeys.add(collectionId);
    _coverQueue
        .enqueue(collectionId, () async {
          if (trackFolder) _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
          try {
            // 「预生成视频悬停帧」关闭时，只提取单帧默认封面，不抽整套 scrub 帧；
            // 整套悬停帧仅由悬停（prefetch / hover）路径触发生成。
            if (!mediaPrefs.videoScrubPreload.value) {
              final single = await media_api.ensureCoverThumbnail(
                filePath: videoPath,
                width: mediaPrefs.localPreviewWidth.value,
              );
              if (single == null || single.isEmpty) {
                _logger.info(
                  '[VideoThumb] 单帧封面为空，不缓存: collectionId=$collectionId',
                );
                _collectionCoverFailed.add(collectionId);
                _notifyCoverChanged();
                return;
              }
              _collectionVideoThumbnails[collectionId] = single;
              _notifyCoverChanged();
              return;
            }
            final frames = await _doGetScrubFrames(videoPath);
            if (frames.isEmpty) {
              _logger.info('[VideoThumb] 帧为空，不缓存: collectionId=$collectionId');
              _collectionCoverFailed.add(collectionId);
              _notifyCoverChanged();
              return;
            }
            final thumb = _pickCoverFrame(frames);
            _logger.info(
              '[VideoThumb] 封面生成成功: collectionId=$collectionId thumb=$thumb',
            );
            _collectionVideoThumbnails[collectionId] = thumb;
            _notifyCoverChanged();
          } catch (e) {
            _logger.error(
              '[VideoThumb] 封面生成失败: collectionId=$collectionId err=$e',
            );
            // 记录失败，避免卡片永久停在加载态；重启/重建 VM 后可再次尝试
            _collectionCoverFailed.add(collectionId);
            _notifyCoverChanged();
          }
        })
        .whenComplete(() {
          // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
          if (trackFolder) _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
        });
  }

  void _generateCollectionAudioCoverAsync(
    String collectionId,
    String audioPath, {
    bool trackFolder = true,
    bool force = false,
  }) {
    if (_collectionVideoThumbnails.containsKey(collectionId) ||
        _audioCoverEmptyCollections.contains(collectionId) ||
        _collectionCoverFailed.contains(collectionId) ||
        _coverQueue.contains(collectionId) ||
        _inFlightCoverKeys.contains(collectionId)) {
      return;
    }
    if (force) {
      _enqueueCollectionAudioCover(collectionId, audioPath, trackFolder: trackFolder);
      return;
    }
    // 与视频封面同构：先查磁盘，命中就不排任务（音频封面宽度固定 300）
    _inFlightCoverKeys.add(collectionId);
    _adoptReadyCoverCover(collectionId, audioPath).then((ready) {
      _inFlightCoverKeys.remove(collectionId);
      if (ready) {
        _logger.info('[AudioCover] 磁盘已就绪，跳过入队: collectionId=$collectionId');
        _notifyCoverChanged();
        return;
      }
      _enqueueCollectionAudioCover(collectionId, audioPath, trackFolder: trackFolder);
    });
  }

  void _enqueueCollectionAudioCover(
    String collectionId,
    String audioPath, {
    bool trackFolder = true,
  }) {
    if (_collectionVideoThumbnails.containsKey(collectionId) ||
        _audioCoverEmptyCollections.contains(collectionId) ||
        _collectionCoverFailed.contains(collectionId) ||
        _coverQueue.contains(collectionId) ||
        _inFlightCoverKeys.contains(collectionId)) {
      return;
    }
    _logger.info('[AudioCover] 入队集合封面: collectionId=$collectionId');
    // 仅卡片惰性触发的任务跟随文件夹取消；导入/启动预热任务必须跑完
    if (trackFolder) _currentFolderCoverKeys.add(collectionId);
    _inFlightCoverKeys.add(collectionId);
    _coverQueue
        .enqueue(collectionId, () async {
          if (trackFolder) _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
          try {
            final coverPath = await getAudioCoverSource(audioPath);
            if (coverPath == null || coverPath.isEmpty) {
              // 文件没变就不可能从无封面变成有封面：记住，页内不再重投
              _audioCoverEmptyCollections.add(collectionId);
              _logger.info('[AudioCover] 无嵌入封面: collectionId=$collectionId');
              _notifyCoverChanged();
              return;
            }
            _logger.info('[AudioCover] 封面提取成功: collectionId=$collectionId');
            _collectionVideoThumbnails[collectionId] = coverPath;
            _notifyCoverChanged();
          } catch (e) {
            _logger.error(
              '[AudioCover] 封面提取失败: collectionId=$collectionId err=$e',
            );
            _collectionCoverFailed.add(collectionId);
            _notifyCoverChanged();
          }
        })
        .whenComplete(() {
          // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
          if (trackFolder) _currentFolderCoverKeys.remove(collectionId);
          _inFlightCoverKeys.remove(collectionId);
        });
  }

  /// 为本地图片条目入队缩略图生成任务（宽度取「本地图片清晰度」设置，或 widthOverride）。
  /// 生成期间网格先显示原图，成功后切换到缩略图并缓存进 .SlimeWorks/tmp。
  ///
  /// 入队前先问 Rust「磁盘缓存是否就绪」：内存缓存只活在本次进程里，
  /// 重启后再导入/重扫时它必然是空的——不查磁盘就会把已经生成好的封面对统统
  /// 重排一遍，用户看到的就是"文件没动却又冒出一批任务"。
  void _enqueueItemThumbnail(String filePath, {int? widthOverride}) {
    if (thumbGenerationPaused.value) return;
    if (_itemThumbnails.containsKey(filePath) ||
        _itemThumbFailed.contains(filePath)) {
      return;
    }
    final key = 'item-thumb:$filePath';
    if (_coverQueue.contains(key) || _inFlightCoverKeys.contains(key)) return;
    final w = widthOverride ?? mediaPrefs.localPreviewWidth.value;
    final width = w > 0 ? w : 480;
    // 入队前先查磁盘：命中就直接采用，连任务都不产生
    // （放在闭包里查的话任务照样会被排进队列，用户看到的仍是"一批新任务"）
    _inFlightCoverKeys.add(key);
    media_api
        .readyCoverThumbnailPath(filePath: filePath, width: width)
        .then((ready) {
          if (ready != null && ready.isNotEmpty) {
            _inFlightCoverKeys.remove(key);
            _itemThumbnails[filePath] = ready;
            _notifyCoverChanged();
            return;
          }
          _coverQueue
              .enqueue(key, () async {
                _inFlightCoverKeys.remove(key);
                try {
                  // FRB 异步调用（Rust 端在后台线程池解码缩放，不阻塞 UI 线程）
                  final thumb = await media_api.ensureCoverThumbnail(
                    filePath: filePath,
                    width: width,
                  );
                  if (thumb == null || thumb.isEmpty) {
                    _itemThumbFailed.add(filePath);
                    // 失败也要通知：卡片此刻停在加载态，不重建就会一直转圈
                    _notifyCoverChanged();
                    return;
                  }
                  _logger.info('[ItemThumb] 缩略图已生成: $thumb');
                  _itemThumbnails[filePath] = thumb;
                  _notifyCoverChanged();
                } catch (e) {
                  _logger.error('[ItemThumb] 缩略图生成失败: $filePath err=$e');
                  _itemThumbFailed.add(filePath);
                  // 同失败分支：让卡片退回原图，而不是永久停留在加载态
                  _notifyCoverChanged();
                }
              })
              .whenComplete(() {
                // 任务被取消时闭包不会执行，此处兜底清理 key，避免永久阻断重新入队
                _inFlightCoverKeys.remove(key);
              });
        })
        .catchError((Object e) {
          // 查询本身失败：不阻断生成，按原路径直接入队（标记已清，不会递归）
          _logger.error('[ItemThumb] 磁盘就绪查询失败: $filePath err=$e');
          _inFlightCoverKeys.remove(key);
          _coverQueue.enqueue(key, () async {
            _inFlightCoverKeys.remove(key);
            try {
              final thumb = await media_api.ensureCoverThumbnail(
                filePath: filePath,
                width: width,
              );
              if (thumb == null || thumb.isEmpty) {
                _itemThumbFailed.add(filePath);
                _notifyCoverChanged();
                return;
              }
              _itemThumbnails[filePath] = thumb;
              _notifyCoverChanged();
            } catch (err) {
              _logger.error('[ItemThumb] 缩略图生成失败: $filePath err=$err');
              _itemThumbFailed.add(filePath);
              _notifyCoverChanged();
            }
          });
        });
  }

  /// 应用启动时从持久化任务表恢复未完成的缩略图任务。
  /// 包括 pending/running/failed 状态，全部重新入队到 VideoThumbQueue。
  /// failed 任务从 _itemThumbFailed 移除以允许重试。
  Future<void> _restorePendingThumbnailTasks() async {
    try {
      final tasks = await media_api.getAllPendingThumbnailTasks();
      if (tasks.isEmpty) return;
      _logger.info('[ThumbRestore] 发现 ${tasks.length} 个未完成缩略图任务，开始重新入队');
      int restored = 0;
      for (final task in tasks) {
        if (task.filePath.isEmpty) continue;
        // 失败任务重新尝试：从失败集合中移除以便重新入队
        _itemThumbFailed.remove(task.filePath);
        _enqueueItemThumbnail(
          task.filePath,
          widthOverride: task.width > 0 ? task.width : null,
        );
        restored++;
      }
      _logger.info('[ThumbRestore] 已重新入队 $restored 个任务');
    } catch (e) {
      _logger.error('[ThumbRestore] 恢复未完成缩略图任务失败: $e');
    }
  }

  String? buildFolderCoverSource(media_api.MediaFolder folder) {
    // 注册响应式依赖：集合排序变更时同步更新文件夹封面
    collectionOrderVersion.value;
    // 优先取「真有封面」的集合：否则首个集合还在生成/已失效时，
    // 文件夹卡会整片空着，哪怕子文件夹里就有现成封面。
    var collection = _findFirstCoveredCollectionForFolder(folder.id);
    if (collection == null && !isDupGroup(folder.id)) {
      // 整棵子树都没有现成封面：退回首个集合，让它异步生成后再显示
      collection = _firstCoverCollectionForFolder(folder);
    }
    if (collection == null) {
      return null;
    }
    // buildCollectionCoverSource 内部已注册封面版本依赖，
    // 视频/音频封面异步生成后文件夹卡也会重建。
    return buildCollectionCoverSource(collection);
  }

  String? buildSmartFolderCoverSource(SmartFolder sf) {
    // 订阅排序版本：集合拖拽重排后封面随之更新
    collectionOrderVersion.value;
    // 过滤后应用自定义排序（与 currentCollections 一致），保证封面反映用户拖拽位置
    final sorted = _applySortOrder(
      List.of(collectionsMatchingSmartFolder(sf)),
      sf.id,
    );
    if (sorted.isEmpty) return null;
    return buildCollectionCoverSource(sorted.first);
  }

  /// 返回最多 [_kHoverScrubFrames] 个均匀采样的封面路径，用于集合卡片悬停预览。
  /// - 图片：直接返回文件路径
  /// - 视频：若已有缩略图则返回缩略图路径，否则返回 null 占位（稍后异步触发生成）
  /// - 远程集合：返回空
  List<String?> buildCollectionHoverSources(
    media_api.MediaCollection collection,
  ) {
    if (isRemoteCollection(collection.id)) return const [];
    final cached = _hoverSourcesCache[collection.id];
    if (cached != null) return cached;
    try {
      // 从按需缓存读取文件路径，避免 build 期间同步 FFI 调用阻塞 UI
      final paths = _getCollectionItemPaths(collection.id);
      if (paths.isEmpty) {
        // 路径还没到：后台补拉，结果到达时 _invalidateVisible 会让卡片重算。
        // 注意**不**缓存空结果——缓存了就再也不会重新计算悬停源。
        if (collection.itemCount > BigInt.zero) {
          requestCollectionItemPaths(collection.id);
        }
        return const [];
      }
      final n = paths.length;
      final count = n.clamp(1, MediaLibraryViewModel._kHoverScrubFrames);
      final result = <String?>[];
      final videoPaths = <String>[];
      for (int i = 0; i < count; i++) {
        final idx = ((i / (count - 1).clamp(1, count - 1)) * (n - 1))
            .round()
            .clamp(0, n - 1);
        final p = paths[idx];
        if (MediaLibraryViewModel._isVideoPath(p)) {
          // 视频：使用已有缩略图或 null 占位；后台触发生成
          final thumb = _collectionVideoThumbnails[collection.id];
          result.add(thumb);
          videoPaths.add(p);
          final hoverKey = 'hover:${collection.id}:$i';
          // 仅在「预生成视频悬停帧」开启时才在 build 时后台为 hover 槽位抽帧；
          // 关闭后不预抽，整套帧只由实际悬停（prefetch / hover）路径触发。
          if (thumb == null &&
              mediaPrefs.videoScrubPreload.value &&
              !thumbGenerationPaused.value &&
              !_coverQueue.contains(hoverKey) &&
              !_inFlightCoverKeys.contains(hoverKey)) {
            _generateHoverVideoThumbnailAsync(collection.id, p, i, count);
          }
        } else {
          result.add(p);
        }
      }
      if (videoPaths.isNotEmpty) {
        _hoverVideoPathsCache[collection.id] = videoPaths;
      }
      _hoverSourcesCache[collection.id] = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  /// 后台为集合 hover 预览中的指定视频帧生成缩略图，完成后触发 UI 刷新。
  void _generateHoverVideoThumbnailAsync(
    String collectionId,
    String videoPath,
    int slotIdx,
    int totalSlots,
  ) {
    final hoverKey = 'hover:$collectionId:$slotIdx';
    _coverQueue.enqueue(hoverKey, () async {
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) return;
        final frameIdx = totalSlots == 1
            ? 0
            : ((slotIdx / (totalSlots - 1)) * (frames.length - 1))
                  .round()
                  .clamp(0, frames.length - 1);
        final thumb = frames[frameIdx];
        final sources = _hoverSourcesCache[collectionId];
        if (sources != null && slotIdx < sources.length) {
          sources[slotIdx] = thumb;
        }
        _notifyCoverChanged();
      } catch (e) {
        _logger.error(
          '[VideoThumb] hover 封面生成失败: collectionId=$collectionId slotIdx=$slotIdx err=$e',
        );
      }
    });
  }

  /// 实时取帧：根据鼠标在卡片上的水平比例 [fraction]∈[0,1]，
  /// 利用该集合内视频的 scrub 帧缓存按比例返回路径。
  /// 若缓存未就绪返回 null（调用方显示 coverSource 即可）。
  String? getCollectionVideoFrameAtFraction(
    String collectionId,
    double fraction,
  ) {
    final videoPaths = _hoverVideoPathsCache[collectionId];
    if (videoPaths == null || videoPaths.isEmpty) return null;
    final slotFraction = fraction.clamp(0.0, 1.0);
    final slotIdx = videoPaths.length == 1
        ? 0
        : (slotFraction * (videoPaths.length - 1)).round().clamp(
              0,
              videoPaths.length - 1,
            );
    final videoPath = videoPaths[slotIdx];
    final frames = _videoFrameResults[videoPath];
    if (frames == null || frames.isEmpty) return null;
    final frameIdx = frames.length == 1
        ? 0
        : (slotFraction * (frames.length - 1)).round().clamp(
            0,
            frames.length - 1,
          );
    return frames[frameIdx];
  }

  /// 将集合内视频的 scrub 帧任务提到 [_scrubQueue] 队首（高优先级预取）。
  /// 供卡片 hover 3s 后触发实时预览使用。
  void prefetchCollectionVideoFrames(String collectionId) {
    final videoPaths = _hoverVideoPathsCache[collectionId];
    if (videoPaths == null) return;
    for (final vp in videoPaths) {
      _enqueueOrPrioritizeScrub(vp, prioritize: true);
    }
  }

  /// 内部：将 [videoPath] 的 scrub 帧抽取任务入队（[prioritize]=true 则插队首）。
  /// 结果写入 [_videoFrameCache]。
  void _enqueueOrPrioritizeScrub(String videoPath, {bool prioritize = false}) {
    // 用户暂停封面生成期间不入队 scrub 帧任务
    if (thumbGenerationPaused.value) return;
    if (_videoFrameCache.containsKey(videoPath)) {
      if (prioritize) _scrubQueue.prioritize(videoPath, () async {});
      return;
    }
    final completer = Completer<List<String>>();
    _videoFrameCache[videoPath] = completer.future;

    Future<void> work() async {
      try {
        final frames = await _doGetScrubFrames(videoPath);
        if (frames.isEmpty) {
          _videoFrameCache.remove(videoPath);
          _videoFrameResults.remove(videoPath);
          completer.complete(const []);
        } else {
          _videoFrameResults[videoPath] = frames;
          completer.complete(frames);
          _notifyCoverChanged();
        }
      } catch (e) {
        _videoFrameCache.remove(videoPath);
        _videoFrameResults.remove(videoPath);
        completer.complete(const []);
        _logger.error('[VideoThumb] scrub 帧失败: $videoPath err=$e');
      }
    }

    if (prioritize) {
      _scrubQueue.prioritize(videoPath, work);
    } else {
      _scrubQueue.enqueue(videoPath, work);
    }
  }

  /// 返回视频的悬停悔放帧列表（异步缓存，重复调用直接返回）。
  /// 优先使用内置 ffmpeg 模块，其次系统 ffmpeg，否则返回空列表（可重试）。
  Future<List<String>> getVideoScrubFrames(String videoPath) async {
    // 若有缓存且非空则直接返回
    final cached = _videoFrameCache[videoPath];
    if (cached != null) {
      final result = await cached;
      if (result.isNotEmpty) return result;
      // 空结果（ffmpeg 当时失败）——移除缓存以便重试
      _videoFrameCache.remove(videoPath);
    }
    // 通过队列排队（普通优先级），结果写入 _videoFrameCache
    _enqueueOrPrioritizeScrub(videoPath);
    return await (_videoFrameCache[videoPath] ?? Future.value(const []));
  }

  /// 异步获取音频文件的封面缩略图路径（提取嵌入的专辑封面）。
  /// 结果缓存在 [_audioCoverCache] 中，相同路径只执行一次。
  Future<String?> getAudioCoverSource(String filePath) {
    return _audioCoverCache.putIfAbsent(
      filePath,
      () => _doGetAudioCover(filePath),
    );
  }

  Future<String?> _doGetAudioCover(String filePath) async {
    // 通过 Rust FFI 调用 ensure_cover_thumbnail（已支持音频封面提取）
    try {
      // 磁盘已就绪就直接用，别为了一张已有的封面再去解一遍文件
      final ready = await media_api.readyCoverThumbnailPath(filePath: filePath, width: 300);
      if (ready != null && ready.isNotEmpty) return ready;
      return await media_api.ensureCoverThumbnail(
        filePath: filePath,
        width: 300,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _doGetScrubFrames(String videoPath) async {
    // 通过 Rust FFI 调用 extract_video_scrub_frames
    try {
      final frameCount = mediaPrefs.currentLevel.frameCount;
      final result = await media_api.extractVideoScrubFrames(
        videoPath: videoPath,
        frameCount: frameCount,
      );
      return result;
    } catch (e) {
      _logger.error('[VideoThumb] scrub 帧提取失败: $e');
      return const <String>[];
    }
  }
}
