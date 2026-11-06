import 'package:slime_works/mock/mock_assets.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 小说书架演示数据：多层文件夹、章节正文、收藏与标签。
class MockNovelData {
  MockNovelData._() {
    _seed();
  }

  static final MockNovelData instance = MockNovelData._();

  final List<NovelFolder> folders = <NovelFolder>[];
  final List<NovelMetadata> novels = <NovelMetadata>[];
  final Map<String, NovelContent> contents = <String, NovelContent>{};
  int _seq = 0;

  void _seed() {
    const ts = 1735689600000;
    folders.addAll([
      NovelFolder(id: 'nf-ongoing', name: '连载追更', createdAt: ts, order: 0),
      NovelFolder(
        id: 'nf-fantasy',
        name: '奇幻',
        createdAt: ts,
        order: 0,
        parentId: 'nf-ongoing',
      ),
      NovelFolder(
        id: 'nf-sci-fi',
        name: '科幻',
        createdAt: ts,
        order: 1,
        parentId: 'nf-ongoing',
      ),
      NovelFolder(id: 'nf-finished', name: '已完结', createdAt: ts, order: 1),
      NovelFolder(id: 'nf-classic', name: '经典文学', createdAt: ts, order: 2),
    ]);

    void add({
      required String seed,
      required String title,
      required String author,
      String? folderId,
      int chapters = 12,
      double progress = 0,
      bool favorite = false,
      List<String> tags = const [],
      String? notes,
    }) {
      final id = 'novel-${++_seq}';
      final path = '/mock/novels/$seed.epub';
      novels.add(
        NovelMetadata(
          id: id,
          title: title,
          author: author,
          filePath: path,
          format: NovelFormat.epub,
          fileSize: BigInt.from(1024 * 1024 + _seq * 86000),
          modifiedAt: ts + _seq * 86400000,
          addedAt: ts + _seq * 3600000,
          progress: progress,
          lastReadAt: progress > 0 ? ts + _seq * 7200000 : null,
          coverPath: MockAssets.imagePath(
            'novel-$seed',
            width: 300,
            height: 420,
            style: 1,
          ),
          folderId: folderId,
          customOrder: _seq,
          isFavorite: favorite,
          tags: tags,
          notes: notes,
        ),
      );
      contents[path] = NovelContent(
        novelId: id,
        chapters: List<NovelChapter>.generate(chapters, (i) {
          final index = i + 1;
          return NovelChapter(
            id: '$id-ch-$index',
            title: '第 $index 章 ${_chapterTitles[(i) % _chapterTitles.length]}',
            index: BigInt.from(i),
            content: _chapterBody(title, index),
          );
        }),
      );
    }

    add(
      seed: 'starfall',
      title: '星落之城',
      author: '迟野',
      folderId: 'nf-fantasy',
      chapters: 18,
      progress: 0.42,
      favorite: true,
      tags: ['奇幻', '群像'],
    );
    add(
      seed: 'winter',
      title: '长冬纪事',
      author: '南枝',
      folderId: 'nf-fantasy',
      chapters: 24,
      progress: 0.08,
      tags: ['史诗'],
    );
    add(
      seed: 'orbit',
      title: '轨道之外',
      author: '林一舟',
      folderId: 'nf-sci-fi',
      chapters: 15,
      progress: 0.66,
      tags: ['科幻', '硬核'],
      notes: '第三卷节奏很好',
    );
    add(
      seed: 'echo',
      title: '回声协议',
      author: '陆拾',
      folderId: 'nf-sci-fi',
      chapters: 20,
      tags: ['赛博朋克'],
    );
    add(
      seed: 'river',
      title: '河岸手记',
      author: '沈砚',
      folderId: 'nf-finished',
      chapters: 10,
      progress: 1.0,
      favorite: true,
      tags: ['治愈'],
    );
    add(
      seed: 'letter',
      title: '未寄出的信',
      author: '顾青',
      folderId: 'nf-finished',
      chapters: 8,
      progress: 1.0,
    );
    add(
      seed: 'moon',
      title: '月光下的旧书店',
      author: '苏木',
      folderId: 'nf-classic',
      chapters: 14,
      progress: 0.23,
      tags: ['日常'],
    );
    add(
      seed: 'mountain',
      title: '山路与雾',
      author: '陈迹',
      chapters: 16,
      progress: 0.5,
      tags: ['公路'],
    );
    add(
      seed: 'clock',
      title: '停摆的钟',
      author: '白屿',
      chapters: 22,
      progress: 0.12,
      tags: ['悬疑'],
    );
    add(
      seed: 'seed',
      title: '种子计划',
      author: '周未',
      chapters: 19,
      tags: ['科幻'],
    );
    add(
      seed: 'paper',
      title: '纸飞机航线',
      author: '温言',
      chapters: 11,
      progress: 0.75,
      tags: ['青春'],
    );
    add(
      seed: 'island',
      title: '孤岛来信',
      author: '简宁',
      chapters: 13,
      favorite: true,
      tags: ['悬疑', '旅行'],
    );
    add(
      seed: 'fire',
      title: '篝火旁的故事',
      author: '叶川',
      chapters: 9,
      tags: ['短篇'],
    );
    add(
      seed: 'dust',
      title: '尘埃与光',
      author: '林晚',
      chapters: 17,
      tags: ['散文'],
    );
  }

  static const List<String> _chapterTitles = [
    '出发',
    '雨夜',
    '旧友',
    '回声',
    '岔路',
    '远山',
    '余烬',
    '归途',
    '黎明',
    '重逢',
  ];

  String _chapterBody(String title, int index) {
    final buffer = StringBuffer();
    for (var p = 0; p < 6; p++) {
      buffer.writeln(
        '　　《$title》第 $index 章。窗外的光沿着旧木桌慢慢移动，'
        '他把杯子挪开一点，让那道光落在摊开的纸页上。'
        '远处传来列车经过的声音，像有人在很低的地方呼吸。',
      );
      buffer.writeln();
    }
    return buffer.toString();
  }

  NovelMetadata? byId(String id) {
    for (final n in novels) {
      if (n.id == id) return n;
    }
    return null;
  }

  NovelMetadata? byPath(String path) {
    for (final n in novels) {
      if (n.filePath == path) return n;
    }
    return null;
  }

  NovelFolder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<NovelFolder> childFolders(String parentId) =>
      folders.where((f) => f.parentId == parentId).toList();

  NovelFolder createFolder(String name, {String? parentId}) {
    final folder = NovelFolder(
      id: 'nf-${++_seq}',
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
    folders[i] = NovelFolder(
      id: f.id,
      name: name,
      createdAt: f.createdAt,
      order: f.order,
      parentId: f.parentId,
    );
    return true;
  }

  void deleteFolder(String id, {bool withNovels = false}) {
    folders.removeWhere((f) => f.id == id);
    if (withNovels) {
      novels.removeWhere((n) => n.folderId == id);
    } else {
      for (var i = 0; i < novels.length; i++) {
        if (novels[i].folderId == id) {
          novels[i] = _copy(novels[i], clearFolder: true);
        }
      }
    }
  }

  void moveNovel(String id, String? folderId) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i < 0) return;
    novels[i] = folderId == null
        ? _copy(novels[i], clearFolder: true)
        : _copy(novels[i], folderId: folderId);
  }

  void remove(String id) {
    novels.removeWhere((n) => n.id == id);
  }

  NovelMetadata addFromPath(String path, {String? folderId}) {
    final existing = byPath(path);
    if (existing != null) return existing;
    final name = path.split(RegExp(r'[/\\]')).last.replaceAll('.epub', '');
    final meta = NovelMetadata(
      id: 'novel-${++_seq}',
      title: name,
      author: '未知作者',
      filePath: path,
      format: NovelFormat.epub,
      fileSize: BigInt.from(1024 * 512),
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      progress: 0,
      coverPath: MockAssets.imagePath(
        'novel-new-$name',
        width: 300,
        height: 420,
        style: 1,
      ),
      folderId: folderId,
      customOrder: _seq,
      isFavorite: false,
      tags: const [],
    );
    novels.add(meta);
    contents[path] = NovelContent(
      novelId: meta.id,
      chapters: List<NovelChapter>.generate(5, (i) {
        final index = i + 1;
        return NovelChapter(
          id: '${meta.id}-ch-$index',
          title: '第 $index 章 ${_chapterTitles[i]}',
          index: BigInt.from(i),
          content: _chapterBody(name, index),
        );
      }),
    );
    return meta;
  }

  void updateProgress(String id, double progress) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i < 0) return;
    novels[i] = _copy(novels[i], progress: progress.clamp(0.0, 1.0));
  }

  void setFavorite(String id, bool value) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i >= 0) novels[i] = _copy(novels[i], isFavorite: value);
  }

  void updateTags(String id, List<String> tags) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i >= 0) novels[i] = _copy(novels[i], tags: tags);
  }

  void updateInfo(
    String id, {
    String? title,
    String? author,
    String? notes,
    List<String>? tags,
  }) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i >= 0) {
      novels[i] = _copy(
        novels[i],
        title: title,
        author: author,
        notes: notes,
        tags: tags,
      );
    }
  }

  void updateCover(String id, String imagePath) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i >= 0) novels[i] = _copy(novels[i], coverPath: imagePath);
  }

  void rename(String id, String title) {
    final i = novels.indexWhere((n) => n.id == id);
    if (i >= 0) novels[i] = _copy(novels[i], title: title);
  }

  List<SearchMatch> searchIn(NovelMetadata novel, String keyword) {
    final content = contents[novel.filePath];
    if (content == null || keyword.trim().isEmpty) return const [];
    final matches = <SearchMatch>[];
    for (final chapter in content.chapters) {
      final body = chapter.content ?? '';
      final at = body.indexOf(keyword);
      if (at >= 0) {
        matches.add(
          SearchMatch(
            chapterIndex: chapter.index,
            chapterTitle: chapter.title,
            position: BigInt.from(at),
            snippet: body.substring(
              (at - 24).clamp(0, body.length),
              (at + keyword.length + 40).clamp(0, body.length),
            ),
          ),
        );
      }
    }
    return matches;
  }

  NovelMetadata _copy(
    NovelMetadata n, {
    String? title,
    String? author,
    String? notes,
    List<String>? tags,
    String? coverPath,
    String? folderId,
    bool clearFolder = false,
    double? progress,
    bool? isFavorite,
  }) => NovelMetadata(
    id: n.id,
    title: title ?? n.title,
    author: author ?? n.author,
    filePath: n.filePath,
    format: n.format,
    fileSize: n.fileSize,
    modifiedAt: n.modifiedAt,
    addedAt: n.addedAt,
    progress: progress ?? n.progress,
    lastReadAt: n.lastReadAt,
    coverPath: coverPath ?? n.coverPath,
    folderId: clearFolder ? null : (folderId ?? n.folderId),
    customOrder: n.customOrder,
    isFavorite: isFavorite ?? n.isFavorite,
    tags: tags ?? n.tags,
    notes: notes ?? n.notes,
  );
}
