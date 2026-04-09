library;

/// PicACG 漫画阅读器页面
///
/// 支持纵向滚动阅读，图片逐张加载
/// 移动端和桌面端均可使用

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/picacg/components/picacg_image_view.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';
import 'package:slime_works/pages/picacg/view_models/picacg_reader_viewmodel.dart';

class PicAcgReaderScreen extends BasePage<PicAcgReaderViewModel> {
  const PicAcgReaderScreen({
    super.key,
    required this.comicId,
    required this.epsOrder,
    this.epsTitle = '',
  });

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  State<PicAcgReaderScreen> createState() => _PicAcgReaderScreenState();
}

class _PicAcgReaderScreenState extends BasePageState<PicAcgReaderViewModel, PicAcgReaderScreen> {
  final ScrollController _scrollController = ScrollController();

  void _handleBack() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    PicAcgComicDetailRoute(comicId: widget.comicId).go(context);
  }

  @override
  PicAcgReaderViewModel createViewModel() => PicAcgReaderViewModel();

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

  /// 滚动到底部附近时触发加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      viewModel.loadMore();
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    /// isLoading 由基类 GetBuilder 触发重建，此处直接读取即可
    if (viewModel.isLoading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    /// 用 Obx 监听 readerError（独立于基类 SnackBar 机制，避免错误被提前清除）
    return ColoredBox(
      color: Colors.black,
      child: Obx(() {
        final error = viewModel.readerError.value;
        if (error != null) {
          return _buildErrorView(context, error);
        }
        return _buildReaderView(context);
      }),
    );
  }

  /// 错误页面（支持重试）
  Widget _buildErrorView(BuildContext context, String error) {
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
                  error,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => viewModel.loadPages(widget.comicId, widget.epsOrder),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 阅读器主视图
  Widget _buildReaderView(BuildContext context) {
    return Stack(
      children: [
        /// 竖向滚动图片列表
        /// 使用 Obx 响应 pages / pagination 变化（loadMore 时 RxList 不触发 GetBuilder）
        Obx(
          () => ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: viewModel.pages.length + (viewModel.hasMore ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i >= viewModel.pages.length) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(color: Colors.white)),
                );
              }
              final page = viewModel.pages[i];
              return _ComicPageImage(image: page.media, pageIndex: i + 1);
            },
          ),
        ),

        /// 透明点击检测层 —— 放在 ListView 上方但不包裹它
        /// HitTestBehavior.translucent 使滑动事件穿透到下方 ListView，
        /// 避免 GestureDetector 包裹 ListView 时产生的手势竞争，解决无法滚动问题
        Positioned.fill(
          child: GestureDetector(
            onTap: viewModel.toggleToolbar,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),

        /// 顶部工具栏（半透明渐变背景）
        /// 隐藏时通过 IgnorePointer 允许点击事件穿透，确保点击可重新唤起工具栏
        Obx(
          () => IgnorePointer(
            ignoring: !viewModel.showToolbar.value,
            child: AnimatedOpacity(
              opacity: viewModel.showToolbar.value ? 1.0 : 0.0,
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
        ),
      ],
    );
  }
}

/// 单张漫画图片组件
class _ComicPageImage extends StatelessWidget {
  const _ComicPageImage({required this.image, required this.pageIndex});

  final PicAcgImage image;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.3),
      child: PicAcgImageView(
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
        errorBuilder: (_, e) => SizedBox(
          height: scaleW(200),
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}
