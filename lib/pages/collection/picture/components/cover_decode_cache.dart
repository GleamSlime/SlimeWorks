import 'dart:io';

import 'package:flutter/widgets.dart';

/// 预览页与列表封面之间的「图片缓存条目」约定。
///
/// 为什么要这个文件：Flutter 的 ImageCache 按 provider key 存条目，key 里含
/// 解码尺寸（`ResizeImageKey` = 内部 provider key + policy + width + height +
/// allowUpscaling）。列表卡片用 `ResizeImage(cacheWidth)` 解码，预览页原先
/// 不带任何尺寸参数，于是：
///
/// 1. 预览一张 4K 图会按**原始分辨率**解码（30MB 上下）。要么它超过
///    `maximumSizeBytes` 干脆不进缓存，要么它把 `_cache` 里的封面条目整批
///    挤掉——两种情况都会让返回列表时的封面重新解码；
/// 2. `_preloadNeighborMedia` 又按原图尺寸多解一张「下一页」，等于每翻页
///    再撑爆一次缓存；
/// 3. 缓存条目 key 不同 → 预览页解码的结果对列表毫无帮助，列表卡片用的
///    条目也从来没被预热过。表现就是「预览完返回列表 cover 重新加载且很慢」。
///
/// 这里统一两件事：
/// - **解码封顶**：预览图按视口物理像素（带上/下限）解码，单条目从 30MB 级
///   降到几 MB 级；
/// - **共享条目**：预览某项时，把它对应的**列表封面条目**（与 `MediaCardCover`
///   逐字同 key）预热进缓存，返回列表时直接命中，不再发起第二次解码。
class CoverDecodeCache {
  const CoverDecodeCache._();

  /// 解码边长下限：窗口很小（或测试环境）时也不低于这个值，避免缩放后发糊。
  static const int _minSide = 1080;

  /// 解码边长上限：再大就不值得了——2560 长边≈17MB（3:2 图），已能铺满常见
  /// 高分屏的 1:1 采样；不封顶的话一张 4K 原图就是 30MB+，ImageCache 只有
  /// 80MB 预算，几张预览图就能把列表封面条目全挤出去。
  /// 代价：预览里放大到 1x 以上会比原始分辨率略糊，这是「返回列表秒开」的交换。
  static const int _maxSide = 2560;

  /// 预览页的解码上限（物理像素边长）。
  ///
  /// 只依赖 MediaQuery 的尺寸与 dpr：当前页与预热的邻居页必须算出**同一个数**，
  /// 否则 ResizeImageKey 不同、预热换不来命中。所以不能用 LayoutBuilder 的约束
  /// （那会随每页内边距/视频覆盖层不同而变）。
  static int viewerDecodeSide(Size viewportLogicalSize, double devicePixelRatio) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final longest = viewportLogicalSize.longestSide * dpr;
    return longest.round().clamp(_minSide, _maxSide);
  }

  /// 预览图的 provider：与列表同源的「按上限解码」，不再全分辨率解码。
  ///
  /// 用 `resizeIfNeeded(maxSide, null, …)`：exact 策略只给宽、高度为 null 时
  /// 解码器按比例缩放，与原图观感一致；且这正是 `Image.network(cacheWidth:)`
  /// /`Image.file(cacheWidth:)` 内部生成的同一个 key——显示路径与预热路径
  /// 必须逐字相同，否则白解一遍。
  static ImageProvider<Object> viewerProvider(String src, int maxSide) {
    return ResizeImage.resizeIfNeeded(maxSide, null, _raw(src));
  }

  /// 列表卡片用的封面 provider。
  ///
  /// 构造必须与 `MediaCardCover._cover()` 里的完全一致（同 cacheWidth、同
  /// 「http 不缩放」规则），key 才相等；[coverSrc] 就是 `buildMediaSource(isCover: true)`
  /// 的结果。[cacheWidth] 传 `MediaPrefsService.localPreviewWidth.value ?? 480`，
  /// 与卡片一样：<=0 表示不缩放。
  static ImageProvider<Object>? gridCoverProvider(String? coverSrc, int? cacheWidth) {
    if (coverSrc == null || coverSrc.isEmpty) return null;
    final isHttp = coverSrc.startsWith('http');
    return ResizeImage.resizeIfNeeded(
      isHttp ? null : cacheWidth,
      null,
      _raw(coverSrc),
    );
  }

  /// http 走 NetworkImage，其余按本地文件读。
  static ImageProvider<Object> _raw(String src) {
    return src.startsWith('http') ? NetworkImage(src) : FileImage(File(src));
  }

  /// 把设置里的「本地封面宽度」换算成卡片实际用的 cacheWidth。
  ///
  /// 规则与 `MediaCardCover._cover()` 保持一致：<=0 表示不缩放（返回 null）。
  /// 两边必须算出同一个数，ResizeImageKey 才相等、预热才换得来命中。
  static int? gridCacheWidth(int? localPreviewWidth) {
    final w = localPreviewWidth ?? 480;
    return w > 0 ? w : null;
  }

  /// 预热一项媒体会用到的缓存条目。
  ///
  /// - [coverSrc]：列表卡片用的封面条目（与 `MediaCardCover` 同 key）。
  ///   这一条是「返回列表不重新加载」的关键。
  /// - [fullSrc]：预览页要显示的封顶解码条目。传 null 表示这项不需要预览条目
  ///   （例如视频：显示的是播放器画面，图片缓存里只需要封面）。
  ///
  /// 失败一律静默：预热只是加速，真正的加载错误由显示路径报。
  /// 实际解码放到下一帧：调用点常在 build/首帧回调里，同帧解码会挤占布局。
  static void warmupItem({
    required BuildContext context,
    required String? fullSrc,
    required String? coverSrc,
    required int? coverCacheWidth,
    required int viewerMaxSide,
  }) {
    final cover = gridCoverProvider(coverSrc, coverCacheWidth);
    final needsViewer = fullSrc != null && fullSrc.isNotEmpty;
    if (cover == null && !needsViewer) return;
    final viewer = needsViewer ? viewerProvider(fullSrc, viewerMaxSide) : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      // 1) 列表封面条目：返回列表时命中的就是这一条
      if (cover != null) {
        _safePrecache(cover, context);
      }
      // 2) 预览解码条目：滑到这页时不空屏
      if (viewer != null) {
        _safePrecache(viewer, context);
      }
    });
  }

  static void _safePrecache(ImageProvider<Object> provider, BuildContext context) {
    // precacheImage 内部会 resolve 到 ImageCache，完成后再解除监听：
    // 条目留在 keepAlive 区，等列表卡片真正订阅时直接命中。
    // onError 给个空实现：预加载失败不该往 FlutterError 里灌噪音，
    // 真正的加载错误由显示路径的 errorBuilder 负责。
    precacheImage(provider, context, onError: (Object _, StackTrace? _) {});
  }
}
