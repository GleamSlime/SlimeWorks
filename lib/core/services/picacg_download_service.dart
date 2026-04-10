library;

/// PicACG 漫画下载服务
///
/// 负责管理下载队列，协调 Dart 侧下载逻辑：
///  1. 从 API 获取章节图片列表
///  2. 依次下载每张图片并保存到本地文件系统
///  3. 通过 RxMap / RxBool 触发 UI 响应
///  4. 下载进度元数据使用 SharedPreferences 持久化

import 'dart:io';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/picacg/models/picacg_download_models.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

const String _kDownloadMetaKey = 'picacg_downloads_meta_v1';

/// PicACG 下载服务（全局单例，通过 GetIt 注入）
class PicAcgDownloadService {
  PicAcgDownloadService._();

  static final PicAcgDownloadService _instance = PicAcgDownloadService._();

  factory PicAcgDownloadService() => _instance;

  final PicAcgService _api = PicAcgService();

  /// 所有下载条目（comicId → entry）
  final RxMap<String, PicAcgDownloadEntry> entries = <String, PicAcgDownloadEntry>{}.obs;

  /// 当前正在下载的 comicId:epsOrder 键（格式 "$comicId:$epsOrder"）
  final RxSet<String> _activeKeys = <String>{}.obs;

  /// 是否有任何下载正在进行
  bool get hasActiveDownloads => _activeKeys.isNotEmpty;

  /// ---- 初始化 ----

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDownloadMetaKey);
      if (raw != null && raw.isNotEmpty) {
        entries.value = PicAcgDownloadEntry.decodeAll(raw);
      }
    } catch (e) {
      logger.error('PicACG 下载服务初始化失败: $e');
    }
    logger.info('PicACG 下载服务已初始化，共 ${entries.length} 条记录');
  }

  /// ---- 外部 API ----

  /// 添加章节到下载队列并开始下载
  Future<void> downloadEps(PicAcgComic comic, PicAcgEps eps) async {
    final entry = entries.putIfAbsent(
      comic.id,
      () => PicAcgDownloadEntry(comicId: comic.id, comicTitle: comic.title, thumb: comic.thumb),
    );
    // 已完成则跳过
    if (entry.episodes[eps.order]?.isCompleted == true) return;

    entry.episodes[eps.order] = PicAcgDownloadEpsInfo(
      epsOrder: eps.order,
      epsTitle: eps.title,
      status: PicAcgDownloadStatus.waiting,
    );
    entries.refresh();
    await _persistMeta();

    _startDownloadEps(comic.id, eps.order);
  }

  /// 批量添加章节（一次选多章）
  Future<void> downloadEpsMultiple(PicAcgComic comic, List<PicAcgEps> epsList) async {
    for (final eps in epsList) {
      await downloadEps(comic, eps);
    }
  }

  /// 重试出错的章节（直接用 comicId + epsOrder）
  Future<void> retryEps(String comicId, int epsOrder) async {
    final entry = entries[comicId];
    if (entry == null) return;
    final info = entry.episodes[epsOrder];
    if (info == null) return;
    info.status = PicAcgDownloadStatus.waiting;
    info.errorMsg = null;
    entries.refresh();
    _startDownloadEps(comicId, epsOrder);
  }

  /// 删除本地已下载的漫画（整本或单章）
  Future<void> deleteDownload(String comicId, {int? epsOrder}) async {
    final entry = entries[comicId];
    if (entry == null) return;

    final baseDir = await _comicDir(comicId);
    if (epsOrder != null) {
      final epsDir = Directory('${baseDir.path}/$epsOrder');
      if (await epsDir.exists()) await epsDir.delete(recursive: true);
      entry.episodes.remove(epsOrder);
      if (entry.episodes.isEmpty) {
        entries.remove(comicId);
        if (await baseDir.exists()) await baseDir.delete(recursive: true);
      } else {
        entries.refresh();
      }
    } else {
      if (await baseDir.exists()) await baseDir.delete(recursive: true);
      entries.remove(comicId);
    }
    await _persistMeta();
  }

  /// 检查章节是否已完全下载
  bool isEpsDownloaded(String comicId, int epsOrder) {
    return entries[comicId]?.episodes[epsOrder]?.isCompleted == true;
  }

  /// 获取某章节某页的本地文件路径（用于离线阅读）
  Future<String?> getLocalPagePath(String comicId, int epsOrder, int pageIndex) async {
    if (!isEpsDownloaded(comicId, epsOrder)) return null;
    final dir = await _epsDir(comicId, epsOrder);
    final file = File('${dir.path}/${_pageFileName(pageIndex)}');
    return (await file.exists()) ? file.path : null;
  }

  /// 获取某章节所有本地图片路径（按页序排列）
  Future<List<String>> getLocalPages(String comicId, int epsOrder) async {
    final dir = await _epsDir(comicId, epsOrder);
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((f) => f is File && f.path.endsWith('.jpg'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.map((f) => f.path).toList();
  }

  /// ---- 内部实现 ----

  void _startDownloadEps(String comicId, int epsOrder) {
    final key = '$comicId:$epsOrder';
    if (_activeKeys.contains(key)) return;
    _activeKeys.add(key);
    _downloadEpsImpl(comicId, epsOrder).whenComplete(() {
      _activeKeys.remove(key);
    });
  }

  Future<void> _downloadEpsImpl(String comicId, int epsOrder) async {
    final entry = entries[comicId];
    if (entry == null) return;

    final info = entry.episodes[epsOrder]!;
    info.status = PicAcgDownloadStatus.downloading;
    entries.refresh();

    try {
      // 1. 获取所有图片页（支持多服务器分页）
      final allPages = <PicAcgPage>[];
      int page = 1;
      int totalPages = 1;
      do {
        final result = await _api.getEpsPages(comicId, epsOrder, page: page);
        allPages.addAll(result.pages);
        totalPages = result.pagination.pages;
        page++;
      } while (page <= totalPages);

      info.totalPages = allPages.length;
      info.downloadedPages = 0;
      entries.refresh();
      await _persistMeta();

      // 2. 逐张下载保存
      final dir = await _epsDir(comicId, epsOrder);
      await dir.create(recursive: true);

      for (int i = 0; i < allPages.length; i++) {
        final imgFile = File('${dir.path}/${_pageFileName(i + 1)}');
        if (await imgFile.exists()) {
          info.downloadedPages++;
          entries.refresh();
          continue;
        }

        try {
          final Uint8List bytes = await _api.fetchImageBytes(allPages[i].media);
          await imgFile.writeAsBytes(bytes, flush: true);
          info.downloadedPages++;
          entries.refresh();
        } catch (e) {
          logger.error('PicACG 图片下载失败 $comicId/$epsOrder/p${i + 1}: $e');
          // 单张失败不中断整体，继续下载剩余
        }
      }

      if (info.downloadedPages >= info.totalPages) {
        info.status = PicAcgDownloadStatus.completed;
      } else {
        info.status = PicAcgDownloadStatus.error;
        info.errorMsg = '部分图片下载失败（${info.downloadedPages}/${info.totalPages}）';
      }
    } catch (e) {
      info.status = PicAcgDownloadStatus.error;
      info.errorMsg = e.toString();
      logger.error('PicACG 章节下载失败 $comicId/$epsOrder: $e');
    }

    entries.refresh();
    await _persistMeta();
  }

  Future<Directory> _comicDir(String comicId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/picacg_downloads/$comicId');
  }

  Future<Directory> _epsDir(String comicId, int epsOrder) async {
    final base = await _comicDir(comicId);
    return Directory('${base.path}/$epsOrder');
  }

  String _pageFileName(int index) => 'p${index.toString().padLeft(4, '0')}.jpg';

  Future<void> _persistMeta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDownloadMetaKey, PicAcgDownloadEntry.encodeAll(entries));
    } catch (e) {
      logger.error('PicACG 下载元数据持久化失败: $e');
    }
  }
}
