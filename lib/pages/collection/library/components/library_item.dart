import 'package:slime_works/src/rust/api/novel_reader.dart';

/// 书籍库展示条目的联合类型：文件夹 或 书籍
sealed class LibraryItem {
  String get id;
}

/// 文件夹条目
class LibraryFolderItem extends LibraryItem {
  final NovelFolder folder;

  LibraryFolderItem(this.folder);

  @override
  String get id => folder.id;
}

/// 书籍条目
class LibraryBookItem extends LibraryItem {
  final NovelMetadata metadata;

  LibraryBookItem(this.metadata);

  @override
  String get id => metadata.id;
}
