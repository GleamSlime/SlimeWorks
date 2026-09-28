import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../kit.dart';

/// 8 号镂空卡：白表面咬进图里，接缝上是两条内弧
///
/// 这一格的看点不是"浮层盖在图上"，是**同一块白表面在图里挖出一个洞**：左下角那枚
/// 标签贴着图的左边和下边长出来，它的上边和右边各接一块 32×32 的垫角。四块垫角是
/// **同一条 path**（`M0 200C…200 0V200H0Z`：贴着某一个角、斜边内凹的月牙）转 ±90° 摆的 ——
/// 靠内凹那一侧接住标签的直边，接缝读起来是一条连续的曲线，而不是两个矩形贴在一起。
/// 右上角那枚深色标签用同一条弧的另一头（转 −90°，尖角落在**右上**）：它贴着图的上边和
/// 右边，所以一块垫角往左铺、一块往下铺。
///
/// 三层动画各走各的时长，参考稿就是三个互不相同的 transition：
/// 1. 外壳的投影 + 描边 —— `.5s cubic-bezier(.23,1,.32,1)`，三档糊光同时加深同时爬远
///    （偏移 1/4/8 → 2/8/16，模糊 2/8/16 → 4/16/32，扩散 −1/−2/−4 → −1/−4/−8）；描边从 80% 走满；
/// 2. 图自己 `scale(1.05)` —— 同一根曲线走 700ms，比外壳慢 200ms，所以悬停途中壳已经稳了
///    图还在推；
/// 3. 右下角那颗胶囊从 `opacity 0 / translateY 8` 进来 —— 300ms。
///
/// 三处本地例外，不藏：
/// 1. **图**：参考稿挂的是一张线上占位图，离线跑不出同一份像素。这里改成 16×12 的采样色
///    马赛克（就是那张图的逐格取色）+ 一遍 σ7 的糊：形状读起来还是"山顶 + 晚霞"，
///    而且完全确定 —— 出图不依赖网络，也不会因为图片解码时序多抖一帧；
/// 2. 第 3 层的**进场时长**参考稿是脚本驱动的，量不到，300ms 本地定。另外参考稿那句
///    `active:scale-[0.97]` 是死代码 —— 包着胶囊的那一层 `pointer-events:none`，按下根本
///    到不了它，所以这里也不做按压反馈；
/// 3. **减弱动效**：三层全部瞬时到位（[_Ease] 直接给终值），不做"演一半就掐掉"。
///
/// 移动端：这一格只有悬停、没有跟手拖，所以不挂 [SvTouchLock]（没有要接管的滚动手势）；
/// 指尖走 [SvHoverRegion] 那条桥 —— 点一下当"指针进来并停在原地"，再点一下当离开。
/// 受理区就是整张卡（446×482），远在 44 以上，不用另垫带子。
class Case08CutoutCard extends StatefulWidget {
  const Case08CutoutCard({super.key});

  static const cardKey = ValueKey<String>('sv-c08-card');
  static const mediaKey = ValueKey<String>('sv-c08-media');
  static const artKey = ValueKey<String>('sv-c08-art');
  static const labelKey = ValueKey<String>('sv-c08-label');
  static const pinKey = ValueKey<String>('sv-c08-pin');
  static const titleKey = ValueKey<String>('sv-c08-title');
  static const bodyKey = ValueKey<String>('sv-c08-body');
  static const footKey = ValueKey<String>('sv-c08-foot');
  static const avatarKey = ValueKey<String>('sv-c08-avatar');
  static const nameKey = ValueKey<String>('sv-c08-name');
  static const timeKey = ValueKey<String>('sv-c08-time');
  static const actionKey = ValueKey<String>('sv-c08-action');

  /// 四块垫角：两块白的接标签，两块深的接那枚深色标签
  static Key flareKey(String id) => ValueKey<String>('sv-c08-flare-$id');

  /// 舞台：卡 448×484，四周各让 32 给悬停那三档糊光
  static const stageW = 512.0;
  static const stageH = 548.0;

  // ===== 量出来的那一套（字面 px，例外只圈在这一页）=====

  /// 外框：448×484 含 1px 描边，所以描边里面那一格是 446×482
  static const cardW = 448.0;
  static const cardH = 484.0;
  static const cardRadius = 28.0;
  static const edge = 1.0;
  static const bodyW = cardW - edge * 2; // 446
  static const bodyH = cardH - edge * 2; // 482

  static const mediaH = 288.0;
  static const contentH = bodyH - mediaH; // 194

  /// 左下角标签：量出来 105.1×49.2 —— `px-5` 的两档内衬 + 中间那行 11px 的字。
  /// 高度钉死（垫角要按它算落点），宽度交给内衬自己撑：字形宽度换一档就露缝，
  /// 所以这里不拿量到的 105.1 去钉布局，只拿它当测试预期。
  static const labelW = 105.1;
  static const labelH = 49.2;
  static const labelRadius = 20.0;
  static const labelPad = 20.0;

  /// 两块白色垫角 32×32：一块骑在标签上边外侧（贴着图的左缘），一块骑在右边外侧。
  /// 量到的落点是图坐标的 (-1, 207.8) 和 (104.1, 257)，也就是**各探出 31、回叠 1**
  static const labelFlare = 32.0;

  /// 右上角深色标签：量出来 62×36（`px-4 py-2` 包一行 14/20 的字），钉在图的右上角。
  /// 只有左下一个角是圆的（16），另外三个角是直的 —— 靠右边和上边那条缝自己收
  static const pinW = 62.0;
  static const pinH = 36.0;
  static const pinPadX = 16.0;
  static const pinRadius = 16.0;

  /// 深色那两块 24×24：一块往左铺、一块往下铺，同样是探出 23、回叠 1
  static const pinFlare = 24.0;

  /// 内容区 `p-6` = 24
  static const pad = 24.0;

  /// 右下角那颗胶囊：102.6×36，钉在 `right:20 bottom:20`
  static const actionW = 102.6;
  static const actionH = 36.0;
  static const actionInset = 20.0;

  /// 静止档：淡掉 + 往下沉 8，悬停才浮到 `bottom:20` 那一格
  static const actionRise = 8.0;

  /// 马赛克那遍糊
  static const artSigma = 7.0;

  @override
  State<Case08CutoutCard> createState() => _Case08CutoutCardState();
}

class _Case08CutoutCardState extends State<Case08CutoutCard> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    return SvStage(
      // 参考稿的 preview 是白页：卡自己也是白的，压在灰舞台上就看不出那三档糊光
      color: Colors.white,
      width: Case08CutoutCard.stageW,
      height: Case08CutoutCard.stageH,
      child: SvHoverRegion(
        group: 'sv-c08',
        onEnter: () => setState(() => _hot = true),
        onExit: () => setState(() => _hot = false),
        child: _Shell(hot: _hot),
      ),
    );
  }
}

/// 这一格吃到的几档盘：全是参考稿的 `--*` 原值，只有 80% 那一档另算
const _white = SvColor.pane; // 卡壳和标签：#FFFFFF
const _ink = SvColor.fg; // #0A0A0A
const _subtle = SvColor.mutedFg; // #737373
const _dark = SvColor.primary; // 深色标签与胶囊：#171717
const _onDark = SvColor.onPrimary; // #FAFAFA

/// `--border` 压在白底上那三档都是 80%，只有外壳悬停时走满
const _hair = Color(0xCCE5E5E5);
const _borderRest = _hair;
const _borderHot = SvColor.border;

/// 外壳：描边 + 三档糊光跟着悬停走 500ms，里面裁成 27 的圆角
class _Shell extends StatelessWidget {
  const _Shell({required this.hot});

  final bool hot;

  /// 静止三档：`0 1 2 -1 / 0 4 8 -2 / 0 8 16 -4`，色是 #0A0A0A 的 8/6/5%
  static const _shadowRest = <BoxShadow>[
    BoxShadow(color: Color(0x140A0A0A), blurRadius: 2, offset: Offset(0, 1), spreadRadius: -1),
    BoxShadow(color: Color(0x0F0A0A0A), blurRadius: 8, offset: Offset(0, 4), spreadRadius: -2),
    BoxShadow(color: Color(0x0D0A0A0A), blurRadius: 16, offset: Offset(0, 8), spreadRadius: -4),
  ];

  /// 悬停三档：`0 2 4 -1 / 0 8 16 -4 / 0 16 32 -8`，10/8/6%
  static const _shadowHot = <BoxShadow>[
    BoxShadow(color: Color(0x1A0A0A0A), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -1),
    BoxShadow(color: Color(0x140A0A0A), blurRadius: 16, offset: Offset(0, 8), spreadRadius: -4),
    BoxShadow(color: Color(0x0F0A0A0A), blurRadius: 32, offset: Offset(0, 16), spreadRadius: -8),
  ];

  @override
  Widget build(BuildContext context) {
    return _Ease(
      ms: 500,
      target: hot ? 1 : 0,
      builder: (context, q) => DecoratedBox(
        key: Case08CutoutCard.cardKey,
        decoration: BoxDecoration(
          color: _white,
          borderRadius: const BorderRadius.all(Radius.circular(Case08CutoutCard.cardRadius)),
          border: Border.all(color: Color.lerp(_borderRest, _borderHot, q)!),
          boxShadow: BoxShadow.lerpList(_shadowRest, _shadowHot, q)!,
        ),
        // `DecoratedBox` 只画描边、不把边挪进盒子里（那是 `Container` 的额外一步），
        // 所以这里自己让 1px：外框才是量到的 448×484，里面那一格 446×482
        child: Padding(
          padding: const EdgeInsets.all(Case08CutoutCard.edge),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Case08CutoutCard.cardRadius - Case08CutoutCard.edge),
            child: SizedBox(
              width: Case08CutoutCard.bodyW,
              height: Case08CutoutCard.bodyH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(top: 0, left: 0, child: _Media(hot: hot)),
                  const Positioned(top: Case08CutoutCard.mediaH, left: 0, child: _Content()),
                  Positioned(
                    right: Case08CutoutCard.actionInset,
                    bottom: Case08CutoutCard.actionInset,
                    child: _Action(hot: hot),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图那一格：446×288，`overflow-hidden` —— 垫角探出边界的 1px 就是被这一层裁掉的
class _Media extends StatelessWidget {
  const _Media({required this.hot});

  final bool hot;

  /// 白纱：`to top` 从底部 35% 白走到一半处透明。
  /// 中间那一档必须是**同一种透明的白**（0x00FFFFFF），否则淡出往黑走
  static const _scrimStops = <Color>[Color(0x59FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF)];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        key: Case08CutoutCard.mediaKey,
        width: Case08CutoutCard.bodyW,
        height: Case08CutoutCard.mediaH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _Art(hot: hot)),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: _scrimStops,
                      stops: <double>[0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ),
            // 标签：白底 + 它那两块垫角，整组贴着图的左下角
            const Positioned(left: 0, bottom: 0, child: _InsetLabel()),
            // 深色标签：同一块弧的另一头，整组贴着图的右上角
            const Positioned(right: 0, top: 0, child: _Tag()),
          ],
        ),
      ),
    );
  }
}

/// 图：16×12 采样色马赛克 + 一遍 σ7，悬停时整块推近到 1.05（700ms，比外壳慢 200）
class _Art extends StatelessWidget {
  const _Art({required this.hot});

  final bool hot;

  @override
  Widget build(BuildContext context) {
    return _Ease(
      ms: 700,
      target: hot ? 1 : 0,
      builder: (context, q) => Transform.scale(
        key: Case08CutoutCard.artKey,
        scale: 1.0 + 0.05 * q,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: Case08CutoutCard.artSigma,
            sigmaY: Case08CutoutCard.artSigma,
            tileMode: TileMode.clamp,
          ),
          child: const SizedBox.expand(child: CustomPaint(painter: _ArtPainter())),
        ),
      ),
    );
  }
}

/// 左下角那枚白标签和它的两块垫角：只有右上一个圆角，字左右各让 20、竖着居中
///
/// 垫角**锚在标签自己的边上**（探出 31、回叠 1），不锚在量到的那个横坐标上：
/// 标签的宽是内衬撑出来的，字形一换档就跟量到的 105.1 差几像素，横坐标摆法会在
/// 接缝处留一道白缝或压出一道白边，锚在边上则永远咬住。
class _InsetLabel extends StatelessWidget {
  const _InsetLabel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          key: Case08CutoutCard.labelKey,
          height: Case08CutoutCard.labelH,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.only(topRight: Radius.circular(Case08CutoutCard.labelRadius)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Case08CutoutCard.labelPad),
              child: Center(
                child: Text(
                  'FEATURED',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: SvFont.family,
                    fontFamilyFallback: SvFont.fallback,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    height: 16.5 / 11,
                    color: _subtle,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 上边外侧那块：尖角落左下，所以内凹的斜边正好接住标签的上边
        Positioned(
          left: -1,
          top: -31,
          child: _Flare(key: Case08CutoutCard.flareKey('label-top'), side: Case08CutoutCard.labelFlare),
        ),
        // 右边外侧那块：同样尖角左下，内凹斜边从标签右上角扫到图的下边
        Positioned(
          right: -31,
          bottom: -1,
          child: _Flare(key: Case08CutoutCard.flareKey('label-right'), side: Case08CutoutCard.labelFlare),
        ),
      ],
    );
  }
}

/// 右上角那枚深色标签和它的两块垫角：贴着图的上边和右边，只有左下一个圆角
///
/// 垫角用同一块弧的另一头（尖角落**右上**）：一块从标签左上角往左铺、一块从右下角
/// 往下铺，量到的探出/回叠同样是 23/1。锚法同 [_InsetLabel]，跟着标签自己的边走。
class _Tag extends StatelessWidget {
  const _Tag();

  /// `ring` 30% 那一圈 + 和胶囊同款的两档投影
  static const _shadow = <BoxShadow>[
    BoxShadow(color: Color(0x4DE5E5E5), blurRadius: 0, spreadRadius: 1),
    BoxShadow(color: Color(0x1A0A0A0A), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
    BoxShadow(color: Color(0x140A0A0A), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          key: Case08CutoutCard.pinKey,
          height: Case08CutoutCard.pinH,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _dark,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(Case08CutoutCard.pinRadius)),
              boxShadow: _shadow,
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: Case08CutoutCard.pinPadX),
              child: Center(
                child: Text(
                  'New',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: SvFont.family,
                    fontFamilyFallback: SvFont.fallback,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 20 / 14,
                    color: _onDark,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: -23,
          top: 0,
          child: _Flare(
            key: Case08CutoutCard.flareKey('pin-left'),
            color: _dark,
            side: Case08CutoutCard.pinFlare,
            flip: false,
          ),
        ),
        Positioned(
          right: -1,
          bottom: -23,
          child: _Flare(
            key: Case08CutoutCard.flareKey('pin-bottom'),
            color: _dark,
            side: Case08CutoutCard.pinFlare,
            flip: false,
          ),
        ),
      ],
    );
  }
}

/// 内容区：标题 + 两行正文 + 一条压着 hairline 的页脚
///
/// 四段全按量到的落点摆，不靠排版流往下排：Flutter 的行盒按整像素取整
/// （`20/27.5` 那一档实测 28.0，`14/22.75` 两行实测 46.0），流式排会把这 194 的一格
/// 顶爆半像素，而段落多出来的那半格本来就落在段与段之间的空隙里，摆法换成绝对
/// 落点后一格不挪。
class _Content extends StatelessWidget {
  const _Content();

  /// 正文宽 = 446 − 24×2
  static const textW = Case08CutoutCard.bodyW - Case08CutoutCard.pad * 2;

  /// 相对内容区左上角的四条上沿：24 / 24+27.5+8 / +45.5+16 / +1+16
  static const titleY = 24.0;
  static const bodyY = 59.5;
  static const hairY = 121.0;
  static const footY = 138.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Case08CutoutCard.bodyW,
      height: Case08CutoutCard.contentH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: Case08CutoutCard.pad,
            top: titleY,
            width: textW,
            child: const Text(
              'Alpine Adventures',
              key: Case08CutoutCard.titleKey,
              maxLines: 1,
              style: TextStyle(
                fontFamily: SvFont.family,
                fontFamilyFallback: SvFont.fallback,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 27.5 / 20,
                color: _ink,
              ),
            ),
          ),
          Positioned(
            left: Case08CutoutCard.pad,
            top: bodyY,
            width: textW,
            child: const Text(
              'Discover breathtaking mountain landscapes and experience the serenity '
              'of nature at its finest.',
              key: Case08CutoutCard.bodyKey,
              style: TextStyle(
                fontFamily: SvFont.family,
                fontFamilyFallback: SvFont.fallback,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 22.75 / 14,
                color: _subtle,
              ),
            ),
          ),
          Positioned(
            left: Case08CutoutCard.pad,
            top: hairY,
            width: textW,
            height: 1,
            child: const ColoredBox(color: _hair),
          ),
          Positioned(left: Case08CutoutCard.pad, top: footY, width: textW, child: const _Foot()),
        ],
      ),
    );
  }
}

/// 页脚那一行 32：头像 + 名字，读数贴右
class _Foot extends StatelessWidget {
  const _Foot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Case08CutoutCard.footKey,
      height: 32,
      child: Row(
        children: <Widget>[
          SizedBox(
            key: Case08CutoutCard.avatarKey,
            width: 32,
            height: 32,
            child: _Avatar(),
          ),
          SizedBox(width: 12),
          Text(
            'Sarah Chen',
            key: Case08CutoutCard.nameKey,
            style: TextStyle(
              fontFamily: SvFont.family,
              fontFamilyFallback: SvFont.fallback,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 20 / 14,
              color: _ink,
            ),
          ),
          Spacer(),
          Text(
            '5 min read',
            key: Case08CutoutCard.timeKey,
            style: TextStyle(
              fontFamily: SvFont.family,
              fontFamilyFallback: SvFont.fallback,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 16 / 12,
              color: _subtle,
              fontFeatures: SvFont.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// 头像：`to bottom right` 的两档橙 + `ring-2` 白 + `shadow-sm`
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFB800), Color(0xFFFF9800)],
        ),
        boxShadow: <BoxShadow>[
          // ring-2：只画环不占位，所以那一行还是 32 高
          BoxShadow(color: _white, blurRadius: 0, spreadRadius: 2),
          BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1), spreadRadius: -1),
        ],
      ),
    );
  }
}

/// 右下角的胶囊：静止是 `opacity 0 / translateY 8`，悬停才浮到 `bottom:20` 那一格
///
/// 参考稿没有按压反馈（外面那层 `pointer-events:none`），所以这里只画、不接事件。
class _Action extends StatelessWidget {
  const _Action({required this.hot});

  final bool hot;

  @override
  Widget build(BuildContext context) {
    return _Ease(
      ms: 300,
      target: hot ? 1 : 0,
      builder: (context, q) => Opacity(
        opacity: q,
        child: Transform.translate(
          offset: Offset(0, (1 - q) * Case08CutoutCard.actionRise),
          child: SizedBox(
            key: Case08CutoutCard.actionKey,
            width: Case08CutoutCard.actionW,
            height: Case08CutoutCard.actionH,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: _dark,
                borderRadius: BorderRadius.all(Radius.circular(Case08CutoutCard.actionH / 2)),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Color(0x1A0A0A0A), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -1),
                  BoxShadow(color: Color(0x140A0A0A), blurRadius: 4, offset: Offset(0, 2), spreadRadius: -2),
                ],
              ),
              child: Center(
                child: Text(
                  'Read More',
                  style: TextStyle(
                    fontFamily: SvFont.family,
                    fontFamilyFallback: SvFont.fallback,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 20 / 14,
                    color: _onDark,
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

/// 一块内弧垫角：四块共用同一条 path，只是朝向
///
/// 原路径在 200 的视野里是 `M0 200C…200 0V200H0Z` —— 贴着右下角、斜边从左下角走到右上角
/// 的月牙。转 +90° 后尖角落在**左下**（白的两块用它），转 −90° 落在**右上**（深的两块用它）。
/// 盒子是正方形，绕中心转正好落回自己那一格，摆位只看外层的 `Positioned`。
class _Flare extends StatelessWidget {
  const _Flare({super.key, required this.side, this.color = _white, this.flip = true});

  final double side;
  final Color color;

  /// true = +90°（尖角左下），false = −90°（尖角右上）
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

  /// 归一化系数（原路径的两个控制点 / 200）
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

/// 一层独立时长的补间：减弱动效时直接给终值，不演一半
///
/// 三层的时长各不相同（500/700/300），所以每层各挂一个，不合并成一条。
class _Ease extends StatelessWidget {
  const _Ease({required this.ms, required this.target, required this.builder});

  final int ms;
  final double target;
  final Widget Function(BuildContext context, double value) builder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return builder(context, target);
    return SvTween(
      target: target,
      duration: Duration(milliseconds: ms),
      curve: SvEase.smoothOut,
      builder: builder,
    );
  }
}

/// 图上那张参考稿占位图的逐格取色：16 列 × 12 行，行优先，每格 `0xRRGGBB`
///
/// 顶端是深蓝的天、中段一道橙红的晚霞、底下一路紫到品红 —— 马赛克 + σ7 之后
/// 读起来就是"山 + 晚霞"，而且是本地常量，出图不依赖网络。
class _ArtPainter extends CustomPainter {
  const _ArtPainter();

  static const _cols = 16;
  static const _rows = 12;

  static const _cells = <int>[
    // 深蓝的天
    0x0b3c64, 0x0c3b63, 0x0d3962, 0x0e385f, 0x0e365b, 0x0e3559, 0x0c355d, 0x084071, //
    0x064e8c, 0x055aa1, 0x0460af, 0x0464b7, 0x0465b3, 0x065fac, 0x0759a0, 0x095394, //
    0x0a4171, 0x0a3e6e, 0x0b3e6a, 0x0a3e68, 0x0a3d65, 0x0c3b64, 0x0c3962, 0x0c3862, //
    0x0b3862, 0x0a3a67, 0x074176, 0x064f8e, 0x0559a0, 0x065ca8, 0x0859a0, 0x095395, //
    0x094679, 0x094476, 0x0a4273, 0x0a4171, 0x0b406f, 0x0b3e6d, 0x0a3e69, 0x0a3d67, //
    0x0b3e69, 0x0b3a62, 0x093a62, 0x083e6f, 0x074880, 0x065393, 0x07579a, 0x095294, //
    0x0b4a7f, 0x0b4b7f, 0x0b497d, 0x0a497d, 0x0a487d, 0x0b487c, 0x0b4a7e, 0x0d4f86, //
    0x0f5895, 0x115ca0, 0x105b9e, 0x0a447a, 0x083f72, 0x07477f, 0x074e8a, 0x094d88, //
    // 霞光压进山脊
    0xbc2d55, 0x823657, 0x0e5188, 0x0c528a, 0x0d538a, 0x585062, 0x9c6d51, 0x32638a, //
    0x1160a4, 0x1363ac, 0x1365b5, 0x57658a, 0x4e536f, 0x093d6e, 0x083e70, 0x083e70, //
    0xbc2f54, 0xbf324d, 0x454873, 0x105893, 0x91434c, 0xc74635, 0xc64a2c, 0xec943a, //
    0xe79340, 0xa58460, 0xe47e32, 0xe78338, 0xe8803b, 0xe36c36, 0xbe5b3b, 0xdb5e3a, //
    0xb22947, 0xbc3149, 0xc13944, 0xc23c3c, 0xc74238, 0xc74834, 0xc74d2c, 0xc75327, //
    0xf4a23f, 0xef963b, 0xd66b27, 0xe38034, 0xe98639, 0xe87e38, 0xe57437, 0xdf6939, //
    0xa4223a, 0xad2c3d, 0xb1323a, 0xb63836, 0xb53a30, 0xaf3a27, 0xab3a23, 0xac3e1e, //
    0xc65220, 0xc9581d, 0xcb5f1f, 0xd47027, 0xe38233, 0xe88536, 0xe67a33, 0xdf6d31, //
    0x9d1f36, 0x9c2535, 0x9d2830, 0x9b2b2c, 0x992c29, 0x992f26, 0x9b3221, 0x9d361e, //
    0xa33e1a, 0xc9591e, 0xc95d1d, 0xc6611f, 0xcc6c25, 0xd57228, 0xd36e28, 0xc96422, //
    // 山脚的紫
    0x992141, 0x91233c, 0x8d2639, 0x8c273a, 0x8b293c, 0x882b39, 0x852d32, 0x86302a, //
    0x8a3522, 0x913b1d, 0x9a4219, 0xa34a18, 0xab511a, 0xb1561c, 0xb55a1c, 0xb95c18, //
    0x942854, 0x882a54, 0x832c55, 0x7f2e57, 0x7e315c, 0x7a335e, 0x74345a, 0x703451, //
    0x703547, 0x72353a, 0x77372f, 0x7e3a25, 0x873d1d, 0x934319, 0xa04a15, 0xaa5014, //
    0x8c2f66, 0x80336c, 0x793570, 0x753875, 0x703b7a, 0x693e7f, 0x624082, 0x5e4081, //
    0x5b407d, 0x5b3f75, 0x5e3e68, 0x643b58, 0x6c3845, 0x753732, 0x823822, 0x8f3b17, //
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / _cols;
    final h = size.height / _rows;
    final paint = Paint();
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        paint.color = Color(0xFF000000 | _cells[r * _cols + c]);
        canvas.drawRect(Rect.fromLTRB(c * w, r * h, (c + 1) * w, (r + 1) * h), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => false;
}
