library;

/// Manga 下载管理页面 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/manga_download_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/manga/models/manga_download_model.dart';

class MangaDownloadsViewModel extends BaseViewModel {
  final MangaDownloadService _dl = getIt<MangaDownloadService>();

  /// 所有下载条目（实时响应，直接绑定 service RxMap）
  RxMap<String, MangaDownloadEntry> get entries => _dl.entries;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
  }

  /// 删除某漫画的所有下载
  Future<void> deleteAll(String comicId) async {
    await _dl.deleteDownload(comicId);
  }

  /// 删除某章节的下载
  Future<void> deleteEps(String comicId, int epsOrder) async {
    await _dl.deleteDownload(comicId, epsOrder: epsOrder);
  }

  /// 重新下载出错的章节
  Future<void> retryEps(String comicId, int epsOrder) async {
    await _dl.retryEps(comicId, epsOrder);
  }
}
