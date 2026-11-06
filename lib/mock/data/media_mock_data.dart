import 'package:slime_works/mock/mock_assets.dart';
import 'package:slime_works/src/rust/api/media_collection.dart';

/// 媒体库演示数据：多层文件夹 + 图片/视频/音频混合 + 收藏与智能文件夹。
class MockMediaData {
  MockMediaData._() {
    _seed();
  }

  static final MockMediaData instance = MockMediaData._();

  final List<MediaFolder> folders = <MediaFolder>[];
  final List<MediaCollection> collections = <MediaCollection>[];
  final Map<String, List<MediaItem>> items = <String, List<MediaItem>>{};
  final List<SmartFolderInfo> smartFolders = <SmartFolderInfo>[];
  final Set<String> favorites = <String>{};
  final Map<String, List<String>> orders = <String, List<String>>{};

  int _idSeq = 0;
  String _newId(String prefix) => '$prefix-${++_idSeq}';

  void _seed() {
    const ts = 1735689600000; // 2025-01-01
    folders.addAll([
      MediaFolder(id: 'mf-travel', name: '旅行摄影', createdAt: ts, order: 0),
      MediaFolder(
        id: 'mf-kyoto',
        name: '2024 京都',
        createdAt: ts,
        order: 0,
        parentId: 'mf-travel',
      ),
      MediaFolder(
        id: 'mf-hokkaido',
        name: '2025 北海道',
        createdAt: ts,
        order: 1,
        parentId: 'mf-travel',
      ),
      MediaFolder(id: 'mf-design', name: '设计素材', createdAt: ts, order: 1),
      MediaFolder(
        id: 'mf-ui',
        name: 'UI 参考',
        createdAt: ts,
        order: 0,
        parentId: 'mf-design',
      ),
      MediaFolder(
        id: 'mf-wallpaper',
        name: '壁纸',
        createdAt: ts,
        order: 1,
        parentId: 'mf-design',
      ),
      MediaFolder(id: 'mf-private', name: '私人收藏', createdAt: ts, order: 2),
    ]);

    _addCollection(
      id: 'mc-kyoto-2024',
      title: '京都赏樱 2024',
      folderId: 'mf-kyoto',
      count: 26,
      seed: 'kyoto',
      kinds: const [MediaKind.image, MediaKind.image, MediaKind.video],
    );
    _addCollection(
      id: 'mc-kyoto-night',
      title: '祇园夜拍',
      folderId: 'mf-kyoto',
      count: 18,
      seed: 'gion',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-hokkaido-2025',
      title: '北海道自驾',
      folderId: 'mf-hokkaido',
      count: 14,
      seed: 'hokkaido',
      kinds: const [MediaKind.video, MediaKind.image],
    );
    _addCollection(
      id: 'mc-hokkaido-food',
      title: '函馆早市',
      folderId: 'mf-hokkaido',
      count: 16,
      seed: 'hakodate',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-ui-ref',
      title: '移动端 UI 参考',
      folderId: 'mf-ui',
      count: 32,
      seed: 'ui-ref',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-icon-set',
      title: '描边图标合集',
      folderId: 'mf-ui',
      count: 24,
      seed: 'icons',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-wallpaper-4k',
      title: '4K 风景壁纸',
      folderId: 'mf-wallpaper',
      count: 20,
      seed: 'wallpaper',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-wallpaper-live',
      title: '动态壁纸素材',
      folderId: 'mf-wallpaper',
      count: 10,
      seed: 'live-wall',
      kinds: const [MediaKind.video],
    );
    _addCollection(
      id: 'mc-concert',
      title: '现场录音',
      folderId: 'mf-private',
      count: 12,
      seed: 'concert',
      kinds: const [MediaKind.audio],
    );
    _addCollection(
      id: 'mc-podcast',
      title: '播客剪辑',
      folderId: 'mf-private',
      count: 9,
      seed: 'podcast',
      kinds: const [MediaKind.audio],
    );
    _addCollection(
      id: 'mc-travel-vlog',
      title: '旅行 Vlog 原片',
      folderId: null,
      count: 11,
      seed: 'vlog',
      kinds: const [MediaKind.video],
    );
    _addCollection(
      id: 'mc-family',
      title: '家庭相册',
      folderId: null,
      count: 30,
      seed: 'family',
      kinds: const [MediaKind.image, MediaKind.video],
    );
    _addCollection(
      id: 'mc-manga-scan',
      title: '漫画扫描件',
      folderId: null,
      count: 15,
      seed: 'manga-scan',
      kinds: const [MediaKind.image],
    );
    _addCollection(
      id: 'mc-empty',
      title: '待整理（空）',
      folderId: null,
      count: 0,
      seed: 'empty',
      kinds: const [MediaKind.image],
    );

    favorites.addAll(['mc-kyoto-2024', 'mc-wallpaper-4k']);
    orders['root'] = collections.map((c) => c.id).toList();

    smartFolders.addAll([
      const SmartFolderInfo(
        id: 'sf-video',
        name: '全部视频',
        regexPattern: r'\.(mp4|mov|mkv)$',
        keywords: ['vlog', '自驾'],
        regexTarget: SmartFolderRegexTarget.fileName,
        fileTypeFilter: SmartFolderFileType.videos,
        targetFolderIds: [],
      ),
      const SmartFolderInfo(
        id: 'sf-travel',
        name: '旅行相关',
        regexPattern: '旅行|京都|北海道',
        keywords: ['旅行', '京都'],
        regexTarget: SmartFolderRegexTarget.collectionName,
        fileTypeFilter: SmartFolderFileType.all,
        targetFolderIds: ['mf-travel'],
      ),
    ]);
  }

  void _addCollection({
    required String id,
    required String title,
    required String? folderId,
    required int count,
    required String seed,
    required List<MediaKind> kinds,
  }) {
    final generated = <MediaItem>[];
    for (var i = 0; i < count; i++) {
      final kind = kinds[i % kinds.length];
      final index = i + 1;
      final (:path, :suffix) = switch (kind) {
        MediaKind.image => (
          path: MockAssets.imagePath('$seed-$index', width: 1200, height: 800),
          suffix: 'JPG',
        ),
        MediaKind.video => (
          path: '/mock/media/$seed/clip_${index.toString().padLeft(3, '0')}.mp4',
          suffix: 'MP4',
        ),
        MediaKind.audio => (
          path: '/mock/media/$seed/track_${index.toString().padLeft(2, '0')}.flac',
          suffix: 'FLAC',
        ),
      };
      generated.add(
        MediaItem(
          id: '$id-item-$index',
          collectionId: id,
          title: '$title ${index.toString().padLeft(2, '0')}.$suffix',
          filePath: path,
          kind: kind,
          fileSize: BigInt.from(1024 * (240 + index * 37)),
          modifiedAt: 1735689600000 + index * 3600000,
          width: kind == MediaKind.image ? 1200 : null,
          height: kind == MediaKind.image ? 800 : null,
          durationMs: kind == MediaKind.image ? null : BigInt.from(18000 + index * 700),
          order: index,
        ),
      );
    }
    items[id] = generated;
    collections.add(
      MediaCollection(
        id: id,
        title: title,
        folderPath: '/mock/library/$seed',
        folderId: folderId,
        coverPath: count == 0
            ? null
            : MockAssets.imagePath('$seed-cover', width: 480, height: 320),
        itemCount: BigInt.from(count),
        createdAt: 1735689600000,
        updatedAt: 1735689600000 + count * 60000,
      ),
    );
  }

  List<MediaItem> itemsOf(String collectionId) =>
      List<MediaItem>.of(items[collectionId] ?? const []);

  List<MediaFolder> rootFolders() =>
      folders.where((f) => f.parentId == null).toList();

  List<MediaFolder> childFolders(String parentId) =>
      folders.where((f) => f.parentId == parentId).toList();

  bool renameCollection(String id, String title) {
    final i = collections.indexWhere((c) => c.id == id);
    if (i < 0) return false;
    final c = collections[i];
    collections[i] = MediaCollection(
      id: c.id,
      title: title,
      folderPath: c.folderPath,
      folderId: c.folderId,
      coverPath: c.coverPath,
      itemCount: c.itemCount,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    );
    return true;
  }

  bool moveCollection(String id, String? folderId) {
    final i = collections.indexWhere((c) => c.id == id);
    if (i < 0) return false;
    final c = collections[i];
    collections[i] = MediaCollection(
      id: c.id,
      title: c.title,
      folderPath: c.folderPath,
      folderId: folderId,
      coverPath: c.coverPath,
      itemCount: c.itemCount,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    );
    return true;
  }

  bool deleteCollection(String id) {
    final before = collections.length;
    collections.removeWhere((c) => c.id == id);
    items.remove(id);
    favorites.remove(id);
    return collections.length != before;
  }

  MediaFolder createFolder(String name, {String? parentId}) {
    final folder = MediaFolder(
      id: _newId('mf'),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      order: folders.length,
      parentId: parentId,
    );
    folders.add(folder);
    return folder;
  }

  bool renameFolder(String id, String name) {
    final i = folders.indexWhere((f) => f.id == id);
    if (i < 0) return false;
    final f = folders[i];
    folders[i] = MediaFolder(
      id: f.id,
      name: name,
      createdAt: f.createdAt,
      order: f.order,
      parentId: f.parentId,
    );
    return true;
  }

  bool deleteFolder(String id) {
    final before = folders.length;
    folders.removeWhere((f) => f.id == id);
    collections.removeWhere((c) => c.folderId == id);
    return folders.length != before;
  }

  bool deleteItemFile(String filePath) {
    var removed = false;
    for (final entry in items.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((e) => e.filePath == filePath);
      removed = removed || entry.value.length != before;
    }
    return removed;
  }

  SmartFolderInfo createSmartFolder({
    required String name,
    required String regexPattern,
    required List<String> keywords,
    required String regexTarget,
    required String fileTypeFilter,
    required List<String> targetFolderIds,
  }) {
    final sf = SmartFolderInfo(
      id: _newId('sf'),
      name: name,
      regexPattern: regexPattern,
      keywords: keywords,
      regexTarget: SmartFolderRegexTarget.values.firstWhere(
        (e) => e.name == regexTarget,
        orElse: () => SmartFolderRegexTarget.fileName,
      ),
      fileTypeFilter: SmartFolderFileType.values.firstWhere(
        (e) => e.name == fileTypeFilter,
        orElse: () => SmartFolderFileType.all,
      ),
      targetFolderIds: targetFolderIds,
    );
    smartFolders.add(sf);
    return sf;
  }

  SmartFolderInfo? updateSmartFolder({
    required String id,
    required String name,
    required String regexPattern,
    required List<String> keywords,
    required String regexTarget,
    required String fileTypeFilter,
    required List<String> targetFolderIds,
  }) {
    final i = smartFolders.indexWhere((s) => s.id == id);
    if (i < 0) return null;
    final sf = SmartFolderInfo(
      id: id,
      name: name,
      regexPattern: regexPattern,
      keywords: keywords,
      regexTarget: SmartFolderRegexTarget.values.firstWhere(
        (e) => e.name == regexTarget,
        orElse: () => SmartFolderRegexTarget.fileName,
      ),
      fileTypeFilter: SmartFolderFileType.values.firstWhere(
        (e) => e.name == fileTypeFilter,
        orElse: () => SmartFolderFileType.all,
      ),
      targetFolderIds: targetFolderIds,
    );
    smartFolders[i] = sf;
    return sf;
  }

  bool deleteSmartFolder(String id) {
    final before = smartFolders.length;
    smartFolders.removeWhere((s) => s.id == id);
    return smartFolders.length != before;
  }

  MediaCollection? collectionById(String id) {
    for (final c in collections) {
      if (c.id == id) return c;
    }
    return null;
  }

  MediaCollection importFromPath(String folderPath) {
    final parts = folderPath
        .split(RegExp(r'[/\\]'))
        .where((e) => e.isNotEmpty)
        .toList();
    final name = parts.isEmpty ? '导入的媒体' : parts.last;
    final id = _newId('mc');
    _addCollection(
      id: id,
      title: name,
      folderId: null,
      count: 8,
      seed: id,
      kinds: const [MediaKind.image, MediaKind.video],
    );
    return collections.last;
  }
}
