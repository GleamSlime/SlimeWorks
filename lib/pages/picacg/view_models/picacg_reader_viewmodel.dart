library;

/// PicACG 阅读器 ViewModel

import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_history_viewmodel.dart';

/// 阅读器状态管理
class PicAcgReaderViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 当前章节所有图片页
  final RxList<PicAcgPage> pages = <PicAcgPage>[].obs;

  /// 当前服务器分页信息
  final Rx<PicAcgPagination?> pagination = Rx<PicAcgPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  /// 阅读器专属错误（独立于 BasePage 的 errorMessage，避免被 SnackBar 自动清除）
  final Rx<String?> readerError = Rx<String?>(null);

  /// 章节列表（用于前后章节导航）
  final RxList<PicAcgEps> epsList = <PicAcgEps>[].obs;

  /// 当前漫画信息（用于下载弹层）
  PicAcgComic? comic;

  // ==================== 阅读器设置（持久化）====================

  /// 图片左右内边距（px，默认 0）
  final RxDouble imageHorizontalPadding = 0.0.obs;

  /// 预加载图片数量（默认 5）
  final RxInt preloadCount = 5.obs;

  /// 自动进入沉浸模式的延迟秒数（0 = 不自动进入）
  final RxInt autoImmersiveSeconds = 0.obs;

  /// 是否在向下滚动时自动进入沉浸模式
  final RxBool autoImmersiveOnScrollDown = false.obs;

  static const String _kSettingsKey = 'picacg_reader_settings';

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSettingsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      imageHorizontalPadding.value = (map['hPad'] as num?)?.toDouble() ?? 0.0;
      preloadCount.value = (map['preload'] as num?)?.toInt() ?? 5;
      autoImmersiveSeconds.value = (map['autoImmSec'] as num?)?.toInt() ?? 0;
      autoImmersiveOnScrollDown.value = map['autoImmScroll'] as bool? ?? false;
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSettingsKey,
        jsonEncode({
          'hPad': imageHorizontalPadding.value,
          'preload': preloadCount.value,
          'autoImmSec': autoImmersiveSeconds.value,
          'autoImmScroll': autoImmersiveOnScrollDown.value,
        }),
      );
    } catch (_) {}
  }

  String _comicId = '';
  int _epsOrder = 1;
  int _currentServerPage = 1;

  /// 当前 eps 在列表中的索引（按 order 排序）
  int get _currentEpsIndex => epsList.indexWhere((e) => e.order == _epsOrder);

  /// 上一章（order 更小）
  PicAcgEps? get prevEps {
    final idx = _currentEpsIndex;
    if (idx <= 0) return null;
    return epsList[idx - 1];
  }

  /// 下一章（order 更大）
  PicAcgEps? get nextEps {
    final idx = _currentEpsIndex;
    if (idx < 0 || idx >= epsList.length - 1) return null;
    return epsList[idx + 1];
  }

  /// 当前章节序号
  int get currentEpsOrder => _epsOrder;

  /// 格式化错误信息，截断过长的堆栈
  String _formatReaderError(Object error) {
    final raw = error.toString().replaceAll('\r\n', '\n').trim();
    if (raw.isEmpty) return '章节加载失败';

    final lines = raw
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return '章节加载失败';

    final shortened = lines.take(6).join('\n');
    final wasTruncated = lines.length > 6 || raw.length > 600;
    if (!wasTruncated) return shortened;

    return '$shortened\n\n错误详情已截断，请重试或切换分流节点。';
  }

  /// 加载章节图片（第一页）兼加载章节列表
  Future<void> loadPages(String comicId, int epsOrder) async {
    _comicId = comicId;
    _epsOrder = epsOrder;
    _currentServerPage = 1;
    pages.clear();
    readerError.value = null;
    setLoading(true);
    try {
      await loadSettings();
      final results = await Future.wait([
        _service.getEpsPages(comicId, epsOrder, page: 1),
        if (epsList.isEmpty) _service.getComicEps(comicId, page: 1),
      ]);
      final pageList = results[0] as PicAcgPageList;
      pages.assignAll(pageList.pages);
      pagination.value = pageList.pagination;

      if (epsList.isEmpty && results.length > 1 && results[1] is PicAcgEpsList) {
        final epsList0 = results[1] as PicAcgEpsList;
        epsList.assignAll(epsList0.eps);
        _loadRestEps(comicId, epsList0.pagination);
      }

      // 后台静默拉取漫画信息（用于下载弹层 + 历史记录封面）
      if (comic == null) {
        _service.getComicDetail(comicId).then((c) {
          comic = c;
          // 更新元数据缓存（确保历史记录封面有效）
          _service.cacheComicMeta(comicId, c.title, c.thumb.fullUrl);
          // 若 _saveProgress 先执行时封面为空，补存一次
          _saveProgress();
        }).ignore();
      }

      // 预加载前 N 张图片
      prefetchAhead(0);
      // 记录阅读进度（章节标题用 epsList 中查找）
      _saveProgress();
    } catch (e) {
      readerError.value = _formatReaderError(e);
    } finally {
      setLoading(false);
    }
  }

  /// 后台静默加载剩余章节页（不影响阅读）
  Future<void> _loadRestEps(String comicId, PicAcgPagination firstPagination) async {
    for (int page = 2; page <= firstPagination.pages; page++) {
      try {
        final more = await _service.getComicEps(comicId, page: page);
        epsList.addAll(more.eps);
      } catch (_) {
        break;
      }
    }
    // 按 order 升序排列（API 返回可能是降序）
    epsList.sort((a, b) => a.order.compareTo(b.order));
  }

  /// 切换到另一章节（保留已加载的 epsList）
  Future<void> switchEps(int epsOrder) async {
    _epsOrder = epsOrder;
    _currentServerPage = 1;
    pages.clear();
    readerError.value = null;
    setLoading(true);
    try {
      final result = await _service.getEpsPages(_comicId, epsOrder, page: 1);
      pages.assignAll(result.pages);
      pagination.value = result.pagination;
      prefetchAhead(0);
      _saveProgress();
    } catch (e) {
      readerError.value = _formatReaderError(e);
    } finally {
      setLoading(false);
    }
  }

  /// 保存阅读进度到 SharedPreferences，同时更新观看记录
  /// 格式：picacg_progress_{comicId} = '{epsOrder}:1:{epsTitle}'
  Future<void> _saveProgress() async {
    if (_comicId.isEmpty) return;
    try {
      final epsTitle =
          epsList
              .cast<PicAcgEps?>()
              .firstWhere((e) => e?.order == _epsOrder, orElse: () => null)
              ?.title ??
          '第$_epsOrder话';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('picacg_progress_$_comicId', '$_epsOrder:1:$epsTitle');

      /// 从元数据缓存获取漫画标题和封面（由详情页 getComicDetail 写入缓存）
      final meta = getIt<PicAcgService>().getComicMeta(_comicId);
      await PicAcgHistoryViewModel.saveRecord(
        comicId: _comicId,
        comicTitle: meta?.title ?? '',
        thumbUrl: meta?.thumbUrl ?? '',
        epsOrder: _epsOrder,
        epsTitle: epsTitle,
      );
    } catch (_) {}
  }

  /// 加载下一服务器分页
  Future<void> loadMore() async {
    final p = pagination.value;
    if (p == null || _currentServerPage >= p.pages) return;
    if (isLoadingMore.value) return;
    isLoadingMore.value = true;
    try {
      _currentServerPage++;
      final result = await _service.getEpsPages(_comicId, _epsOrder, page: _currentServerPage);
      pages.addAll(result.pages);
      pagination.value = result.pagination;
      // 新分页加载后继续预取
      prefetchAhead(pages.length - result.pages.length);
    } catch (e) {
      _currentServerPage--;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// 从 [fromIndex] 开始，预取后 [preloadCount] 张图片（已缓存则跳过）
  void prefetchAhead(int fromIndex) {
    final count = preloadCount.value.clamp(1, 20);
    final end = (fromIndex + count).clamp(0, pages.length);
    if (fromIndex >= end) return;
    _service.prefetchImages(pages.sublist(fromIndex, end).map((p) => p.media).toList());
  }

  /// 是否还有更多服务器分页
  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentServerPage < p.pages;
  }
}
