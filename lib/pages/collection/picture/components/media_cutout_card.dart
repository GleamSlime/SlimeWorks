import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';
import 'package:slime_works/pages/collection/picture/components/debug_image_size_badge.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 镂空卡的一套几何
///
/// 卡片分两段：上面是封面（按 [mediaRatio] 横幅），下面是实色文字区。
/// 网格的 `childAspectRatio`、框选的命中矩形、瀑布流的格子高度都必须和
/// 卡片自己排出来的尺寸同源，所以这三处一律从这里取数，不再各写一份字面量。
abstract final class MediaCutoutGeometry {
  /// 封面宽高比
  static const double mediaRatio = 1.5;

  /// 描边宽：层次主要靠这一圈实心描边拉开，投影只负责"离地一点点"
  static const double edge = 1.0;

  /// 浏览网格一格的宽度上限：网格排布和框选命中都按它算列数
  static double get maxCellWidth => scaleW(220);

  static double get pad => appMetrics.kSpace12;
  static double get titleGap => appMetrics.kSpace4;
  static double get blockGap => appMetrics.kSpace10;

  /// 左下标签：只有右上角是圆的，另外两条直边直接长到图的边界上
  static double get labelRadius => scaleW(10);
  static double get labelPadX => appMetrics.kSpace10;
  static double get labelPadY => appMetrics.kSpace6;

  /// 右上标签
  static double get tagRadius => scaleW(8);
  static double get tagPadX => appMetrics.kSpace8;
  static double get tagPadY => appMetrics.kSpace4;

  /// 接缝上的内凹垫角：白色那两块接标签的直边，深色那两块接标签的另一头
  static double get labelFlare => scaleW(16);
  static double get tagFlare => scaleW(12);

  /// 页脚那一行：图标底 + 名称 + 右读数
  static double get avatarSize => scaleW(22);
  static double get avatarIcon => scaleW(12);
  static double get trailingSize => scaleW(26);
  static double get trailingInset => appMetrics.kSpace10;

  /// 静止时封面底部那层"白纱"的浓度
  static const double scrimAlpha = 0.36;

  /// 文字区高度：和内容区实际排的三段同源，网格按它反推卡片总高
  ///
  /// 字号一律吃字号族（含用户字号比例），否则用户把字号调到 1.5×，
  /// 这里按宽度族算出来的高度就会把文字挤出格子。
  static double contentExtent({bool withFoot = true}) {
    final m = appMetrics;
    final title = m.fontSize13 * 1.45;
    final body = m.fontSize11 * 1.5 * (withFoot ? 2 : 1);
    if (!withFoot) return pad * 2 + title + titleGap + body;
    final foot = math.max(avatarSize, m.fontSize13 * 1.4);
    return pad * 2 + title + titleGap + body + blockGap + 1 + blockGap + foot;
  }

  /// 定宽网格：按真实格宽反推卡片总高
  ///
  /// 文字区高度是定值（[contentExtent]），封面才是随格子伸缩的那一段。
  /// 网格只有拿到真实格宽才能把封面排成 [mediaRatio]，所以布局侧一律走这里。
  static double aspectFor(double cellWidth, {bool withFoot = true}) {
    if (cellWidth <= 0) return 1;
    return cellWidth / (cellWidth / mediaRatio + contentExtent(withFoot: withFoot));
  }
}

/// 媒体库四类卡共用的外壳：封面挖洞 + 实色文字区
///
/// 白表面咬进图里：左下的类型标签贴着图的左边缘和下边缘长出来，它的上边和右边
/// 各接一块内凹垫角；右上的深色标签用同一条弧的另一头，一块垫角往左铺、一块往下铺。
/// 标签底色取 [AppSemantic.surface]（也就是卡片自己那层表面），所以暗色档下
/// 挖出来的仍然是同一个形状，不会变成一块贴上去的白贴纸。
///
/// 三层动效各走各的时长：外壳描边+投影（[AppMotion.emphasis]）→ 封面推近
/// （[AppMotion.entrance]，比壳慢一档，所以悬停途中壳已稳而图还在推）→ 右下那颗
/// 按钮浮出（[AppMotion.slow]）。
class MediaCutoutCard extends StatelessWidget {
  const MediaCutoutCard({
    super.key,
    required this.media,
    required this.label,
    required this.title,
    this.tagLabel,
    this.tagIcon,
    this.body,
    this.bodyMono = false,
    this.footIcon,
    this.footName,
    this.footReadout,
    this.trailingIcon,
    this.trailingOnTap,
    this.trailingAtRest = false,
    this.mediaOverlay,
    this.selected = false,
    this.hovered = false,
    this.withFoot = true,
  });

  /// 封面本体（占位、模糊、调试徽标都由调用方决定，镂空层不关心图源）
  final Widget media;

  /// 左下镂空标签：卡片类型
  final String label;

  /// 右上镂空标签：主读数（条数 / 时长），为空则不挖这一块
  final String? tagLabel;
  final StrokeIcon? tagIcon;

  final String title;

  /// 次级说明：集合的所在目录 / 文件夹的资源摘要 / 智能文件夹的正则
  final String? body;

  /// 正文走等宽（正则模式）
  final bool bodyMono;

  final StrokeIcon? footIcon;
  final String? footName;

  /// 页脚右读数：体积
  final String? footReadout;

  /// 右下那颗悬停才浮出的按钮（收藏 / 编辑）
  final StrokeIcon? trailingIcon;
  final VoidCallback? trailingOnTap;

  /// 静止时也把它显示出来（已收藏要常驻可读，不能只在悬停时露一下）
  final bool trailingAtRest;

  /// 图区内的覆盖层：丢失徽标、悬停抽帧进度条
  final Widget? mediaOverlay;

  final bool selected;
  final bool hovered;

  /// 资源卡不带页脚：瀑布流里每格多一行元数据只会糊成噪声
  final bool withFoot;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final lifted = selected || hovered;
    return Container(
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: appMetrics.radiusCard,
        border: Border.all(
          color: selected ? s.accent : (hovered ? s.borderStrong : s.border),
          width: selected ? scaleW(2) : MediaCutoutGeometry.edge,
        ),
        boxShadow: s.elevation(lifted ? Elevation.card : Elevation.raised),
      ),
      // Container 已经把描边让进盒子，这里只补上圆角差
      child: ClipRRect(
        borderRadius: BorderRadius.all(
          Radius.circular(appMetrics.radiusCard.topLeft.x - MediaCutoutGeometry.edge),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _CutoutMedia(
                    label: label,
                    tagLabel: tagLabel,
                    tagIcon: tagIcon,
                    overlay: mediaOverlay,
                    hovered: hovered,
                    child: media,
                  ),
                ),
                SizedBox(
                  height: MediaCutoutGeometry.contentExtent(withFoot: withFoot),
                  child: _CutoutContent(
                    title: title,
                    body: body,
                    bodyMono: bodyMono,
                    footIcon: footIcon,
                    footName: footName,
                    footReadout: footReadout,
                    withFoot: withFoot,
                  ),
                ),
              ],
            ),
            // 右下那颗按钮压在文字区右下角，浮出时盖住右读数
            if (trailingIcon != null) _trailing(s),
          ],
        ),
      ),
    );
  }

  /// 悬停浮出的按钮：静止是淡掉 + 往下沉
  ///
  /// 移动端没有悬停这一档，按钮常驻，否则收藏/编辑就没有入口了。
  Widget _trailing(AppSemantic s) {
    final visible = hovered || trailingAtRest || PlatformUtil.isMobile;
    return Positioned(
      right: MediaCutoutGeometry.trailingInset,
      bottom: MediaCutoutGeometry.trailingInset,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.slow,
          curve: AppMotion.decelerate,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.3),
            duration: AppMotion.slow,
            curve: AppMotion.decelerate,
            child: GestureDetector(
              onTap: trailingOnTap,
              behavior: HitTestBehavior.opaque,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: s.accent,
                  borderRadius: appMetrics.radiusPill,
                  boxShadow: s.elevation(Elevation.raised),
                ),
                child: SizedBox(
                  width: MediaCutoutGeometry.trailingSize,
                  height: MediaCutoutGeometry.trailingSize,
                  child: Center(
                    child: DrawIcon(
                      trailingIcon!,
                      size: scaleW(14),
                      color: s.accentOn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 封面那一格：图 + 底部白纱 + 两块镂空标签
///
/// 推近只推画层：垫角和标签钉在格子上，图在它们底下自己放大，接缝不会跟着抖。
class _CutoutMedia extends StatelessWidget {
  const _CutoutMedia({
    required this.child,
    required this.label,
    required this.hovered,
    this.tagLabel,
    this.tagIcon,
    this.overlay,
  });

  final Widget child;
  final String label;
  final String? tagLabel;
  final StrokeIcon? tagIcon;
  final Widget? overlay;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final scrim = s.surface;
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedScale(
              scale: hovered ? 1.05 : 1.0,
              duration: AppMotion.entrance,
              curve: AppMotion.decelerate,
              child: child,
            ),
          ),
          // 白纱：从底部往上走到透明。中间那档必须是同一种透明的表面色，
          // 否则淡出会往黑走。
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[
                      scrim.withAlpha((MediaCutoutGeometry.scrimAlpha * 255).round()),
                      scrim.withAlpha(0),
                      scrim.withAlpha(0),
                    ],
                    stops: const <double>[0, 0.5, 1],
                  ),
                ),
              ),
            ),
          ),
          if (overlay != null) Positioned.fill(child: overlay!),
          // 资源卡关掉叠加信息时 label 是空串：不挖这一格，否则图上贴一枚空标签
          if (label.isNotEmpty)
            Positioned(left: 0, bottom: 0, child: _CutoutLabel(text: label)),
          if (tagLabel != null && tagLabel!.isNotEmpty)
            Positioned(right: 0, top: 0, child: _CutoutTag(text: tagLabel!, icon: tagIcon)),
        ],
      ),
    );
  }
}

/// 左下那枚表面色标签和它的两块垫角
///
/// 垫角**锚在标签自己的边上**（探出一档、回叠 1px），不锚在量出来的横坐标上：
/// 标签宽度是内衬撑出来的，类型名换一档就差几像素，横坐标摆法会在接缝处
/// 留缝或压边，锚在边上则永远咬住。
class _CutoutLabel extends StatelessWidget {
  const _CutoutLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final over = MediaCutoutGeometry.labelFlare - MediaCutoutGeometry.edge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(MediaCutoutGeometry.labelRadius),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaCutoutGeometry.labelPadX,
              vertical: MediaCutoutGeometry.labelPadY,
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.overline(context),
            ),
          ),
        ),
        // 上边外侧那块：内凹的斜边正好接住标签的上边
        Positioned(
          left: -MediaCutoutGeometry.edge,
          top: -over,
          child: _Flare(side: MediaCutoutGeometry.labelFlare, color: s.surface),
        ),
        // 右边外侧那块：内凹斜边从标签右上角扫到图的下边
        Positioned(
          right: -over,
          bottom: -MediaCutoutGeometry.edge,
          child: _Flare(side: MediaCutoutGeometry.labelFlare, color: s.surface),
        ),
      ],
    );
  }
}

/// 右上那枚墨色标签和它的两块垫角：贴着图的上边和右边，只有左下一个圆角
///
/// 垫角用同一块弧的另一头（尖角落右上）：一块从标签左上角往左铺、
/// 一块从右下角往下铺。
class _CutoutTag extends StatelessWidget {
  const _CutoutTag({required this.text, this.icon});

  final String text;
  final StrokeIcon? icon;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final over = MediaCutoutGeometry.tagFlare - MediaCutoutGeometry.edge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: s.accent,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(MediaCutoutGeometry.tagRadius),
            ),
            boxShadow: s.elevation(Elevation.raised),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaCutoutGeometry.tagPadX,
              vertical: MediaCutoutGeometry.tagPadY,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  DrawIcon(icon!, size: MediaCutoutGeometry.avatarIcon, color: s.accentOn),
                  SizedBox(width: appMetrics.kSpace4),
                ],
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: appMetrics.fontSize11,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: s.accentOn,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: -over,
          top: 0,
          child: _Flare(side: MediaCutoutGeometry.tagFlare, color: s.accent, flip: false),
        ),
        Positioned(
          right: -MediaCutoutGeometry.edge,
          bottom: -over,
          child: _Flare(side: MediaCutoutGeometry.tagFlare, color: s.accent, flip: false),
        ),
      ],
    );
  }
}

/// 文字区：标题 + 说明 + 一条发丝线 + 页脚
///
/// 高度由 [MediaCutoutGeometry.contentExtent] 钉死（网格按同一份数反推卡片高），
/// 多出来的余量落在正文那一段下面，所以标题和页脚的位置始终稳。
class _CutoutContent extends StatelessWidget {
  const _CutoutContent({
    required this.title,
    required this.withFoot,
    this.body,
    this.bodyMono = false,
    this.footIcon,
    this.footName,
    this.footReadout,
  });

  final String title;
  final String? body;
  final bool bodyMono;
  final StrokeIcon? footIcon;
  final String? footName;
  final String? footReadout;
  final bool withFoot;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Padding(
      padding: EdgeInsets.all(MediaCutoutGeometry.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.cardTitle(context),
            ),
          ),
          SizedBox(height: MediaCutoutGeometry.titleGap),
          Expanded(
            child: body == null || body!.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    body!,
                    maxLines: withFoot ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: bodyMono
                        ? AppTextStyles.mono(context, size: appMetrics.fontSize11)
                        : AppTextStyles.caption(context),
                  ),
          ),
          if (withFoot) ...[
            SizedBox(height: MediaCutoutGeometry.blockGap),
            SizedBox(height: 1, child: ColoredBox(color: s.hairline)),
            SizedBox(height: MediaCutoutGeometry.blockGap),
            Row(
              children: [
                if (footIcon != null) ...[
                  _Avatar(icon: footIcon!),
                  SizedBox(width: appMetrics.kSpace8),
                ],
                Expanded(
                  child: Text(
                    footName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption(context),
                  ),
                ),
                SizedBox(width: appMetrics.kSpace8),
                Text(
                  footReadout ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(context).copyWith(
                    color: s.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 页脚那个圆底图标：容器底 + 描边，只当"这一行讲的是什么"的锚点
class _Avatar extends StatelessWidget {
  const _Avatar({required this.icon});

  final StrokeIcon icon;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: s.accentContainer,
        border: Border.all(color: s.accentContainerBorder),
      ),
      child: SizedBox(
        width: MediaCutoutGeometry.avatarSize,
        height: MediaCutoutGeometry.avatarSize,
        child: Center(
          child: DrawIcon(
            icon,
            size: MediaCutoutGeometry.avatarIcon,
            color: s.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 一块内凹垫角：四块共用同一条 path，只是朝向和颜色
///
/// 视野里是贴着某一个角、斜边内凹的月牙：转 +90° 尖角落在**左下**（表面色那两块），
/// 转 −90° 落在**右上**（墨色那两块）。盒子是正方形，绕中心转正好落回自己那一格。
class _Flare extends StatelessWidget {
  const _Flare({required this.side, required this.color, this.flip = true});

  final double side;
  final Color color;

  /// true = 尖角左下，false = 尖角右上
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: flip ? math.pi / 2 : -math.pi / 2,
      child: CustomPaint(size: Size(side, side), painter: _FlarePainter(color)),
    );
  }
}

class _FlarePainter extends CustomPainter {
  const _FlarePainter(this.color);

  final Color color;

  /// 归一化系数：控制点落在 0.78 / 1.0 两档上，斜边才读起来是一条连续的弧
  static const _c1x = 0.77998, _c1y = 0.999805, _c2x = 1.000145, _c2y = 0.78154;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawPath(
      Path()
        ..moveTo(0, s)
        ..cubicTo(_c1x * s, _c1y * s, _c2x * s, _c2y * s, s, 0)
        ..lineTo(s, s)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_FlarePainter old) => old.color != color;
}

/// 卡片封面那一层：取图、隐私打码、加载失败兜底、调试徽标
///
/// 四类卡的封面逻辑本来各抄了一份同样的四段（http/本地、隐私模糊、占位、debug 尺寸），
/// 收到这里一份。镂空样式只关心"图区里放什么"，图源怎么解码归这里管。
class MediaCardCover extends StatelessWidget {
  const MediaCardCover({
    super.key,
    required this.source,
    required this.placeholderIcon,
    this.lostIcon,
    this.isLost = false,
  });

  final String? source;

  /// 没有封面时显示的图标
  final StrokeIcon placeholderIcon;

  /// 丢失 / 解码失败时的图标，缺省沿用 [placeholderIcon]
  final StrokeIcon? lostIcon;

  final bool isLost;

  @override
  Widget build(BuildContext context) {
    // 用 Obx 自己监听隐私开关，而不是靠宿主卡片那几个 ever(prefs.privacyMode) worker：
    // 伪封面是新增的第三条通路，四类卡都从这里过，一处监听就够了。
    return Obx(() => _cover(context));
  }

  Widget _cover(BuildContext context) {
    final s = AppSemantic.of(context);
    final src = source;
    final prefs = getIt.isRegistered<MediaPrefsService>()
        ? getIt.get<MediaPrefsService>()
        : null;
    // 两个开关在任何提前 return 之前无条件读一遍：Obx 只登记本次构建真读到的 Rx，
    // 写在 return 后面会让没有封面的卡片这次构建漏听，之后切换开关不再重绘。
    final fakeCover = prefs?.fakeCover.value ?? false;
    final privacyOn = prefs?.privacyMode.value ?? false;
    final broken = _CoverPlaceholder(icon: lostIcon ?? placeholderIcon, background: s.surfaceSunken);
    if (isLost || src == null || src.isEmpty) return broken;

    // 伪封面：整张换成设置里指定的那张无害图片，不糊也不加锁角标，优先于隐私模糊
    if (fakeCover) return const FakeCover();

    final isHttp = src.startsWith('http');
    final cacheWidth = isHttp
        ? null
        : () {
            final w = prefs?.localPreviewWidth.value ?? 480;
            return w > 0 ? w : null;
          }();
    // 封面与 debug 徽标共用同一个 provider，徽标才不会触发第二次下载/解码
    final provider = ResizeImage.resizeIfNeeded(
      cacheWidth,
      null,
      isHttp ? NetworkImage(src) : FileImage(File(src)),
    );
    final image = Image(
      image: provider,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => broken,
    );

    if (privacyOn) {
      final sigma = prefs?.privacyBlurSigma.value ?? 15.0;
      return Stack(
        fit: StackFit.expand,
        children: [
          image,
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: const ColoredBox(color: Colors.transparent),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: s.scrim, borderRadius: appMetrics.radius999),
              child: Padding(
                padding: EdgeInsets.all(appMetrics.kSpace6),
                child: DrawIcon(
                  StrokeIcons.lockOutline,
                  size: appMetrics.iconSize16,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (!kDebugMode) return image;
    // 右下角标一枚真实解码尺寸，用来核对「本地/远程清晰度」到底生效了没
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(
          right: appMetrics.kSpace4,
          bottom: appMetrics.kSpace4,
          child: DebugImageSizeBadge(provider: provider),
        ),
      ],
    );
  }
}

/// 无封面 / 封面读不出来时的实色底 + 居中图标
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.icon, required this.background});

  final StrokeIcon icon;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Center(
        child: DrawIcon(icon, size: scaleW(44), color: AppSemantic.of(context).textTertiary),
      ),
    );
  }
}
