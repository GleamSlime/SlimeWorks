library;

/// Manga 漫画阅读器页面
///
/// 支持纵向滚动阅读，图片逐张加载
/// AppBar/BottomBar 由页面内部 Stack 覆盖层直接管理，支持沉浸模式（点击切换）

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/manga_download_service.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/viewmodels/base_page.dart';
import 'package:slime_works/pages/manga/components/manga_image_view.dart';
import 'package:slime_works/pages/manga/models/manga_models.dart';
import 'package:slime_works/pages/manga/view_models/manga_reader_viewmodel.dart';

/// 阅读器顶底栏深色背景色（与漫画黑色背景协调）
// 已改为使用主题色，去除硬编码暗色

class MangaReaderScreen extends BasePage<MangaReaderViewModel> {
  const MangaReaderScreen({
    super.key,
    required this.comicId,
    required this.epsOrder,
    this.epsTitle = '',
  });

  final String comicId;
  final int epsOrder;
  final String epsTitle;

  @override
  State<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState
    extends BasePageState<MangaReaderViewModel, MangaReaderScreen> {
  final ScrollController _scrollController = ScrollController();

  /// 本地沉浸模式状态（替代全局 DesktopScreenProvider.mobileImmersiveMode）
  final RxBool _isImmersive = false.obs;

  /// 自动沉浸定时 Timer（定时进入）
  Timer? _autoImmersiveTimer;

  /// 防止底部弹层重复弹出
  bool _isBottomSheetOpen = false;

  /// 记录上次 scroll 位置，用于计算偏移距离
  double _lastScrollPixels = 0;

  /// 向下累计滚动距离（进入沉浸）
  double _scrollDownAccum = 0;

  /// 向上累计滚动距离（退出沉浸）
  double _scrollUpAccum = 0;

  /// 历导当前章节已加载图片的高度缓存，防止 ListView 回收 Widget 后高度抖动
  final Map<int, double> _pageHeights = {};

  static const double _kImmersiveScrollThreshold = 100;
  static const double _kExitImmersiveScrollUp = 60;
  static const Duration _kOverlayAnim = Duration(milliseconds: 180);

  void _handleBack() {
    _isImmersive.value = false;
    if (context.canPop()) {
      context.pop();
      return;
    }
    MangaComicDetailRoute(comicId: widget.comicId).go(context);
  }

  @override
  MangaReaderViewModel createViewModel() => MangaReaderViewModel();

  @override
  bool get showAppBar => false;

  @override
  Future<void> onPageInit() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await viewModel.loadPages(widget.comicId, widget.epsOrder);
    _scrollController.addListener(_onScroll);
    _scheduleAutoImmersive();
  }

  /// 根据设置启动自动沉浸定时器
  void _scheduleAutoImmersive() {
    _autoImmersiveTimer?.cancel();
    final secs = viewModel.autoImmersiveSeconds.value;
    if (secs <= 0) return;
    _autoImmersiveTimer = Timer(Duration(seconds: secs), () {
      if (mounted && !_isImmersive.value) {
        _isImmersive.value = true;
      }
    });
  }

  @override
  void dispose() {
    _isImmersive.close();
    _autoImmersiveTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到底部附近时触发加载更多
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      viewModel.loadMore();
    }
    final firstVisible = (pos.pixels / 600).floor();
    viewModel.prefetchAhead(firstVisible + 1);

    // 向下累积 100px → 进入沉浸；向上累积 60px → 退出沉浸
    if (viewModel.autoImmersiveOnScrollDown.value) {
      final delta = pos.pixels - _lastScrollPixels;
      if (delta > 0) {
        // 向下
        _scrollUpAccum = 0;
        _scrollDownAccum += delta;
        if (_scrollDownAccum >= _kImmersiveScrollThreshold &&
            !_isImmersive.value) {
          _scrollDownAccum = 0;
          _isImmersive.value = true;
        }
      } else if (delta < 0) {
        // 向上
        _scrollDownAccum = 0;
        _scrollUpAccum += (-delta);
        if (_scrollUpAccum >= _kExitImmersiveScrollUp && _isImmersive.value) {
          _scrollUpAccum = 0;
          _isImmersive.value = false;
        }
      }
    }
    _lastScrollPixels = pos.pixels;
  }

  @override
  Widget buildContent(BuildContext context) {
    final String epsTitle = widget.epsTitle.isNotEmpty
        ? widget.epsTitle
        : '第 ${widget.epsOrder} 话';

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          // 内容区：点击切换沉浸模式
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _isImmersive.value = !_isImmersive.value,
            child: Obx(() {
              final error = viewModel.readerError.value;
              if (error != null) return _buildErrorView(context, error);
              return _buildReaderView(context);
            }),
          ),

          // 顶部 AppBar 覆盖层（返回 + 章节标题 + 更多）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Obx(() {
              final isImmersive = _isImmersive.value;
              return IgnorePointer(
                ignoring: isImmersive,
                child: AnimatedSlide(
                  duration: _kOverlayAnim,
                  curve: Curves.easeOutCubic,
                  offset: isImmersive ? const Offset(0, -1) : Offset.zero,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.62),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: SizedBox(
                            height: AppTheme.metrics.kSpace48,
                            child: AppBar(
                              primary: false,
                              toolbarHeight: AppTheme.metrics.kSpace48,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              foregroundColor: Colors.black87,
                              leading: IconButton(
                                icon: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: AppTheme.metrics.iconSize20,
                                ),
                                onPressed: _handleBack,
                                color: Colors.black87,
                              ),
                              centerTitle: true,
                              title: Text(
                                epsTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: AppTheme.metrics.fontSize15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              actions: [
                                IconButton(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    size: AppTheme.metrics.iconSize22,
                                  ),
                                  onPressed: () => _showMoreMenu(context),
                                  color: Colors.black87,
                                ),
                              ],
                              actionsPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          // 底部 BottomBar 覆盖层（章节导航）
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Obx(() {
              final isImmersive = _isImmersive.value;
              if (viewModel.epsList.isEmpty) return const SizedBox.shrink();
              return IgnorePointer(
                ignoring: isImmersive,
                child: AnimatedSlide(
                  duration: _kOverlayAnim,
                  curve: Curves.easeOutCubic,
                  offset: isImmersive ? const Offset(0, 1) : Offset.zero,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.62),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Obx(
                            () => _ReaderBottomBar(
                              currentEps: viewModel.currentEpsOrder,
                              totalEps: viewModel.epsList.length,
                              onEpsTap: () => _showEpsSheet(context),
                              onSettingsTap: () => _showSettingsSheet(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载'),
              subtitle: Text(
                '选择章节下载',
                style: TextStyle(fontSize: AppTheme.metrics.fontSize11),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _showDownloadSheet(context);
              },
            ),
            if (PlatformUtil.isDesktop)
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('离线保存到媒体库'),
                subtitle: Text(
                  '保存所有已加载图片',
                  style: TextStyle(fontSize: AppTheme.metrics.fontSize11),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('待实现：保存到媒体库')));
                },
              ),
            SizedBox(height: AppTheme.metrics.kSpace8),
          ],
        ),
      ),
    ).whenComplete(() => _isBottomSheetOpen = false);
  }

  void _showDownloadSheet(BuildContext context) {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;
    if (viewModel.epsList.isEmpty) {
      _isBottomSheetOpen = false;
      return;
    }

    // 如果 comic 还没拉到就先等待，或用空对象占位（id/title/thumb 从 service 缓存取）
    Future<MangaComic?> getComic() async {
      if (viewModel.comic != null) return viewModel.comic;
      try {
        final c = await getIt<MangaService>().getComicDetail(widget.comicId);
        viewModel.comic = c;
        return c;
      } catch (_) {
        return null;
      }
    }

    // 提前捕获 context 相关对象，避免跨异步间隙使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final ctx = context;

    getComic().then((comic) {
      if (!mounted) {
        _isBottomSheetOpen = false;
        return;
      }
      if (comic == null) {
        _isBottomSheetOpen = false;
        messenger.showSnackBar(const SnackBar(content: Text('获取漫画信息失败，请重试')));
        return;
      }
      final dl = getIt<MangaDownloadService>();
      final selected = <int>{};

      // ignore: use_build_context_synchronously
      showModalBottomSheet(
        // ignore: use_build_context_synchronously
        context: ctx,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx2, setSheetState) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                builder: (_, controller) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          children: [
                            Text(
                              '选择下载章节',
                              style: TextStyle(
                                fontSize: AppTheme.metrics.fontSize15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  if (selected.length ==
                                      viewModel.epsList.length) {
                                    selected.clear();
                                  } else {
                                    selected.addAll(
                                      viewModel.epsList.map((e) => e.order),
                                    );
                                  }
                                });
                              },
                              child: Text(
                                selected.length == viewModel.epsList.length
                                    ? '取消全选'
                                    : '全选',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          controller: controller,
                          padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 2.5,
                              ),
                          itemCount: viewModel.epsList.length,
                          itemBuilder: (_, i) {
                            final ep = viewModel.epsList[i];
                            final info =
                                dl.entries[comic.id]?.episodes[ep.order];
                            final isDownloaded = info?.isCompleted == true;
                            final isSelected = selected.contains(ep.order);
                            return GestureDetector(
                              onTap: () => setSheetState(() {
                                if (isDownloaded) return;
                                if (isSelected) {
                                  selected.remove(ep.order);
                                } else {
                                  selected.add(ep.order);
                                }
                              }),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isDownloaded
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : isSelected
                                      ? Theme.of(ctx2).colorScheme.primary
                                            .withValues(alpha: 0.3)
                                      : Theme.of(
                                          ctx2,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: AppTheme.metrics.radius6,
                                  border: isSelected
                                      ? Border.all(
                                          color: Theme.of(
                                            ctx2,
                                          ).colorScheme.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  '${ep.order}',
                                  style: TextStyle(
                                    color: isDownloaded
                                        ? Colors.green
                                        : Theme.of(ctx2).colorScheme.onSurface,
                                    fontSize: AppTheme.metrics.fontSize11,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SafeArea(
                          top: false,
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      final eps = viewModel.epsList
                                          .where(
                                            (e) => selected.contains(e.order),
                                          )
                                          .toList();
                                      dl.downloadEpsMultiple(comic, eps);
                                    },
                              child: Text(
                                '下载 ${selected.isEmpty ? '' : selected.length} 章',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ).whenComplete(() => _isBottomSheetOpen = false);
    });
  }

  void _showSettingsSheet(BuildContext context) {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ReaderSettingsSheet(viewModel: viewModel),
    ).whenComplete(() => _isBottomSheetOpen = false);
  }

  /// 显示章节列表底部弹窗
  void _showEpsSheet(BuildContext context) {
    if (_isBottomSheetOpen) return;
    _isBottomSheetOpen = true;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  vertical: AppTheme.metrics.kSpace12,
                ),
                child: Text(
                  '章节列表',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Obx(
                  () => GridView.builder(
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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
                            _pageHeights.clear();
                            viewModel.switchEps(eps.order);
                          }
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? Theme.of(ctx).colorScheme.primary
                                : Theme.of(
                                    ctx,
                                  ).colorScheme.surfaceContainerHighest,
                            borderRadius: AppTheme.metrics.radius6,
                          ),
                          child: Text(
                            '${eps.order}',
                            style: TextStyle(
                              color: isCurrent
                                  ? Theme.of(ctx).colorScheme.onPrimary
                                  : Theme.of(ctx).colorScheme.onSurface,
                              fontSize: AppTheme.metrics.fontSize11,
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
    ).whenComplete(() => _isBottomSheetOpen = false);
  }

  /// 错误页面（支持重试）
  Widget _buildErrorView(BuildContext context, String error) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(AppTheme.metrics.kSpace24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.white70,
                  size: AppTheme.metrics.iconSize48,
                ),
                SizedBox(height: AppTheme.metrics.kSpace16),
                SelectableText(
                  error,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppTheme.metrics.kSpace16),
                FilledButton(
                  onPressed: () =>
                      viewModel.loadPages(widget.comicId, widget.epsOrder),
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
    return Obx(() {
      final extraCount = viewModel.hasMore
          ? 1
          : (viewModel.nextEps != null ? 1 : 0);
      return ListView.builder(
        controller: _scrollController,
        cacheExtent: 2000,
        physics: const ClampingScrollPhysics(),
        itemCount: viewModel.pages.length + extraCount,
        itemBuilder: (ctx, i) {
          if (i >= viewModel.pages.length) {
            if (viewModel.hasMore) {
              return Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            }
            // 所有部分已加载完毕，显示下一章公告
            final next = viewModel.nextEps;
            if (next == null) return const SizedBox.shrink();
            return _NextChapterBanner(
              nextEps: next,
              onTap: () {
                _scrollController.jumpTo(0);
                _pageHeights.clear();
                viewModel.switchEps(next.order);
              },
            );
          }
          final page = viewModel.pages[i];
          return Obx(
            () => Padding(
              padding: EdgeInsets.symmetric(
                horizontal:
                    MediaQuery.of(context).size.width *
                    (viewModel.imageHorizontalPadding.value / 100),
              ),
              child: _ComicPageImage(
                image: page.media,
                pageIndex: i + 1,
                initialHeight: _pageHeights[i],
                onImageLoaded: (h) => _pageHeights[i] = h,
              ),
            ),
          );
        },
      );
    });
  }
}

/// 底部操作栏（背景由外层磨砂玻璃容器提供，此处透明）
class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.onEpsTap,
    required this.onSettingsTap,
    required this.currentEps,
    required this.totalEps,
  });

  final VoidCallback onEpsTap;
  final VoidCallback onSettingsTap;
  final int currentEps;
  final int totalEps;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Expanded(
            child: _BarBtn(
              icon: Icons.menu_book_outlined,
              label: '章节',
              badge: '$currentEps / $totalEps',
              onTap: onEpsTap,
            ),
          ),
          Container(
            width: 0.5,
            height: AppTheme.metrics.kSpace32,
            color: Colors.black.withValues(alpha: 0.1),
          ),
          Expanded(
            child: _BarBtn(
              icon: Icons.tune_rounded,
              label: '设置',
              onTap: onSettingsTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({
    required this.icon,
    required this.label,
    this.badge,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    /// 图标和文字固定使用深色，以适配白色磨砂背景
    const iconColor = Color(0xFF1A1A1A);
    const labelColor = Color(0xFF444444);
    const badgeColor = Color(0xFF888888);

    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.metrics.radius10,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace16,
          vertical: AppTheme.metrics.kSpace6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: AppTheme.metrics.iconSize20),
            SizedBox(height: AppTheme.metrics.kSpace2),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: AppTheme.metrics.fontSize10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
            if (badge != null) ...[
              SizedBox(height: AppTheme.metrics.kSpace1),
              Text(
                badge!,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: AppTheme.metrics.fontSize9,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单张漫画图片组件
///
/// [Memory Optimization] 移除 AutomaticKeepAliveClientMixin，允许 ListView 回收屏幕
/// 外的图片 Widget，防止大量图片常驻内存导致 OOM（高水位内存超限）。
/// 图片字节由 MangaService 的 LRU 缓存持有，即使 Widget 被回收后滚回来时
/// 也会命中缓存，快速恢复显示。使用 initialHeight 减少布局抖动。
class _ComicPageImage extends StatefulWidget {
  const _ComicPageImage({
    required this.image,
    required this.pageIndex,
    this.initialHeight,
    this.onImageLoaded,
  });

  final MangaImage image;
  final int pageIndex;

  /// 上次已知的显示高度（从父组件传入，用于平滑 placeholder 高度防止抖动）
  final double? initialHeight;

  /// 图片成功渲染后回调实际高度
  final ValueChanged<double>? onImageLoaded;

  @override
  State<_ComicPageImage> createState() => _ComicPageImageState();
}

class _ComicPageImageState extends State<_ComicPageImage> {
  final GlobalKey _containerKey = GlobalKey();

  /// 图片加载完成或刷新后测量并上报容器高度
  void _measureAndReportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _containerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if (h > 0) widget.onImageLoaded?.call(h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholderHeight = widget.initialHeight ?? scaleW(400);
    return ColoredBox(
      key: _containerKey,
      color: Colors.black,
      child: MangaImageView(
        image: widget.image,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        onLoad: _measureAndReportHeight,
        loadingBuilder: (_) {
          return SizedBox(
            height: placeholderHeight,
            child: Center(
              child: MangaProgressRing(size: scaleW(44), color: Colors.white70),
            ),
          );
        },
        errorBuilder: (_, e, onRetry) => SizedBox(
          height: placeholderHeight,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: AppTheme.metrics.iconSize48,
                ),
                SizedBox(height: AppTheme.metrics.kSpace12),
                Text(
                  'P${widget.pageIndex} 加载失败',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: AppTheme.metrics.fontSize11,
                  ),
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: Icon(
                    Icons.refresh,
                    color: Colors.white70,
                    size: AppTheme.metrics.iconSize16,
                  ),
                  label: const Text(
                    '重试',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 阅读器设置面板
///
/// 包含：图片左右间距 / 预加载图片数 / 自动沉浸倒计时 / 向下滚动自动沉浸开关
class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({required this.viewModel});
  final MangaReaderViewModel viewModel;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late double _padding;
  late int _preloadCount;
  late int _autoImmersiveSec;
  late bool _autoImmersiveOnScroll;

  @override
  void initState() {
    super.initState();
    _padding = widget.viewModel.imageHorizontalPadding.value;
    _preloadCount = widget.viewModel.preloadCount.value;
    _autoImmersiveSec = widget.viewModel.autoImmersiveSeconds.value;
    _autoImmersiveOnScroll = widget.viewModel.autoImmersiveOnScrollDown.value;
  }

  void _save() {
    widget.viewModel.imageHorizontalPadding.value = _padding;
    widget.viewModel.preloadCount.value = _preloadCount;
    widget.viewModel.autoImmersiveSeconds.value = _autoImmersiveSec;
    widget.viewModel.autoImmersiveOnScrollDown.value = _autoImmersiveOnScroll;
    widget.viewModel.saveSettings();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.6),
      fontSize: AppTheme.metrics.fontSize13,
    );
    final titleStyle = TextStyle(
      color: cs.onSurface,
      fontWeight: FontWeight.bold,
      fontSize: AppTheme.metrics.fontSize15,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace20,
          vertical: AppTheme.metrics.kSpace8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '阅读设置',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace18),

            // ── 图片左右间距 ──
            Row(
              children: [
                Expanded(child: Text('图片左右间距', style: titleStyle)),
                Text('${_padding.toInt()} %', style: labelStyle),
              ],
            ),
            Slider(
              value: _padding,
              min: 0,
              max: 40,
              divisions: 8,
              onChanged: (v) => setState(() => _padding = v),
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),

            // ── 预加载图片数量 ──
            Text('预加载图片数量', style: titleStyle),
            SizedBox(height: AppTheme.metrics.kSpace8),
            Wrap(
              spacing: 8,
              children: [1, 3, 5, 10].map((n) {
                final selected = _preloadCount == n;
                return ChoiceChip(
                  label: Text('$n 张'),
                  selected: selected,
                  onSelected: (_) => setState(() => _preloadCount = n),
                );
              }).toList(),
            ),
            SizedBox(height: AppTheme.metrics.kSpace16),

            // ── 自动进入沉浸式时间 ──
            Text('自动进入沉浸模式', style: titleStyle),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text('进入阅读器后自动隐藏顶底栏（0 = 关闭）', style: labelStyle),
            SizedBox(height: AppTheme.metrics.kSpace8),
            Wrap(
              spacing: 8,
              children: [0, 3, 5, 10, 30].map((s) {
                final selected = _autoImmersiveSec == s;
                return ChoiceChip(
                  label: Text(s == 0 ? '不自动' : '$s 秒'),
                  selected: selected,
                  onSelected: (_) => setState(() => _autoImmersiveSec = s),
                );
              }).toList(),
            ),
            SizedBox(height: AppTheme.metrics.kSpace16),

            // ── 向下滚动自动沉浸 ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('向下滚动时自动沉浸', style: titleStyle),
                      SizedBox(height: AppTheme.metrics.kSpace2),
                      Text('向下滚动时自动隐藏顶底栏', style: labelStyle),
                    ],
                  ),
                ),
                Switch(
                  value: _autoImmersiveOnScroll,
                  onChanged: (v) => setState(() => _autoImmersiveOnScroll = v),
                ),
              ],
            ),
            SizedBox(height: AppTheme.metrics.kSpace20),

            // ── 保存按钮 ──
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下一章引导横幅
class _NextChapterBanner extends StatelessWidget {
  const _NextChapterBanner({required this.nextEps, required this.onTap});
  final MangaEps nextEps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(color: theme.colorScheme.outlineVariant),
          SizedBox(height: AppTheme.metrics.kSpace16),
          Text(
            '本章已读完',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace12),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.navigate_next),
            label: Text('下一章：第 ${nextEps.order} 话'),
          ),
          SizedBox(height: AppTheme.metrics.kSpace8),
        ],
      ),
    );
  }
}
