/// PicACG 漫画阅读器页面
///
/// 支持纵向滚动阅读，图片逐张加载
/// 移动端和桌面端均可使用

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 阅读器 ViewModel
class PicacgReaderViewModel extends BaseViewModel {
  final PicacgService _service = getIt<PicacgService>();

  final RxList<PicacgPage> pages = <PicacgPage>[].obs;
  final Rx<PicacgPagination?> pagination = Rx<PicacgPagination?>(null);
  final RxBool isLoadingMore = false.obs;
  final RxBool showToolbar = true.obs;

  String _comicId = '';
  int _epsOrder = 1;
  int _currentServerPage = 1;

  String _formatReaderError(Object error) {
    final raw = error.toString().replaceAll('\r\n', '\n').trim();
    if (raw.isEmpty) {
      return '章节加载失败';
    }

    final lines = raw
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return '章节加载失败';
    }

    final shortened = lines.take(6).join('\n');
    final wasTruncated = lines.length > 6 || raw.length > 600;
    if (!wasTruncated) {
      return shortened;
    }

    return '$shortened\n\n错误详情已截断，请重试或切换分流节点。';
  }

  Future<void> loadPages(String comicId, int epsOrder) async {
    _comicId = comicId;
    _epsOrder = epsOrder;
    _currentServerPage = 1;
    pages.clear();
    setLoading(true);
    try {
      final result = await _service.getEpsPages(comicId, epsOrder, page: 1);
      pages.assignAll(result.pages);
      pagination.value = result.pagination;
      clearError();
    } catch (e) {
      setError(_formatReaderError(e));
    } finally {
      setLoading(false);
    }
  }

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

  bool get hasMore {
    final p = pagination.value;
    return p != null && _currentServerPage < p.pages;
  }

  void toggleToolbar() {
    showToolbar.value = !showToolbar.value;
  }
}

class PicacgReaderScreen extends BasePage<PicacgReaderViewModel> {
  const PicacgReaderScreen({
    super.key,
    required this.comicId,
    required this.epsOrder,
    this.epsTitle = '',
  });

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  State<PicacgReaderScreen> createState() => _PicacgReaderScreenState();
}

class _PicacgReaderScreenState extends BasePageState<PicacgReaderViewModel, PicacgReaderScreen> {
  final ScrollController _scrollController = ScrollController();

  void _handleBack() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    PicacgComicDetailRoute(comicId: widget.comicId).go(context);
  }

  @override
  PicacgReaderViewModel createViewModel() => PicacgReaderViewModel();

  @override
  bool get showAppBar => false;

  @override
  Future<void> onPageInit() async {
    /// 阅读器进入时设置沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await viewModel.loadPages(widget.comicId, widget.epsOrder);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    /// 退出时恢复系统UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      viewModel.loadMore();
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GetBuilder<PicacgReaderViewModel>(
        builder: (vm) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (vm.errorMessage != null) {
            return SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white70, size: 48),
                        const SizedBox(height: 16),
                        SelectableText(
                          vm.errorMessage!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => vm.loadPages(widget.comicId, widget.epsOrder),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              /// 竖向滚动图片列表
              GestureDetector(
                onTap: vm.toggleToolbar,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  itemCount: vm.pages.length + (vm.hasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= vm.pages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: Colors.white)),
                      );
                    }
                    final page = vm.pages[i];
                    return _ComicPageImage(image: page.media, pageIndex: i + 1);
                  },
                ),
              ),

              /// 顶部工具栏（半透明）
              Obx(
                () => AnimatedOpacity(
                  opacity: vm.showToolbar.value ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      child: AppBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: _handleBack,
                        ),
                        title: Text(
                          widget.epsTitle.isNotEmpty ? widget.epsTitle : '第 ${widget.epsOrder} 话',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 单张漫画图片组件
class _ComicPageImage extends StatelessWidget {
  const _ComicPageImage({required this.image, required this.pageIndex});

  final PicacgImage image;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.3),
      child: PicacgImageView(
        image: image,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        loadingBuilder: (_) {
          return SizedBox(
            height: scaleW(400),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  const SizedBox(height: 8),
                  Text('P$pageIndex', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          );
        },
        errorBuilder: (_, __) => SizedBox(
          height: scaleW(200),
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}
