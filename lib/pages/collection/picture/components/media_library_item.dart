import 'package:slime_works/pages/collection/picture/components/smart_folder.dart';
import 'package:slime_works/src/rust/api/media_collection.dart' as media_api;

sealed class MediaLibraryItem {
  String get id;
}

class MediaLibraryFolderItem extends MediaLibraryItem {
  MediaLibraryFolderItem(this.folder);

  final media_api.MediaFolder folder;

  @override
  String get id => folder.id;
}

class MediaLibraryCollectionItem extends MediaLibraryItem {
  MediaLibraryCollectionItem(this.collection);

  final media_api.MediaCollection collection;

  @override
  String get id => collection.id;
}

class MediaLibrarySmartFolderItem extends MediaLibraryItem {
  MediaLibrarySmartFolderItem(this.smartFolder);

  final SmartFolder smartFolder;

  @override
  String get id => smartFolder.id;
}
