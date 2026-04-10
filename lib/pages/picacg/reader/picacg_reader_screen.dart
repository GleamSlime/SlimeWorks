library;

/// PicACG 漫画阅读器页面
///
/// 支持纵向滚动阅读，图片逐张加载
/// 点击屏幕切换顶部/底部 UI 显隐（沉浸模式）

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
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

class _PicAcgReaderScreenState extends BasePageState<PicAcgReaderViewModel, PicAcgReaderScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _uiController;
  late final Animation<double> _uiAnim;
  bool _uiVisible = true;

  ScreenChromeData _buildScreenChromeData() {
    return ScreenChromeData(
      titleWidget: Text(
        widget.epsTitle.isNotEmpty ? widget.epsTitle : '第 ${widget.epsOrder} 话',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handleBack),
      enableMobileImmersiveMode: true,
      mobileBodyHandlesInsets: true,
    );
  }

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
  void initState() {
    super.initState();
    _uiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _uiAnim = CurvedAnimation(parent: _uiController, curve: Curves.easeInOut);
  }

  @override
  Future<void> onPageInit() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await viewModel.loadPages(widget.comicId, widget.epsOrder);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    _uiController.dispose();
    super.dispose();
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _uiController.forward();
    } else {
      _uiController.reverse();
    }
  }

  /// 滚动到底部附近时触发加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      viewModel.loadMore();
    }
  }

  @override
  Widget buildContent(BuildContext context) {
    return ScreenChrome(
      data: _buildScreenChromeData(),
      child: ColoredBox(
        color: Colors.black,
        child: Obx(() {
          final error = viewModel.readerError.value;
          if (error != null) return _buildErrorView(context, error);
          return GestureDetector(
            onTap: _toggleUi,
            behavior: HitTestBehavior.opaque,
            child: Stack(children: [_buildReaderView(context), _buildBottomBar(context)]),
          );
        }),
      ),
    );
  }

  /// 底部操作栏（章节 / 更多 / 设置）
  Widget _buildBottomBar(BuildContext context) {
    return Obx(() {
      if (viewModel.epsList.isEmpty) return const SizedBox.shrink();
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: FadeTransition(
          opacity: _uiAnim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(_uiAnim),
            child: _ReaderBottomBar(
              currentEps: viewModel.currentEpsOrder,
              totalEps: viewModel.epsList.length,
              onEpsTap: () => _showEpsSheet(context),
              onMoreTap: () => _showMoreMenu(context),
              onSettingsTap: () => _showSettingsSheet(context),
            ),
          ),
        ),
      );
    });
  }

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.white70),
              title: const Text('离线保存到媒体库', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                '保存所有已加载图片',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('待实现：保存到媒体库')));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '阅读设置',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('更多设置选项待扩展', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示章节列表底部弹窗
  void _showEpsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '章节列表',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Obx(
                  () => GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.5,
                    ),
                    itemCount: viewModel.epsList.length,
                    itemBuilder: (_, i) {
                      final eps = viewModel.epsList[i];
                      final isCurrent = eps.order == viewModel.currentEpsOrder;
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (!isCurrent) {
                            _scrollController.jumpTo(0);
                            viewModel.switchEps(eps.order);
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.blue : Colors.grey[800],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${eps.order}',
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  /// [Fix] cacheExtent 加大到 2000，防止上滑时因 item 被回收/重建触发布局抖动
  /// [Fix] 使用 ClampingScrollPhysics，去掉 Bouncing 弹性边界减少位置重算
  Widget _buildReaderView(BuildContext context) {
    return Obx(
      () => ListView.builder(
        controller: _scrollController,
        cacheExtent: 2000,
        physics: const ClampingScrollPhysics(),
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
    );
  }
}

/// 底部操作栏（不透明深色背景）
class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.onEpsTap,
    required this.onMoreTap,
    required this.onSettingsTap,
    required this.currentEps,
    required this.totalEps,
  });

  final VoidCallback onEpsTap;
  final VoidCallback onMoreTap;
  final VoidCallback onSettingsTap;
  final int currentEps;
  final int totalEps;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xE6121212),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BarBtn(
                icon: Icons.menu_book_outlined,
                label: '章节',
                badge: '$currentEps/$totalEps',
                onTap: onEpsTap,
              ),
              _BarBtn(icon: Icons.more_horiz, label: '更多', onTap: onMoreTap),
              _BarBtn(icon: Icons.settings_outlined, label: '设置', onTap: onSettingsTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({required this.icon, required this.label, this.badge, required this.onTap});
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 22),
            const SizedBox(height: 2),
            Text(
              badge != null ? '$label  $badge' : label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
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
    return ColoredBox(
      color: Colors.black,
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
