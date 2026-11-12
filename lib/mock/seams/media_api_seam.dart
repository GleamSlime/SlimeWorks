import 'package:slime_works/mock/data/media_mock_data.dart';
import 'package:slime_works/mock/mock_assets.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/media_collection.dart'
    show
        CachedCollectionStats,
        CollectionCount,
        CollectionLiveStats,
        CoverReadiness,
        MediaCollection,
        MediaFolder,
        MediaItem,
        SmartFolderInfo,
        ThumbnailTaskInfo,
        TransferOutcome;
import 'package:slime_works/src/rust/api/media_collection.dart' as rust;

export 'package:slime_works/src/rust/api/media_collection.dart'
    show
        CachedCollectionStats,
        CollectionCount,
        CollectionLiveStats,
        CoverReadiness,
        MediaCollection,
        MediaFolder,
        MediaItem,
        MediaKind,
        SmartFolderFileType,
        SmartFolderInfo,
        SmartFolderRegexTarget,
        ThumbnailTaskInfo;

/// 媒体库数据接缝：Mock 开启时走本地演示数据，否则原样转发 Rust。
MockMediaData get _m => MockMediaData.instance;

void registerFfmpegConcurrency({required int limit}) {
  if (MockMode.enabled) return;
  rust.registerFfmpegConcurrency(limit: limit);
}

String? findCollectionConfigDir({required String rootDir}) {
  if (MockMode.enabled) return null;
  return rust.findCollectionConfigDir(rootDir: rootDir);
}

String? ensureCollectionConfigDir({required String rootDir}) {
  if (MockMode.enabled) return '$rootDir/.SlimeWorks';
  return rust.ensureCollectionConfigDir(rootDir: rootDir);
}

Future<List<MediaCollection>> getAllMediaCollections() async {
  if (MockMode.enabled) return List<MediaCollection>.of(_m.collections);
  return rust.getAllMediaCollections();
}

Future<List<MediaFolder>> getAllMediaFolders() async {
  if (MockMode.enabled) return List<MediaFolder>.of(_m.folders);
  return rust.getAllMediaFolders();
}

Future<List<MediaFolder>> getChildMediaFolders({required String parentId}) async {
  if (MockMode.enabled) return _m.childFolders(parentId);
  return rust.getChildMediaFolders(parentId: parentId);
}

Future<List<MediaItem>> getMediaCollectionItems({
  required String collectionId,
}) async {
  if (MockMode.enabled) return _m.itemsOf(collectionId);
  return rust.getMediaCollectionItems(collectionId: collectionId);
}

Future<MediaCollection> importMediaFolder({required String folderPath}) async {
  if (MockMode.enabled) return _m.importFromPath(folderPath);
  return rust.importMediaFolder(folderPath: folderPath);
}

Future<MediaCollection> rescanMediaFolder({required String folderPath}) async {
  if (MockMode.enabled) {
    for (final c in _m.collections) {
      if (c.folderPath == folderPath) return c;
    }
    return _m.importFromPath(folderPath);
  }
  return rust.rescanMediaFolder(folderPath: folderPath);
}

Future<List<MediaCollection>> scanMediaFolders({required String folderPath}) async {
  if (MockMode.enabled) return <MediaCollection>[_m.importFromPath(folderPath)];
  return rust.scanMediaFolders(folderPath: folderPath);
}

MediaFolder createMediaFolder({required String name}) {
  if (MockMode.enabled) return _m.createFolder(name);
  return rust.createMediaFolder(name: name);
}

MediaFolder createChildMediaFolder({
  required String name,
  required String parentId,
}) {
  if (MockMode.enabled) return _m.createFolder(name, parentId: parentId);
  return rust.createChildMediaFolder(name: name, parentId: parentId);
}

bool renameMediaCollection({
  required String collectionId,
  required String title,
}) {
  if (MockMode.enabled) return _m.renameCollection(collectionId, title);
  return rust.renameMediaCollection(collectionId: collectionId, title: title);
}

bool moveMediaCollectionToFolder({
  required String collectionId,
  String? folderId,
}) {
  if (MockMode.enabled) return _m.moveCollection(collectionId, folderId);
  return rust.moveMediaCollectionToFolder(
    collectionId: collectionId,
    folderId: folderId,
  );
}

bool renameMediaFolder({required String folderId, required String name}) {
  if (MockMode.enabled) return _m.renameFolder(folderId, name);
  return rust.renameMediaFolder(folderId: folderId, name: name);
}

bool deleteMediaFolder({required String folderId}) {
  if (MockMode.enabled) return _m.deleteFolder(folderId);
  return rust.deleteMediaFolder(folderId: folderId);
}

bool deleteMediaCollection({required String collectionId}) {
  if (MockMode.enabled) return _m.deleteCollection(collectionId);
  return rust.deleteMediaCollection(collectionId: collectionId);
}

(int, int) clearAllLocalMedia({
  required bool clearAppThumbnailCache,
  required bool clearResourceThumbnailCache,
}) {
  if (MockMode.enabled) {
    _m.collections.clear();
    _m.items.clear();
    return (0, 0);
  }
  return rust.clearAllLocalMedia(
    clearAppThumbnailCache: clearAppThumbnailCache,
    clearResourceThumbnailCache: clearResourceThumbnailCache,
  );
}

Future<List<ThumbnailTaskInfo>> getAllPendingThumbnailTasks() async {
  if (MockMode.enabled) return const <ThumbnailTaskInfo>[];
  return rust.getAllPendingThumbnailTasks();
}

Future<String?> ensureCoverThumbnail({
  required String filePath,
  required int width,
}) async {
  if (MockMode.enabled) {
    if (filePath.endsWith('.png')) return filePath;
    return MockAssets.imagePath(
      'thumb-$filePath',
      width: width <= 0 ? 480 : width,
      height: ((width <= 0 ? 480 : width) * 0.72).round(),
    );
  }
  return rust.ensureCoverThumbnail(filePath: filePath, width: width);
}

/// 只查不生成：磁盘上已有该宽度缩略图缓存时返回其路径，否则 null。
///
/// Mock 模式没有真实磁盘缓存，一律返回 null 让上层走正常生成路径；
/// 否则会拿真实文件路径去 mock 资源里查，结果不可预期。
Future<String?> readyCoverThumbnailPath({
  required String filePath,
  required int width,
}) async {
  if (MockMode.enabled) return null;
  return rust.readyCoverThumbnailPath(filePath: filePath, width: width);
}

/// 批量版就绪判定：一次 FFI 判一整批文件（三态：ready/no_cover/pending/missing）。
///
/// 用途：重扫封面、启动预热这类「一上来就是几十上百个文件」的场景。
/// 逐个调 [readyCoverThumbnailPath] 是每文件一次跨语言往返，实测一个
/// 34 个 m4a 的目录要空转几十秒；批量把 N 次往返压成 1 次。
/// Mock 模式没有真实磁盘，一律 pending 让上层走正常生成路径。
Future<List<CoverReadiness>> coverReadinessBatch({
  required List<String> filePaths,
  required int width,
}) async {
  if (filePaths.isEmpty) return const <CoverReadiness>[];
  if (MockMode.enabled) {
    return List<CoverReadiness>.filled(
      filePaths.length,
      const CoverReadiness(status: 'pending'),
    );
  }
  return rust.coverReadinessBatch(filePaths: filePaths, width: width);
}

/// 只查不生成：读取资源旁已缓存的振幅波形（没有/源文件已变则 null）。
Future<List<double>?> readVideoWaveform({
  required String filePath,
  required int bins,
}) async {
  if (MockMode.enabled) return null;
  return rust.readVideoWaveform(filePath: filePath, bins: bins);
}

/// 该文件是否「已知没有音轨」（负缓存命中）。
///
/// GIF 转出来的 mp4、纯画面录屏根本没有音频流，补波形注定失败。Rust 侧按
/// 文件身份（size|mtime）记住这个结论，这里在入队前先问一句，命中就完全不
/// 排任务——省掉每次导入/重扫对这些文件白跑一遍 symphonia + ffmpeg 探测。
/// 异步：内部 stat 在网络卷上是往返开销，不能挂在 UI isolate（见 Rust 侧注释）。
Future<bool> videoWaveformAbsent({required String filePath}) async {
  if (MockMode.enabled) return false;
  return rust.videoWaveformAbsent(filePath: filePath);
}

/// 生成（或读缓存）振幅波形，结果写入资源旁 .SlimeWorks/waveform。
Future<List<double>> ensureVideoWaveform({
  required String filePath,
  required int bins,
}) async {
  if (MockMode.enabled) return <double>[];
  return rust.ensureVideoWaveform(filePath: filePath, bins: bins);
}

// getAllCollectionStats 接缝已删除：遗留死接口（整表冷加载 + 全量路径跨 FFI），
// 生产链路已改走聚合小表（getCachedCollectionLiveStats）与按需路径
// （getCollectionFilePaths），Mock 侧无需再保留对应桩。

Future<List<bool>> checkPathsExist({required List<String> paths}) async {
  if (MockMode.enabled) return List<bool>.filled(paths.length, true);
  return rust.checkPathsExist(paths: paths);
}

Future<List<CollectionLiveStats>> getAllCollectionLiveStats() async {
  if (MockMode.enabled) {
    return _m.collections.map((c) {
      final list = _m.itemsOf(c.id);
      return CollectionLiveStats(
        collectionId: c.id,
        liveSize: list.fold(BigInt.zero, (sum, e) => sum + e.fileSize),
        liveCount: list.length,
      );
    }).toList();
  }
  return rust.getAllCollectionLiveStats();
}

/// 读缓存版现存统计：只查聚合小表，过期时 Rust 侧后台补扫。
Future<List<CachedCollectionStats>> getCachedCollectionLiveStats() async {
  if (MockMode.enabled) {
    return _m.collections.map((c) {
      final list = _m.itemsOf(c.id);
      final size = list.fold(BigInt.zero, (sum, e) => sum + e.fileSize);
      return CachedCollectionStats(
        collectionId: c.id,
        recordedSize: size,
        liveSize: size,
        liveCount: list.length,
      );
    }).toList();
  }
  return rust.getCachedCollectionLiveStats();
}

/// 按需取单个集合的文件路径快照。
Future<List<String>> getCollectionFilePaths({required String collectionId}) async {
  if (MockMode.enabled) {
    return _m.itemsOf(collectionId).map((e) => e.filePath).toList();
  }
  return rust.getCollectionFilePaths(collectionId: collectionId);
}

Future<List<CollectionCount>> getAllCollectionCounts() async {
  if (MockMode.enabled) {
    return _m.collections
        .map(
          (c) => CollectionCount(
            collectionId: c.id,
            itemCount: _m.itemsOf(c.id).length,
            totalSize: _m.itemsOf(c.id).fold(
              BigInt.zero,
              (sum, e) => sum + e.fileSize,
            ),
          ),
        )
        .toList();
  }
  return rust.getAllCollectionCounts();
}

Future<List<String>> extractVideoScrubFrames({
  required String videoPath,
  required int frameCount,
}) async {
  if (MockMode.enabled) {
    final count = frameCount.clamp(1, 12);
    return List<String>.generate(
      count,
      (i) => MockAssets.imagePath(
        'scrub-$videoPath-$i',
        width: 640,
        height: 360,
      ),
    );
  }
  return rust.extractVideoScrubFrames(
    videoPath: videoPath,
    frameCount: frameCount,
  );
}

bool deleteMediaItemFile({required String itemFilePath}) {
  if (MockMode.enabled) return _m.deleteItemFile(itemFilePath);
  return rust.deleteMediaItemFile(itemFilePath: itemFilePath);
}

int deleteCollectionLocalFiles({required String collectionId}) {
  if (MockMode.enabled) {
    _m.items.remove(collectionId);
    return 1;
  }
  return rust.deleteCollectionLocalFiles(collectionId: collectionId);
}

/// 转移集合，同时带回成功与失败数量。
///
/// 旧实现只回成功数：中途失败的集合在 UI 上和"没转移"完全一样，
/// 用户看到"成功转移 3 个"却少了一个，也无从知道有失败。
Future<TransferOutcome> transferCollectionsWithStats({
  required List<String> collectionIds,
  required String targetDir,
}) async {
  if (MockMode.enabled) {
    return TransferOutcome(successCount: collectionIds.length, failCount: 0);
  }
  return rust.transferCollectionsWithStats(
    collectionIds: collectionIds,
    targetDir: targetDir,
  );
}

Future<int> transferCollections({
  required List<String> collectionIds,
  required String targetDir,
}) async {
  if (MockMode.enabled) return collectionIds.length;
  return rust.transferCollections(
    collectionIds: collectionIds,
    targetDir: targetDir,
  );
}

Future<void> openInFileManager({required String filePath}) async {
  if (MockMode.enabled) return;
  return rust.openInFileManager(filePath: filePath);
}

Future<List<(String, List<String>)>> getAllCollectionOrders() async {
  if (MockMode.enabled) {
    return _m.orders.entries.map((e) => (e.key, e.value)).toList();
  }
  return rust.getAllCollectionOrders();
}

void saveCollectionOrder({required String orderKey, required List<String> ids}) {
  if (MockMode.enabled) {
    _m.orders[orderKey] = List<String>.of(ids);
    return;
  }
  rust.saveCollectionOrder(orderKey: orderKey, ids: ids);
}

Future<List<String>> getFavoriteCollectionIds() async {
  if (MockMode.enabled) return _m.favorites.toList();
  return rust.getFavoriteCollectionIds();
}

void saveFavoriteCollectionIds({required List<String> ids}) {
  if (MockMode.enabled) {
    _m.favorites
      ..clear()
      ..addAll(ids);
    return;
  }
  rust.saveFavoriteCollectionIds(ids: ids);
}

Future<List<SmartFolderInfo>> getAllSmartFolders() async {
  if (MockMode.enabled) return List<SmartFolderInfo>.of(_m.smartFolders);
  return rust.getAllSmartFolders();
}

SmartFolderInfo createSmartFolder({
  required String name,
  required String regexPattern,
  required List<String> keywords,
  required String regexTarget,
  required String fileTypeFilter,
  required List<String> targetFolderIds,
}) {
  if (MockMode.enabled) {
    return _m.createSmartFolder(
      name: name,
      regexPattern: regexPattern,
      keywords: keywords,
      regexTarget: regexTarget,
      fileTypeFilter: fileTypeFilter,
      targetFolderIds: targetFolderIds,
    );
  }
  return rust.createSmartFolder(
    name: name,
    regexPattern: regexPattern,
    keywords: keywords,
    regexTarget: regexTarget,
    fileTypeFilter: fileTypeFilter,
    targetFolderIds: targetFolderIds,
  );
}

SmartFolderInfo updateSmartFolder({
  required String id,
  required String name,
  required String regexPattern,
  required List<String> keywords,
  required String regexTarget,
  required String fileTypeFilter,
  required List<String> targetFolderIds,
}) {
  if (MockMode.enabled) {
    return _m.updateSmartFolder(
          id: id,
          name: name,
          regexPattern: regexPattern,
          keywords: keywords,
          regexTarget: regexTarget,
          fileTypeFilter: fileTypeFilter,
          targetFolderIds: targetFolderIds,
        ) ??
        createSmartFolder(
          name: name,
          regexPattern: regexPattern,
          keywords: keywords,
          regexTarget: regexTarget,
          fileTypeFilter: fileTypeFilter,
          targetFolderIds: targetFolderIds,
        );
  }
  return rust.updateSmartFolder(
    id: id,
    name: name,
    regexPattern: regexPattern,
    keywords: keywords,
    regexTarget: regexTarget,
    fileTypeFilter: fileTypeFilter,
    targetFolderIds: targetFolderIds,
  );
}

bool deleteSmartFolder({required String id}) {
  if (MockMode.enabled) return _m.deleteSmartFolder(id);
  return rust.deleteSmartFolder(id: id);
}

/// 该视频容器是否已 faststart（`moov` 在 `mdat` 之前）。
///
/// 非 faststart 的 MP4 远程播放要先跳到文件尾读索引，每次跳转都是一趟网络
/// 往返，表现为「打开半天、之后断续」——与编码无关，纯容器布局问题。
/// 非 MP4/MOV 返回 null（无从判断，也不需处理）。
Future<bool?> videoIsFaststart({required String filePath}) async {
  if (MockMode.enabled) return true;
  try {
    return await rust.videoIsFaststart(filePath: filePath);
  } catch (_) {
    // 探测是「锦上添花」：拿不到结论按「判不了」处理（返回 null 不改动任何行为），
    // 不该让它把播放/导入链路打成错误态
    return null;
  }
}

/// 把非 faststart 的 MP4 重封装成 faststart 副本（`-c copy`，无损），返回副本路径。
/// 已是 faststart 或非 MP4 返回 null；副本写资源旁 `.SlimeWorks/faststart/`。
Future<String?> ensureFaststartCopy({required String filePath}) async {
  if (MockMode.enabled) return null;
  try {
    return await rust.ensureFaststartCopy(filePath: filePath);
  } catch (_) {
    // 重封装失败只意味着「继续用原文件」，调用方无需感知
    return null;
  }
}
