import 'package:slime_works/mock/data/media_mock_data.dart';
import 'package:slime_works/mock/mock_assets.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/media_collection.dart'
    show
        CollectionCount,
        CollectionLiveStats,
        CollectionStats,
        MediaCollection,
        MediaFolder,
        MediaItem,
        SmartFolderInfo,
        ThumbnailTaskInfo;
import 'package:slime_works/src/rust/api/media_collection.dart' as rust;

export 'package:slime_works/src/rust/api/media_collection.dart'
    show
        CollectionCount,
        CollectionLiveStats,
        CollectionStats,
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

Future<List<CollectionStats>> getAllCollectionStats() async {
  if (MockMode.enabled) {
    return _m.collections.map((c) {
      final list = _m.itemsOf(c.id);
      return CollectionStats(
        collectionId: c.id,
        totalSize: list.fold(BigInt.zero, (sum, e) => sum + e.fileSize),
        filePaths: list.map((e) => e.filePath).toList(),
      );
    }).toList();
  }
  return rust.getAllCollectionStats();
}

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

List<SmartFolderInfo> getAllSmartFolders() {
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
