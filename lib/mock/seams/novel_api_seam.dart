import 'package:slime_works/mock/data/novel_mock_data.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart'
    show
        KeywordApplyBatchResult,
        KeywordRuleInput,
        NovelContent,
        NovelFolder,
        NovelMetadata,
        NovelSearchResult,
        ScanBatchResult,
        SearchBatchResult,
        SearchMatch;
import 'package:slime_works/src/rust/api/novel_reader.dart' as rust;

export 'package:slime_works/src/rust/api/novel_reader.dart'
    show
        KeywordApplyBatchResult,
        KeywordRuleInput,
        NovelChapter,
        NovelContent,
        NovelFolder,
        NovelFormat,
        NovelMetadata,
        NovelSearchResult,
        ScanBatchResult,
        SearchBatchResult,
        SearchMatch;

MockNovelData get _m => MockNovelData.instance;

List<NovelMetadata> scanNovelsFolder({required String folderPath}) {
  if (MockMode.enabled) {
    return <NovelMetadata>[_m.addFromPath('$folderPath/演示书籍.epub')];
  }
  return rust.scanNovelsFolder(folderPath: folderPath);
}

List<NovelMetadata> getAllNovels() {
  if (MockMode.enabled) return List<NovelMetadata>.of(_m.novels);
  return rust.getAllNovels();
}

List<NovelMetadata> addNovel({required List<String> filePaths}) {
  if (MockMode.enabled) {
    return filePaths.map((p) => _m.addFromPath(p)).toList();
  }
  return rust.addNovel(filePaths: filePaths);
}

List<NovelMetadata> addNovelToFolder({
  required List<String> filePaths,
  required String folderId,
}) {
  if (MockMode.enabled) {
    return filePaths.map((p) => _m.addFromPath(p, folderId: folderId)).toList();
  }
  return rust.addNovelToFolder(filePaths: filePaths, folderId: folderId);
}

void removeNovel({required String novelId}) {
  if (MockMode.enabled) {
    _m.remove(novelId);
    return;
  }
  rust.removeNovel(novelId: novelId);
}

void removeNovelWithFile({required String novelId}) {
  if (MockMode.enabled) {
    _m.remove(novelId);
    return;
  }
  rust.removeNovelWithFile(novelId: novelId);
}

void clearAllNovels() {
  if (MockMode.enabled) {
    _m.novels.clear();
    return;
  }
  rust.clearAllNovels();
}

Future<NovelContent> getNovelContent({required String filePath}) async {
  if (MockMode.enabled) {
    final content = _m.contents[filePath];
    if (content != null) return content;
    final meta = _m.addFromPath(filePath);
    return _m.contents[meta.filePath]!;
  }
  return rust.getNovelContent(filePath: filePath);
}

Future<String> getChapterContent({
  required String filePath,
  required BigInt chapterIndex,
}) async {
  if (MockMode.enabled) {
    final content = _m.contents[filePath];
    if (content == null) return '演示章节内容尚未生成。';
    final i = chapterIndex.toInt();
    if (i < 0 || i >= content.chapters.length) return '';
    return content.chapters[i].content ?? '';
  }
  return rust.getChapterContent(
    filePath: filePath,
    chapterIndex: chapterIndex,
  );
}

Future<List<SearchMatch>> searchInNovel({
  required String filePath,
  required String keyword,
}) async {
  if (MockMode.enabled) {
    final novel = _m.byPath(filePath);
    if (novel == null) return const <SearchMatch>[];
    return _m.searchIn(novel, keyword);
  }
  return rust.searchInNovel(filePath: filePath, keyword: keyword);
}

void updateReadingProgress({
  required String novelId,
  required double progress,
}) {
  if (MockMode.enabled) {
    _m.updateProgress(novelId, progress);
    return;
  }
  rust.updateReadingProgress(novelId: novelId, progress: progress);
}

NovelFolder createFolder({required String name}) {
  if (MockMode.enabled) return _m.createFolder(name);
  return rust.createFolder(name: name);
}

NovelFolder createChildFolder({
  required String name,
  required String parentId,
}) {
  if (MockMode.enabled) return _m.createFolder(name, parentId: parentId);
  return rust.createChildFolder(name: name, parentId: parentId);
}

List<NovelFolder> getAllFolders() {
  if (MockMode.enabled) return List<NovelFolder>.of(_m.folders);
  return rust.getAllFolders();
}

List<NovelFolder> getChildFolders({required String parentId}) {
  if (MockMode.enabled) return _m.childFolders(parentId);
  return rust.getChildFolders(parentId: parentId);
}

void deleteFolder({required String folderId}) {
  if (MockMode.enabled) {
    _m.deleteFolder(folderId);
    return;
  }
  rust.deleteFolder(folderId: folderId);
}

void deleteFolderWithNovels({required String folderId}) {
  if (MockMode.enabled) {
    _m.deleteFolder(folderId, withNovels: true);
    return;
  }
  rust.deleteFolderWithNovels(folderId: folderId);
}

void moveNovelToFolder({required String novelId, String? folderId}) {
  if (MockMode.enabled) {
    _m.moveNovel(novelId, folderId);
    return;
  }
  rust.moveNovelToFolder(novelId: novelId, folderId: folderId);
}

void updateNovelOrder({required String novelId, required int order}) {
  if (MockMode.enabled) return;
  rust.updateNovelOrder(novelId: novelId, order: order);
}

void batchUpdateNovelOrders({required List<String> novelIds}) {
  if (MockMode.enabled) return;
  rust.batchUpdateNovelOrders(novelIds: novelIds);
}

void renameNovel({required String novelId, required String title}) {
  if (MockMode.enabled) {
    _m.rename(novelId, title);
    return;
  }
  rust.renameNovel(novelId: novelId, title: title);
}

void setNovelFavorite({required String novelId, required bool isFavorite}) {
  if (MockMode.enabled) {
    _m.setFavorite(novelId, isFavorite);
    return;
  }
  rust.setNovelFavorite(novelId: novelId, isFavorite: isFavorite);
}

void updateNovelTags({required String novelId, required List<String> tags}) {
  if (MockMode.enabled) {
    _m.updateTags(novelId, tags);
    return;
  }
  rust.updateNovelTags(novelId: novelId, tags: tags);
}

Future<void> updateNovelCover({
  required String novelId,
  required String imagePath,
}) async {
  if (MockMode.enabled) {
    _m.updateCover(novelId, imagePath);
    return;
  }
  await rust.updateNovelCover(novelId: novelId, imagePath: imagePath);
}

void updateNovelAuthor({required String novelId, required String author}) {
  if (MockMode.enabled) {
    _m.updateInfo(novelId, author: author);
    return;
  }
  rust.updateNovelAuthor(novelId: novelId, author: author);
}

void updateNovelNotes({required String novelId, required String notes}) {
  if (MockMode.enabled) {
    _m.updateInfo(novelId, notes: notes);
    return;
  }
  rust.updateNovelNotes(novelId: novelId, notes: notes);
}

void updateNovelInfo({
  required String novelId,
  String? title,
  String? author,
  String? notes,
  List<String>? tags,
}) {
  if (MockMode.enabled) {
    _m.updateInfo(
      novelId,
      title: title,
      author: author,
      notes: notes,
      tags: tags,
    );
    return;
  }
  rust.updateNovelInfo(
    novelId: novelId,
    title: title,
    author: author,
    notes: notes,
    tags: tags,
  );
}

void clearNovelCache({required String filePath}) {
  if (MockMode.enabled) return;
  rust.clearNovelCache(filePath: filePath);
}

void renameFolder({required String folderId, required String name}) {
  if (MockMode.enabled) {
    _m.renameFolder(folderId, name);
    return;
  }
  rust.renameFolder(folderId: folderId, name: name);
}

void batchUpdateFolderOrders({required List<String> folderIds}) {
  if (MockMode.enabled) return;
  rust.batchUpdateFolderOrders(folderIds: folderIds);
}

void cancelSearch() {
  if (MockMode.enabled) return;
  rust.cancelSearch();
}

Future<List<SearchBatchResult>> searchInAllNovelsBatched({
  required String keyword,
  required BigInt batchSize,
}) async {
  if (MockMode.enabled) {
    final results = <NovelSearchResult>[];
    for (final novel in _m.novels) {
      final hits = _m.searchIn(novel, keyword);
      if (hits.isNotEmpty) {
        results.add(
          NovelSearchResult(novel: novel, matchCount: BigInt.from(hits.length)),
        );
      }
    }
    return <SearchBatchResult>[
      SearchBatchResult(
        results: results,
        completed: BigInt.from(_m.novels.length),
        total: BigInt.from(_m.novels.length),
        isFinished: true,
      ),
    ];
  }
  return rust.searchInAllNovelsBatched(keyword: keyword, batchSize: batchSize);
}

Future<List<NovelSearchResult>> searchInAllNovels({required String keyword}) async {
  if (MockMode.enabled) {
    return _m.novels
        .where((n) => _m.searchIn(n, keyword).isNotEmpty)
        .map(
          (n) => NovelSearchResult(
            novel: n,
            matchCount: BigInt.from(_m.searchIn(n, keyword).length),
          ),
        )
        .toList();
  }
  return rust.searchInAllNovels(keyword: keyword);
}

Future<List<ScanBatchResult>> scanNovelsFolderBatched({
  required String folderPath,
  required BigInt batchSize,
}) async {
  if (MockMode.enabled) {
    final added = <NovelMetadata>[
      _m.addFromPath('$folderPath/演示书籍.epub'),
    ];
    return <ScanBatchResult>[
      ScanBatchResult(
        novels: added,
        completed: BigInt.one,
        total: BigInt.one,
        isFinished: true,
      ),
    ];
  }
  return rust.scanNovelsFolderBatched(
    folderPath: folderPath,
    batchSize: batchSize,
  );
}

Future<KeywordApplyBatchResult> applyKeywordRulesToAllNovelsBatch({
  required List<KeywordRuleInput> rules,
  required BigInt start,
  required BigInt batchSize,
}) async {
  if (MockMode.enabled) {
    var updated = 0;
    for (final novel in List<NovelMetadata>.of(_m.novels)) {
      final tags = <String>{...novel.tags};
      for (final rule in rules) {
        if (novel.title.contains(rule.keyword)) tags.add(rule.tag);
      }
      if (tags.length != novel.tags.length) {
        _m.updateTags(novel.id, tags.toList());
        updated++;
      }
    }
    return KeywordApplyBatchResult(
      completed: BigInt.from(_m.novels.length),
      total: BigInt.from(_m.novels.length),
      updated: BigInt.from(updated),
      isFinished: true,
    );
  }
  return rust.applyKeywordRulesToAllNovelsBatch(
    rules: rules,
    start: start,
    batchSize: batchSize,
  );
}
