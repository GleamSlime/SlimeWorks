library;

/// PicACG 阅读器 ViewModel

import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 阅读器状态管理
class PicAcgReaderViewModel extends BaseViewModel {
  final PicAcgService _service = getIt<PicAcgService>();

  /// 当前章节所有图片页
  final RxList<PicAcgPage> pages = <PicAcgPage>[].obs;

  /// 当前服务器分页信息
  final Rx<PicAcgPagination?> pagination = Rx<PicAcgPagination?>(null);

  /// 是否正在加载更多
  final RxBool isLoadingMore = false.obs;

  /// 工具栏是否可见
  final RxBool showToolbar = true.obs;

  /// 阅读器专属错误（独立于 BasePage 的 errorMessage，避免被 SnackBar 自动清除）
  final Rx<String?> readerError = Rx<String?>(null);

  String _comicId = '';
  int _epsOrder = 1;
  int _currentServerPage = 1;

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

  /// 加载章节图片（第一页）
  Future<void> loadPages(String comicId, int epsOrder) async {
    _comicId = comicId;
    _epsOrder = epsOrder;
    _currentServerPage = 1;
    pages.clear();
    readerError.value = null;
    setLoading(true);
    try {
      final result = await _service.getEpsPages(comicId, epsOrder, page: 1);
      pages.assignAll(result.pages);
      pagination.value = result.pagination;
    } catch (e) {
      readerError.value = _formatReaderError(e);
    } finally {
      setLoading(false);
    }
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
    } catch (e) {
      _currentServerPage--;
    } finally {
      isLoadingMore.value = false;
    }
  }

  /// 是否还有更多服务器分页
  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentServerPage < p.pages;
  }

  /// 切换工具栏显示状态
  void toggleToolbar() {
    showToolbar.value = !showToolbar.value;
  }
}
